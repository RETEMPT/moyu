[CmdletBinding()]
param(
    [string]$Target = '',
    [string]$StudioDir = 'E:\devecostudio-windows-26.0.0.821\devecostudio-windows-26.0.0.821\DevEco Studio',
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$hdcExecutable = Join-Path $StudioDir 'sdk\default\openharmony\toolchains\hdc.exe'
$bundleName = 'com.retempt.flowmind'

function Invoke-Hdc {
    param([string[]]$CommandArgs, [int]$TimeoutSeconds = 30)
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $hdcExecutable
    # Windows argument quoting: double backslashes before quotes and at the end.
    $startInfo.Arguments = ($CommandArgs | ForEach-Object {
        $escaped = [regex]::Replace($_, '(\\*)"', '$1$1\"')
        '"' + [regex]::Replace($escaped, '(\\+)$', '$1$1') + '"'
    }) -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill()
            throw "hdc timed out: $($CommandArgs -join ' ')"
        }
        $output = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        return [PSCustomObject]@{ ExitCode = $process.ExitCode; Output = $output.Trim() }
    } finally {
        $process.Dispose()
    }
}

function Get-ConnectedTargets {
    $result = Invoke-Hdc -CommandArgs @('list', 'targets', '-v')
    if ($result.ExitCode -ne 0) { throw $result.Output }
    foreach ($line in ($result.Output -split '\r?\n')) {
        $fields = $line.Trim() -split '\s+'
        if ($fields.Length -ge 3 -and $fields[2] -eq 'Connected') { $fields[0] }
    }
}

function Wait-ForTarget {
    param([string]$ConnectKey)
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $probe = Invoke-Hdc -CommandArgs @('-t', $ConnectKey, 'shell', 'echo flowmind-deploy-ready')
        if ($probe.ExitCode -eq 0 -and $probe.Output -eq 'flowmind-deploy-ready') { return }
        if ($attempt -lt 3) {
            Write-Host "Connection not ready ($attempt/3). Waiting for $ConnectKey..."
            # Reconnect only this TCP target; do not restart the shared hdc server.
            if ($ConnectKey -match '^[A-Za-z0-9_.-]+:\d+$') {
                [void](Invoke-Hdc -CommandArgs @('tconn', $ConnectKey))
            }
            Start-Sleep -Seconds 2
        }
    }
    throw "Target connection is unavailable: $ConnectKey. Wait for the emulator to finish booting, then retry."
}

try {
    if (-not (Test-Path -LiteralPath $hdcExecutable -PathType Leaf)) {
        throw "hdc was not found. Pass -StudioDir with the path to your DevEco Studio installation."
    }
    $connected = @(Get-ConnectedTargets)
    if ($Target.Length -eq 0) {
        if ($connected.Count -eq 0) { throw 'No connected device or emulator. Ready/offline ports cannot be deployed to.' }
        if ($connected.Count -gt 1) { throw "Multiple connected targets: $($connected -join ', '). Pass -Target to select one." }
        $Target = $connected[0]
    } elseif ($connected -notcontains $Target) {
        throw "Target is not connected: $Target. Connected targets: $($connected -join ', ')"
    }
    Write-Host "[1/4] Verifying connection to $Target..."
    Wait-ForTarget -ConnectKey $Target

    if (-not $SkipBuild) {
        Write-Host '[2/4] Building HAP...'
        $env:PATH = (Join-Path $StudioDir 'jbr\bin') + ';' + $env:PATH
        $env:DEVECO_SDK_HOME = Join-Path $StudioDir 'sdk'
        $hvigor = Join-Path $StudioDir 'tools\hvigor\bin\hvigorw.bat'
        Push-Location -LiteralPath $projectDirectory
        try {
            & $hvigor assembleHap --mode module -p module=entry@default -p product=default
            if ($LASTEXITCODE -ne 0) { throw 'HAP build failed.' }
        } finally { Pop-Location }
    } else {
        Write-Host '[2/4] Using existing HAP (-SkipBuild).'
    }

    $outputDirectory = Join-Path $projectDirectory 'entry\build\default\outputs\default'
    $unsignedPath = Join-Path $outputDirectory 'entry-default-unsigned.hap'
    $signedPath = Join-Path $outputDirectory 'entry-default-signed.hap'
    $hapPath = $unsignedPath
    if ((Test-Path -LiteralPath $signedPath) -and
        (-not (Test-Path -LiteralPath $unsignedPath) -or
        (Get-Item -LiteralPath $signedPath).LastWriteTime -ge (Get-Item -LiteralPath $unsignedPath).LastWriteTime)) {
        $hapPath = $signedPath
    }
    if (-not (Test-Path -LiteralPath $hapPath -PathType Leaf)) { throw "HAP not found: $hapPath" }
    Write-Host "[3/4] Installing $hapPath (replace, keep application data)..."
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Wait-ForTarget -ConnectKey $Target
        $install = Invoke-Hdc -CommandArgs @('-t', $Target, 'install', '-r', $hapPath) -TimeoutSeconds 60
        Write-Host $install.Output
        if ($install.ExitCode -eq 0 -and $install.Output -match 'install bundle successfully') { break }
        $transportFailure = $install.Output -match '(?i)FileTransfer|device not found|found no devices|not connected|connect.*fail|connection.*closed'
        if (-not $transportFailure -or $attempt -eq 3) {
            throw 'Installation failed. Check the message above for connection, signing or SDK compatibility errors.'
        }
        Write-Host "Transfer interrupted ($attempt/3); retrying the same target..."
        Start-Sleep -Seconds 2
    }

    Write-Host "[4/4] Starting $bundleName..."
    Wait-ForTarget -ConnectKey $Target
    $launch = Invoke-Hdc -CommandArgs @('-t', $Target, 'shell', "aa start -a EntryAbility -b $bundleName -m entry")
    Write-Host $launch.Output
    if ($launch.ExitCode -ne 0 -or $launch.Output -notmatch 'start ability successfully') { throw 'Ability launch failed.' }
    Start-Sleep -Seconds 2
    $ability = Invoke-Hdc -CommandArgs @('-t', $Target, 'shell', 'aa dump -a')
    if ($ability.ExitCode -ne 0 -or $ability.Output -notmatch '(?s)app name \[com\.retempt\.flowmind\].{0,800}?state #FOREGROUND') {
        throw 'The ability is not in the foreground. Check application crash logs or whether another app took focus.'
    }
    Write-Host "[SUCCESS] Installed and running in foreground on $Target."
    exit 0
} catch {
    Write-Host "[ERROR] $($_.Exception.Message)"
    exit 1
}
