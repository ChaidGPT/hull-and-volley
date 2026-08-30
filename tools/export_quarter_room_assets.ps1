$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $projectRoot "assets\Aesprite\Base_QuarterRoom.aseprite"
$output = Join-Path $projectRoot "assets\sprites\interiors\rooms\quarter"
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
    throw "Quarter-room source is missing: $source"
}

New-Item -ItemType Directory -Path $output -Force | Out-Null
& $aseprite -b --layer "Base" $source --save-as (Join-Path $output "base.png")
& $aseprite -b --layer "Connectors" $source --save-as (Join-Path $output "connector.png")

Write-Output "Exported quarter-room base and connector from $source"
