param([switch]$Elevated)

$ErrorActionPreference = "SilentlyContinue"

if (-not $Elevated) {
  $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output "Requesting administrator elevation to clean Nimino processes..."
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Elevated"
    $elevatedProcess = Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments -Wait -PassThru
    exit $elevatedProcess.ExitCode
  }
}

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
