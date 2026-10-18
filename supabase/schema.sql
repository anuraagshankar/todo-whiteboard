-- Whiteboard Todos: one row per note, shared by the web app and the Apple apps.
-- No login: the publishable key (built into the apps) can read and edit every note.

create table notes (
  id uuid primary key default gen_random_uuid(),
  title text not null default '',
  mode text not null default 'text' check (mode in ('text', 'checklist')),
  text text not null default '',
  items jsonb not null default '[]', -- [{ text, done, level }], level 0 or 1
  x double precision, -- null until first placed on the Mac canvas
  y double precision,
  w double precision not null default 288,
  h double precision, -- null while the note grows with its content
  z integer not null default 0,
  position double precision not null default extract(epoch from now()), -- list order on the iPhone and widget
  created_at timestamptz not null default now()
);

alter table notes enable row level security;
create policy "Anyone with the key can read and edit notes" on notes for all to anon using (true) with check (true);
grant select, insert, update, delete on notes to anon;

-- Realtime: other devices get every insert, update and delete as it happens.
alter publication supabase_realtime add table notes;
