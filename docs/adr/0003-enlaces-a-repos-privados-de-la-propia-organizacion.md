# 0003. Los enlaces a repos privados de la propia organización no se comprueban en la puerta

- Estado: aceptado
- Fecha: 2026-11-13
- Seguimiento: Nashei-Studios/.github#26
- Complementa a 0002 (deja de regir su frase "el workflow no lleva ninguna regla escrita": lleva una, derivada del runner)

## Contexto

Los repos de Nashei-Studios son privados. lychee corre en el `pr-gate` sin sesión de GitHub, así que
cada `https://github.com/Nashei-Studios/<repo>` responde 404 y el gate falla, aunque el repo exista.
Pasó en `Nashei-Studios/studio#98`: seis enlaces del README a repos de la org, todos vivos, rechazados.

El `GITHUB_TOKEN` del job solo alcanza al repo que corre el workflow, no a los demás de la org. Darle a
lychee un token de organización exigiría un secreto por repo y pasarle credenciales a un binario externo.

## Opciones evaluadas

| Opción | Costo | Qué se pierde |
|---|---|---|
| Regex `Nashei-Studios` en `sync/lychee.toml` | Una línea | Lista fija: otra organización que herede el gate tiene que editarla |
| `--exclude` en la línea de comandos | Una línea | Reemplaza la lista del config en vez de sumarse (lychee 0.24.2) |
| `.lycheeignore` escrito por el job con `GITHUB_REPOSITORY_OWNER` | Dos líneas | Los enlaces internos de la org quedan sin verificar por máquina |
| Token de organización para lychee | Un secreto por repo, rotación | Credencial en manos de un binario de terceros |

## Decisión

El job escribe en `.lycheeignore` el patrón `^https?://github\.com/<dueño>(/|$)`, con el dueño tomado del
runner. `.lycheeignore` se suma a las exclusiones del config; `--exclude` las habría reemplazado.
Si el repo trae su propio `.lycheeignore`, la línea se agrega al final, no lo pisa.

## Consecuencias

- Positivas: ningún enlace a un repo propio tumba una PR; funciona igual en cualquier organización que
  herede el gate, sin editar nada.
- Negativas: un enlace a un repo propio renombrado o borrado ya no lo detecta la máquina; lo ve quien
  revisa la PR. Si la org pasa a pública, este ADR se supersede y el patrón se quita.

## Cómo se comprobó

Local con lychee 0.24.2 y el `sync/lychee.toml` vigente: un archivo con un enlace privado de la org, un
placeholder `{id}`, un repo muerto de otro dueño y uno vivo da `1 OK, 1 Error, 2 Excluded`, código 2.
