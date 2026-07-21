param(
  [Parameter(Mandatory = $true)]
  [string]$HostExecutable,
  [switch]$WaitForNewWindowRequest
)

## Keep this value in sync with packages/wsl/src/nimino_wsl/protocol/versioning.nim.
$script:protocolVersion = 2

function Assert-WebView2Runtime {
  $roots = @(
    (Join-Path ${env:ProgramFiles(x86)} "Microsoft\EdgeWebView\Application"),
    (Join-Path $env:ProgramFiles "Microsoft\EdgeWebView\Application")
  ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
  $versions = foreach ($root in $roots) {
    Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' }
  }
  if (-not $versions) {
    throw "WebView2 Evergreen Runtime is not installed. Run: make setup-windows-webview2"
  }
}
Assert-WebView2Runtime

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
  $message.version = $script:protocolVersion
  $json = [System.Text.Encoding]::UTF8.GetBytes(($message | ConvertTo-Json -Compress))
  $length = [System.BitConverter]::GetBytes([uint32]$json.Length)
  if ([System.BitConverter]::IsLittleEndian) { [System.Array]::Reverse($length) }
  $stream = $process.StandardInput.BaseStream
  $stream.Write($length, 0, $length.Length)
  $stream.Write($json, 0, $json.Length)
  $stream.Flush()
}

function Read-Exactly([int]$count, [int]$timeoutMs = 0) {
  $buffer = New-Object byte[] $count
  $offset = 0
  while ($offset -lt $count) {
    if ($timeoutMs -gt 0) {
      $task = $process.StandardOutput.BaseStream.ReadAsync($buffer, $offset, $count - $offset)
      if (-not $task.Wait($timeoutMs)) { throw [System.TimeoutException]::new("Timed out waiting for interactive host output") }
      $read = $task.Result
    } else {
      $read = $process.StandardOutput.BaseStream.Read($buffer, $offset, $count - $offset)
    }
    if ($read -le 0) { throw "Interactive host closed stdout" }
    $offset += $read
  }
  return ,$buffer
}

function Read-RawFrame([int]$timeoutMs = 0) {
  $lengthBytes = Read-Exactly 4 $timeoutMs
  if ([System.BitConverter]::IsLittleEndian) { [System.Array]::Reverse($lengthBytes) }
  $length = [System.BitConverter]::ToUInt32($lengthBytes, 0)
  if ($length -gt 1048576) { throw "Interactive host returned an oversized frame" }
  [System.Text.Encoding]::UTF8.GetString((Read-Exactly ([int]$length) $timeoutMs)) | ConvertFrom-Json
}

function Respond-ToPolicyRequest($message) {
  $request = $message.payload | ConvertFrom-Json
  $allow = $request.kind -in @("navigation", "close")
  Write-Frame @{ version = 1; kind = "response"; sessionId = $ready.sessionId; authenticationToken = ""; requestId = $message.requestId; eventId = "0"; method = ""; payload = (ConvertTo-Json -Compress @{ allow = $allow; error = "" }); error = ""; timeoutMs = 5000 }
}

function Read-Frame([int]$timeoutMs = 0) {
  while ($true) {
    $message = Read-RawFrame $timeoutMs
    if ($message.kind -eq "request" -and $message.method -eq "native.webview.policyRequested") {
      Respond-ToPolicyRequest $message
      continue
    }
    return $message
  }
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
  if ($ready.kind -ne "ready" -or $ready.version -ne $script:protocolVersion) {
    throw "Host handshake failed"
  }
  Write-Frame @{ version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""; requestId = "2"; eventId = "0"; method = "native.window.create"; payload = '{"title":"Nimino interactive WebView2","width":1000,"height":700,"appId":"tech.asopi.nimino.smoke","profile":"windows-gui"}'; error = ""; timeoutMs = 5000 }
  $window = Read-Frame
  $windowId = ($window.payload | ConvertFrom-Json).windowId
  Write-Frame @{ version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""; requestId = "3"; eventId = "0"; method = "native.webview.create"; payload = (ConvertTo-Json -Compress @{ windowId = $windowId }); error = ""; timeoutMs = 5000 }
  $view = Read-Frame
  $webViewId = ($view.payload | ConvertFrom-Json).webViewId
  Write-Frame @{ version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""; requestId = "4"; eventId = "0"; method = "native.webview.setNavigationRules"; payload = (ConvertTo-Json -Compress @{ webViewId = $webViewId; allow = @("**"); deny = @() }); error = ""; timeoutMs = 5000 }
  [void](Read-Frame)
  $popupDocument = '<!doctype html><p>popup request handled by Nimino</p>'
  $popupUrl = "data:text/html," + [System.Uri]::EscapeDataString($popupDocument)
  $html = '<!doctype html><meta charset="utf-8"><h1>Nimino WebView2 interactive test</h1><p>Click the control below.</p><a id="popup" href="' + $popupUrl + '" target="_blank" onclick="chrome.webview.postMessage(''clicked-link'')">OPEN POPUP LINK</a><br><button onclick="window.open(''' + $popupUrl + ''', ''_blank'')">OPEN POPUP BUTTON</button>'
  Write-Frame @{ version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""; requestId = "5"; eventId = "0"; method = "native.webview.loadHtml"; payload = (ConvertTo-Json -Compress @{ webViewId = $webViewId; html = $html }); error = ""; timeoutMs = 5000 }
  [void](Read-Frame)
  Write-Host "Window opened. Click the link or button; Ctrl+C closes the interactive host." -ForegroundColor Green
  if ($WaitForNewWindowRequest) {
    Write-Host "New-window request test is armed; click once and wait for automatic result." -ForegroundColor Yellow
    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    while ([DateTime]::UtcNow -lt $deadline) {
      try { $message = Read-Frame 1000 } catch [System.TimeoutException] { continue }
      if ($message.kind -eq "event" -and $message.method -eq "native.webview.newWindowRequested") {
        $payload = $message.payload | ConvertFrom-Json
        if ($payload.webViewId -eq $webViewId) {
          $popupWindowPayload = ConvertTo-Json -Compress @{ title = "Nimino interactive popup"; width = 500; height = 350; appId = "tech.asopi.nimino.interactive-popup"; profile = "interactive-popup" }
          Write-Frame @{ version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""; requestId = "6"; eventId = "0"; method = "native.window.create"; payload = $popupWindowPayload; error = ""; timeoutMs = 5000 }
          $popupWindow = Read-Frame 5000
          if (-not [string]::IsNullOrEmpty($popupWindow.error)) { throw "Could not create explicit popup window: $($popupWindow.error)" }
          $popupWindowId = ($popupWindow.payload | ConvertFrom-Json).windowId
          Write-Frame @{ version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""; requestId = "7"; eventId = "0"; method = "native.webview.create"; payload = (ConvertTo-Json -Compress @{ windowId = $popupWindowId }); error = ""; timeoutMs = 5000 }
          $popupView = Read-Frame 5000
          if (-not [string]::IsNullOrEmpty($popupView.error)) { throw "Could not create explicit popup WebView: $($popupView.error)" }
          $popupViewId = ($popupView.payload | ConvertFrom-Json).webViewId
          $popupHtml = '<!doctype html><meta charset="utf-8"><script>window.onload=()=>chrome.webview.postMessage("interactive-popup-message")</script><p>Nimino popup opened</p>'
          Write-Frame @{ version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""; requestId = "8"; eventId = "0"; method = "native.webview.loadHtml"; payload = (ConvertTo-Json -Compress @{ webViewId = $popupViewId; html = $popupHtml }); error = ""; timeoutMs = 5000 }
          $popupLoad = Read-Frame 5000
          if (-not [string]::IsNullOrEmpty($popupLoad.error)) { throw "Could not load explicit popup HTML: $($popupLoad.error)" }
          $messageDeadline = [DateTime]::UtcNow.AddSeconds(30)
          while ([DateTime]::UtcNow -lt $messageDeadline) {
            try { $popupMessage = Read-Frame 1000 } catch [System.TimeoutException] { continue }
            if ($popupMessage.kind -eq "event" -and $popupMessage.method -eq "native.webview.message") {
              $popupMessagePayload = $popupMessage.payload | ConvertFrom-Json
              if ($popupMessagePayload.webViewId -eq $popupViewId -and $popupMessagePayload.message -eq "interactive-popup-message") {
                Write-Output "WSL new-window request and explicit popup message smoke passed"
                return
              }
            }
          }
          throw "Explicit popup did not deliver its message within 30 seconds"
        }
      }
    }
    throw "New-window request was not received within 60 seconds"
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
  if ($process -and -not $process.HasExited) {
    & taskkill.exe /PID $process.Id /T /F *> $null
  }
  if ($process) { $process.Dispose() }
}
