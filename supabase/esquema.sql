-- ==========================================
-- TRAZOS LIBRES - ESQUEMA DE BASE DE DATOS
-- Supabase (PostgreSQL)
-- ==========================================


-- ==========================================
-- TABLAS
-- ==========================================

create table if not exists public.categorias (
    id      bigint generated always as identity primary key,
    nombre  text not null unique check (char_length(nombre) between 1 and 40)
);


-- Perfil público de cada usuario.
-- La contraseña NO está aquí: la guarda Supabase Auth con hash bcrypt.
create table if not exists public.perfiles (
    id            uuid primary key references auth.users (id) on delete cascade,
    nombre        text not null check (char_length(nombre) between 1 and 80),
    artistico     text not null default '' check (char_length(artistico) <= 60),
    foto_url      text,
    categoria_id  bigint references public.categorias (id) on delete set null,
    rol           text not null default 'artista' check (rol in ('artista', 'admin')),
    estado        text not null default 'activo' check (estado in ('activo', 'suspendido')),
    ciudad        text not null default '' check (char_length(ciudad) <= 80),
    especialidad  text not null default '' check (char_length(especialidad) <= 120),
    bio           text not null default '' check (char_length(bio) <= 1000),
    instagram     text not null default '' check (char_length(instagram) <= 80),
    tiktok        text not null default '' check (char_length(tiktok) <= 80),
    otra_red      text not null default '' check (char_length(otra_red) <= 150),
    formacion     text not null default '' check (char_length(formacion) <= 1000),
    exposiciones  text not null default '' check (char_length(exposiciones) <= 1000),
    experiencia   text not null default '' check (char_length(experiencia) <= 1000),
    creado_en     timestamptz not null default now()
);


create table if not exists public.publicaciones (
    id            bigint generated always as identity primary key,
    autor_id      uuid not null references public.perfiles (id) on delete cascade,
    titulo        text not null check (char_length(titulo) between 1 and 80),
    descripcion   text not null default '' check (char_length(descripcion) <= 1000),
    imagen_url    text not null,
    imagen_ruta   text not null,
    categoria_id  bigint references public.categorias (id) on delete set null,
    tecnica       text not null check (char_length(tecnica) between 1 and 40),
    estado        text not null default 'visible' check (estado in ('visible', 'oculta')),
    creado_en     timestamptz not null default now()
);

create index if not exists publicaciones_creado_idx on public.publicaciones (creado_en desc);
create index if not exists publicaciones_autor_idx  on public.publicaciones (autor_id);


create table if not exists public.etiquetas (
    id      bigint generated always as identity primary key,
    nombre  text not null unique check (char_length(nombre) between 1 and 30)
);


create table if not exists public.publicacion_etiqueta (
    publicacion_id  bigint not null references public.publicaciones (id) on delete cascade,
    etiqueta_id     bigint not null references public.etiquetas (id) on delete cascade,
    primary key (publicacion_id, etiqueta_id)
);


create table if not exists public.comentarios (
    id              bigint generated always as identity primary key,
    publicacion_id  bigint not null references public.publicaciones (id) on delete cascade,
    usuario_id      uuid not null references public.perfiles (id) on delete cascade,
    texto           text not null check (char_length(texto) between 1 and 500),
    creado_en       timestamptz not null default now()
);


create table if not exists public.megusta (
    publicacion_id  bigint not null references public.publicaciones (id) on delete cascade,
    usuario_id      uuid not null references public.perfiles (id) on delete cascade,
    primary key (publicacion_id, usuario_id)
);


create table if not exists public.seguimientos (
    seguidor_id  uuid not null references public.perfiles (id) on delete cascade,
    seguido_id   uuid not null references public.perfiles (id) on delete cascade,
    primary key (seguidor_id, seguido_id),
    check (seguidor_id <> seguido_id)
);


create table if not exists public.reportes (
    id              bigint generated always as identity primary key,
    publicacion_id  bigint not null references public.publicaciones (id) on delete cascade,
    usuario_id      uuid not null references public.perfiles (id) on delete cascade,
    motivo          text not null check (char_length(motivo) between 1 and 80),
    detalle         text not null default '' check (char_length(detalle) <= 300),
    estado          text not null default 'pendiente' check (estado in ('pendiente', 'resuelto')),
    creado_en       timestamptz not null default now()
);


-- ==========================================
-- FUNCIONES DE APOYO
-- ==========================================

-- ¿El usuario que hace la consulta es administrador?
create or replace function public.es_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from public.perfiles
        where id = auth.uid() and rol = 'admin' and estado = 'activo'
    );
$$;


-- ¿El usuario que hace la consulta tiene la cuenta activa?
create or replace function public.es_activo()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from public.perfiles
        where id = auth.uid() and estado = 'activo'
    );
$$;


-- ¿El autor de una publicación tiene la cuenta activa?
create or replace function public.autor_activo(autor uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from public.perfiles
        where id = autor and estado = 'activo'
    );
$$;


-- ¿La publicación pertenece al usuario que consulta?
create or replace function public.es_mi_publicacion(pub bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1 from public.publicaciones
        where id = pub and autor_id = auth.uid()
    );
$$;


-- Al registrarse, se crea el perfil automáticamente
-- con los datos enviados desde el formulario.
create or replace function public.crear_perfil()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.perfiles (id, nombre, artistico, categoria_id)
    values (
        new.id,
        left(coalesce(nullif(trim(new.raw_user_meta_data ->> 'nombre'), ''), 'Artista'), 80),
        left(coalesce(trim(new.raw_user_meta_data ->> 'artistico'), ''), 60),
        (select id from public.categorias
         where id::text = nullif(new.raw_user_meta_data ->> 'categoria_id', ''))
    );
    return new;
end;
$$;

drop trigger if exists al_registrar_usuario on auth.users;

create trigger al_registrar_usuario
    after insert on auth.users
    for each row execute function public.crear_perfil();


-- Un artista no puede cambiarse el rol ni el estado a sí mismo.
create or replace function public.proteger_perfil()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    -- auth.uid() es nulo cuando el cambio se hace desde el panel de Supabase
    if auth.uid() is not null and not public.es_admin() then
        new.rol    := old.rol;
        new.estado := old.estado;
    end if;
    new.id := old.id;
    new.creado_en := old.creado_en;
    return new;
end;
$$;

drop trigger if exists proteger_perfil on public.perfiles;

create trigger proteger_perfil
    before update on public.perfiles
    for each row execute function public.proteger_perfil();


-- Un artista no puede volver a mostrar una obra que el admin ocultó.
create or replace function public.proteger_publicacion()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if auth.uid() is not null and not public.es_admin() then
        new.estado := old.estado;
    end if;
    new.autor_id  := old.autor_id;
    new.creado_en := old.creado_en;
    return new;
end;
$$;

drop trigger if exists proteger_publicacion on public.publicaciones;

create trigger proteger_publicacion
    before update on public.publicaciones
    for each row execute function public.proteger_publicacion();


-- Solo el administrador ve los correos de los usuarios.
create or replace function public.admin_listar_usuarios()
returns table (
    id uuid, correo text, nombre text, artistico text, foto_url text,
    rol text, estado text, obras bigint, creado_en timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
    if not public.es_admin() then
        raise exception 'No autorizado';
    end if;

    return query
        select p.id, u.email::text, p.nombre, p.artistico, p.foto_url,
               p.rol, p.estado,
               (select count(*) from public.publicaciones x where x.autor_id = p.id),
               p.creado_en
        from public.perfiles p
        join auth.users u on u.id = p.id
        order by p.creado_en desc;
end;
$$;


-- Las funciones internas no se pueden llamar desde la página
revoke execute on function public.crear_perfil() from public, anon, authenticated;
revoke execute on function public.proteger_perfil() from public, anon, authenticated;
revoke execute on function public.proteger_publicacion() from public, anon, authenticated;
revoke execute on function public.admin_listar_usuarios() from public, anon;


-- ==========================================
-- SEGURIDAD POR FILAS (RLS)
-- ==========================================

alter table public.categorias           enable row level security;
alter table public.perfiles             enable row level security;
alter table public.publicaciones        enable row level security;
alter table public.etiquetas            enable row level security;
alter table public.publicacion_etiqueta enable row level security;
alter table public.comentarios          enable row level security;
alter table public.megusta              enable row level security;
alter table public.seguimientos         enable row level security;
alter table public.reportes             enable row level security;


-- CATEGORÍAS: todos leen, solo el admin modifica
create policy "categorias_leer"     on public.categorias for select using (true);
create policy "categorias_insertar" on public.categorias for insert with check (public.es_admin());
create policy "categorias_editar"   on public.categorias for update using (public.es_admin());
create policy "categorias_borrar"   on public.categorias for delete using (public.es_admin());


-- PERFILES: públicos; cada uno edita el suyo; el admin todos
create policy "perfiles_leer"   on public.perfiles for select using (true);
create policy "perfiles_editar" on public.perfiles for update
    using (id = auth.uid() or public.es_admin())
    with check (id = auth.uid() or public.es_admin());

-- El admin puede eliminar una cuenta: se borran en cascada
-- sus obras, comentarios, me gusta, seguimientos y reportes
create policy "perfiles_borrar" on public.perfiles for delete
    using (public.es_admin() and id <> auth.uid());


-- PUBLICACIONES
create policy "publicaciones_leer" on public.publicaciones for select using (
    (estado = 'visible' and public.autor_activo(autor_id))
    or autor_id = auth.uid()
    or public.es_admin()
);
create policy "publicaciones_insertar" on public.publicaciones for insert
    with check (autor_id = auth.uid() and public.es_activo());
create policy "publicaciones_editar" on public.publicaciones for update
    using (autor_id = auth.uid() or public.es_admin());
create policy "publicaciones_borrar" on public.publicaciones for delete
    using (autor_id = auth.uid() or public.es_admin());


-- ETIQUETAS
create policy "etiquetas_leer"     on public.etiquetas for select using (true);
create policy "etiquetas_insertar" on public.etiquetas for insert
    with check (auth.uid() is not null and public.es_activo());

create policy "pub_etiqueta_leer" on public.publicacion_etiqueta for select using (true);
create policy "pub_etiqueta_insertar" on public.publicacion_etiqueta for insert
    with check (public.es_mi_publicacion(publicacion_id));
create policy "pub_etiqueta_borrar" on public.publicacion_etiqueta for delete
    using (public.es_mi_publicacion(publicacion_id) or public.es_admin());


-- COMENTARIOS
create policy "comentarios_leer" on public.comentarios for select using (true);
create policy "comentarios_insertar" on public.comentarios for insert
    with check (usuario_id = auth.uid() and public.es_activo());
create policy "comentarios_borrar" on public.comentarios for delete using (
    usuario_id = auth.uid()
    or public.es_mi_publicacion(publicacion_id)
    or public.es_admin()
);


-- ME GUSTA: cada uno ve los suyos; el autor ve los de su obra.
-- Así nadie puede armar un ranking público.
create policy "megusta_leer" on public.megusta for select using (
    usuario_id = auth.uid()
    or public.es_mi_publicacion(publicacion_id)
    or public.es_admin()
);
create policy "megusta_insertar" on public.megusta for insert
    with check (usuario_id = auth.uid() and public.es_activo());
create policy "megusta_borrar" on public.megusta for delete
    using (usuario_id = auth.uid());


-- SEGUIMIENTOS: los números solo los ve el propio artista
create policy "seguimientos_leer" on public.seguimientos for select using (
    seguidor_id = auth.uid() or seguido_id = auth.uid() or public.es_admin()
);
create policy "seguimientos_insertar" on public.seguimientos for insert
    with check (seguidor_id = auth.uid() and public.es_activo());
create policy "seguimientos_borrar" on public.seguimientos for delete
    using (seguidor_id = auth.uid());


-- REPORTES
create policy "reportes_leer" on public.reportes for select
    using (usuario_id = auth.uid() or public.es_admin());
create policy "reportes_insertar" on public.reportes for insert
    with check (usuario_id = auth.uid() and public.es_activo());
create policy "reportes_editar" on public.reportes for update using (public.es_admin());
create policy "reportes_borrar" on public.reportes for delete using (public.es_admin());


-- ==========================================
-- ALMACENAMIENTO DE IMÁGENES
-- Cada usuario sube solo a su propia carpeta: obras/<id>/...
-- ==========================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('obras', 'obras', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
    set public = true,
        file_size_limit = excluded.file_size_limit,
        allowed_mime_types = excluded.allowed_mime_types;

-- (las imágenes se ven por su URL pública; esta política
--  solo hace falta para poder reemplazarlas o borrarlas)
create policy "obras_leer" on storage.objects for select to authenticated
    using (
        bucket_id = 'obras'
        and ((storage.foldername(name))[1] = auth.uid()::text or public.es_admin())
    );

create policy "obras_subir" on storage.objects for insert to authenticated
    with check (
        bucket_id = 'obras'
        and (storage.foldername(name))[1] = auth.uid()::text
        and public.es_activo()
    );

create policy "obras_actualizar" on storage.objects for update to authenticated
    using (bucket_id = 'obras' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "obras_borrar" on storage.objects for delete to authenticated
    using (
        bucket_id = 'obras'
        and ((storage.foldername(name))[1] = auth.uid()::text or public.es_admin())
    );


-- ==========================================
-- DATOS INICIALES
-- ==========================================

insert into public.categorias (nombre) values
    ('Dibujo tradicional'),
    ('Arte digital'),
    ('Pintura'),
    ('Ilustración'),
    ('Fanart'),
    ('Anime y manga'),
    ('Bocetos'),
    ('Otro')
on conflict (nombre) do nothing;


-- Para convertir una cuenta en administrador
-- (después de registrarla desde la página):
--
-- update public.perfiles set rol = 'admin'
-- where id = (select id from auth.users where email = 'correo@ejemplo.com');
