$ProjectPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$Headless = $false

foreach ($Arg in $args)
{
    if ($Arg -eq "--headless")
    {
        $Headless = $true
    }
}

function Get-PowerShellExecutable
{
    $Pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($Pwsh -ne $null)
    {
        return $Pwsh.Source
    }

    return (Get-Command powershell).Source
}

function New-GodotZoneArgs
{
    param(
        [string] $ZoneName,
        [int] $Port,
        [int] $X,
        [int] $Y
    )

    $GodotArgs = @("--path", "./godot")
    if ($Headless)
    {
        $GodotArgs += "--headless"
    }
    else
    {
        $GodotArgs += @(
            "--windowed",
            "--position", "$X,$Y"
        )
    }

    $GodotArgs += @(
        "--scene", "res://projects/game-server/src/main.tscn",
        "--",
        "--zone", $ZoneName,
        "--port", "$Port",
        "--advertise-address", "127.0.0.1",
        "--orchestrator-url", "ws://127.0.0.1:9000/ws"
    )

    return $GodotArgs
}

$PowerShell = Get-PowerShellExecutable
$OrchestratorScript = Join-Path $ProjectPath "run_orchestrator.ps1"
$OrchestratorArgs = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $OrchestratorScript,
    "--default-zone", "mvp",
    "--game-server-port", "9000",
    "--client-port", "9001",
    "--health-port", "9100"
)

$OrchestratorProcess = Start-Process `
    -FilePath $PowerShell `
    -WorkingDirectory $ProjectPath `
    -ArgumentList $OrchestratorArgs `
    -WindowStyle Normal `
    -PassThru

Start-Sleep -Milliseconds 750

$MvpX = 80
$ForestX = 1240
$ZoneY = 40
if (-not $Headless)
{
    Add-Type -AssemblyName System.Windows.Forms
    $Screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $EstimatedWindowWidth = 1152
    $MvpX = $Screen.Left + 80
    $ForestX = $Screen.Right - $EstimatedWindowWidth - 80
    $ZoneY = $Screen.Top + 40
}

$MvpProcess = Start-Process `
    -FilePath godot `
    -WorkingDirectory $ProjectPath `
    -ArgumentList (New-GodotZoneArgs -ZoneName "mvp" -Port 4242 -X $MvpX -Y $ZoneY) `
    -PassThru

$ForestProcess = Start-Process `
    -FilePath godot `
    -WorkingDirectory $ProjectPath `
    -ArgumentList (New-GodotZoneArgs -ZoneName "forest" -Port 4243 -X $ForestX -Y $ZoneY) `
    -PassThru

Write-Host "Started orchestrator pid=$($OrchestratorProcess.Id)"
Write-Host "Started MVP zone pid=$($MvpProcess.Id) port=4242"
Write-Host "Started forest zone pid=$($ForestProcess.Id) port=4243"
