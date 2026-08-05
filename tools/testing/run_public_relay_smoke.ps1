param(
    [string]$GodotPath = "C:\Program Files\Godot_v4.5.1-stable_win64.exe\Godot_v4.5.1-stable_win64_console.exe",
    [string]$PythonPath = "python",
    [int]$HttpPort = 18788,
    [int]$RelayPort = 24673
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$gamePath = Join-Path $repoRoot "game"
$outputPath = Join-Path $gamePath ".godot\public-relay-smoke"
New-Item -ItemType Directory -Force -Path $outputPath | Out-Null
$serviceUrl = "http://127.0.0.1:$HttpPort"
$processes = @()
$processOutput = @{}
$room = $null

function Start-CapturedProcess {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$Name
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
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw "Unable to start $Name."
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
    $service = Start-CapturedProcess `
        -FilePath $PythonPath `
        -Name "room-service" `
        -Arguments @(
            "server\public_room_service.py",
            "--bind-host", "127.0.0.1",
            "--http-port", $HttpPort,
            "--public-relay-host", "127.0.0.1",
            "--relay-port-start", $RelayPort,
            "--relay-port-end", $RelayPort,
            "--godot-bin", $GodotPath,
            "--project-path", $gamePath
        )
    Start-Sleep -Milliseconds 500
    if ($service.HasExited) {
        throw "Public room service exited during startup."
    }

    $createBody = @{
        host_name = "PublicRelayOwner"
        max_players = 4
        direct_address = ""
        direct_port = 24567
        direct_available = $false
    } | ConvertTo-Json
    $room = Invoke-RestMethod `
        -Uri "$serviceUrl/v1/rooms" `
        -Method Post `
        -ContentType "application/json" `
        -Body $createBody
    if ($room.status -ne "RELAY" -or $room.relay_port -ne $RelayPort) {
        throw "Room service did not return the expected relay endpoint."
    }

    Start-Sleep -Milliseconds 400
    $owner = Start-CapturedProcess `
        -FilePath $GodotPath `
        -Name "owner" `
        -Arguments @(
            "--headless",
            "--path", $gamePath,
            "--log-file", (Join-Path $outputPath "owner.godot.log"),
            "--scene", "res://scenes/multiplayer_relay_smoke_test.tscn",
            "--",
            "--role=owner",
            "--port=$RelayPort",
            "--owner-token=$($room.host_token)"
        )
    Start-Sleep -Milliseconds 250
    $client = Start-CapturedProcess `
        -FilePath $GodotPath `
        -Name "client" `
        -Arguments @(
            "--headless",
            "--path", $gamePath,
            "--log-file", (Join-Path $outputPath "client.godot.log"),
            "--scene", "res://scenes/multiplayer_relay_smoke_test.tscn",
            "--",
            "--role=client",
            "--port=$RelayPort"
        )

    foreach ($process in @($owner, $client)) {
        if (-not $process.WaitForExit(25000)) {
            throw "Public relay smoke-test client timed out."
        }
        $captured = $processOutput[$process.Id]
        $captured.Stdout.Result
        $captured.Stderr.Result
        if ($process.ExitCode -ne 0) {
            throw "Public relay smoke-test client exited with code $($process.ExitCode)."
        }
    }
    Write-Output "Central room service to dedicated relay smoke test passed."
}
finally {
    if ($room -and $room.host_token) {
        try {
            Invoke-RestMethod `
                -Uri "$serviceUrl/v1/rooms/$($room.room_code)" `
                -Method Delete `
                -Headers @{ Authorization = "Bearer $($room.host_token)" } | Out-Null
        }
        catch {
            Write-Warning "Unable to close smoke-test room cleanly: $($_.Exception.Message)"
        }
    }
    foreach ($process in $processes) {
        if (-not $process.HasExited) {
            $process.Kill()
            $process.WaitForExit(3000) | Out-Null
        }
    }
}
