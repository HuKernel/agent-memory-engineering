# agent-memory-engineering installer for Windows (PowerShell 5.1+)
# Canonical source: <repo>\skills\agent-memory-engineering (the ONLY maintained copy)
# Installs are plain directory copies - Windows symlinks need dev mode/admin, so copy is the default.

[CmdletBinding()]
param(
    [ValidateSet('Claude', 'Codex', 'All')]
    [string]$Target = 'All',

    [ValidateSet('User', 'Project')]
    [string]$Scope = 'User',

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$SkillSrc = Join-Path $RepoRoot 'skills\agent-memory-engineering'
$SkillName = 'agent-memory-engineering'

# --- validate canonical source ---
if (-not (Test-Path (Join-Path $SkillSrc 'SKILL.md'))) {
    Write-Error "Canonical skill not found at $SkillSrc\SKILL.md"
}
$fm = Get-Content (Join-Path $SkillSrc 'SKILL.md') -TotalCount 30
if ($fm[0] -ne '---') { Write-Error 'SKILL.md is missing YAML frontmatter' }
$fmBody = $fm | Select-Object -Skip 1
foreach ($key in @('name', 'description')) {
    if (-not ($fmBody | Where-Object { $_ -match "^$key\:" })) {
        Write-Error "SKILL.md frontmatter is missing required key: $key"
    }
}

function Get-DestRoot([string]$Host_) {
    switch ('{0}:{1}' -f $Host_, $Scope) {
        'claude:User'    { Join-Path $HOME '.claude\skills' }
        'claude:Project' { Join-Path (Get-Location) '.claude\skills' }
        'codex:User'     { Join-Path $HOME '.agents\skills' }
        'codex:Project'  { Join-Path (Get-Location) '.agents\skills' }
    }
}

function Test-SameContent([string]$A, [string]$B) {
    $filesA = Get-ChildItem $A -Recurse -File
    $filesB = Get-ChildItem $B -Recurse -File
    if ($filesA.Count -ne $filesB.Count) { return $false }
    foreach ($f in $filesA) {
        $rel = $f.FullName.Substring($A.Length)
        $other = Join-Path $B $rel
        if (-not (Test-Path $other)) { return $false }
        $hA = (Get-FileHash $f.FullName -Algorithm SHA256).Hash
        $hB = (Get-FileHash $other -Algorithm SHA256).Hash
        if ($hA -ne $hB) { return $false }
    }
    return $true
}

function Install-One([string]$Host_) {
    $destRoot = Get-DestRoot $Host_
    $dest = Join-Path $destRoot $SkillName

    if (Test-Path $dest) {
        if (Test-SameContent $SkillSrc $dest) {
            Write-Host "[$Host_] already up to date: $dest"
            return
        }
        if (-not $Force) {
            Write-Error "[$Host_] $dest exists and content differs. Re-run with -Force to replace (a timestamped backup is kept)."
        }
        $backup = "$dest.bak.$(Get-Date -Format yyyyMMddHHmmss)"
        Move-Item $dest $backup
        Write-Host "[$Host_] backed up existing install to: $backup"
    }

    New-Item -ItemType Directory -Path $destRoot -Force | Out-Null
    Copy-Item $SkillSrc $dest -Recurse
    Write-Host "[$Host_] installed (copy): $dest"
    Write-Host "        canonical source remains: skills\$SkillName in this repository"
}

if ($Target -in @('Claude', 'All')) { Install-One 'claude' }
if ($Target -in @('Codex', 'All'))  { Install-One 'codex' }

Write-Host 'Done. Restart your agent host (Claude Code / Codex) to pick up the skill.'
