$ErrorActionPreference = "Continue"

$processes = @()
$processes += Get-CimInstance Win32_Process -Filter "Name='nimino-wsl-host.exe'" -ErrorAction SilentlyContinue
$processes += Get-CimInstance Win32_Process -Filter "Name='msedgewebview2.exe'" |
  Where-Object { $_.CommandLine -match '(?i)nimino' }

if (-not $processes) {
  Write-Output "No Nimino host or Nimino WebView2 process found"
  exit 0
}

$failed = $false
foreach ($process in $processes | Sort-Object ProcessId -Unique) {
  Write-Output ("Killing {0} PID {1}" -f $process.Name, $process.ProcessId)
  & taskkill.exe /PID $process.ProcessId /T /F *> $null
  for ($attempt = 0; $attempt -lt 20; $attempt++) {
    if ($null -eq (Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue)) {
      break
    }
    Start-Sleep -Milliseconds 100
  }
  if ($null -ne (Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue)) {
    Write-Error ("Could not terminate {0} PID {1} without elevation" -f $process.Name, $process.ProcessId)
    $failed = $true
  }
}

if ($failed) { exit 1 }
