-- Security and behaviour tests for backend/schema.sql (run by run_tests.sh).
\set ON_ERROR_STOP 1

create function pg_temp.act_as(uid text, r text) returns void language plpgsql as $$
begin
    perform set_config('request.jwt.claim.sub', coalesce(uid, ''), false);
    execute format('set role %I', r);
end $$;

-- Sign-ups (GoTrue inserts into auth.users as a privileged role)
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-00000000000a', 'alice@example.com', '{"username":"Alice"}'),
    ('00000000-0000-0000-0000-00000000000b', 'bob@example.com',   '{"username":"bob_99"}'),
    ('00000000-0000-0000-0000-00000000000c', 'carol@example.com', '{"username":"carol"}');

do $$ begin
    assert (select is_admin from public.profiles where username = 'Alice'), 'first account must be admin';
    assert not (select is_admin from public.profiles where username = 'bob_99'), 'bob must not be admin';
    assert (select count(*) from public.profiles) = 3, 'three profiles';
end $$;

-- Bad and duplicate usernames are rejected
do $$ begin
    begin
        insert into auth.users (email, raw_user_meta_data) values ('x@example.com', '{"username":"no"}');
        raise exception 'TEST FAILED: short username accepted';
    exception when raise_exception then
        if sqlerrm like 'TEST FAILED%' then raise; end if;
    end;
    begin
        insert into auth.users (email, raw_user_meta_data) values ('y@example.com', '{"username":"ALICE"}');
        raise exception 'TEST FAILED: duplicate username accepted';
    exception when raise_exception then
        if sqlerrm like 'TEST FAILED%' then raise; end if;
    end;
end $$;

-- Anonymous visitors: can browse and check names, cannot publish or like
select pg_temp.act_as(null, 'anon');
do $$ begin
    assert (select count(*) from public.profiles) = 3, 'anon can read profiles';
    assert public.username_available('dave'), 'dave is free';
    assert not public.username_available('CAROL'), 'carol is taken (case-insensitive)';
    assert not public.username_available('a b'), 'spaces are invalid';
    begin
        insert into public.levels (title, data) values ('Nope', '{}');
        raise exception 'TEST FAILED: anon published';
    exception when insufficient_privilege then null;
    end;
    begin
        perform public.toggle_like(gen_random_uuid());
        raise exception 'TEST FAILED: anon liked';
    exception when insufficient_privilege then null;
    end;
end $$;
reset role;

-- Bob publishes; forged author and counters are overwritten
select pg_temp.act_as('00000000-0000-0000-0000-00000000000b', 'authenticated');
insert into public.levels (id, author_id, title, data, views, likes)
values ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000c',
        '  Bob''s Cave  ', '{"version":1}', 999, 999);
do $$
declare l record;
begin
    select * into l from public.levels where id = '10000000-0000-0000-0000-000000000001';
    assert l.author_id = '00000000-0000-0000-0000-00000000000b', 'author forced to caller';
    assert l.views = 0 and l.likes = 0, 'counters start at zero';
    assert l.title = 'Bob''s Cave', 'title trimmed';
    begin
        update public.levels set likes = 500 where id = l.id;
        raise exception 'TEST FAILED: author edited counters';
    exception when insufficient_privilege then null;
    end;
    begin
        insert into public.levels (title, data) values ('', '{}');
        raise exception 'TEST FAILED: empty title accepted';
    exception when check_violation then null;
    end;
    begin
        insert into public.levels (title, data) values ('Array', '[1,2]');
        raise exception 'TEST FAILED: non-object data accepted';
    exception when check_violation then null;
    end;
    begin
        update public.profiles set is_admin = true where username = 'bob_99';
        raise exception 'TEST FAILED: bob made himself admin';
    exception when insufficient_privilege then null;
    end;
    begin
        perform public.set_admin('bob_99', true);
        raise exception 'TEST FAILED: non-admin used set_admin';
    exception when raise_exception then
        if sqlerrm like 'TEST FAILED%' then raise; end if;
    end;
end $$;
reset role;

-- Carol: views and likes work; she cannot delete Bob's level
select pg_temp.act_as('00000000-0000-0000-0000-00000000000c', 'authenticated');
do $$
declare r json;
begin
    assert public.register_view('10000000-0000-0000-0000-000000000001') = 1, 'first view';
    assert public.register_view('10000000-0000-0000-0000-000000000001') = 2, 'second view';
    r := public.toggle_like('10000000-0000-0000-0000-000000000001');
    assert (r ->> 'liked')::boolean and (r ->> 'likes')::int = 1, 'like recorded: ' || r::text;
    assert (select count(*) from public.level_likes) = 1, 'carol sees her like';
    r := public.toggle_like('10000000-0000-0000-0000-000000000001');
    assert not (r ->> 'liked')::boolean and (r ->> 'likes')::int = 0, 'unlike recorded: ' || r::text;
    r := public.toggle_like('10000000-0000-0000-0000-000000000001');
    assert (r ->> 'likes')::int = 1, 'liked again';
    delete from public.levels where id = '10000000-0000-0000-0000-000000000001';
    assert (select count(*) from public.levels) = 1, 'carol could not delete bob''s level';
    begin
        insert into public.level_likes (level_id, user_id)
        values ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000b');
        raise exception 'TEST FAILED: forged like row';
    exception when insufficient_privilege then null;
    end;
end $$;
reset role;

-- Anonymous views count too
select pg_temp.act_as(null, 'anon');
do $$ begin
    assert public.register_view('10000000-0000-0000-0000-000000000001') = 3, 'anon view';
end $$;
reset role;

-- Bob only sees his own likes (none)
select pg_temp.act_as('00000000-0000-0000-0000-00000000000b', 'authenticated');
do $$ begin
    assert (select count(*) from public.level_likes) = 0, 'likes are private';
end $$;
reset role;

-- Daily publish limit: 20 per player
select pg_temp.act_as('00000000-0000-0000-0000-00000000000c', 'authenticated');
do $$ begin
    for i in 1..20 loop
        insert into public.levels (title, data) values ('Level ' || i, '{"version":1}');
    end loop;
    begin
        insert into public.levels (title, data) values ('One too many', '{"version":1}');
        raise exception 'TEST FAILED: publish limit not enforced';
    exception when raise_exception then
        if sqlerrm like 'TEST FAILED%' then raise; end if;
    end;
    -- players can delete their own levels
    delete from public.levels where title = 'Level 1';
    assert (select count(*) from public.levels where title = 'Level 1') = 0, 'own level deleted';
end $$;
reset role;

-- Alice (admin) deletes anyone's level and can promote players
select pg_temp.act_as('00000000-0000-0000-0000-00000000000a', 'authenticated');
do $$ begin
    assert public.is_admin(), 'alice is admin';
    delete from public.levels where id = '10000000-0000-0000-0000-000000000001';
    assert (select count(*) from public.levels where id = '10000000-0000-0000-0000-000000000001') = 0,
        'admin deleted bob''s level';
    perform public.set_admin('bob_99', true);
end $$;
reset role;
do $$ begin
    assert (select is_admin from public.profiles where username = 'bob_99'), 'bob promoted';
    assert (select count(*) from public.level_likes) = 0, 'likes removed with the level';
end $$;

-- Deleting an account removes its profile, levels and likes
delete from auth.users where id = '00000000-0000-0000-0000-00000000000c';
do $$ begin
    assert (select count(*) from public.profiles where username = 'carol') = 0, 'profile removed';
    assert (select count(*) from public.levels) = 0, 'carol''s levels removed';
end $$;
