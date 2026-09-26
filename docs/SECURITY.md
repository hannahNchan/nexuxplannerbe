# NexusPlanner Backend Security

Ultima revision: 2026-09-26

## 1. Proposito

Este documento explica los controles de seguridad que existen hoy en el repositorio y los riesgos confirmados al leer migraciones, Edge Functions, configuracion y CLI. No describe una arquitectura idealizada.

La seguridad depende de varias capas simultaneas:

1. Supabase Auth autentica al usuario y emite JWT.
2. PostgREST propaga la identidad a PostgreSQL.
3. RLS filtra filas para lecturas y mutaciones directas.
4. Los command RPCs vuelven a validar permisos e invariantes.
5. Edge Functions separan commands HTTP de consultas de datos.
6. Storage policies controlan objetos.
7. El worker usa una credencial de maquina distinta de los JWT de usuario.

Ninguna capa debe asumirse como sustituto automatico de las demas.

## 2. Fronteras de confianza

| Zona | Confianza | Credencial |
| --- | --- | --- |
| Navegador/frontend | No confiable | Publishable key + JWT de usuario |
| CLI de usuario | No confiable | Publishable key + JWT de usuario |
| Auth/Data API/Edge gateway | Publica | Valida protocolo y JWT |
| PostgreSQL/RPCs | Privada | `auth.uid()`, RLS y permisos SQL |
| Edge Functions de usuario | Semiconfiable | Reenvian Authorization del usuario |
| `job-worker` | Servicio privilegiado | Service role + secreto del worker |
| Raspberry/host | Administrativa | Acceso SSH, archivos de entorno y volumen |
| GitHub | Publicable | Solo codigo, migraciones y seed sin datos reales |

El frontend nunca debe contener la service-role key, la contrasena de PostgreSQL ni el secreto del worker.

## 3. Inventario de secretos

| Variable | Donde vive | Quien la usa | Puede publicarse |
| --- | --- | --- | --- |
| `SUPABASE_URL` | Entorno backend/funciones | Edge Functions y herramientas | La URL puede ser publica |
| `SUPABASE_ANON_KEY` o publishable key | Frontend y CLI | Sesiones de usuario | Si; esta disenada para clientes |
| `SUPABASE_SERVICE_ROLE_KEY` | Solo backend/worker | Operaciones privilegiadas | No |
| `SUPABASE_DB_PASSWORD` | Entorno administrativo | CLI/migraciones remotas | No |
| `JOB_WORKER_SECRET` | Worker y scheduler | Autorizacion de invocacion | No |
| JWT de usuario | Memoria/config CLI | Usuario autenticado | No |
| S3 secret key local | Host de Storage | API compatible S3 | No |

Reglas:

- `.env` esta ignorado por Git y debe seguir asi.
- `.env.example` solo contiene nombres y placeholders.
- No pegar secretos en issues, logs, commits ni documentacion.
- Si una clave real se expone, rotarla aunque la instalacion sea temporal.
- En produccion, usar el gestor de secretos del despliegue o `supabase secrets`, no archivos compartidos.

## 4. Autenticacion

La configuracion local actual permite signup por email, no exige confirmacion de email y deshabilita proveedores sociales, telefono, anonimato y MFA. Esto simplifica desarrollo, pero no es una politica de produccion.

`site_url` y redirects apuntan al frontend local. Antes de desplegar se deben registrar explicitamente los origenes publicos autorizados.

La sesion se representa por un JWT enviado como:

```http
Authorization: Bearer <access-token>
```

La publishable key identifica el proyecto y habilita el acceso publico a la API; no autentica por si sola a una persona. La identidad valida proviene del JWT.

## 5. Modelo de roles

### Organizacion

| Rol | Capacidades esperadas |
| --- | --- |
| `owner` | Administrar organizacion, miembros y eliminacion |
| `admin` | Administrar identidad y miembros, con limites de ownership |
| `member` | Ver la organizacion y participar en proyectos permitidos |

`current_organization_role()`, `can_view_organization()` y `can_manage_organization()` centralizan la evaluacion.

### Proyecto

| Rol | Capacidades esperadas |
| --- | --- |
| `owner` | Configurar proyecto, membresia y automatizaciones |
| `member` | Mutar trabajo ordinario |

`current_project_role()`, `can_view_project()`, `can_mutate_project()` y `can_manage_project()` son los helpers principales.

Un proyecto `organization` puede ser visible para miembros de la organizacion aun sin fila explicita en `project_members`; uno `private` requiere membresia.

## 6. RLS realmente habilitado

El baseline habilita RLS en:

- `activity_events`
- `automation_rules`
- `automation_runs`
- `boards`
- `column_order`
- `columns`
- `command_jobs`
- `editor_notes`
- `epic_dependencies`
- `organization_invitations`
- `organization_members`
- `organizations`
- `project_invitations`
- `project_members`
- `project_tags`
- `projects`
- `roadmap_settings`
- `sprint_reports`
- `sprints`
- `task_dependencies`
- `tasks`
- `user_notifications`
- `user_profiles`

El baseline no habilita RLS en:

- `epics`
- `epic_phases`
- `issue_types`
- `priorities`
- `point_systems`
- `point_values`

Esto es importante: existen policies declaradas para `epics`, pero una policy no se aplica mientras RLS no este habilitado en la tabla. Ademas, el baseline concede privilegios amplios a `anon`, `authenticated` y `service_role`. Por ello estas tablas no deben considerarse protegidas solo porque haya una policy escrita.

Los catalogos pueden ser publicamente legibles por diseno, pero su escritura debe limitarse explicitamente. `epics` contiene datos de proyecto y necesita una revision prioritaria de RLS/grants.

## 7. Politicas por dominio

### Organizaciones y proyectos

Las policies usan membresia, invitaciones y helpers de rol. Los commands refuerzan reglas como conservar un owner y exigir membresia de organizacion antes de membresia de proyecto.

### Tareas, columnas y sprints

Las policies acumuladas incluyen reglas actuales por proyecto y reglas historicas por `user_id`/`board_id`. Esa superposicion aumenta la superficie de acceso: en PostgreSQL las policies permisivas se combinan con OR. Al cambiar este dominio se deben revisar todas las policies de la tabla, no solo la mas reciente.

### Perfiles

Un usuario puede insertar y actualizar su perfil. Los perfiles son visibles para usuarios autenticados. No guardar alli datos que deban ser privados frente a otros miembros.

### Notificaciones

El usuario autenticado solo puede seleccionar y actualizar sus propias notificaciones. La creacion ocurre mediante funciones/triggers con privilegios controlados.

### Jobs

`command_jobs` tiene RLS y no expone policies de usuario ordinarias. Su operacion normal es por funciones privilegiadas y service role.

## 8. Commands SQL y `SECURITY DEFINER`

Las mutaciones importantes usan funciones `SECURITY DEFINER`. Eso permite encapsular transacciones y atravesar RLS, pero tambien exige disciplina:

- `search_path` debe fijarse a `public, pg_temp` o equivalente seguro.
- La funcion debe leer `auth.uid()` y rechazar sesiones ausentes cuando sea un command de usuario.
- Debe validar el rol antes de tocar datos.
- Los parametros UUID nunca deben considerarse autorizacion.
- Debe usar nombres de esquema explicitos.
- Debe concederse `EXECUTE` solo a roles necesarios.
- Debe registrar actividad despues de una mutacion exitosa.

Los commands existentes siguen en general este patron, pero cualquier funcion nueva requiere revision individual.

## 9. Matriz de Edge Functions

| Funcion | Autorizacion | Privilegio DB | Proposito |
| --- | --- | --- | --- |
| `workspace-commands` | JWT usuario | Cliente con token usuario | Organizaciones, invitaciones, membresia y proyecto |
| `task-commands` | JWT usuario | Cliente con token usuario | Crear, asignar, mover y planificar tareas |
| `epic-commands` | JWT usuario | Cliente con token usuario | Crear epicas |
| `sprint-commands` | JWT usuario | Cliente con token usuario | Crear y cerrar sprints |
| `notification-commands` | JWT usuario | Cliente con token usuario | Marcar todas como leidas |
| `agent-commands` | Depende del gateway/config | Cliente con token recibido | Validar/aplicar planes de agente |
| `job-worker` | `x-job-worker-secret` | Service role | Procesar cola |

Las funciones de usuario reenvian `Authorization` a Supabase para conservar `auth.uid()` y RLS. No deben cambiarse a service role para "resolver" errores de permisos.

`agent-commands` permite validar un plan sin consultar datos, pero el `config.toml` no declara actualmente `verify_jwt = false` para esa funcion. Por tanto el gateway local puede exigir JWT incluso para `validate_plan`. Documentar o configurar deliberadamente ese contrato antes de exponerlo.

## 10. CORS y exposicion HTTP

El helper compartido responde actualmente con `Access-Control-Allow-Origin: *`. Esto no otorga acceso a la base por si mismo porque siguen aplicando JWT/RLS, pero permite que cualquier origen intente invocar las funciones.

Para un despliegue publico conviene restringir origenes a dominios conocidos, especialmente si en el futuro se habilitan cookies o endpoints menos protegidos. Los preflight `OPTIONS` deben seguir funcionando.

Las respuestas de error no deben incluir stack traces, queries, secretos o contenido de otras filas. Los logs del servidor pueden tener mas detalle, pero tambien deben evitar tokens.

## 11. Seguridad de Storage

Los tres buckets son publicos para lectura. Eso significa que el control principal aplica a escritura/eliminacion, no a confidencialidad del archivo.

### `project-assets`

La ruta codifica el proyecto u organizacion y las policies comprueban `can_manage_project()` o `can_manage_organization()`. Cambiar la convencion de paths rompe el control aunque la UI siga subiendo archivos.

### `avatars`

El primer segmento debe ser el UUID del usuario autenticado. Cada usuario administra su propio prefijo.

### `task-images`

La policy versionada permite a cualquier usuario autenticado administrar objetos del bucket. No valida que el path corresponda a una tarea/proyecto visible. Esta es una brecha de aislamiento confirmada y debe corregirse antes de considerar Storage multi-tenant robusto.

### Eliminacion

No borrar directamente filas de `storage.objects`. La API de Storage realiza el borrado de objeto y metadatos. El error SQL que impide borrado directo es una proteccion intencional.

## 12. Worker y service role

`job-worker` es la unica Edge Function que necesita service role. Tambien exige `JOB_WORKER_SECRET` mediante header. Ambas barreras son necesarias:

```http
x-job-worker-secret: <secret>
```

La invocacion debe venir de un scheduler o proceso controlado. No se debe llamar desde el navegador.

Riesgos operativos actuales:

- Varios tipos de jobs reconocidos se marcan completados sin ejecutar una integracion externa.
- Jobs de email son no-op cuando `EMAIL_PROVIDER_ENABLED` no es `true`; si se activa, la funcion falla porque el proveedor aun no esta implementado.
- `activity.organization_deleted` se encola al borrar una organizacion, pero no esta en la lista de tipos reconocidos por el worker.
- No existe scheduler versionado para invocar el worker o mantenimiento.

Estos comportamientos deben interpretarse como scaffolding, no como entrega garantizada.

## 13. CLI

La CLI usa publishable key y token de usuario, lo cual conserva RLS. Su archivo por defecto `~/.nexusplanner/config.json` guarda configuracion y token en texto plano.

Consecuencias:

- Proteger permisos del archivo en equipos compartidos.
- No sincronizarlo con dotfiles publicos.
- `nexus auth token` imprime el token; no usarlo en logs o demos grabadas.
- Preferir variables de entorno efimeras en CI.
- Revocar/cerrar sesion si el equipo se pierde.

La CLI no debe aceptar service role como reemplazo del login de usuario.

## 14. Configuracion local que no debe copiarse a produccion

`supabase/config.toml` esta optimizado para desarrollo:

- API y Studio en loopback.
- TLS deshabilitado.
- confirmacion de email deshabilitada.
- red de base sin restricciones explicitas.
- Mailpit local.
- buckets publicos.
- redirects locales.

Un reverse proxy publico debe terminar TLS y reenviar solo los puertos necesarios. PostgreSQL, Studio, Mailpit, analytics y el inspector no deben exponerse a Internet.

## 15. Hallazgos confirmados y prioridad

### Alta

1. `epics` no tiene RLS habilitado aunque posee datos multi-tenant y policies declaradas.
2. Los catalogos no tienen RLS y reciben grants amplios; al menos la escritura debe restringirse.
3. `task-images` permite escritura/eliminacion a cualquier usuario autenticado sin comprobar proyecto.

### Media

1. Policies actuales e historicas se superponen en varias tablas; una policy antigua puede ampliar acceso por OR.
2. CORS permite cualquier origen.
3. `agent-commands` no documenta claramente si validar planes es publico o requiere JWT.
4. `workspace-commands` importa `@supabase/supabase-js@2` sin version exacta, mientras otras funciones fijan `2.110.7`.
5. El token CLI se almacena en texto plano.

### Operativa

1. No hay cron/scheduler versionado para jobs, mantenimiento o deadlines.
2. Parte del worker confirma jobs sin trabajo externo real.
3. Existe un tipo de job de eliminacion de organizacion no reconocido.
4. La funcion de perfil existe sin trigger de Auth versionado.

Estos hallazgos son documentacion del estado actual, no cambios aplicados. Deben resolverse mediante migraciones y pruebas separadas para no alterar la base personal de manera sorpresiva.

## 16. Checklist para cambios de seguridad

Antes de publicar una migracion o endpoint:

1. Identificar actor, recurso, organizacion y proyecto.
2. Definir lectura, insercion, update y delete por separado.
3. Confirmar si RLS esta habilitado en la tabla.
4. Revisar todas las policies existentes y su combinacion permisiva/restrictiva.
5. Revisar grants a `anon` y `authenticated`.
6. Evitar service role salvo proceso backend controlado.
7. Fijar `search_path` en funciones privilegiadas.
8. Probar como usuario autorizado, usuario de otro tenant, anonimo y service role.
9. Probar Storage con rutas validas y rutas de otro proyecto.
10. Verificar que errores no filtren datos.
11. Ejecutar `supabase db reset` solo en local desechable.
12. Actualizar esta documentacion.

## 17. Consultas de auditoria

```sql
-- RLS habilitado o no
select tablename, rowsecurity
from pg_tables
where schemaname = 'public'
order by tablename;

-- Grants de tablas
select table_name, grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and grantee in ('anon', 'authenticated', 'service_role')
order by table_name, grantee, privilege_type;

-- Funciones SECURITY DEFINER
select n.nspname as schema_name,
       p.proname,
       p.prosecdef,
       p.proconfig
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.prosecdef
order by p.proname;
```

Ejecutar estas consultas en una copia o con una cuenta administrativa de solo inspeccion. No incluir su salida con datos sensibles en el repositorio.
