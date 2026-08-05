param(
    [string]$GodotPath = "C:\Program Files\Godot_v4.5.1-stable_win64.exe\Godot_v4.5.1-stable_win64_console.exe",
    [int]$Port = 24672
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$gamePath = Join-Path $repoRoot "game"
$outputPath = Join-Path $gamePath ".godot\relay-smoke"
New-Item -ItemType Directory -Force -Path $outputPath | Out-Null
$ownerToken = "relay-smoke-owner-token"
$processes = @()
$processOutput = @{}

function Start-GodotProcess {
    param(
        [string[]]$GodotArguments,
        [string]$Name
    )
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
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $script:processes += $process
    $script:processOutput[$process.Id] = @{
        Name = $Name
        Stdout = $stdoutTask
        Stderr = $stderrTask
    }
    return $process
}

try {
    $relay = Start-GodotProcess -Name "relay" -GodotArguments @(
        "--headless",
        "--path", $gamePath,
        "--log-file", (Join-Path $outputPath "relay.godot.log"),
        "--script", "res://scripts/multiplayer/dedicated_room_server.gd",
        "--",
        "--relay-port=$Port",
        "--room-code=SMOKE1",
        "--owner-token=$ownerToken",
        "--idle-timeout=30"
    )
    Start-Sleep -Milliseconds 700

    $owner = Start-GodotProcess -Name "owner" -GodotArguments @(
        "--headless",
        "--path", $gamePath,
        "--log-file", (Join-Path $outputPath "owner.godot.log"),
        "--scene", "res://scenes/multiplayer_relay_smoke_test.tscn",
        "--",
        "--role=owner",
        "--port=$Port",
        "--owner-token=$ownerToken"
    )
    Start-Sleep -Milliseconds 250
    $client = Start-GodotProcess -Name "client" -GodotArguments @(
        "--headless",
        "--path", $gamePath,
        "--log-file", (Join-Path $outputPath "client.godot.log"),
        "--scene", "res://scenes/multiplayer_relay_smoke_test.tscn",
        "--",
        "--role=client",
        "--port=$Port"
    )

    foreach ($process in @($owner, $client)) {
        if (-not $process.WaitForExit(25000)) {
            throw "Godot smoke-test client timed out."
        }
        if ($process.ExitCode -ne 0) {
            throw "Godot smoke-test client exited with code $($process.ExitCode)."
        }
    }

    foreach ($process in @($owner, $client)) {
        $captured = $processOutput[$process.Id]
        $captured.Stdout.Result
        $captured.Stderr.Result
    }
    Write-Output "Dedicated relay smoke test passed."
}
finally {
    foreach ($process in $processes) {
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force
        }
    }
}
