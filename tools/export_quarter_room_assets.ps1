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

function Export-QuarterLayer {
    param(
        [Parameter(Mandatory = $true)][string]$Layer,
        [Parameter(Mandatory = $true)][string]$Filename
    )
    $destination = Join-Path $output $Filename
    $arguments = @(
        '-b',
        '--layer', ('"{0}"' -f $Layer),
        ('"{0}"' -f $source),
        '--save-as', ('"{0}"' -f $destination)
    )
    $process = Start-Process -FilePath $aseprite -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $destination)) {
        throw "Aseprite failed to export layer '$Layer'."
    }
}

Export-QuarterLayer -Layer "Base" -Filename "base.png"
Export-QuarterLayer -Layer "Connectors_SingleSide" -Filename "connector.png"
Export-QuarterLayer -Layer "Connectors_LR" -Filename "connector_straight.png"
Export-QuarterLayer -Layer "Connectors_LU" -Filename "connector_corner.png"

Write-Output "Exported quarter-room base and single, straight, and corner connectors from $source"
