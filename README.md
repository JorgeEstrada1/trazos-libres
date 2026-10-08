# 🎨 Trazos Libres

Sistema web para la publicación de dibujos y la gestión de portafolio de artistas independientes.

Proyecto de grado — Unidad Educativa "Colegio Alemán del Sud", Tarija, Bolivia, 2026.

## Funciones

- Registro, inicio y cierre de sesión
- Perfil profesional del artista (biografía, especialidad, redes, formación, exposiciones, experiencia)
- Publicación, edición y eliminación de dibujos con categoría, técnica y etiquetas
- Marca de agua automática con el nombre del artista
- Exploración de obras en orden cronológico, con buscador y filtros
- Comentarios, "me gusta" y seguimiento de artistas, sin rankings públicos
- Reporte de obras
- Panel de administración: usuarios, publicaciones, categorías, comentarios y reportes

## Tecnologías

- **Interfaz:** HTML, CSS y JavaScript
- **Base de datos:** Supabase (PostgreSQL) con seguridad por filas (RLS)
- **Cuentas:** Supabase Auth (contraseñas con hash bcrypt)
- **Imágenes:** Supabase Storage
- **Publicación:** GitHub Pages

La estructura de la base de datos y sus reglas de seguridad están en [`supabase/esquema.sql`](supabase/esquema.sql).
