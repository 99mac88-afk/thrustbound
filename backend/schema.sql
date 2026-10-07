-- Thrustbound community backend (Supabase / PostgreSQL)
--
-- Setup: Supabase dashboard -> SQL Editor -> New query -> paste this whole
-- file -> Run. It is safe to run again after updates.
--
-- What it creates
--   profiles     one row per account (username, admin flag)
--   levels       published community levels (title, level data, views, likes)
--   level_likes  who liked what (one like per player per level)
--
-- Rules (enforced by row level security, not by the app)
--   * anyone can browse levels and see usernames
--   * signed-in players publish levels as themselves; views and likes always
--     start at 0 and can only change through register_view / toggle_like
--   * players can delete their own levels; admins can delete any level
--   * the FIRST account ever created becomes the admin; admins can promote
--     or demote others with set_admin('username', true|false)

-- ------------------------------------------------------------------ tables

create table if not exists public.profiles (
    id         uuid primary key references auth.users (id) on delete cascade,
    username   text not null,
    is_admin   boolean not null default false,
    created_at timestamptz not null default now(),
    constraint profiles_username_format check (username ~ '^[A-Za-z0-9_]{3,20}$')
);
create unique index if not exists profiles_username_ci on public.profiles (lower(username));

create table if not exists public.levels (
    id         uuid primary key default gen_random_uuid(),
    author_id  uuid not null references public.profiles (id) on delete cascade,
    title      text not null,
    data       jsonb not null,
    views      integer not null default 0,
    likes      integer not null default 0,
    created_at timestamptz not null default now(),
    constraint levels_title_length check (char_length(btrim(title)) between 1 and 40),
    constraint levels_data_object check (jsonb_typeof(data) = 'object'),
    constraint levels_data_size check (pg_column_size(data) < 200000)
);
create index if not exists levels_newest on public.levels (created_at desc);
create index if not exists levels_most_liked on public.levels (likes desc, created_at desc);
create index if not exists levels_most_viewed on public.levels (views desc, created_at desc);
create index if not exists levels_by_author on public.levels (author_id);

create table if not exists public.level_likes (
    level_id   uuid not null references public.levels (id) on delete cascade,
    user_id    uuid not null references public.profiles (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (level_id, user_id)
);
create index if not exists level_likes_by_user on public.level_likes (user_id);

-- ------------------------------------------------------------------ helpers

create or replace function public.is_admin()
returns boolean
language sql stable security definer
set search_path = public
as $$
    select coalesce((select p.is_admin from public.profiles p where p.id = auth.uid()), false)
$$;

create or replace function public.username_available(p_name text)
returns boolean
language sql stable security definer
set search_path = public
as $$
    select p_name ~ '^[A-Za-z0-9_]{3,20}$'
       and not exists (select 1 from public.profiles p where lower(p.username) = lower(p_name))
$$;

-- New account -> profile. The first account ever becomes the admin.
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
    wanted text := btrim(coalesce(new.raw_user_meta_data ->> 'username', ''));
begin
    if wanted !~ '^[A-Za-z0-9_]{3,20}$' then
        raise exception 'Username must be 3-20 letters, numbers or underscores';
    end if;
    if exists (select 1 from public.profiles p where lower(p.username) = lower(wanted)) then
        raise exception 'That username is already taken';
    end if;
    insert into public.profiles (id, username, is_admin)
    values (new.id, wanted, not exists (select 1 from public.profiles));
    return new;
end
$$;

-- auth.users belongs to Supabase Auth, so only create the trigger once
-- (the function above is replaced in place on every run).
do $$
begin
    if not exists (select 1 from pg_trigger
                   where tgname = 'on_auth_user_created' and tgrelid = 'auth.users'::regclass) then
        create trigger on_auth_user_created
            after insert on auth.users
            for each row execute function public.handle_new_user();
    end if;
end
$$;

-- Publishing: the author is always the caller, counters always start at 0,
-- and each player can publish at most 20 levels a day.
create or replace function public.levels_before_insert()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
    new.author_id := auth.uid();
    new.title := btrim(new.title);
    new.views := 0;
    new.likes := 0;
    new.created_at := now();
    if new.author_id is null then
        raise exception 'Sign in to publish levels';
    end if;
    if (select count(*) from public.levels l
        where l.author_id = new.author_id and l.created_at > now() - interval '1 day') >= 20 then
        raise exception 'Daily publish limit reached (20 levels)';
    end if;
    return new;
end
$$;

drop trigger if exists levels_before_insert on public.levels;
create trigger levels_before_insert
    before insert on public.levels
    for each row execute function public.levels_before_insert();

-- Keep levels.likes in step with level_likes.
create or replace function public.level_likes_count()
returns trigger
language plpgsql security definer
set search_path = public
as $$
begin
    if tg_op = 'INSERT' then
        update public.levels set likes = likes + 1 where id = new.level_id;
    elsif tg_op = 'DELETE' then
        update public.levels set likes = greatest(likes - 1, 0) where id = old.level_id;
    end if;
    return null;
end
$$;

drop trigger if exists level_likes_count on public.level_likes;
create trigger level_likes_count
    after insert or delete on public.level_likes
    for each row execute function public.level_likes_count();

-- ------------------------------------------------------------------ actions (RPC)

-- Called when someone starts playing a community level.
create or replace function public.register_view(p_level uuid)
returns integer
language sql volatile security definer
set search_path = public
as $$
    update public.levels set views = views + 1 where id = p_level returning views
$$;

-- Like or unlike a level. Returns {"liked": bool, "likes": int}.
create or replace function public.toggle_like(p_level uuid)
returns json
language plpgsql volatile security definer
set search_path = public
as $$
declare
    uid   uuid := auth.uid();
    liked boolean;
    total integer;
begin
    if uid is null then
        raise exception 'Sign in to like levels';
    end if;
    delete from public.level_likes where level_id = p_level and user_id = uid;
    if found then
        liked := false;
    else
        insert into public.level_likes (level_id, user_id) values (p_level, uid);
        liked := true;
    end if;
    select l.likes into total from public.levels l where l.id = p_level;
    return json_build_object('liked', liked, 'likes', coalesce(total, 0));
end
$$;

-- Admins only: grant or remove admin rights.
create or replace function public.set_admin(p_username text, p_admin boolean)
returns void
language plpgsql volatile security definer
set search_path = public
as $$
begin
    if not public.is_admin() then
        raise exception 'Only admins can change admin rights';
    end if;
    update public.profiles set is_admin = p_admin where lower(username) = lower(p_username);
    if not found then
        raise exception 'No player called %', p_username;
    end if;
end
$$;

-- ------------------------------------------------------------------ permissions

alter table public.profiles enable row level security;
alter table public.levels enable row level security;
alter table public.level_likes enable row level security;

drop policy if exists "profiles are public" on public.profiles;
create policy "profiles are public" on public.profiles
    for select using (true);

drop policy if exists "levels are public" on public.levels;
create policy "levels are public" on public.levels
    for select using (true);

drop policy if exists "players publish their own levels" on public.levels;
create policy "players publish their own levels" on public.levels
    for insert to authenticated
    with check (author_id = auth.uid());

drop policy if exists "authors and admins delete levels" on public.levels;
create policy "authors and admins delete levels" on public.levels
    for delete to authenticated
    using (author_id = auth.uid() or public.is_admin());

drop policy if exists "players see their own likes" on public.level_likes;
create policy "players see their own likes" on public.level_likes
    for select to authenticated
    using (user_id = auth.uid());

-- Supabase grants everything to anon/authenticated by default; start from
-- nothing and allow only what the app needs.
revoke all on public.profiles, public.levels, public.level_likes from public, anon, authenticated;
grant usage on schema public to anon, authenticated;
grant select on public.profiles, public.levels to anon, authenticated;
grant insert, delete on public.levels to authenticated;
grant select on public.level_likes to authenticated;

revoke all on function public.is_admin() from public, anon, authenticated;
revoke all on function public.username_available(text) from public, anon, authenticated;
revoke all on function public.register_view(uuid) from public, anon, authenticated;
revoke all on function public.toggle_like(uuid) from public, anon, authenticated;
revoke all on function public.set_admin(text, boolean) from public, anon, authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.levels_before_insert() from public, anon, authenticated;
revoke all on function public.level_likes_count() from public, anon, authenticated;
grant execute on function public.is_admin() to anon, authenticated;
grant execute on function public.username_available(text) to anon, authenticated;
grant execute on function public.register_view(uuid) to anon, authenticated;
grant execute on function public.toggle_like(uuid) to authenticated;
grant execute on function public.set_admin(text, boolean) to authenticated;
