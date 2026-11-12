<#
.SYNOPSIS
  Plants the inherited gitflow of Nashei-Studios in one repo, or reports drift (docs/adr/0001).
.DESCRIPTION
  Idempotent. Server side (gh api): develop branch, merge settings, Actions permissions, labels and,
  where the plan allows it, the rulesets `production` and `develop`. Local side (-RepoPath): the thin
  caller workflows, dependabot.yml and the pre-push hook, to be committed through a PR into develop.
.PARAMETER Repo
  owner/repo of the target.
.PARAMETER RepoPath
  Local clone of the target. When given, the inherited files are copied into it.
.PARAMETER Check
  Changes nothing: prints every difference and exits 1 when there is drift.
.PARAMETER EnableAutomerge
  Sets AUTOMERGE_ENABLED=true so green PRs into develop merge themselves.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Repo,
  [string]$RepoPath,
  [switch]$Check,
  [switch]$EnableAutomerge
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$drift = [System.Collections.Generic.List[string]]::new()

function Invoke-Gh { param([string[]]$GhArgs) $out = & gh @GhArgs 2>&1; if ($LASTEXITCODE -ne 0) { throw "gh $($GhArgs -join ' '): $out" }; $out }

$info = Invoke-Gh @('api', "repos/$Repo") | ConvertFrom-Json
$private = $info.visibility -ne 'public'

# 1. develop exists.
& gh api "repos/$Repo/branches/develop" --silent 2>$null
if ($LASTEXITCODE -ne 0) {
  if ($Check) { $drift.Add('branch develop is missing') }
  else {
    $sha = Invoke-Gh @('api', "repos/$Repo/git/ref/heads/main", '--jq', '.object.sha')
    Invoke-Gh @('api', '-X', 'POST', "repos/$Repo/git/refs", '-f', 'ref=refs/heads/develop', '-f', "sha=$sha", '--silent') | Out-Null
    Write-Host 'created develop from main'
  }
}

# 2. Merge settings. A private repo on the Free plan has no enforced ruleset, so GitHub's own
#    auto-delete would remove develop when someone merges develop -> main by hand: it stays off there
#    and the gate deletes the work branches itself.
$want = [ordered]@{
  default_branch = 'main'; delete_branch_on_merge = (-not $private); allow_auto_merge = $true; allow_update_branch = $true
  allow_squash_merge = $true; allow_merge_commit = $true; allow_rebase_merge = $false
  squash_merge_commit_title = 'PR_TITLE'; squash_merge_commit_message = 'BLANK'
  merge_commit_title = 'PR_TITLE'; merge_commit_message = 'PR_BODY'
}
$off = @($want.Keys | Where-Object { "$($info.$_)" -ne "$($want[$_])" })
if ($off.Count) {
  if ($Check) { $drift.Add("settings differ: $($off -join ', ')") }
  else {
    $ghArgs = @('api', '-X', 'PATCH', "repos/$Repo", '--silent')
    foreach ($k in $want.Keys) { $v = $want[$k]; if ($v -is [bool]) { $ghArgs += @('-F', "$k=$("$v".ToLower())") } else { $ghArgs += @('-f', "$k=$v") } }
    Invoke-Gh $ghArgs | Out-Null
    Write-Host "settings fixed: $($off -join ', ')"
  }
}

# 3. Actions: read-only token by default, allowed to open the release PRs.
$perm = Invoke-Gh @('api', "repos/$Repo/actions/permissions/workflow") | ConvertFrom-Json
if ($perm.default_workflow_permissions -ne 'read' -or -not $perm.can_approve_pull_request_reviews) {
  if ($Check) { $drift.Add('actions workflow permissions differ') }
  else { Invoke-Gh @('api', '-X', 'PUT', "repos/$Repo/actions/permissions/workflow", '-f', 'default_workflow_permissions=read', '-F', 'can_approve_pull_request_reviews=true', '--silent') | Out-Null }
}

# 4. Labels the workflows read.
$labels = @(Invoke-Gh @('label', 'list', '--repo', $Repo, '--limit', '200', '--json', 'name', '--jq', '.[].name'))
foreach ($label in 'hold', 'keep') {
  if ($labels -notcontains $label) {
    if ($Check) { $drift.Add("label $label is missing") }
    else { Invoke-Gh @('label', 'create', $label, '--repo', $Repo, '--force', '--color', 'b60205', '--description', "gitflow: $label") | Out-Null }
  }
}

# 5. Rulesets. A private repo on the Free plan rejects the API (403): there they are imported once
#    from the web (Settings > Rules > Rulesets > Import) and audit-push covers what is not enforced.
$existing = & gh api "repos/$Repo/rulesets" --jq '.[].name' 2>$null
if ($LASTEXITCODE -eq 0) {
  foreach ($name in 'production', 'develop') {
    if (@($existing) -notcontains $name) {
      if ($Check) { $drift.Add("ruleset $name is missing") }
      else { Invoke-Gh @('api', '-X', 'POST', "repos/$Repo/rulesets", '--input', (Join-Path $PSScriptRoot "rulesets\$name.json"), '--silent') | Out-Null; Write-Host "ruleset $name created" }
    }
  }
} else {
  Write-Host 'rulesets: the API is closed for this private repo on the Free plan; import sync/rulesets/*.json from the web.'
}

# 6. Automerge switch.
if ($EnableAutomerge -and -not $Check) { Invoke-Gh @('variable', 'set', 'AUTOMERGE_ENABLED', '--body', 'true', '--repo', $Repo) | Out-Null }

# 7. Files.
$files = [ordered]@{
  'workflow-templates\release.yml' = '.github\workflows\release.yml'
  'workflow-templates\stale.yml'   = '.github\workflows\stale.yml'
  'sync\dependabot.yml'            = '.github\dependabot.yml'
  'sync\githooks\pre-push'         = '.githooks\pre-push'
}
if ($private) { $files['workflow-templates\audit-push.yml'] = '.github\workflows\audit-push.yml' }
if ($RepoPath) {
  # ci.yml is only planted when missing: a repo with code keeps its own jobs and calls pr-gate itself.
  $ci = Join-Path $RepoPath '.github\workflows\ci.yml'
  if (-not (Test-Path $ci)) { $files['workflow-templates\ci.yml'] = '.github\workflows\ci.yml' }
  elseif (-not (Select-String -Path $ci -Pattern 'pr-gate.yml' -Quiet)) { $drift.Add('ci.yml does not call pr-gate.yml') }
  foreach ($src in $files.Keys) {
    $from = Join-Path $root $src; $to = Join-Path $RepoPath $files[$src]
    $same = (Test-Path $to) -and ((Get-FileHash $from).Hash -eq (Get-FileHash $to).Hash)
    if ($same) { continue }
    if ($Check) { $drift.Add("file differs: $($files[$src])") }
    else { New-Item -ItemType Directory -Force (Split-Path $to) | Out-Null; Copy-Item $from $to -Force; Write-Host "copied $($files[$src])" }
  }
  if (-not $Check) { & git -C $RepoPath config core.hooksPath .githooks }
}

if ($Check) {
  if ($drift.Count) { $drift | ForEach-Object { Write-Host "DRIFT $Repo`: $_" }; exit 1 }
  Write-Host "ok $Repo"
} elseif ($drift.Count) { $drift | ForEach-Object { Write-Warning $_ } }
