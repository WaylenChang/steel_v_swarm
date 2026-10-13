param([Parameter(Mandatory = $true)][string]$Godot)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$processes = @()
try {
    foreach ($mode in @('enet', 'websocket')) {
        $listenPort = if ($mode -eq 'enet') { 18762 } else { 18763 }
        $serverArguments = @('--headless', '--path', $projectRoot, '--', '--server', '--port', $listenPort)
        if ($mode -eq 'websocket') { $serverArguments += '--websocket' }
        $server = Start-Process -FilePath $Godot -ArgumentList $serverArguments -WindowStyle Hidden -PassThru -RedirectStandardOutput "$projectRoot/tests/$mode-server.log" -RedirectStandardError "$projectRoot/tests/$mode-server-errors.log"
        $processes += $server
        $target = if ($mode -eq 'enet') { '127.0.0.1' } else { "ws://127.0.0.1:$listenPort" }
        $client = Start-Process -FilePath $Godot -ArgumentList @('--headless', '--path', $projectRoot, '--', '--connect', $target, '--port', $listenPort, '--network-test') -WindowStyle Hidden -PassThru -RedirectStandardOutput "$projectRoot/tests/$mode-client.log" -RedirectStandardError "$projectRoot/tests/$mode-client-errors.log"
        $processes += $client
        if (-not $client.WaitForExit(20000)) { throw "$mode connection test timed out" }
        $log = Get-Content -LiteralPath "$projectRoot/tests/$mode-client.log" -Raw
        $errors = Get-Content -LiteralPath "$projectRoot/tests/$mode-client-errors.log" -Raw
        $serverErrors = Get-Content -LiteralPath "$projectRoot/tests/$mode-server-errors.log" -Raw
        if ($client.ExitCode -ne 0 -or $log -notmatch 'NETWORK_PASS' -or $errors -match 'ERROR|above the MTU' -or $serverErrors -match 'ERROR|above the MTU') {
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
