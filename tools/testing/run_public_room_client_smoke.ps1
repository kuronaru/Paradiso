param(
    [string]$GodotPath = "C:\Program Files\Godot_v4.5.1-stable_win64.exe\Godot_v4.5.1-stable_win64_console.exe",
    [string]$PythonPath = "python",
    [int]$HttpPort = 18787
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$gamePath = Join-Path $repoRoot "game"
$outputPath = Join-Path $gamePath ".godot\public-room-smoke"
New-Item -ItemType Directory -Force -Path $outputPath | Out-Null
$service = $null
$client = $null

function New-BackgroundProcess {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [hashtable]$Environment = @{}
    )
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = ($Arguments | ForEach-Object {
        '"' + $_.Replace('"', '\"') + '"'
    }) -join " "
    $startInfo.WorkingDirectory = $repoRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($key in $Environment.Keys) {
        $startInfo.Environment[$key] = [string]$Environment[$key]
    }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw "Unable to start $FilePath."
    }
    return @{
        Process = $process
        Stdout = $process.StandardOutput.ReadToEndAsync()
        Stderr = $process.StandardError.ReadToEndAsync()
    }
}

try {
    $service = New-BackgroundProcess `
        -FilePath $PythonPath `
        -Arguments @(
            "server\public_room_service.py",
            "--bind-host", "127.0.0.1",
            "--http-port", $HttpPort
        )
    Start-Sleep -Milliseconds 500
    if ($service.Process.HasExited) {
        throw "Public room service exited during startup: $($service.Stderr.Result)"
    }

    $client = New-BackgroundProcess `
        -FilePath $GodotPath `
        -Arguments @(
            "--headless",
            "--path", $gamePath,
            "--log-file", (Join-Path $outputPath "client.godot.log"),
            "--script", "res://scripts/testing/public_room_client_smoke_test.gd",
            "--",
            "--service-url=http://127.0.0.1:$HttpPort"
        )
    if (-not $client.Process.WaitForExit(15000)) {
        throw "Public room Godot client timed out."
    }
    $client.Stdout.Result
    $client.Stderr.Result
    if ($client.Process.ExitCode -ne 0) {
        throw "Public room Godot client exited with code $($client.Process.ExitCode)."
    }
    Write-Output "Public room HTTP client smoke test passed."
}
finally {
    foreach ($entry in @($client, $service)) {
        if ($entry -and -not $entry.Process.HasExited) {
            $entry.Process.Kill()
            $entry.Process.WaitForExit(3000) | Out-Null
        }
    }
}
