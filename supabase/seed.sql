set check_function_bodies = false;

insert into public.issue_types (name, icon, color, position)
values
  ('Tarea', 'check-square', '#3B82F6', 0),
  ('Historia', 'book-open', '#22C55E', 1),
  ('Bug', 'bug', '#EF4444', 2),
  ('Mejora', 'sparkles', '#A855F7', 3),
  ('Sub-tarea', 'list-tree', '#06B6D4', 4)
on conflict (name) do update
set
  icon = excluded.icon,
  color = excluded.color,
  position = excluded.position;

insert into public.priorities (name, level, color, position)
values
  ('Baja', 1, '#22C55E', 0),
  ('Media', 2, '#F59E0B', 1),
  ('Alta', 3, '#F97316', 2),
  ('Critica', 4, '#EF4444', 3)
on conflict (name) do update
set
  level = excluded.level,
  color = excluded.color,
  position = excluded.position;

insert into public.epic_phases (name, color, position)
values
  ('Backlog', '#64748B', 0),
  ('Descubrimiento', '#06B6D4', 1),
  ('Diseno', '#A855F7', 2),
  ('Desarrollo', '#3B82F6', 3),
  ('Validacion', '#F59E0B', 4),
  ('Cerrada', '#22C55E', 5)
on conflict (name) do update
set
  color = excluded.color,
  position = excluded.position;

insert into public.point_systems (name, description, is_default)
values (
  'Fibonacci',
  'Sistema de estimacion default para story points.',
  true
)
on conflict (name) do update
set
  description = excluded.description,
  is_default = excluded.is_default;

do $$
declare
  v_system_id uuid;
begin
  select id
    into v_system_id
  from public.point_systems
  where name = 'Fibonacci';

  delete from public.point_values
  where system_id = v_system_id;

  insert into public.point_values (system_id, value, numeric_value, position)
  values
    (v_system_id, '1', 1, 0),
    (v_system_id, '2', 2, 1),
    (v_system_id, '3', 3, 2),
    (v_system_id, '5', 5, 3),
    (v_system_id, '8', 8, 4),
    (v_system_id, '13', 13, 5),
    (v_system_id, '21', 21, 6);
end;
$$;
