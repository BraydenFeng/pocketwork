-- One row per person: their whole routine library as JSON, the same shape the web editor and iPhone app keep locally.
-- Run this once in the Supabase SQL editor (Database → SQL). Safe to re-run.

create table if not exists public.libraries (
	user_id uuid primary key references auth.users (id) on delete cascade,
	library jsonb not null,
	updated_at timestamptz not null default now()
);

alter table public.libraries enable row level security;

drop policy if exists "people read their own library" on public.libraries;
create policy "people read their own library" on public.libraries
	for select using (auth.uid() = user_id);

drop policy if exists "people write their own library" on public.libraries;
create policy "people write their own library" on public.libraries
	for insert with check (auth.uid() = user_id);

drop policy if exists "people update their own library" on public.libraries;
create policy "people update their own library" on public.libraries
	for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Keeps updated_at honest without trusting the client.
create or replace function public.touch_updated_at() returns trigger language plpgsql as $$
begin
	new.updated_at = now();
	return new;
end;
$$;

drop trigger if exists libraries_touch_updated_at on public.libraries;
create trigger libraries_touch_updated_at before update on public.libraries
	for each row execute function public.touch_updated_at();

-- Optional status the phone shares when the person opts in: running state, minutes left today, a 30-day history.
-- Minute counts only; never app identities or locations. One row per user, replaced on every report.
create table if not exists public.routine_status (
	user_id uuid primary key references auth.users (id) on delete cascade,
	status jsonb not null,
	updated_at timestamptz not null default now()
);

alter table public.routine_status enable row level security;

drop policy if exists "people read their own status" on public.routine_status;
create policy "people read their own status" on public.routine_status
	for select using (auth.uid() = user_id);

drop policy if exists "people write their own status" on public.routine_status;
create policy "people write their own status" on public.routine_status
	for insert with check (auth.uid() = user_id);

drop policy if exists "people update their own status" on public.routine_status;
create policy "people update their own status" on public.routine_status
	for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "people delete their own status" on public.routine_status;
create policy "people delete their own status" on public.routine_status
	for delete using (auth.uid() = user_id);

drop trigger if exists routine_status_touch_updated_at on public.routine_status;
create trigger routine_status_touch_updated_at before update on public.routine_status
	for each row execute function public.touch_updated_at();

-- Server-verified Apple subscriptions. Clients may read their own plan, never grant it.
create table if not exists public.page_subscriptions (
	user_id uuid primary key references auth.users(id) on delete cascade,
	original_transaction_id text not null unique,
	pro boolean not null default false,
	expires_at timestamptz not null,
	verified_at timestamptz not null
);
alter table public.page_subscriptions enable row level security;
revoke all on public.page_subscriptions from anon, authenticated;
grant select on public.page_subscriptions to authenticated;
drop policy if exists "people read their own plan" on public.page_subscriptions;
create policy "people read their own plan" on public.page_subscriptions for select using (auth.uid() = user_id);

-- Enforced for web, native, and MCP writes alike. Lapsed accounts retain editing,
-- exporting, and deleting all existing pages. A new page needs a free slot or Pro.
create or replace function public.enforce_page_limit() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
	old_ids jsonb := '[]'::jsonb;
	page_count integer;
	new_ids integer;
	paid boolean;
begin
	if jsonb_typeof(new.library -> 'tools') is distinct from 'array' then
		raise exception 'Invalid page library';
	end if;
	page_count := jsonb_array_length(new.library -> 'tools');
	if page_count > 50 then raise exception 'This workspace supports up to 50 pages'; end if;
	if tg_op = 'UPDATE' then
		select coalesce(jsonb_agg(item -> 'document' -> 'id'), '[]'::jsonb) into old_ids from jsonb_array_elements(old.library -> 'tools') item;
	end if;
	select count(*) into new_ids from jsonb_array_elements(new.library -> 'tools') item where not (old_ids @> jsonb_build_array(item -> 'document' -> 'id'));
	select exists(select 1 from public.page_subscriptions where user_id = new.user_id and pro and expires_at > now() and verified_at > now() - interval '5 minutes') into paid;
	if page_count > 3 and new_ids > 0 and not paid then
		raise exception 'Your free plan holds 3 pages. Delete a page or refresh your Pro subscription in Account.' using errcode = 'P0001';
	end if;
	return new;
end;
$$;
revoke all on function public.enforce_page_limit() from public, anon, authenticated;
drop trigger if exists libraries_page_limit on public.libraries;
create trigger libraries_page_limit before insert or update on public.libraries for each row execute function public.enforce_page_limit();

-- Short-lived, single-use Sign in with Apple account-deletion handshakes.
create table if not exists public.account_deletion_requests (
	state_hash text primary key,
	user_id uuid not null unique references auth.users(id) on delete cascade,
	apple_subject text not null,
	nonce text not null,
	platform text not null check (platform in ('web', 'ios')),
	expires_at timestamptz not null
);
alter table public.account_deletion_requests enable row level security;
revoke all on public.account_deletion_requests from anon, authenticated;
