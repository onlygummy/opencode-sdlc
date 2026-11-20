#Requires -Version 5.1
<#
.SYNOPSIS
  Validate agent and skill frontmatter, the OpenCode JSON config, and permission rule order.
.DESCRIPTION
  Exits 0 when every check passes. Exits 1 when any check fails. The checks are
  structural: a broken frontmatter, a missing description, an invalid mode, a
  skill name that does not match its folder, malformed JSONC, or a broad
  permission rule placed after a specific rule for the same action.
#>
[CmdletBinding()]
param(
  [string]$Root
)

if ([string]::IsNullOrWhiteSpace($Root)) {
  $Root = Split-Path -Parent $PSScriptRoot
}

$ErrorActionPreference = 'Stop'
$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Add-Error {
  param([string]$Message)
  $errors.Add($Message) | Out-Null
}

function Add-Warning {
  param([string]$Message)
  $warnings.Add($Message) | Out-Null
}

function Get-Frontmatter {
  param([string]$Path)
  $lines = @(Get-Content -LiteralPath $Path)
  if ($lines.Count -lt 3 -or $lines[0].Trim() -ne '---') {
    return $null
  }
  $end = -1
  for ($i = 1; $i -lt $lines.Count; $i++) {
    if ($lines[$i].Trim() -eq '---') {
      $end = $i
      break
    }
  }
  if ($end -lt 0) {
    return $null
  }
  if ($end -eq 1) {
    return @()
  }
  return @($lines[1..($end - 1)])
}

function Get-Field {
  param([string[]]$Frontmatter, [string]$Name)
  $pattern = '^' + [regex]::Escape($Name) + ':\s*(.*)$'
  for ($i = 0; $i -lt $Frontmatter.Count; $i++) {
    if ($Frontmatter[$i] -match $pattern) {
      $value = $Matches[1].Trim()
      if ($value -match '^[|>][+-]?$') {
        $parts = New-Object System.Collections.Generic.List[string]
        for ($j = $i + 1; $j -lt $Frontmatter.Count; $j++) {
          if ($Frontmatter[$j] -match '^\s+\S') {
            $parts.Add($Frontmatter[$j].Trim()) | Out-Null
          }
          elseif ($Frontmatter[$j].Trim() -eq '') {
            continue
          }
          else {
            break
          }
        }
        return ($parts -join ' ')
      }
      return $value.Trim('"', "'")
    }
  }
  return $null
}

function Get-PermissionRules {
  param([string[]]$Frontmatter)
  $rules = New-Object System.Collections.Generic.List[object]
  $pattern = '^\s*-\s*\{\s*action:\s*"([^"]+)"\s*,\s*resource:\s*"([^"]+)"\s*,\s*effect:\s*"([^"]+)"\s*\}\s*$'
  foreach ($line in $Frontmatter) {
    if ($line -match $pattern) {
      $rules.Add([pscustomobject]@{
        Action   = $Matches[1]
        Resource = $Matches[2]
        Effect   = $Matches[3]
      }) | Out-Null
    }
  }
  return $rules
}

function Test-PermissionRules {
  param(
    [string]$Label,
    [object[]]$Rules
  )
  $allowedActions = @('edit', 'read', 'glob', 'grep', 'webfetch', 'skill', 'subagent', 'shell')
  $allowedEffects = @('allow', 'deny', 'ask')
  $seenSpecific = @{}

  foreach ($rule in $Rules) {
    if ($null -eq $rule) {
      continue
    }
    $action = [string]$rule.action
    $resource = [string]$rule.resource
    $effect = [string]$rule.effect

    if ($allowedActions -notcontains $action) {
      Add-Error "$Label`: unknown permission action '$action'"
    }
    if ($allowedEffects -notcontains $effect) {
      Add-Error "$Label`: unknown permission effect '$effect'"
    }
    if ([string]::IsNullOrWhiteSpace($resource)) {
      Add-Error "$Label`: permission resource is empty for action '$action'"
    }

    if ($resource -eq '*') {
      if ($seenSpecific.ContainsKey($action)) {
        Add-Error "$Label`: broad rule for '$action' appears after a specific rule; last-match-wins makes the broad rule win"
      }
    }
    else {
      $seenSpecific[$action] = $true
    }
  }
}

$agentNames = New-Object System.Collections.Generic.List[string]
$skillDirs = @()
$agentsPath = Join-Path $Root 'agents'
if (-not (Test-Path -LiteralPath $agentsPath -PathType Container)) {
  Add-Error "Missing agents directory: $agentsPath"
}
else {
  $agentFiles = @(Get-ChildItem -LiteralPath $agentsPath -Filter '*.md' -File | Sort-Object Name)
  if ($agentFiles.Count -eq 0) {
    Add-Error "No agent files found in $agentsPath"
  }
  foreach ($file in $agentFiles) {
    $agentNames.Add($file.BaseName) | Out-Null
    $frontmatter = Get-Frontmatter -Path $file.FullName
    if ($null -eq $frontmatter) {
      Add-Error "$($file.Name): missing or unclosed frontmatter"
      continue
    }
    $description = Get-Field -Frontmatter $frontmatter -Name 'description'
    $mode = Get-Field -Frontmatter $frontmatter -Name 'mode'
    if ([string]::IsNullOrWhiteSpace($description)) {
      Add-Error "$($file.Name): description is required"
    }
    if (@('primary', 'subagent', 'all') -notcontains $mode) {
      Add-Error "$($file.Name): mode must be primary, subagent, or all (found '$mode')"
    }
    $rules = @(Get-PermissionRules -Frontmatter $frontmatter)
    if ($rules.Count -eq 0) {
      Add-Warning "$($file.Name): no permission rules parsed"
    }
    Test-PermissionRules -Label $file.Name -Rules $rules
  }
}

$skillsPath = Join-Path $Root 'skills'
if (-not (Test-Path -LiteralPath $skillsPath -PathType Container)) {
  Add-Error "Missing skills directory: $skillsPath"
}
else {
  $skillDirs = @(Get-ChildItem -LiteralPath $skillsPath -Directory | Sort-Object Name)
  foreach ($dir in $skillDirs) {
    $skillFile = Join-Path $dir.FullName 'SKILL.md'
    if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) {
      Add-Error "$($dir.Name): missing SKILL.md"
      continue
    }
    $frontmatter = Get-Frontmatter -Path $skillFile
    if ($null -eq $frontmatter) {
      Add-Error "$($dir.Name)/SKILL.md: missing or unclosed frontmatter"
      continue
    }
    $name = Get-Field -Frontmatter $frontmatter -Name 'name'
    $description = Get-Field -Frontmatter $frontmatter -Name 'description'
    if ([string]::IsNullOrWhiteSpace($name)) {
      Add-Error "$($dir.Name)/SKILL.md: name is required"
    }
    elseif ($name -ne $dir.Name) {
      Add-Error "$($dir.Name)/SKILL.md: name '$name' does not match folder '$($dir.Name)'"
    }
    if ([string]::IsNullOrWhiteSpace($description)) {
      Add-Error "$($dir.Name)/SKILL.md: description is required"
    }
  }
}

$configPath = Join-Path $Root 'opencode.jsonc'
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
  Add-Error "Missing config: $configPath"
}
else {
  $raw = Get-Content -LiteralPath $configPath -Raw
  $withoutComments = [regex]::Replace($raw, '(?m)^\s*//.*$', '')
  $withoutTrailingCommas = [regex]::Replace($withoutComments, ',(\s*[}\]])', '$1')
  try {
    $config = $withoutTrailingCommas | ConvertFrom-Json
  }
  catch {
    Add-Error "opencode.jsonc: $($_.Exception.Message)"
    $config = $null
  }
  if ($null -ne $config) {
    $defaultAgent = [string]$config.default_agent
    if ([string]::IsNullOrWhiteSpace($defaultAgent)) {
      Add-Error 'opencode.jsonc: default_agent is required'
    }
    elseif (-not $agentNames.Contains($defaultAgent)) {
      Add-Error "opencode.jsonc: default_agent '$defaultAgent' does not match an agent file"
    }
    $globalRules = @($config.permissions)
    if ($globalRules.Count -eq 0) {
      Add-Warning 'opencode.jsonc: no global permissions parsed'
    }
    Test-PermissionRules -Label 'opencode.jsonc' -Rules $globalRules
  }
}

if ($warnings.Count -gt 0) {
  Write-Output 'Warnings:'
  foreach ($warning in $warnings) {
    Write-Output "  - $warning"
  }
}

if ($errors.Count -gt 0) {
  Write-Output 'Errors:'
  foreach ($errorItem in $errors) {
    Write-Output "  - $errorItem"
  }
  exit 1
}

Write-Output "OK: validated $($agentNames.Count) agent file(s), $($skillDirs.Count) skill folder(s), and opencode.jsonc."
exit 0
