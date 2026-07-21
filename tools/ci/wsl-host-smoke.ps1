param(
  [Parameter(Mandatory = $true)]
  [string]$HostExecutable,
  [switch]$AbnormalClientEof,
  [switch]$VerifyNewWindow
)

## Keep this value in sync with packages/wsl/src/nimino_wsl/protocol/versioning.nim.
## Write-Frame owns the wire version so every request uses one negotiated value.
$script:protocolVersion = 2
$script:deniedNavigationUrl = "https://example.com/private/token"
$script:pendingFrames = New-Object System.Collections.Queue

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
$script:smokePhase = "process startup"
$loaderPath = Join-Path (Split-Path -Parent $HostExecutable) "WebView2Loader.dll"
if (-not (Test-Path -LiteralPath $loaderPath -PathType Leaf)) {
  throw "WebView2Loader.dll must be staged beside nimino-wsl-host.exe"
}
if (-not $process.Start()) {
  throw "Unable to start nimino-wsl-host.exe"
}

function Write-Frame([hashtable]$message) {
  $message.version = $script:protocolVersion
  $json = [System.Text.Encoding]::UTF8.GetBytes(($message | ConvertTo-Json -Compress))
  $length = [System.BitConverter]::GetBytes([uint32]$json.Length)
  if ([System.BitConverter]::IsLittleEndian) {
    [System.Array]::Reverse($length)
  }
  $stream = $process.StandardInput.BaseStream
  $stream.Write($length, 0, $length.Length)
  $stream.Write($json, 0, $json.Length)
  $stream.Flush()
}

function Read-Exactly([int]$count) {
  $buffer = New-Object byte[] $count
  $offset = 0
  while ($offset -lt $count) {
    $readTask = $process.StandardOutput.BaseStream.ReadAsync($buffer, $offset, $count - $offset)
    if (-not $readTask.Wait(10000)) {
      throw "Host stdout timed out during $script:smokePhase before a complete frame was received"
    }
    $read = $readTask.Result
    if ($read -le 0) {
      $diagnostic = ""
      if ($process.HasExited) {
        $diagnostic = " (exit code $($process.ExitCode); stderr: $($process.StandardError.ReadToEnd().Trim()))"
      }
      throw "Host stdout ended during $script:smokePhase before a complete frame was received$diagnostic"
    }
    $offset += $read
  }
  return ,$buffer
}

function Read-RawFrame {
  $lengthBytes = Read-Exactly 4
  if ([System.BitConverter]::IsLittleEndian) {
    [System.Array]::Reverse($lengthBytes)
  }
  $length = [System.BitConverter]::ToUInt32($lengthBytes, 0)
  if ($length -gt 1048576) {
    throw "Host returned an oversized protocol frame"
  }
  $payload = Read-Exactly ([int]$length)
  return ([System.Text.Encoding]::UTF8.GetString($payload) | ConvertFrom-Json)
}

function Respond-ToPolicyRequest($message) {
  $request = $message.payload | ConvertFrom-Json
  $allow = $false
  if ($request.kind -eq "navigation") {
    $allow = ($request.url -ne $script:deniedNavigationUrl)
  }
  elseif ($request.kind -eq "close") {
    ## Shutdown is initiated by this harness after its assertions complete.
    $allow = $true
  }
  Write-Frame @{
    version = 1; kind = "response"; sessionId = $ready.sessionId; authenticationToken = ""
    requestId = $message.requestId; eventId = "0"; method = ""
    payload = (ConvertTo-Json -Compress @{ allow = $allow; error = "" })
    error = ""; timeoutMs = 5000
  }
}

function Read-ProtocolFrame {
  while ($true) {
    $message = Read-RawFrame
    if ($message.kind -eq "request" -and
        $message.method -eq "native.webview.policyRequested") {
      Respond-ToPolicyRequest $message
      continue
    }
    return $message
  }
}

function Read-Frame {
  if ($script:pendingFrames.Count -gt 0) {
    return $script:pendingFrames.Dequeue()
  }
  return Read-ProtocolFrame
}

function Read-Response([string]$requestId) {
  ## A WebView callback can be emitted before ExecuteScript's completion
  ## callback. Preserve those events for the assertion that follows instead
  ## of treating the transport ordering as a protocol error.
  for ($attempt = 0; $attempt -lt 8; $attempt++) {
    $message = Read-ProtocolFrame
    if ($message.kind -eq "response" -and $message.requestId -eq $requestId) {
      return $message
    }
    $script:pendingFrames.Enqueue($message)
  }
  throw "Host did not return response $requestId before unrelated protocol frames"
}

function Wait-ForHostExit {
  ## app.close() posts WM_CLOSE.  The native close callback can emit one final
  ## synchronous policy request after the shutdown acknowledgement, so keep
  ## consuming protocol frames until the process closes stdout.
  while (-not $process.HasExited) {
    try {
      [void](Read-Frame)
    }
    catch {
      if ($process.HasExited) { break }
      throw
    }
  }
  if (-not $process.WaitForExit(5000)) {
    throw "Host did not exit after shutdown"
  }
}

function Get-WebViewErrorText($message) {
  if (-not [string]::IsNullOrEmpty($message.error)) { return $message.error }
  try {
    $payload = $message.payload | ConvertFrom-Json
    return ("{0}: {1} (code={2})" -f $payload.operation, $payload.detail,
      $payload.platformCode)
  }
  catch {
    return "native.webview.error payload was invalid"
  }
}

function Wait-ForNavigationCompleted([string]$webViewId) {
  for ($attempt = 0; $attempt -lt 8; $attempt++) {
    $message = Read-Frame
    if ($message.kind -eq "event" -and $message.method -eq "native.webview.error") {
      throw "WebView reported an error: $(Get-WebViewErrorText $message)"
    }
    if ($message.kind -ne "event" -or $message.method -ne "native.webview.navigationCompleted") {
      continue
    }
    $payload = $message.payload | ConvertFrom-Json
    if ($payload.webViewId -ne $webViewId) {
      continue
    }
    if (-not $payload.succeeded) {
      throw "WebView navigation did not complete successfully"
    }
    return
  }
  throw "WebView did not emit a successful navigation-completed event"
}

function Wait-ForWebMessage([string]$webViewId, [string]$expectedMessage) {
  for ($attempt = 0; $attempt -lt 8; $attempt++) {
    $message = Read-Frame
    if ($message.kind -eq "event" -and $message.method -eq "native.webview.error") {
      throw "WebView reported an error: $(Get-WebViewErrorText $message)"
    }
    if ($message.kind -ne "event" -or $message.method -ne "native.webview.message") {
      continue
    }
    $payload = $message.payload | ConvertFrom-Json
    if ($payload.webViewId -eq $webViewId -and $payload.message -eq $expectedMessage) {
      return
    }
  }
  throw "WebView did not emit the expected message"
}

function Wait-ForNavigationCancelled([string]$webViewId, [string]$expectedUrl) {
  $sawStart = $false
  for ($attempt = 0; $attempt -lt 12; $attempt++) {
    $message = Read-Frame
    if ($message.kind -ne "event") { continue }
    if ($message.method -eq "native.webview.navigationStarting") {
      $payload = $message.payload | ConvertFrom-Json
      if ($payload.webViewId -eq $webViewId -and $payload.url -eq $expectedUrl) {
        $sawStart = $true
      }
      continue
    }
    if ($message.method -ne "native.webview.navigationCompleted") { continue }
    $payload = $message.payload | ConvertFrom-Json
    if ($payload.webViewId -eq $webViewId -and -not $payload.succeeded) {
      if (-not $sawStart) { throw "WebView completed a cancelled navigation without a starting event" }
      return
    }
  }
  throw "WebView did not report the expected cancelled navigation"
}

function Wait-ForNewWindowRequest([string]$webViewId) {
  $sawTrigger = $false
  $sawNewWindowRequest = $false
  for ($attempt = 0; $attempt -lt 16; $attempt++) {
    $message = Read-Frame
    if ($message.kind -eq "event" -and $message.method -eq "native.webview.error") {
      throw "WebView reported an error: $(Get-WebViewErrorText $message)"
    }
    if ($message.kind -ne "event") { continue }
    $payload = $message.payload | ConvertFrom-Json
    if ($message.method -eq "native.webview.message" -and
        $payload.webViewId -eq $webViewId -and $payload.message -eq "new-window-triggered") {
      $sawTrigger = $true
    }
    if ($message.method -eq "native.webview.newWindowRequested" -and
        $payload.webViewId -eq $webViewId) {
      if ([string]::IsNullOrEmpty($payload.url) -or
          -not $payload.url.StartsWith("data:text/html,")) {
        throw "WebView emitted a new-window request with an unexpected URL"
      }
      $sawNewWindowRequest = $payload
    }
    if ($sawTrigger -and $sawNewWindowRequest) { return $sawNewWindowRequest }
  }
  throw "New-window trigger did not produce both the DOM message and new-window request"
}

try {
  $script:smokePhase = "handshake"
  Write-Frame @{
    version = 1; kind = "hello"; sessionId = ""; authenticationToken = $token
    requestId = "1"; eventId = "0"; method = ""; payload = ""; error = ""; timeoutMs = 5000
  }
  $ready = Read-Frame
  if ($ready.kind -ne "ready" -or $ready.version -ne $script:protocolVersion -or
      [string]::IsNullOrEmpty($ready.sessionId)) {
    throw "Host did not return a valid ready message"
  }
  $capabilities = $ready.payload | ConvertFrom-Json
  if ($null -eq $capabilities.capabilities -or
      $capabilities.capabilities -notcontains "webPermissionEvents") {
    throw "Host ready message did not contain the required native capability snapshot"
  }

  if ($AbnormalClientEof) {
    $script:smokePhase = "abnormal client EOF"
    $process.StandardInput.Close()
    if (-not $process.WaitForExit(5000)) {
      throw "Host did not exit after the client stdin was closed"
    }
    if ($process.ExitCode -ne 0) {
      throw "Host exited with a non-zero status after client EOF"
    }
    Write-Output "WSL host abnormal client EOF smoke passed"
    return
  }

  $script:smokePhase = "window creation"
  $windowRequest = @{
    version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
    requestId = "2"; eventId = "0"; method = "native.window.create"
    payload = '{"title":"WSL smoke","width":800,"height":600,"appId":"tech.asopi.nimino.smoke","profile":"windows-gui"}'; error = ""; timeoutMs = 5000
  }
  Write-Frame $windowRequest
  $windowResponse = Read-Frame
  if ($windowResponse.kind -ne "response" -or $windowResponse.requestId -ne "2" -or
      -not [string]::IsNullOrEmpty($windowResponse.error)) {
    throw "Host did not create a window: $($windowResponse.error)"
  }
  $windowId = ($windowResponse.payload | ConvertFrom-Json).windowId

  $script:smokePhase = "webview creation"
  Write-Frame @{
    version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
    requestId = "3"; eventId = "0"; method = "native.webview.create"
    payload = (ConvertTo-Json -Compress @{ windowId = $windowId }); error = ""; timeoutMs = 5000
  }
  $webViewResponse = Read-Frame
  if ($webViewResponse.kind -ne "response" -or $webViewResponse.requestId -ne "3" -or
      -not [string]::IsNullOrEmpty($webViewResponse.error) -or
      [string]::IsNullOrEmpty(($webViewResponse.payload | ConvertFrom-Json).webViewId)) {
    throw "Host did not create a WebView"
  }
  $webViewId = ($webViewResponse.payload | ConvertFrom-Json).webViewId

  $script:smokePhase = "document-start script registration"
  Write-Frame @{
    version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
    requestId = "4"; eventId = "0"; method = "native.webview.setDocumentStartScript"
    payload = (ConvertTo-Json -Compress @{ webViewId = $webViewId; script = "globalThis.__niminoDocumentStart = 'ready';" })
    error = ""; timeoutMs = 5000
  }
  $documentStartResponse = Read-Frame
  if ($documentStartResponse.kind -ne "response" -or $documentStartResponse.requestId -ne "4" -or
      -not [string]::IsNullOrEmpty($documentStartResponse.error)) {
    throw "Host did not register the document-start script"
  }

  $script:smokePhase = "navigation rule registration"
  Write-Frame @{
    version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
    requestId = "5"; eventId = "0"; method = "native.webview.setNavigationRules"
    payload = (ConvertTo-Json -Compress @{ webViewId = $webViewId; allow = @("**"); deny = @("https://example.com/**") })
    error = ""; timeoutMs = 5000
  }
  $rulesResponse = Read-Frame
  if ($rulesResponse.kind -ne "response" -or $rulesResponse.requestId -ne "5" -or
      -not [string]::IsNullOrEmpty($rulesResponse.error)) {
    throw "Host did not register navigation rules"
  }

  $script:smokePhase = "HTML loading"
  Write-Frame @{
    version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
    requestId = "6"; eventId = "0"; method = "native.webview.loadHtml"
    payload = (ConvertTo-Json -Compress @{ webViewId = $webViewId; html = "<script>document.title = globalThis.__niminoDocumentStart === 'ready' ? 'Nimino WebView2 Runtime Smoke' : 'missing document-start script';</script><main>ready</main>" })
    error = ""; timeoutMs = 5000
  }
  $loadResponse = Read-Frame
  if ($loadResponse.kind -ne "response" -or $loadResponse.requestId -ne "6" -or
      -not [string]::IsNullOrEmpty($loadResponse.error)) {
    throw "Host did not start WebView HTML loading"
  }
  $script:smokePhase = "navigation completion"
  Wait-ForNavigationCompleted $webViewId

  $script:smokePhase = "JavaScript evaluation"
  Write-Frame @{
    version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
    requestId = "7"; eventId = "0"; method = "native.webview.evalJavaScript"
    payload = (ConvertTo-Json -Compress @{ webViewId = $webViewId; script = "document.title" })
    error = ""; timeoutMs = 5000
  }
  $evaluation = Read-Frame
  if ($evaluation.kind -ne "response" -or $evaluation.requestId -ne "7" -or
      -not [string]::IsNullOrEmpty($evaluation.error)) {
    throw "Host did not evaluate JavaScript in the WebView"
  }
  $scriptResult = ($evaluation.payload | ConvertFrom-Json).result | ConvertFrom-Json
  if ($scriptResult -ne "Nimino WebView2 Runtime Smoke") {
    throw "WebView JavaScript result did not match the loaded document title"
  }

  $script:smokePhase = "native window title"
  Write-Frame @{
    version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
    requestId = "8"; eventId = "0"; method = "native.window.setTitle"
    payload = (ConvertTo-Json -Compress @{ windowId = $windowId; title = "Nimino Window Updated" })
    error = ""; timeoutMs = 5000
  }
  $titleResponse = Read-Frame
  if ($titleResponse.kind -ne "response" -or $titleResponse.requestId -ne "8" -or
      -not [string]::IsNullOrEmpty($titleResponse.error)) {
    throw "Host did not update the native window title"
  }

  $script:smokePhase = "native window resize"
  Write-Frame @{
    version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
    requestId = "9"; eventId = "0"; method = "native.window.setSize"
    payload = (ConvertTo-Json -Compress @{ windowId = $windowId; width = 1000; height = 700 })
    error = ""; timeoutMs = 5000
  }
  $sizeResponse = Read-Frame
  if ($sizeResponse.kind -ne "response" -or $sizeResponse.requestId -ne "9" -or
      -not [string]::IsNullOrEmpty($sizeResponse.error)) {
    throw "Host did not resize the native window"
  }

  $script:smokePhase = "resized viewport evaluation"
  Write-Frame @{
    version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
    requestId = "10"; eventId = "0"; method = "native.webview.evalJavaScript"
    payload = (ConvertTo-Json -Compress @{ webViewId = $webViewId; script = "JSON.stringify({ width: innerWidth, height: innerHeight })" })
    error = ""; timeoutMs = 5000
  }
  $viewportEvaluation = Read-Frame
  if ($viewportEvaluation.kind -ne "response" -or $viewportEvaluation.requestId -ne "10" -or
      -not [string]::IsNullOrEmpty($viewportEvaluation.error)) {
    throw "Host did not evaluate the resized WebView viewport"
  }
  $viewport = (($viewportEvaluation.payload | ConvertFrom-Json).result | ConvertFrom-Json) | ConvertFrom-Json
  if ($viewport.width -le 0 -or $viewport.height -le 0) {
    throw "WebView viewport was not available after native window resize"
  }

  $script:smokePhase = "URL loading"
  Write-Frame @{
    version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
    requestId = "11"; eventId = "0"; method = "native.webview.loadUrl"
    payload = (ConvertTo-Json -Compress @{ webViewId = $webViewId; url = "about:blank" })
    error = ""; timeoutMs = 5000
  }
  $urlResponse = Read-Frame
  if ($urlResponse.kind -ne "response" -or $urlResponse.requestId -ne "11" -or
      -not [string]::IsNullOrEmpty($urlResponse.error)) {
    throw "Host did not start WebView URL loading"
  }
  $script:smokePhase = "URL navigation completion"
  Wait-ForNavigationCompleted $webViewId

  $script:smokePhase = "WebView message"
  Write-Frame @{
    version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
    requestId = "12"; eventId = "0"; method = "native.webview.evalJavaScript"
    payload = (ConvertTo-Json -Compress @{ webViewId = $webViewId; script = "chrome.webview.postMessage('nimino-native-message')" })
    error = ""; timeoutMs = 5000
  }
  $messageEvaluation = Read-Frame
  if ($messageEvaluation.kind -ne "response" -or $messageEvaluation.requestId -ne "12" -or
      -not [string]::IsNullOrEmpty($messageEvaluation.error)) {
    throw "Host did not execute the WebView message script"
  }
  Wait-ForWebMessage $webViewId "nimino-native-message"

  $script:smokePhase = "cancelled navigation"
  Write-Frame @{
    version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
    requestId = "13"; eventId = "0"; method = "native.webview.loadUrl"
    payload = (ConvertTo-Json -Compress @{ webViewId = $webViewId; url = "https://example.com/private/token" })
    error = ""; timeoutMs = 5000
  }
  $deniedResponse = Read-Frame
  if ($deniedResponse.kind -ne "response" -or $deniedResponse.requestId -ne "13" -or
      -not [string]::IsNullOrEmpty($deniedResponse.error)) {
    throw "Host rejected the navigation request before WebView2 could evaluate policy"
  }
  Wait-ForNavigationCancelled $webViewId $script:deniedNavigationUrl

  if ($VerifyNewWindow) {
    $newWindowTitle = "Nimino WebView2 New Window Smoke"
    $script:smokePhase = "new-window test title"
    Write-Frame @{
      version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
      requestId = "14"; eventId = "0"; method = "native.window.setTitle"
      payload = (ConvertTo-Json -Compress @{ windowId = $windowId; title = $newWindowTitle })
      error = ""; timeoutMs = 5000
    }
    $newWindowTitleResponse = Read-Frame
    if ($newWindowTitleResponse.kind -ne "response" -or $newWindowTitleResponse.requestId -ne "14" -or
        -not [string]::IsNullOrEmpty($newWindowTitleResponse.error)) {
      throw "Host did not set the new-window test title"
    }

    $popupUrl = "data:text/html," + [System.Uri]::EscapeDataString("<!doctype html><p>Nimino popup target</p>")
    $newWindowHtml = '<!doctype html><meta charset="utf-8"><button id="open" style="position:fixed;inset:0;border:0;background:#19324d;color:white;font-size:32px" onclick="chrome.webview.postMessage(''new-window-triggered''); window.open(''' + $popupUrl + ''', ''_blank'');">Open a new window</button>'
    $script:smokePhase = "new-window page loading"
    Write-Frame @{
      version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
      requestId = "15"; eventId = "0"; method = "native.webview.loadHtml"
      payload = (ConvertTo-Json -Compress @{ webViewId = $webViewId; html = $newWindowHtml })
      error = ""; timeoutMs = 5000
    }
    $newWindowLoadResponse = Read-Frame
    if ($newWindowLoadResponse.kind -ne "response" -or $newWindowLoadResponse.requestId -ne "15" -or
        -not [string]::IsNullOrEmpty($newWindowLoadResponse.error)) {
      throw "Host did not load the new-window test page"
    }
    $script:smokePhase = "new-window page navigation"
    Wait-ForNavigationCompleted $webViewId
    $script:smokePhase = "new-window page message bridge"
    Write-Frame @{
      version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
      requestId = "16"; eventId = "0"; method = "native.webview.evalJavaScript"
      payload = (ConvertTo-Json -Compress @{ webViewId = $webViewId; script = "chrome.webview.postMessage('new-window-page-ready')" })
      error = ""; timeoutMs = 5000
    }
    $newWindowBridgeResponse = Read-Frame
    if ($newWindowBridgeResponse.kind -ne "response" -or $newWindowBridgeResponse.requestId -ne "16" -or
        -not [string]::IsNullOrEmpty($newWindowBridgeResponse.error)) {
      throw "Host did not execute the new-window page bridge preflight"
    }
    Wait-ForWebMessage $webViewId "new-window-page-ready"
    $script:smokePhase = "WebView new-window request"
    Write-Frame @{
      version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
      requestId = "17"; eventId = "0"; method = "native.webview.evalJavaScript"
      payload = (ConvertTo-Json -Compress @{ webViewId = $webViewId; script = "document.getElementById('open').click()" })
      error = ""; timeoutMs = 5000
    }
    $newWindowEvaluation = Read-Response "17"
    if ($newWindowEvaluation.kind -ne "response" -or $newWindowEvaluation.requestId -ne "17" -or
        -not [string]::IsNullOrEmpty($newWindowEvaluation.error)) {
      throw "Host did not invoke the new-window test control"
    }
    $popupRequest = Wait-ForNewWindowRequest $webViewId
    $popupWindowRequestId = "18"
    Write-Frame @{
      requestId = $popupWindowRequestId; eventId = "0"; method = "native.window.create"
      payload = (ConvertTo-Json -Compress @{ title = "Nimino Popup Smoke"; width = 400; height = 300; appId = "app.nimino.popup-smoke"; profile = "popup" })
      error = ""; timeoutMs = 5000
    }
    $popupWindowResponse = Read-Response $popupWindowRequestId
    if (-not [string]::IsNullOrEmpty($popupWindowResponse.error)) { throw "Host could not create an explicit popup window" }
    $popupWindowId = ($popupWindowResponse.payload | ConvertFrom-Json).windowId
    $popupViewRequestId = "19"
    Write-Frame @{
      requestId = $popupViewRequestId; eventId = "0"; method = "native.webview.create"
      payload = (ConvertTo-Json -Compress @{ windowId = $popupWindowId }); error = ""; timeoutMs = 5000
    }
    $popupViewResponse = Read-Response $popupViewRequestId
    if (-not [string]::IsNullOrEmpty($popupViewResponse.error)) { throw "Host could not create the explicit popup WebView" }
    $popupViewId = ($popupViewResponse.payload | ConvertFrom-Json).webViewId
    $popupHtml = '<!doctype html><meta charset="utf-8"><script>window.onload=()=>chrome.webview.postMessage("popup-message-received")</script><p>Nimino popup</p>'
    $popupLoadRequestId = "20"
    Write-Frame @{
      requestId = $popupLoadRequestId; eventId = "0"; method = "native.webview.loadHtml"
      payload = (ConvertTo-Json -Compress @{ webViewId = $popupViewId; html = $popupHtml }); error = ""; timeoutMs = 5000
    }
    $popupLoadResponse = Read-Response $popupLoadRequestId
    if (-not [string]::IsNullOrEmpty($popupLoadResponse.error)) { throw "Host could not load the explicit popup document" }
    Wait-ForWebMessage $popupViewId "popup-message-received"
  }

  $script:smokePhase = "shutdown"
  $shutdownRequestId = if ($VerifyNewWindow) { "21" } else { "14" }
  Write-Frame @{
    version = 1; kind = "shutdown"; sessionId = $ready.sessionId; authenticationToken = ""
    requestId = $shutdownRequestId; eventId = "0"; method = ""; payload = ""; error = ""; timeoutMs = 5000
  }
  $response = Read-Frame
  if ($response.kind -ne "response" -or $response.requestId -ne $shutdownRequestId -or
      $response.sessionId -ne $ready.sessionId -or -not [string]::IsNullOrEmpty($response.error)) {
    throw "Host did not acknowledge shutdown"
  }

  Wait-ForHostExit
  if ($process.ExitCode -ne 0) {
    throw "Host exited with a non-zero status"
  }
  Write-Output "WSL host WebView2 smoke passed"
}
finally {
  if (-not $process.HasExited) {
    $process.Kill()
    $process.WaitForExit()
  }
  $process.Dispose()
}
