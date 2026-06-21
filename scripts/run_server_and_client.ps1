$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectPath = Split-Path -Parent $ScriptPath

Add-Type -AssemblyName System.Windows.Forms

$Screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$InsetX = 80
$InsetY = 40
$EstimatedWindowWidth = 1152
$EstimatedWindowHeight = 648
$LeftX = $Screen.Left + $InsetX
$RightX = $Screen.Right - $EstimatedWindowWidth - $InsetX
$TopY = $Screen.Top + $InsetY
$BottomY = $Screen.Bottom - $EstimatedWindowHeight - $InsetY

function Start-GodotWindow
{
    param(
        [string] $ScenePath,
        [int] $X,
        [int] $Y,
        [string[]] $UserArgs = @()
    )

    $ArgumentList = @(
        "--path", "./godot",
        "--windowed",
        "--position", "$X,$Y",
        "--scene", $ScenePath
    )

    if ($UserArgs.Count -gt 0)
    {
        $ArgumentList += "--"
        $ArgumentList += $UserArgs
    }

    Start-Process godot -WorkingDirectory $ProjectPath -ArgumentList $ArgumentList
}

Start-GodotWindow `
    -ScenePath "res://projects/game-server/src/main.tscn" `
    -X $LeftX `
    -Y $TopY `
    -UserArgs @(
        "--zone", "mvp",
        "--port", "4242",
        "--advertise-address", "127.0.0.1",
        "--orchestrator-url", "ws://127.0.0.1:9000/ws"
    )

Start-Sleep -Milliseconds 500

Start-GodotWindow `
    -ScenePath "res://projects/client/src/client_app.tscn" `
    -X $RightX `
    -Y $TopY

Start-GodotWindow `
    -ScenePath "res://projects/client/src/client_app.tscn" `
    -X $LeftX `
    -Y $BottomY

Start-GodotWindow `
    -ScenePath "res://projects/client/src/client_app.tscn" `
    -X $RightX `
    -Y $BottomY
