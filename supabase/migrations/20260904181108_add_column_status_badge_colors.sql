alter table public.columns
  add column if not exists color text not null default '#64748B';

alter table public.columns
  drop constraint if exists columns_color_palette_check;

alter table public.columns
  add constraint columns_color_palette_check
  check (
    color in (
      '#64748B',
      '#3B82F6',
      '#06B6D4',
      '#14B8A6',
      '#22C55E',
      '#84CC16',
      '#F59E0B',
      '#F97316',
      '#EF4444',
      '#EC4899',
      '#A855F7',
      '#6366F1'
    )
  );

update public.columns
set color = case replace(lower(name), 'ó', 'o')
  when 'por hacer' then '#64748B'
  when 'en progreso' then '#3B82F6'
  when 'en revision' then '#A855F7'
  when 'hecho' then '#22C55E'
  else color
end
where color = '#64748B'
   or replace(lower(name), 'ó', 'o') in ('por hacer', 'en progreso', 'en revision', 'hecho');

drop policy if exists "Project editors can update column badge colors" on public.columns;
create policy "Project editors can update column badge colors"
  on public.columns
  for update
  to authenticated
  using (public.can_mutate_project(project_id))
  with check (public.can_mutate_project(project_id));

grant update (color) on public.columns to authenticated;
