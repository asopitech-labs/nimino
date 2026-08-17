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

# Capture the host's own output. It is a GUI-subsystem binary with no console,
# so without redirection every diagnostic it writes is discarded and a failure
# here looks like silence.  Start it through Process.Start rather than
# Start-Process -PassThru: the object the latter returns reports HasExited but
# leaves ExitCode null once output is redirected, so a clean shutdown becomes
# indistinguishable from a crash and the smoke fails on a host that exited 0.
$startInfo = New-Object System.Diagnostics.ProcessStartInfo
$startInfo.FileName = $hostExecutable
# Windows PowerShell 5.1 runs on .NET Framework, where ProcessStartInfo has no
# ArgumentList; quote the manifest path into the single Arguments string so a
# path containing spaces still reaches the host as one argument.
$startInfo.Arguments = '--manifest "{0}"' -f $manifest
$startInfo.UseShellExecute = $false
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$process = [System.Diagnostics.Process]::Start($startInfo)
# Drain both pipes on background tasks: a GUI host that fills the buffer
# blocks on write, which would look like a hang at the WebView2 check.
$stdoutReader = $process.StandardOutput.ReadToEndAsync()
$stderrReader = $process.StandardError.ReadToEndAsync()
Write-Output ("pack smoke: started nimino-host PID {0}" -f $process.Id)

function Write-HostDiagnostics {
  # The readers complete when the host closes its pipes, which a live process
  # has not done yet; report what has arrived without waiting on either task.
  foreach ($stream in @(
      @{ Name = 'stdout'; Task = $stdoutReader },
      @{ Name = 'stderr'; Task = $stderrReader })) {
    if ($stream.Task.IsCompleted) {
      $text = $stream.Task.Result
      if ($text) {
        Write-Output ("pack smoke: --- {0} ---" -f $stream.Name)
        Write-Output $text
      }
    }
  }
  # MainWindowTitle reports one window; a failure may have put up another.
  Get-Process -Id $process.Id -ErrorAction SilentlyContinue |
    ForEach-Object { $_.Refresh(); $_ } |
    Where-Object { $_.MainWindowHandle -ne 0 } |
    ForEach-Object { Write-Output ("pack smoke: window '{0}'" -f $_.MainWindowTitle) }
}

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
    # Report what the machine actually offers before blaming the package. The
    # bundle does not install the Evergreen Runtime -- the NSIS and MSI
    # installers do that -- so a host that starts and then never spawns a
    # WebView2 child is usually a machine without the runtime, which is a
    # different failure from a broken build.
    $runtimeKeys = @(
      'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
      'HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
    )
    $installed = $false
    foreach ($key in $runtimeKeys) {
      $entry = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
      if ($entry -and $entry.pv) {
        Write-Output ("pack smoke: WebView2 Evergreen Runtime {0} is installed ({1})" -f $entry.pv, $key)
        $installed = $true
      }
    }
    if (-not $installed) {
      Write-Output 'pack smoke: no WebView2 Evergreen Runtime is registered on this machine'
    }
    Write-Output ("pack smoke: main window title at failure: '{0}'" -f $process.MainWindowTitle)
    Write-HostDiagnostics
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
