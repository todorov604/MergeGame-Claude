# 03_Game_ds portability self-check (UTF-8 BOM so Windows PowerShell reads it correctly).
# Usage: powershell -ExecutionPolicy Bypass -File tools\check_portability.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$blocking = @()
$notes = @()

foreach ($f in Get-ChildItem $root -Recurse -File) {
  if ($f.FullName -match '\\\.godot\\|\\output\\') { continue }
  if ($f.Name -eq 'godot_path.txt') { continue }   # machine-local Godot hint
  if ($f.Extension -notin '.gd','.tscn','.tres','.json','.godot','.cfg','.bat','.sh','.import','.txt') { continue }
  $n = 0
  foreach ($line in Get-Content $f.FullName -ErrorAction SilentlyContinue) {
    $n++
    if ($line -match '[A-Za-z]:\\' -or $line -match '[A-Za-z]:/(?!/)') {
      $rel = $f.FullName.Substring($root.Length + 1)
      $blocking += ("absolute path  " + $rel + ":" + $n + "  " + $line.Trim())
    }
  }
}

foreach ($f in Get-ChildItem $root -Recurse -File -Include *.gd,*.json,*.tres,*.tscn) {
  if ($f.FullName -match '\\\.godot\\|\\output\\') { continue }
  $n = 0
  foreach ($line in Get-Content $f.FullName -ErrorAction SilentlyContinue) {
    $n++
    if ($line -match '01_icon|00_design|02_Game') {
      $rel = $f.FullName.Substring($root.Length + 1)
      $txt = $line.Trim()
      if ($txt.Length -gt 72) { $txt = $txt.Substring(0,72) }
      $notes += ("provenance  " + $rel + ":" + $n + "  " + $txt)
    }
  }
}

$registry = Join-Path $root 'data/assets_local.json'
if (Test-Path $registry) {
  $reg = [System.IO.File]::ReadAllText($registry, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
  $dirs = @('assets/ui','assets/fonts','assets/chips')
  foreach ($id in $reg.resources.PSObject.Properties.Name) {
    $name = $reg.resources.$id.file_name
    if ([string]::IsNullOrWhiteSpace($name)) { continue }
    $found = $false
    foreach ($d in $dirs) { if (Test-Path (Join-Path $root ($d + '/' + $name))) { $found = $true } }
    if (-not $found) { $blocking += ("missing file  registry " + $id + " -> " + $name) }
  }
}

Write-Host "=== blocking issues (must be 0) ==="
if ($blocking.Count -eq 0) { Write-Host "  none" } else { $blocking | ForEach-Object { Write-Host ("  " + $_) } }
Write-Host ("=== provenance strings (do not affect runtime): " + $notes.Count + " ===")
$notes | Select-Object -First 4 | ForEach-Object { Write-Host ("  " + $_) }
if (Test-Path (Join-Path $root 'godot_path.txt')) {
  Write-Host "=== godot_path.txt ==="
  Write-Host ("  " + (Get-Content (Join-Path $root 'godot_path.txt') -First 1))
}
exit $(if ($blocking.Count -eq 0) { 0 } else { 1 })