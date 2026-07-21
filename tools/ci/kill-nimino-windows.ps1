$ErrorActionPreference = "SilentlyContinue"

$processes = @()
$processes += Get-CimInstance Win32_Process -Filter "Name='nimino-wsl-host.exe'"
$processes += Get-CimInstance Win32_Process -Filter "Name='msedgewebview2.exe'" |
  Where-Object { $_.CommandLine -match '(?i)nimino' }

if (-not $processes) {
  Write-Output "No Nimino host or Nimino WebView2 process found"
  exit 0
}

foreach ($process in $processes | Sort-Object ProcessId -Unique) {
  Write-Output ("Killing {0} PID {1}" -f $process.Name, $process.ProcessId)
  & taskkill.exe /PID $process.ProcessId /T /F *> $null
}
