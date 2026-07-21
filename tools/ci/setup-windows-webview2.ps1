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

Write-Host "Downloading WebView2 Evergreen Bootstrapper ($Architecture)..."
Invoke-WebRequest -UseBasicParsing -Uri $bootstrapperLinks[$Architecture] -OutFile $installer
if (-not (Test-Path -LiteralPath $installer)) {
  throw "WebView2 bootstrapper was not downloaded"
}

Write-Host "Installing WebView2 Evergreen Runtime..."
$process = Start-Process -FilePath $installer -ArgumentList "/silent", "/install" -Wait -PassThru
if ($process.ExitCode -ne 0) {
  throw "WebView2 installer failed with exit code $($process.ExitCode)"
}

$runtimeRoots = @(
  (Join-Path ${env:ProgramFiles(x86)} "Microsoft\EdgeWebView\Application"),
  (Join-Path $env:ProgramFiles "Microsoft\EdgeWebView\Application")
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
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
