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

-- Progress: saved per player, the best result always wins, private, and
-- cleaned up with the level or account
select pg_temp.act_as('00000000-0000-0000-0000-00000000000b', 'authenticated');
insert into public.levels (id, title, data) values ('abcdef00-0000-0000-0000-0000000000ab', 'Case Cave', '{"version":1}');
reset role;
select pg_temp.act_as('00000000-0000-0000-0000-00000000000c', 'authenticated');
do $$
declare r jsonb;
begin
    r := public.sync_progress('{"1": {"stars": 2, "bestTime": 20.5}, "2": {"stars": 3, "bestTime": 9}}',
                              '{"10000000-0000-0000-0000-000000000001": 31.25}');
    assert r -> 'campaign' -> '1' = '{"stars": 2, "bestTime": 20.5}', 'level 1 saved: ' || r::text;
    assert r -> 'community' -> '10000000-0000-0000-0000-000000000001' = '31.25', 'clear saved: ' || r::text;

    -- stars and time improve separately; worse results never replace better ones
    r := public.sync_progress('{"1": {"stars": 3, "bestTime": 25}, "2": {"stars": 1, "bestTime": 8.5}}',
                              '{"10000000-0000-0000-0000-000000000001": 40}');
    assert r -> 'campaign' -> '1' = '{"stars": 3, "bestTime": 20.5}', 'more stars, time kept: ' || r::text;
    assert r -> 'campaign' -> '2' = '{"stars": 3, "bestTime": 8.5}', 'faster, stars kept: ' || r::text;
    assert r -> 'community' -> '10000000-0000-0000-0000-000000000001' = '31.25', 'slower clear ignored';

    -- anything that doesn't look right is skipped without an error
    r := public.sync_progress(
        '{"0": {"stars": 1, "bestTime": 5}, "01": {"stars": 1, "bestTime": 5}, "x": {"stars": 1, "bestTime": 5},
          "3": {"stars": 4, "bestTime": 5}, "4": {"stars": "3", "bestTime": 5}, "5": {"stars": 1, "bestTime": -1},
          "6": {"stars": 1.5, "bestTime": 5}, "7": 3, "8": {"stars": 1, "bestTime": 1e9}, "9": {"stars": 1}}',
        '{"not-a-uuid": 5, "20000000-0000-0000-0000-000000000009": 5, "abcdef00-0000-0000-0000-0000000000AB": "fast"}');
    assert (select count(*) from jsonb_object_keys(r -> 'campaign')) = 2, 'junk campaign skipped: ' || r::text;
    assert (select count(*) from jsonb_object_keys(r -> 'community')) = 1, 'junk clears skipped: ' || r::text;
    assert public.sync_progress(null, null) = r, 'nulls are fine';

    -- the same level written two ways counts once (best time)
    r := public.sync_progress('{}', '{"abcdef00-0000-0000-0000-0000000000AB": 12, "abcdef00-0000-0000-0000-0000000000ab": 11}');
    assert r -> 'community' -> 'abcdef00-0000-0000-0000-0000000000ab' = '11', 'case duplicates merged: ' || r::text;

    -- Settings -> Reset progress clears the campaign (and only the campaign)
    assert (r ->> 'resets')::int = 0 and not (r ->> 'replaced')::boolean, 'no resets yet: ' || r::text;
    r := public.sync_progress('{"5": {"stars": 1, "bestTime": 50}}', '{}', true, 0);
    assert r -> 'campaign' = '{"5": {"stars": 1, "bestTime": 50}}', 'campaign reset: ' || r::text;
    assert (r ->> 'resets')::int = 1, 'reset counted: ' || r::text;
    assert (select count(*) from jsonb_object_keys(r -> 'community')) = 2, 'clears kept on reset';

    -- another device that synced before the reset doesn't bring the old records back
    r := public.sync_progress('{"1": {"stars": 3, "bestTime": 14}, "5": {"stars": 3, "bestTime": 10}}',
                              '{"abcdef00-0000-0000-0000-0000000000ab": 9}', false, 0);
    assert (r ->> 'replaced')::boolean, 'old device told to replace: ' || r::text;
    assert r -> 'campaign' = '{"5": {"stars": 1, "bestTime": 50}}', 'old records ignored: ' || r::text;
    assert r -> 'community' -> 'abcdef00-0000-0000-0000-0000000000ab' = '9', 'clears still count: ' || r::text;
    -- once it has seen the reset (or never synced before) it merges as usual
    r := public.sync_progress('{"5": {"stars": 3, "bestTime": 10}}', '{}', false, 1);
    assert not (r ->> 'replaced')::boolean and r -> 'campaign' = '{"5": {"stars": 3, "bestTime": 10}}', 'merged: ' || r::text;
    r := public.sync_progress('{"6": {"stars": 2, "bestTime": 30}}', '{}');
    assert not (r ->> 'replaced')::boolean and (select count(*) from jsonb_object_keys(r -> 'campaign')) = 2, 'new device merges: ' || r::text;

    begin
        perform count(*) from public.campaign_progress;
        raise exception 'TEST FAILED: progress table readable';
    exception when insufficient_privilege then null;
    end;
    begin
        insert into public.community_clears (user_id, level_id, best_time)
        values ('00000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-000000000001', 1);
        raise exception 'TEST FAILED: forged clear';
    exception when insufficient_privilege then null;
    end;
end $$;
reset role;

select pg_temp.act_as('00000000-0000-0000-0000-00000000000b', 'authenticated');
do $$ begin
    assert public.sync_progress() = '{"campaign": {}, "community": {}, "resets": 0, "replaced": false}',
        'bob does not see carol''s progress';
end $$;
reset role;

select pg_temp.act_as(null, 'anon');
do $$ begin
    perform public.sync_progress();
    raise exception 'TEST FAILED: anon saved progress';
exception when insufficient_privilege then null;
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
    assert (select count(*) from public.community_clears
            where level_id = '10000000-0000-0000-0000-000000000001') = 0, 'clears removed with the level';
    assert (select count(*) from public.community_clears) = 1, 'other clears kept';
    assert (select count(*) from public.campaign_resets) = 1, 'carol''s reset count kept';
end $$;

-- Deleting an account removes its profile, levels and likes
delete from auth.users where id = '00000000-0000-0000-0000-00000000000c';
do $$ begin
    assert (select count(*) from public.profiles where username = 'carol') = 0, 'profile removed';
    assert (select count(*) from public.levels where author_id = '00000000-0000-0000-0000-00000000000c') = 0,
        'carol''s levels removed';
    assert (select count(*) from public.campaign_progress) = 0, 'carol''s progress removed';
    assert (select count(*) from public.community_clears) = 0, 'carol''s clears removed';
    assert (select count(*) from public.campaign_resets) = 0, 'carol''s reset count removed';
end $$;
