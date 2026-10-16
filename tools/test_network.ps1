param([Parameter(Mandatory = $true)][string]$Godot, [switch]$LobControl, [switch]$KineticShots, [switch]$MissileShots, [switch]$Reachability, [switch]$Footprints, [switch]$Cockpits, [switch]$Cameras, [switch]$Bursts, [switch]$Projectiles, [switch]$Aiming, [switch]$MissileDefenses, [switch]$Bots, [switch]$Bosses, [switch]$Campaign, [switch]$Super, [switch]$Controls, [switch]$Mobile, [switch]$View, [switch]$Bodies, [switch]$Tps, [switch]$Deaths, [switch]$Blasts)
$ErrorActionPreference = 'Stop'
if (@($LobControl, $KineticShots, $MissileShots, $Reachability, $Footprints, $Cockpits, $Cameras, $Bursts, $Projectiles, $Aiming, $MissileDefenses, $Bots, $Bosses, $Campaign, $Super, $Controls, $Mobile, $View, $Bodies, $Tps, $Deaths, $Blasts).Where({ $_ }).Count -gt 1) { throw 'Choose one gameplay transport fixture per run' }
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
        if ($Aiming) { $serverArguments = @('--headless', '--path', $projectRoot, 'res://tests/aiming_network.tscn', '--', '--server', '--port', $listenPort) }
        if ($MissileDefenses) { $serverArguments = @('--headless', '--path', $projectRoot, 'res://tests/missile_defense_network.tscn', '--', '--server', '--port', $listenPort) }
        if ($Bots) { $serverArguments = @('--headless', '--path', $projectRoot, 'res://tests/bot_network.tscn', '--', '--server', '--port', $listenPort) }
        if ($Bosses) { $serverArguments = @('--headless', '--path', $projectRoot, 'res://tests/boss_network.tscn', '--', '--server', '--port', $listenPort) }
        if ($Campaign) { $serverArguments = @('--headless', '--path', $projectRoot, 'res://tests/campaign_network.tscn', '--', '--server', '--campaign', 'ch1', '--side', 'STEEL', '--character', 't06', '--port', $listenPort) }
        if ($Super) { $serverArguments = @('--headless', '--path', $projectRoot, 'res://tests/super_network.tscn', '--', '--server', '--super', '--port', $listenPort) }
        if ($Controls) { $serverArguments = @('--headless', '--path', $projectRoot, 'res://tests/controls_network.tscn', '--', '--server', '--port', $listenPort) }
        if ($Mobile) { $serverArguments = @('--headless', '--path', $projectRoot, 'res://tests/mobile_network.tscn', '--', '--server', '--ctrl', 'pad', '--port', $listenPort) }
        if ($View) { $serverArguments = @('--headless', '--path', $projectRoot, 'res://tests/view_network.tscn', '--', '--server', '--ctrl', 'pad', '--port', $listenPort) }
        if ($Bodies) { $serverArguments = @('--headless', '--path', $projectRoot, 'res://tests/body_network.tscn', '--', '--server', '--port', $listenPort) }
        if ($Tps) { $serverArguments = @('--headless', '--path', $projectRoot, 'res://tests/tps_network.tscn', '--', '--server', '--port', $listenPort) }
        if ($Deaths) { $serverArguments = @('--headless', '--path', $projectRoot, 'res://tests/death_network.tscn', '--', '--server', '--port', $listenPort) }
        if ($Blasts) { $serverArguments = @('--headless', '--path', $projectRoot, 'res://tests/blast_network.tscn', '--', '--server', '--port', $listenPort) }
        $serverArguments += @('--view', $(if ($Tps) { 'tps' } else { 'fpv' }))
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
        if ($Aiming) { $clientArguments = @('--headless', '--path', $projectRoot, 'res://tests/aiming_network.tscn', '--', '--connect', $target, '--port', $listenPort, '--character', 't09', '--side', 'STEEL') }
        if ($MissileDefenses) { $clientArguments = @('--headless', '--path', $projectRoot, 'res://tests/missile_defense_network.tscn', '--', '--connect', $target, '--port', $listenPort, '--character', 't04', '--side', 'STEEL') }
        if ($Bots) { $clientArguments = @('--headless', '--path', $projectRoot, 'res://tests/bot_network.tscn', '--', '--connect', $target, '--port', $listenPort, '--character', 't01', '--side', 'STEEL') }
        if ($Bosses) { $clientArguments = @('--headless', '--path', $projectRoot, 'res://tests/boss_network.tscn', '--', '--connect', $target, '--port', $listenPort, '--character', 't01', '--side', 'STEEL') }
        if ($Campaign) { $clientArguments = @('--headless', '--path', $projectRoot, 'res://tests/campaign_network.tscn', '--', '--connect', $target, '--port', $listenPort, '--character', 't06', '--side', 'STEEL') }
        if ($Super) { $clientArguments = @('--headless', '--path', $projectRoot, 'res://tests/super_network.tscn', '--', '--connect', $target, '--port', $listenPort, '--character', 's09', '--side', 'SUPER') }
        if ($Controls) { $clientArguments = @('--headless', '--path', $projectRoot, 'res://tests/controls_network.tscn', '--', '--connect', $target, '--port', $listenPort, '--character', 't01', '--side', 'STEEL') }
        if ($Mobile) { $clientArguments = @('--headless', '--path', $projectRoot, 'res://tests/mobile_network.tscn', '--', '--connect', $target, '--ctrl', 'pad', '--port', $listenPort, '--character', 't01', '--side', 'STEEL') }
        if ($View) { $clientArguments = @('--headless', '--path', $projectRoot, 'res://tests/view_network.tscn', '--', '--connect', $target, '--ctrl', 'pad', '--port', $listenPort, '--character', 't01', '--side', 'STEEL') }
        if ($Bodies) { $clientArguments = @('--headless', '--path', $projectRoot, 'res://tests/body_network.tscn', '--', '--connect', $target, '--port', $listenPort, '--character', 't01', '--side', 'STEEL') }
        if ($Tps) { $clientArguments = @('--headless', '--path', $projectRoot, 'res://tests/tps_network.tscn', '--', '--connect', $target, '--port', $listenPort, '--character', 't01', '--side', 'STEEL') }
        if ($Deaths) { $clientArguments = @('--headless', '--path', $projectRoot, 'res://tests/death_network.tscn', '--', '--connect', $target, '--port', $listenPort, '--character', 't06', '--side', 'STEEL') }
        if ($Blasts) { $clientArguments = @('--headless', '--path', $projectRoot, 'res://tests/blast_network.tscn', '--', '--connect', $target, '--port', $listenPort, '--character', 't06', '--side', 'STEEL') }
        if ($LobControl) { $clientArguments += @('--character', 't03', '--side', 'STEEL', '--network-lob-test') }
        if ($KineticShots) { $clientArguments += @('--character', 't04', '--side', 'STEEL', '--network-kinetic-test') }
        $clientArguments += @('--view', $(if ($Tps) { 'tps' } else { 'fpv' }))
        $client = Start-Process -FilePath $Godot -ArgumentList $clientArguments -WindowStyle Hidden -PassThru -RedirectStandardOutput "$projectRoot/tests/$mode-client.log" -RedirectStandardError "$projectRoot/tests/$mode-client-errors.log"
        $processes += $client
        if (-not $client.WaitForExit(20000)) { throw "$mode connection test timed out" }
        $log = Get-Content -LiteralPath "$projectRoot/tests/$mode-client.log" -Raw
        $errors = Get-Content -LiteralPath "$projectRoot/tests/$mode-client-errors.log" -Raw
        $serverErrors = Get-Content -LiteralPath "$projectRoot/tests/$mode-server-errors.log" -Raw
        if ($Bursts -and $log -notmatch 'NETWORK_BURST_PASS') { throw "$mode burst fixture failed: $log $errors $serverErrors" }
        if ($Projectiles -and $log -notmatch 'NETWORK_PROJECTILE_VISUAL_PASS') { throw "$mode projectile fixture failed: $log $errors $serverErrors" }
        if ($Aiming -and $log -notmatch 'NETWORK_AIMING_PASS') { throw "$mode aiming fixture failed: $log $errors $serverErrors" }
        if ($MissileDefenses -and $log -notmatch 'NETWORK_MISSILE_DEFENSE_PASS') { throw "$mode missile defense fixture failed: $log $errors $serverErrors" }
        if ($Bots -and $log -notmatch 'NETWORK_BOT_PASS') { throw "$mode bot fixture failed: $log $errors $serverErrors" }
        if ($Bosses -and $log -notmatch 'NETWORK_BOSS_PASS') { throw "$mode boss fixture failed: $log $errors $serverErrors" }
        if ($Campaign -and $log -notmatch 'NETWORK_CAMPAIGN_PASS') { throw "$mode campaign fixture failed: $log $errors $serverErrors" }
        if ($Super -and $log -notmatch 'NETWORK_SUPER_PASS') { throw "$mode super fixture failed: $log $errors $serverErrors" }
        if ($Controls -and $log -notmatch 'NETWORK_CONTROLS_PASS') { throw "$mode controls fixture failed: $log $errors $serverErrors" }
        if ($Mobile -and $log -notmatch 'NETWORK_MOBILE_PASS') { throw "$mode mobile fixture failed: $log $errors $serverErrors" }
        if ($View -and $log -notmatch 'NETWORK_VIEW_PASS') { throw "$mode view fixture failed: $log $errors $serverErrors" }
        if ($Bodies -and $log -notmatch 'NETWORK_BODY_PASS') { throw "$mode body fixture failed: $log $errors $serverErrors" }
        if ($Tps -and $log -notmatch 'NETWORK_TPS_PASS') { throw "$mode TPS fixture failed: $log $errors $serverErrors" }
        if ($Deaths -and $log -notmatch 'NETWORK_DEATH_PASS') { throw "$mode death fixture failed: $log $errors $serverErrors" }
        if ($Blasts -and $log -notmatch 'NETWORK_BLAST_PASS') { throw "$mode blast fixture failed: $log $errors $serverErrors" }
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
