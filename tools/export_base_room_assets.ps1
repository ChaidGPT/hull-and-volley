$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $projectRoot "assets\Aesprite\Base_Room.aseprite"
$output = Join-Path $projectRoot "assets\sprites\interiors\rooms\standard\overlays"
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
    throw "Canonical room source is missing: $source"
}

New-Item -ItemType Directory -Path $output -Force | Out-Null
& $aseprite -b --layer "Weapons" $source --save-as (Join-Path $output "weapon_narrow.png")
& $aseprite -b --layer "Weapon - Space Cutout" $source --save-as (Join-Path $output "weapon_narrow_cutout.png")
& $aseprite -b --layer "Shield" $source --save-as (Join-Path $output "shield.png")

Write-Output "Exported standard-room overlays from $source"
