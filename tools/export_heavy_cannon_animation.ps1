$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$aseprite = 'C:\Program Files (x86)\Steam\steamapps\common\Aseprite\Aseprite.exe'
$source = Join-Path $projectRoot 'assets\Aesprite\Heavy_Canon_Animations.aseprite'
$output = Join-Path $projectRoot 'assets\sprites\weapons\authored\heavy_cannon_fire_strip.png'

if (-not (Test-Path -LiteralPath $aseprite)) {
    throw "Aseprite was not found at $aseprite"
}

& $aseprite -b $source --sheet $output --sheet-type horizontal
if ($LASTEXITCODE -ne 0) {
    throw "Heavy cannon animation export failed with exit code $LASTEXITCODE"
}
