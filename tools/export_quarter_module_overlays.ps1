$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $projectRoot "assets\Aesprite\Weapons_Tileset.aseprite"
$exporter = Join-Path $PSScriptRoot "export_quarter_module_overlays.lua"
$output = Join-Path $projectRoot "assets\sprites\interiors\rooms\quarter\overlays"
$asepriteCandidates = @(
    "C:\Program Files (x86)\Steam\steamapps\common\Aseprite\Aseprite.exe",
    "C:\Program Files\Aseprite\Aseprite.exe",
    (Join-Path $env:LOCALAPPDATA "Programs\Aseprite\Aseprite.exe")
)
$aseprite = $asepriteCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if (-not $aseprite) {
    throw "Aseprite was not found. Install it or update the candidates in this script."
}
if (-not (Test-Path -LiteralPath $source)) {
    throw "Quarter-module source is missing: $source"
}

New-Item -ItemType Directory -Path $output -Force | Out-Null
$arguments = @('-b', ('"{0}"' -f $source), '--script', ('"{0}"' -f $exporter))
$process = Start-Process -FilePath $aseprite -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
if ($process.ExitCode -ne 0) {
    throw "Aseprite failed to export the quarter-module overlays."
}

Write-Output "Exported centered 3x3 quarter-module canvases from $source"
