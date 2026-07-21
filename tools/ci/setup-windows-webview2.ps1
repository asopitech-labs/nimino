param(
  [ValidateSet("x64", "arm64", "x86")]
  [string]$Architecture = "x64",
  [switch]$KeepInstaller
)

$ErrorActionPreference = "Stop"
$bootstrapperLinks = @{
  x64 = "https://go.microsoft.com/fwlink/p/?LinkId=2124703"
  arm64 = "https://go.microsoft.com/fwlink/p/?LinkId=2124704"
  x86 = "https://go.microsoft.com/fwlink/p/?LinkId=2099619"
}
$temp = Join-Path $env:TEMP "nimino-webview2"
$installer = Join-Path $temp "MicrosoftEdgeWebView2RuntimeInstaller.exe"
New-Item -ItemType Directory -Force -Path $temp | Out-Null

$runtimeRoots = @(
  (Join-Path ${env:ProgramFiles(x86)} "Microsoft\EdgeWebView\Application"),
  (Join-Path $env:ProgramFiles "Microsoft\EdgeWebView\Application")
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
$versions = foreach ($root in $runtimeRoots) {
  Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' }
}
if ($versions) {
  Write-Host ("WebView2 Runtime already installed: " + (($versions | Sort-Object Name -Descending | Select-Object -First 1).Name))
  exit 0
}

Write-Host "Downloading WebView2 Evergreen Bootstrapper ($Architecture)..."
Invoke-WebRequest -UseBasicParsing -Uri $bootstrapperLinks[$Architecture] -OutFile $installer
if (-not (Test-Path -LiteralPath $installer)) {
  throw "WebView2 bootstrapper was not downloaded"
}

Write-Host "Installing WebView2 Evergreen Runtime..."
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
  $process = Start-Process -FilePath $installer -ArgumentList "/silent", "/install" -Wait -PassThru
} else {
  Write-Host "Requesting Windows administrator elevation for Edge Update..."
  $process = Start-Process -FilePath $installer -ArgumentList "/silent", "/install" -Verb RunAs -Wait -PassThru
}
if ($process.ExitCode -ne 0) {
  $hex = "0x" + $process.ExitCode.ToString("X8")
  Write-Error "WebView2 installer failed with exit code $($process.ExitCode) ($hex)."
  Write-Error "Check EdgeUpdate logs under $env:ProgramData\Microsoft\EdgeUpdate\Log and $env:LOCALAPPDATA\Microsoft\EdgeUpdate\Log."
  throw "WebView2 Runtime installation failed"
}

$versions = foreach ($root in $runtimeRoots) {
  Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' }
}
if (-not $versions) {
  throw "WebView2 Runtime installation could not be verified"
}
Write-Host ("WebView2 Runtime installed: " + (($versions | Sort-Object Name -Descending | Select-Object -First 1).Name))

if (-not $KeepInstaller) {
  Remove-Item -LiteralPath $installer -Force -ErrorAction SilentlyContinue
}
