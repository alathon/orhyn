$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectPath = Split-Path -Parent $ScriptPath
$OrchestratorPath = Join-Path $ProjectPath "orchestrator"
$BuildPath = Join-Path $OrchestratorPath ".bin"
$ExePath = Join-Path $BuildPath "orchestrator.exe"

Push-Location $OrchestratorPath
try
{
    New-Item -ItemType Directory -Path $BuildPath -Force | Out-Null
    & go @("build", "-o", $ExePath, "./cmd/orchestrator")
    if ($LASTEXITCODE -ne 0)
    {
        exit $LASTEXITCODE
    }

    & $ExePath @args
}
finally
{
    Pop-Location
}
