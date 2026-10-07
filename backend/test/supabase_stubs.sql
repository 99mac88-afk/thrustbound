-- Minimal stand-ins for the parts of Supabase that schema.sql relies on, so
-- the schema and its security rules can be tested on plain PostgreSQL.
create role anon nologin;
create role authenticated nologin;
-- Supabase runs dashboard SQL as "postgres", which owns the tables but is not
-- a superuser. "owner" plays that part here.
create role owner nologin nosuperuser nobypassrls;
grant anon, authenticated to owner;
grant create, usage on schema public to owner;
grant usage on schema public to anon, authenticated;

create schema auth;
create table auth.users (
    id                 uuid primary key default gen_random_uuid(),
    email              text,
    raw_user_meta_data jsonb not null default '{}'::jsonb
);
create function auth.uid() returns uuid
language sql stable
as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth to anon, authenticated, owner;
grant execute on function auth.uid() to anon, authenticated, owner;
grant references, trigger, select on auth.users to owner;
