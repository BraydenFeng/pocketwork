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
