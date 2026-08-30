$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$aseprite = 'C:\Program Files (x86)\Steam\steamapps\common\Aseprite\Aseprite.exe'
$source = Join-Path $projectRoot 'assets\Aesprite\Weapons_Tileset.aseprite'
$destinationDirectory = Join-Path $projectRoot 'assets\sprites\weapons\authored'
$cannonDestination = Join-Path $destinationDirectory 'explosive_cannon_mount.png'
$laserDestination = Join-Path $destinationDirectory 'laser_emitter_mount.png'
$lightBallisticDestination = Join-Path $destinationDirectory 'light_ballistic_mount.png'

if (-not (Test-Path -LiteralPath $aseprite)) {
    throw "Aseprite was not found at $aseprite"
}
if (-not (Test-Path -LiteralPath $source)) {
    throw "Weapon source art was not found at $source"
}

New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null

function Export-WeaponCrop {
    param(
        [Parameter(Mandatory = $true)][string]$Crop,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    # Aseprite is a Windows GUI executable, so invoking it directly can return
    # before the PNG has been flushed. Waiting on the process keeps automated
    # imports from racing the export.
    $arguments = @('-b', ('"{0}"' -f $source), '--crop', $Crop, '--save-as', ('"{0}"' -f $Destination))
    $process = Start-Process -FilePath $aseprite -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $Destination)) {
        throw "Aseprite failed to export $Destination"
    }
}

# The authored explosive cannon occupies the first 3x6 16px tiles. Keeping the
# complete 48x96 authored canvas is intentional: the center of its round base
# is the mount pivot and the bottom-center edge is its deterministic muzzle.
Export-WeaponCrop -Crop '0,0,48,96' -Destination $cannonDestination

# The laser emitter occupies the lower-right 2x4 tile socket. It keeps the same
# transparent canvas and pivot convention as the cannon, so both scenes can be
# installed by the shared weapon-mount code without weapon-specific offsets.
Export-WeaponCrop -Crop '128,64,32,64' -Destination $laserDestination

# The compact ballistic mount occupies the upper-middle 3x4 tile socket. Its
# round base is centered at source pixel (16, 16), while its barrel points
# south/down to match the shared authored-mount rotation convention.
Export-WeaponCrop -Crop '80,0,48,64' -Destination $lightBallisticDestination

Write-Host "Exported $cannonDestination"
Write-Host "Exported $laserDestination"
Write-Host "Exported $lightBallisticDestination"
