# .github de Nashei Studios

De aquí heredan todos los repos de la organización. Qué es:

- **El perfil público** de la organización (`profile/README.md`).
- **Los workflows reutilizables** que definen cómo se versiona en todo repo (`.github/workflows/`).
- **Los archivos por defecto**: plantillas de issue y de PR para los repos que no traen las suyas.
- **Lo que se planta en cada repo** y el script que lo hace (`sync/`).

Qué no es: no guarda código de juegos ni documentación del estudio (eso vive en `studio`).

## El flujo, en corto

1. Todo trabajo tiene un issue. La rama sale de `develop`.
2. La PR va a `develop`, con título en Conventional Commits y `Closes #N` en el cuerpo. Ni el título, ni la descripción ni los commits pueden traer marcas de IA (trailer de coautoría de un asistente, enlace de sesión, pie de generación o el emoji de robot): el gate falla y dice qué línea sacar.
3. Si el gate queda en verde, la PR se mergea sola con squash, se borra la rama y se cierra el issue.
4. `main` solo cambia por release: `gh workflow run release.yml`, o solo los lunes si hay cambios.
   El release crea el tag `vX.Y.Z`, el `CHANGELOG.md` y el GitHub Release.

La comparación con otros sistemas y el porqué: [ADR 0001](docs/adr/0001-gitflow-heredado-por-workflows-reutilizables.md).

## Carpetas

| Carpeta | Qué hay | Por qué está aquí |
|---|---|---|
| `.github/workflows/` | `pr-gate`, `release-plan`, `release-publish`, `stale`, `audit-push` (reutilizables) y los callers de este repo | GitHub solo deja llamar workflows que estén en esta ruta |
| `.github/ISSUE_TEMPLATE/`, `.github/PULL_REQUEST_TEMPLATE.md` | Formularios por defecto | GitHub los aplica a todo repo de la organización que no tenga los suyos |
| `workflow-templates/` | Los callers de diez líneas que usa cada repo | Aparecen en Actions > New workflow de cualquier repo, y `plant.ps1` los copia |
| `sync/` | `plant.ps1`, `cliff.toml`, `dependabot.yml`, el hook `pre-push` y los rulesets en JSON | Lo que no se puede heredar por referencia |
| `docs/adr/` | Decisiones | Una por archivo, numeradas |

## Dar de alta o reparar un repo

```powershell
pwsh sync/plant.ps1 -Repo Nashei-Studios/<repo> -RepoPath <clon> -EnableAutomerge
```

Crea `develop`, deja los ajustes de merge, las etiquetas y los rulesets, y copia los callers al
clon. Esos archivos se commitean por PR a `develop`. Para ver si un repo se desvió, sin tocar nada:

```powershell
pwsh sync/plant.ps1 -Repo Nashei-Studios/<repo> -RepoPath <clon> -Check
```

En un repo privado los rulesets se importan una vez desde la web: Settings > Rules > Rulesets >
New ruleset > Import a ruleset, con `sync/rulesets/production.json` y `develop.json`.

## Un repo con código

Mantiene su `ci.yml` con sus propios jobs y agrega al final el job heredado:

```yaml
  pr:
    needs: [check, test]          # los jobs del repo
    if: ${{ !failure() && !cancelled() }}
    permissions: { contents: write, pull-requests: write, issues: write }
    uses: Nashei-Studios/.github/.github/workflows/pr-gate.yml@main
```

Y en `release.yml` pone un job `gate` entre `plan` y `publish` que llama a su `ci.yml`.

## Cambiar algo aquí

Por PR a `develop`; el CI corre `actionlint` sobre todos los workflows. Los demás repos consumen
`main`, que solo avanza por release: lo que está en `develop` todavía no le llega a nadie.

## Prohibido

- Apuntar un caller a una rama que no sea `main`.
- Acciones de terceros sin fijar por SHA.
- Secretos en estos workflows: son públicos.
