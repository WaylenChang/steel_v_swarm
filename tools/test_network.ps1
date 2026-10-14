param([Parameter(Mandatory = $true)][string]$Godot, [switch]$LobControl, [switch]$KineticShots, [switch]$MissileShots, [switch]$Reachability, [switch]$Footprints, [switch]$Cockpits, [switch]$Cameras, [switch]$Bursts, [switch]$Projectiles)
$ErrorActionPreference = 'Stop'
if (@($LobControl, $KineticShots, $MissileShots, $Reachability, $Footprints, $Cockpits, $Cameras, $Bursts, $Projectiles).Where({ $_ }).Count -gt 1) { throw 'Choose one gameplay transport fixture per run' }
$projectRoot = Split-Path $PSScriptRoot -Parent
$processes = @()
try {
    foreach ($mode in @('enet', 'websocket')) {
        $listenPort = if ($mode -eq 'enet') { 18762 } else { 18763 }
        $serverArguments = @('--headless', '--path', $projectRoot, '--', '--server', '--port', $listenPort)
        if ($MissileShots) { $serverArguments = @('--headless', '--path', $projectRoot, 'res://tests/missile_network.tscn', '--', '--server', '--port', $listenPort) }
        if ($Reachability) { $serverArguments = @('--headless', '--path', $projectRoot, 'res://tests/reachability_network.tscn', '--', '--server', '--port', $listenPort) }
        if ($Footprints) { $serverArguments = @('--headless', '--path', $projectRoot, 'res://tests/footprint_network.tscn', '--', '--server', '--port', $listenPort) }
        if ($Cockpits) { $serverArguments = @('--headless', '--path', $projectRoot, 'res://tests/cockpit_network.tscn', '--', '--server', '--port', $listenPort) }
        if ($Cameras) { $serverArguments = @('--headless', '--path', $projectRoot, 'res://tests/camera_network.tscn', '--', '--server', '--port', $listenPort) }
        if ($Bursts) { $serverArguments = @('--headless', '--path', $projectRoot, 'res://tests/burst_network.tscn', '--', '--server', '--port', $listenPort) }
        if ($Projectiles) { $serverArguments = @('--headless', '--path', $projectRoot, 'res://tests/projectile_visual_network.tscn', '--', '--server', '--port', $listenPort) }
        if ($mode -eq 'websocket') { $serverArguments += '--websocket' }
        $server = Start-Process -FilePath $Godot -ArgumentList $serverArguments -WindowStyle Hidden -PassThru -RedirectStandardOutput "$projectRoot/tests/$mode-server.log" -RedirectStandardError "$projectRoot/tests/$mode-server-errors.log"
        $processes += $server
        $target = if ($mode -eq 'enet') { '127.0.0.1' } else { "ws://127.0.0.1:$listenPort" }
        $clientArguments = @('--headless', '--path', $projectRoot, '--', '--connect', $target, '--port', $listenPort, '--network-test')
        if ($MissileShots) { $clientArguments = @('--headless', '--path', $projectRoot, 'res://tests/missile_network.tscn', '--', '--connect', $target, '--port', $listenPort, '--character', 't08', '--side', 'STEEL') }
        if ($Reachability) { $clientArguments = @('--headless', '--path', $projectRoot, 'res://tests/reachability_network.tscn', '--', '--connect', $target, '--port', $listenPort, '--character', 't09', '--side', 'STEEL') }
        if ($Footprints) { $clientArguments = @('--headless', '--path', $projectRoot, 'res://tests/footprint_network.tscn', '--', '--connect', $target, '--port', $listenPort, '--character', 't09', '--side', 'STEEL') }
        if ($Cockpits) { $clientArguments = @('--headless', '--path', $projectRoot, 'res://tests/cockpit_network.tscn', '--', '--connect', $target, '--port', $listenPort, '--character', 't03', '--side', 'STEEL') }
        if ($Cameras) { $clientArguments = @('--headless', '--path', $projectRoot, 'res://tests/camera_network.tscn', '--', '--connect', $target, '--port', $listenPort, '--character', 'm01', '--side', 'STEEL') }
        if ($Bursts) { $clientArguments = @('--headless', '--path', $projectRoot, 'res://tests/burst_network.tscn', '--', '--connect', $target, '--port', $listenPort, '--character', 't06', '--side', 'STEEL') }
        if ($Projectiles) { $clientArguments = @('--headless', '--path', $projectRoot, 'res://tests/projectile_visual_network.tscn', '--', '--connect', $target, '--port', $listenPort, '--character', 't09', '--side', 'STEEL') }
        if ($LobControl) { $clientArguments += @('--character', 't03', '--side', 'STEEL', '--network-lob-test') }
        if ($KineticShots) { $clientArguments += @('--character', 't04', '--side', 'STEEL', '--network-kinetic-test') }
        $client = Start-Process -FilePath $Godot -ArgumentList $clientArguments -WindowStyle Hidden -PassThru -RedirectStandardOutput "$projectRoot/tests/$mode-client.log" -RedirectStandardError "$projectRoot/tests/$mode-client-errors.log"
        $processes += $client
        if (-not $client.WaitForExit(20000)) { throw "$mode connection test timed out" }
        $log = Get-Content -LiteralPath "$projectRoot/tests/$mode-client.log" -Raw
        $errors = Get-Content -LiteralPath "$projectRoot/tests/$mode-client-errors.log" -Raw
        $serverErrors = Get-Content -LiteralPath "$projectRoot/tests/$mode-server-errors.log" -Raw
        if ($Bursts -and $log -notmatch 'NETWORK_BURST_PASS') { throw "$mode burst fixture failed: $log $errors $serverErrors" }
        if ($Projectiles -and $log -notmatch 'NETWORK_PROJECTILE_VISUAL_PASS') { throw "$mode projectile fixture failed: $log $errors $serverErrors" }
        if ($client.ExitCode -ne 0 -or $log -notmatch 'NETWORK_PASS' -or ($LobControl -and $log -notmatch 'NETWORK_LOB_PASS') -or ($KineticShots -and $log -notmatch 'NETWORK_KINETIC_PASS') -or ($MissileShots -and $log -notmatch 'NETWORK_MISSILE_PASS') -or ($Reachability -and $log -notmatch 'NETWORK_REACHABILITY_PASS') -or ($Footprints -and $log -notmatch 'NETWORK_FOOTPRINT_PASS') -or ($Cockpits -and $log -notmatch 'NETWORK_COCKPIT_PASS') -or ($Cameras -and $log -notmatch 'NETWORK_CAMERA_PASS') -or $errors -match 'ERROR|above the MTU' -or $serverErrors -match 'ERROR|above the MTU') {
            throw "$mode failed: $log $errors $serverErrors"
        }
        Write-Output "$mode $($log.Trim())"
        if (-not $server.HasExited) { Stop-Process -Id $server.Id }
    }
} finally {
    foreach ($process in $processes) {
        if (-not $process.HasExited) { Stop-Process -Id $process.Id }
    }
}
