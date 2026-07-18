param(
  [Parameter(Mandatory = $true)]
  [string]$HostExecutable,
  [switch]$WaitForPopupMessage
)

$tokenBytes = New-Object byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($tokenBytes)
$token = -join ($tokenBytes | ForEach-Object { $_.ToString("x2") })
$startInfo = New-Object System.Diagnostics.ProcessStartInfo
$startInfo.FileName = $HostExecutable
$startInfo.UseShellExecute = $false
$startInfo.RedirectStandardInput = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$startInfo.CreateNoWindow = $true
$startInfo.EnvironmentVariables["NIMINO_WSL_HOST_TOKEN"] = $token
$process = New-Object System.Diagnostics.Process
$process.StartInfo = $startInfo

function Write-Frame([hashtable]$message) {
  $json = [System.Text.Encoding]::UTF8.GetBytes(($message | ConvertTo-Json -Compress))
  $length = [System.BitConverter]::GetBytes([uint32]$json.Length)
  if ([System.BitConverter]::IsLittleEndian) { [System.Array]::Reverse($length) }
  $stream = $process.StandardInput.BaseStream
  $stream.Write($length, 0, $length.Length)
  $stream.Write($json, 0, $json.Length)
  $stream.Flush()
}

function Read-Exactly([int]$count) {
  $buffer = New-Object byte[] $count
  $offset = 0
  while ($offset -lt $count) {
    $read = $process.StandardOutput.BaseStream.Read($buffer, $offset, $count - $offset)
    if ($read -le 0) { throw "Interactive host closed stdout" }
    $offset += $read
  }
  return ,$buffer
}

function Read-Frame {
  $lengthBytes = Read-Exactly 4
  if ([System.BitConverter]::IsLittleEndian) { [System.Array]::Reverse($lengthBytes) }
  $length = [System.BitConverter]::ToUInt32($lengthBytes, 0)
  if ($length -gt 1048576) { throw "Interactive host returned an oversized frame" }
  [System.Text.Encoding]::UTF8.GetString((Read-Exactly ([int]$length))) | ConvertFrom-Json
}

function Close-InteractiveHost {
  if (-not $process -or $process.HasExited) { return }
  try {
    Write-Frame @{ version = 1; kind = "shutdown"; sessionId = $ready.sessionId; authenticationToken = ""; requestId = "99"; eventId = "0"; method = ""; payload = ""; error = ""; timeoutMs = 2000 }
    [void]$process.WaitForExit(2000)
  } catch {
    # Fall through to the hard cleanup below.
  }
  if (-not $process.HasExited) {
    $process.Kill()
    $process.WaitForExit()
  }
}

try {
  if (-not $process.Start()) { throw "Unable to start nimino-wsl-host.exe" }
  Write-Frame @{ version = 1; kind = "hello"; sessionId = ""; authenticationToken = $token; requestId = "1"; eventId = "0"; method = ""; payload = ""; error = ""; timeoutMs = 5000 }
  $ready = Read-Frame
  if ($ready.kind -ne "ready") { throw "Host handshake failed" }
  Write-Frame @{ version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""; requestId = "2"; eventId = "0"; method = "native.window.create"; payload = '{"title":"Nimino interactive WebView2","width":1000,"height":700}'; error = ""; timeoutMs = 5000 }
  $window = Read-Frame
  $windowId = ($window.payload | ConvertFrom-Json).windowId
  Write-Frame @{ version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""; requestId = "3"; eventId = "0"; method = "native.webview.create"; payload = (ConvertTo-Json -Compress @{ windowId = $windowId }); error = ""; timeoutMs = 5000 }
  $view = Read-Frame
  $webViewId = ($view.payload | ConvertFrom-Json).webViewId
  Write-Frame @{ version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""; requestId = "4"; eventId = "0"; method = "native.webview.setNavigationRules"; payload = (ConvertTo-Json -Compress @{ webViewId = $webViewId; allow = @("**"); deny = @() }); error = ""; timeoutMs = 5000 }
  [void](Read-Frame)
  $popupDocument = '<!doctype html><script>window.opener.postMessage("nimino-popup-message", "*");</script><p>popup ready</p>'
  $popupUrl = "data:text/html," + [System.Uri]::EscapeDataString($popupDocument)
  $html = '<!doctype html><meta charset="utf-8"><script>window.addEventListener("message", function(event) { if (event.data === "nimino-popup-message") chrome.webview.postMessage("popup-message-received"); });</script><h1>Nimino WebView2 interactive test</h1><p>Click the control below.</p><a id="popup" href="' + $popupUrl + '" target="_blank" onclick="chrome.webview.postMessage(''clicked-link'')">OPEN POPUP LINK</a><br><button onclick="window.open(''' + $popupUrl + ''', ''_blank'')">OPEN POPUP BUTTON</button>'
  Write-Frame @{ version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""; requestId = "5"; eventId = "0"; method = "native.webview.loadHtml"; payload = (ConvertTo-Json -Compress @{ webViewId = $webViewId; html = $html }); error = ""; timeoutMs = 5000 }
  [void](Read-Frame)
  Write-Host "Window opened. Click the link or button; Ctrl+C closes the interactive host." -ForegroundColor Green
  if ($WaitForPopupMessage) {
    Write-Host "Popup message test is armed; click once and wait for automatic result." -ForegroundColor Yellow
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
      $message = Read-Frame
      if ($message.kind -eq "event" -and $message.method -eq "native.webview.message") {
        $payload = $message.payload | ConvertFrom-Json
        if ($payload.message -eq "popup-message-received") {
          Write-Output "WSL popup message smoke passed"
          return
        }
      }
    }
    throw "Popup message was not received within 60 protocol frames"
  }
  while ($true) {
    $message = Read-Frame
    if ($message.kind -eq "event") {
      Write-Host ("EVENT {0}: {1}" -f $message.method, $message.payload)
    }
  }
}
finally {
  Close-InteractiveHost
  if ($process) { $process.Dispose() }
}
