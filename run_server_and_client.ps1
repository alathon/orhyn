$ProjectPath = Split-Path -Parent $MyInvocation.MyCommand.Path

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

function Start-GodotWindow {
	param(
		[string] $ScenePath,
		[int] $X,
		[int] $Y
	)

	Start-Process godot -WorkingDirectory $ProjectPath -ArgumentList @(
		"--path", ".",
		"--windowed",
		"--position", "$X,$Y",
		"--scene", $ScenePath
	)
}

Start-GodotWindow `
	-ScenePath "res://scripts/server/server_scene.tscn" `
	-X $LeftX `
	-Y $TopY

Start-Sleep -Milliseconds 500

Start-GodotWindow `
	-ScenePath "res://scripts/client/client_scene.tscn" `
	-X $RightX `
	-Y $TopY

Start-GodotWindow `
	-ScenePath "res://scripts/client/client_scene.tscn" `
	-X $LeftX `
	-Y $BottomY

Start-GodotWindow `
	-ScenePath "res://scripts/client/client_scene.tscn" `
	-X $RightX `
	-Y $BottomY
