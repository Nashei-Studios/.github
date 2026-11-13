# 0002. Los enlaces de una PR se comprueban en la puerta, con lychee

- Estado: aceptado
- Fecha: 2026-11-12
- Seguimiento: Nashei-Studios/.github#19

## Contexto

El 12 de noviembre se entregó un enlace armado de memoria: `https://create.roblox.com/credentials`.
Responde 404; el correcto es `https://create.roblox.com/dashboard/credentials`, que responde 200.
Roblox devuelve el código HTTP real, así que un chequeo por estado habría atrapado el error.
Entró a tres archivos de `Nashei-Studios/studio` y nadie lo vio hasta que una persona lo siguió.

Restricciones:

- Los repos privados gastan minutos del plan gratis; el gate actual es un solo job a propósito (ADR 0001).
- Ya hay textos con enlaces que no deben fallar: plantillas con `{id}`, `<placeholder>`, redes que bloquean clientes automáticos.
- Un 403 o 429 de un sitio no prueba que el enlace esté muerto; un 404 o 410 sí.
- El runner es Linux, pero Victor y sus agentes corren lo mismo en Windows, así que la herramienta tiene que existir allí.

## Opciones

| Criterio | lychee 0.24.2 | markdown-link-check 3.15.0 | Script propio con `curl` |
|---|---|---|---|
| Velocidad | Binario Rust asíncrono; 5 enlaces en 1 s medidos en Windows | Node, revisa por archivo; la medición incluyó `npx` y no sirve para comparar | Depende de cómo se escriba |
| Falsos positivos | `accept` por códigos, `exclude` por regex, reintentos con espera | `aliveStatusCodes` e `ignorePatterns` en JSON; marcó `{id}` como 404 sin config | Se reinventa cada regla |
| Caché | `.lycheecache` con `max_cache_age`, cabe en `actions/cache` | No tiene | Se escribe a mano |
| Minutos de CI | Binario fijo con checksum, sin `npm install`, unos segundos | Exige Node y descarga de dependencias | Mínimo, pero se mantiene solo |
| Windows, macOS, Linux | Binarios oficiales para los tres; `scoop install lychee` | Funciona donde corra Node | Depende de `curl` |
| Entradas | Markdown, HTML y texto plano (sirve para `.luau` y `.ps1`) | Solo Markdown | Lo que se programe |
| Mantenimiento | Activo; última versión 0.24.2 y 4.1 mil estrellas | Activo; 3.15.0 de 2026-07-28 | Nuestro |

## Decisión

**lychee**, ejecutado como binario fijado por versión y checksum dentro del job del `pr-gate`, igual que
actionlint en `ci.yml`. No se usa `lychee-action`: descargar el binario evita una dependencia más y deja el
mismo patrón que ya revisa la org.

- Solo mira los archivos que la PR cambia (`pulls/N/files`, sin los borrados) con extensión
  `md, mdx, html, txt, luau, lua, ps1`. Una PR sin esos archivos no gasta ni la descarga.
- Cae con 4xx reales y con dominios que no resuelven. Tolera 403, 429 y 999 como respuesta anti-bot.
- La lista de exclusiones y los códigos aceptados viven en `sync/lychee.toml`, versionados. Un repo la
  reemplaza con su propio `.lychee.toml`. El workflow no lleva ninguna regla escrita.
- Va dentro del job existente (no suma otro job ni otro minuto mínimo) y se apaga con `link_check: false`.
- La caché de `actions/cache` guarda un día de respuestas buenas.

## Consecuencias

- Positivas: el enlace inventado cae en la PR, antes de que alguien lo siga; costo de minutos casi nulo
  cuando no hay Markdown; los agentes pueden correr la misma herramienta en local con la misma config.
- Negativas: se comprueba el archivo entero y no solo las líneas nuevas, así que tocar un archivo viejo
  con un enlace muerto obliga a arreglarlo; un sitio que dé 403 a todo (redes sociales) queda sin
  verificar; los enlaces relativos entre archivos no se miran (`scheme` solo web).
- Qué lo haría cambiar: si los falsos positivos por archivo entero molestan, pasar a comprobar solo las
  líneas añadidas del diff; si lychee deja de mantenerse, markdown-link-check cubre Markdown con la misma
  idea de config versionada.

## Relacionado

- La comprobación local, antes de que Victor actúe sobre un enlace, es un hook de Stop de la configuración
  de Victor (ADR 0028 de `~/.claude`).
