[CmdletBinding()]
param(
    [string]$StudioDir = '',
    [ValidateSet('debug', 'release')][string]$BuildMode = 'debug',
    [switch]$AppPackage
)

$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($StudioDir)) { $StudioDir = $env:DEVECO_STUDIO_HOME }
if ([string]::IsNullOrWhiteSpace($StudioDir)) {
    $candidates = @(
        (Join-Path $env:ProgramFiles 'Huawei\DevEco Studio'),
        'E:\devecostudio-windows-26.0.0.821\devecostudio-windows-26.0.0.821\DevEco Studio'
    )
    $StudioDir = $candidates | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'tools\hvigor\bin\hvigorw.bat') } | Select-Object -First 1
}
if ([string]::IsNullOrWhiteSpace($StudioDir)) {
    Write-Error 'Pass -StudioDir or set DEVECO_STUDIO_HOME to your DevEco Studio installation.'
    exit 1
}
$hvigor = Join-Path $StudioDir 'tools\hvigor\bin\hvigorw.bat'
foreach ($required in @($hvigor, (Join-Path $StudioDir 'jbr\bin\java.exe'), (Join-Path $StudioDir 'sdk'))) {
    if (-not (Test-Path -LiteralPath $required)) { Write-Error "Missing build dependency: $required"; exit 1 }
}
$previousPath = $env:PATH
$previousSdk = $env:DEVECO_SDK_HOME
$previousJava = $env:JAVA_HOME
$buildCode = 1
Push-Location -LiteralPath $projectDirectory
try {
    $env:JAVA_HOME = Join-Path $StudioDir 'jbr'
    $env:PATH = (Join-Path $StudioDir 'jbr\bin') + ';' + (Join-Path $StudioDir 'tools\node') + ';' + $env:PATH
    $env:DEVECO_SDK_HOME = Join-Path $StudioDir 'sdk'
    $buildArgs = @('assembleHap', '--no-daemon', '--mode', 'module', '-p', 'module=entry@default', '-p', 'product=default', '-p', "buildMode=$BuildMode")
    if ($AppPackage) { $buildArgs = @('assembleApp', '--no-daemon', '--mode', 'project', '-p', 'product=default', '-p', "buildMode=$BuildMode") }
    & $hvigor @buildArgs
    $buildCode = $LASTEXITCODE
} catch {
    Write-Host "Build failed: $($_.Exception.Message)"
} finally {
    Pop-Location
    $env:PATH = $previousPath
    $env:DEVECO_SDK_HOME = $previousSdk
    $env:JAVA_HOME = $previousJava
}
exit $buildCode
