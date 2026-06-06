$ProjectPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$Headless = $false
$ZoneArgs = @()

foreach ($Arg in $args)
{
    if ($Arg -eq "--headless")
    {
        $Headless = $true
    }
    else
    {
        $ZoneArgs += $Arg
    }
}

function Test-HasOption
{
    param(
        [string[]] $Values,
        [string[]] $Names
    )

    foreach ($Value in $Values)
    {
        if ($Names -contains $Value)
        {
            return $true
        }
    }
    return $false
}

if (-not (Test-HasOption -Values $ZoneArgs -Names @("--zone", "--zone-name", "--zone-id")))
{
    $ZoneArgs += @("--zone", "mvp")
}

if (-not (Test-HasOption -Values $ZoneArgs -Names @("--port")))
{
    $ZoneArgs += @("--port", "4242")
}

if (-not (Test-HasOption -Values $ZoneArgs -Names @("--advertise-address")))
{
    $ZoneArgs += @("--advertise-address", "127.0.0.1")
}

if (-not (Test-HasOption -Values $ZoneArgs -Names @("--orchestrator-url", "--orchestrator")))
{
    $ZoneArgs += @("--orchestrator-url", "ws://127.0.0.1:9000/ws")
}

$GodotArgs = @("--path", "./godot")
if ($Headless)
{
    $GodotArgs += "--headless"
}
else
{
    $GodotArgs += "--windowed"
}
$GodotArgs += @("--scene", "res://projects/game-server/src/main.tscn", "--")
$GodotArgs += $ZoneArgs

& godot @GodotArgs
