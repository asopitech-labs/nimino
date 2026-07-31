# Launches a nimino-pack generated Windows bundle with the generic host and
# verifies that the packaged application actually starts on this machine:
# runtime DLLs resolve, the Win32 window is created, WebView2 initializes, and
# a WM_CLOSE request shuts the host down with exit code 0.
param(
  [Parameter(Mandatory = $true)][string]$BundleDirectory,
  [int]$StartupTimeoutMs = 30000,
  [int]$WebViewTimeoutMs = 30000,
  [int]$SteadyStateMs = 3000
)

$ErrorActionPreference = 'Stop'

$hostExecutable = Join-Path $BundleDirectory 'nimino-host.exe'
$manifest = Join-Path $BundleDirectory 'nimino-manifest.json'
foreach ($required in @(
    $hostExecutable,
    $manifest,
    (Join-Path $BundleDirectory 'WebView2Loader.dll'),
    (Join-Path $BundleDirectory 'pcre64.dll'))) {
  if (-not (Test-Path -LiteralPath $required)) {
    throw "pack smoke: bundle file is missing: $required"
  }
}

$process = Start-Process -FilePath $hostExecutable `
  -ArgumentList @('--manifest', $manifest) -PassThru
Write-Output ("pack smoke: started nimino-host PID {0}" -f $process.Id)

try {
  $deadline = [DateTime]::UtcNow.AddMilliseconds($StartupTimeoutMs)
  while ([DateTime]::UtcNow -lt $deadline -and $process.MainWindowHandle -eq 0) {
    if ($process.HasExited) {
      throw ("pack smoke: nimino-host exited during startup with code {0}" -f $process.ExitCode)
    }
    Start-Sleep -Milliseconds 200
    $process.Refresh()
  }
  if ($process.MainWindowHandle -eq 0) {
    throw 'pack smoke: nimino-host did not create a main window'
  }
  Write-Output ("pack smoke: main window created: '{0}'" -f $process.MainWindowTitle)

  # WebView2 runtime children carry the owning executable in their command
  # line (--webview-exe-name=nimino-host.exe), which proves the packaged
  # host's WebView2 environment came up regardless of the profile directory.
  $webViewDeadline = [DateTime]::UtcNow.AddMilliseconds($WebViewTimeoutMs)
  $webViewReady = $false
  while ([DateTime]::UtcNow -lt $webViewDeadline) {
    if ($process.HasExited) {
      throw ("pack smoke: nimino-host exited before WebView2 startup with code {0}" -f $process.ExitCode)
    }
    $webView = Get-CimInstance Win32_Process -Filter "Name='msedgewebview2.exe'" -ErrorAction SilentlyContinue |
      Where-Object { $_.CommandLine -match '(?i)--webview-exe-name=nimino-host\.exe' }
    if ($webView) {
      $webViewReady = $true
      break
    }
    Start-Sleep -Milliseconds 500
  }
  if (-not $webViewReady) {
    throw 'pack smoke: no WebView2 runtime process appeared for the packaged host'
  }
  Write-Output 'pack smoke: WebView2 runtime is running'

  Start-Sleep -Milliseconds $SteadyStateMs
  $process.Refresh()
  if ($process.HasExited) {
    throw ("pack smoke: nimino-host crashed after startup with code {0}" -f $process.ExitCode)
  }

  if (-not $process.CloseMainWindow()) {
    throw 'pack smoke: WM_CLOSE could not be delivered to the main window'
  }
  if (-not $process.WaitForExit(10000)) {
    throw 'pack smoke: nimino-host ignored the close request'
  }
  if ($process.ExitCode -ne 0) {
    throw ("pack smoke: nimino-host exited with code {0} after close" -f $process.ExitCode)
  }
  Write-Output 'pack smoke: PASS'
}
finally {
  if (-not $process.HasExited) {
    & taskkill.exe /PID $process.Id /T /F *> $null
  }
}
