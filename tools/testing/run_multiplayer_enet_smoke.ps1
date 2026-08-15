param(
    [string]$GodotPath = "C:\Program Files\Godot_v4.5.1-stable_win64.exe\Godot_v4.5.1-stable_win64_console.exe",
    [int]$Port = 24671
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$gamePath = Join-Path $repoRoot "game"
$outputPath = Join-Path $gamePath ".godot\enet-smoke"
New-Item -ItemType Directory -Force -Path $outputPath | Out-Null
$processes = @()
$processOutput = @{}

function Start-GodotProcess {
    param([string[]]$GodotArguments, [string]$Name)
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $GodotPath
    $startInfo.Arguments = ($GodotArguments | ForEach-Object {
        '"' + $_.Replace('"', '\"') + '"'
    }) -join " "
    $startInfo.WorkingDirectory = $repoRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw "Unable to start Godot process $Name."
    }
    $script:processes += $process
    $script:processOutput[$process.Id] = @{
        Name = $Name
        Stdout = $process.StandardOutput.ReadToEndAsync()
        Stderr = $process.StandardError.ReadToEndAsync()
    }
    return $process
}

try {
    $hostProcess = Start-GodotProcess -Name "host" -GodotArguments @(
        "--headless", "--path", $gamePath,
        "--log-file", (Join-Path $outputPath "host.godot.log"),
        "--scene", "res://scenes/multiplayer_enet_smoke_test.tscn",
        "--", "--role=host", "--port=$Port"
    )
    Start-Sleep -Milliseconds 350
    $clientProcess = Start-GodotProcess -Name "client" -GodotArguments @(
        "--headless", "--path", $gamePath,
        "--log-file", (Join-Path $outputPath "client.godot.log"),
        "--scene", "res://scenes/multiplayer_enet_smoke_test.tscn",
        "--", "--role=client", "--port=$Port"
    )

    foreach ($process in @($hostProcess, $clientProcess)) {
        if (-not $process.WaitForExit(20000)) {
            throw "Godot ENet smoke-test process timed out."
        }
        $captured = $processOutput[$process.Id]
        $captured.Stdout.Result
        $captured.Stderr.Result
        if ($process.ExitCode -ne 0) {
            throw "$($captured.Name) exited with code $($process.ExitCode)."
        }
    }
    Write-Output "LAN ENet smoke test passed."
}
finally {
    foreach ($process in $processes) {
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force
        }
    }
}
