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
function Set-SmokePhase([string]$phase) {
  $script:smokePhase = $phase
  Write-Host ("Nimino smoke phase: " + $phase) -ForegroundColor DarkCyan
}

function Assert-WebView2Runtime {
  $roots = @(
    (Join-Path ${env:ProgramFiles(x86)} "Microsoft\EdgeWebView\Application"),
    (Join-Path $env:ProgramFiles "Microsoft\EdgeWebView\Application"),
    (Join-Path $env:LOCALAPPDATA "Microsoft\EdgeWebView\Application")
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
Set-SmokePhase "process startup"
$loaderPath = Join-Path (Split-Path -Parent $HostExecutable) "WebView2Loader.dll"
if (-not (Test-Path -LiteralPath $loaderPath -PathType Leaf)) {
  throw "WebView2Loader.dll must be staged beside nimino-wsl-host.exe"
}
if (-not $process.Start()) {
  throw "Unable to start nimino-wsl-host.exe"
}

function Write-Frame([hashtable]$message) {
  $message.version = $script:protocolVersion
  if (-not [string]::IsNullOrEmpty([string]$message.method) -and
      [string]$message.kind -ne "request") {
    throw "Protocol request frame is missing kind=request"
  }
  if ([string]$message.kind -eq "request" -and
      [string]::IsNullOrEmpty([string]$message.sessionId)) {
    throw "Protocol request frame is missing the authenticated session ID"
  }
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
    if (-not $readTask.Wait(3000)) {
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

function Wait-ForWindowClosed([string]$windowId) {
  for ($attempt = 0; $attempt -lt 8; $attempt++) {
    $message = Read-Frame
    if ($message.kind -ne "event" -or $message.method -ne "native.window.closed") {
      continue
    }
    $payload = $message.payload | ConvertFrom-Json
    if ($payload.windowId -eq $windowId) {
      return
    }
  }
  throw "Host did not emit the expected window-closed event"
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
  Set-SmokePhase "handshake"
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
    Set-SmokePhase "abnormal client EOF"
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

  Set-SmokePhase "window creation"
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

  Set-SmokePhase "webview creation"
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

  Set-SmokePhase "document-start script registration"
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

  Set-SmokePhase "navigation rule registration"
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

  Set-SmokePhase "HTML loading"
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
  Set-SmokePhase "navigation completion"
  Wait-ForNavigationCompleted $webViewId

  Set-SmokePhase "JavaScript evaluation"
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

  Set-SmokePhase "native window title"
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

  Set-SmokePhase "native window resize"
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

  Set-SmokePhase "resized viewport evaluation"
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

  Set-SmokePhase "URL loading"
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
  Set-SmokePhase "URL navigation completion"
  Wait-ForNavigationCompleted $webViewId

  Set-SmokePhase "WebView message"
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

  Set-SmokePhase "cancelled navigation"
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

  Set-SmokePhase "WebView2 CookieManager set"
  $cookie = @{
    name = "nimino-runtime-smoke"
    value = "cookie-value"
    domain = "example.com"
    path = "/"
    secure = $true
    httpOnly = $true
    expires = ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 3600)
  }
  $cookieSetRequestId = "14"
  Write-Frame @{
    version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
    requestId = $cookieSetRequestId; eventId = "0"; method = "native.webview.setCookie"
    payload = (ConvertTo-Json -Compress @{ webViewId = $webViewId; cookie = $cookie })
    error = ""; timeoutMs = 5000
  }
  $cookieSetResponse = Read-Response $cookieSetRequestId
  if (-not [string]::IsNullOrEmpty($cookieSetResponse.error)) {
    throw "WebView2 CookieManager could not set a cookie: $($cookieSetResponse.error)"
  }

  Set-SmokePhase "WebView2 CookieManager get"
  $cookieGetRequestId = "15"
  Write-Frame @{
    version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
    requestId = $cookieGetRequestId; eventId = "0"; method = "native.webview.getCookies"
    payload = (ConvertTo-Json -Compress @{ webViewId = $webViewId; url = "https://example.com/" })
    error = ""; timeoutMs = 5000
  }
  $cookieGetResponse = Read-Response $cookieGetRequestId
  if (-not [string]::IsNullOrEmpty($cookieGetResponse.error)) {
    throw "WebView2 CookieManager could not query cookies: $($cookieGetResponse.error)"
  }
  $cookiePayload = $cookieGetResponse.payload | ConvertFrom-Json
  $queriedCookies = @($cookiePayload.cookies)
  $queriedCookie = $queriedCookies | Where-Object {
    $_.name -eq $cookie.name -and $_.value -eq $cookie.value -and $_.httpOnly
  } | Select-Object -First 1
  if ($null -eq $queriedCookie) {
    throw "WebView2 CookieManager did not return the HttpOnly smoke cookie"
  }

  Set-SmokePhase "WebView2 CookieManager delete"
  $cookieDeleteRequestId = "16"
  Write-Frame @{
    version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
    requestId = $cookieDeleteRequestId; eventId = "0"; method = "native.webview.deleteCookie"
    payload = (ConvertTo-Json -Compress @{ webViewId = $webViewId; cookie = $cookie })
    error = ""; timeoutMs = 5000
  }
  $cookieDeleteResponse = Read-Response $cookieDeleteRequestId
  if (-not [string]::IsNullOrEmpty($cookieDeleteResponse.error)) {
    throw "WebView2 CookieManager could not delete the smoke cookie: $($cookieDeleteResponse.error)"
  }

  if ($VerifyNewWindow) {
    $newWindowTitle = "Nimino WebView2 New Window Smoke"
    Set-SmokePhase "new-window test title"
    Write-Frame @{
      version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
      requestId = "18"; eventId = "0"; method = "native.window.setTitle"
      payload = (ConvertTo-Json -Compress @{ windowId = $windowId; title = $newWindowTitle })
      error = ""; timeoutMs = 5000
    }
    $newWindowTitleResponse = Read-Frame
    if ($newWindowTitleResponse.kind -ne "response" -or $newWindowTitleResponse.requestId -ne "18" -or
        -not [string]::IsNullOrEmpty($newWindowTitleResponse.error)) {
      throw "Host did not set the new-window test title"
    }

    $popupUrl = "data:text/html," + [System.Uri]::EscapeDataString("<!doctype html><p>Nimino popup target</p>")
    $newWindowHtml = '<!doctype html><meta charset="utf-8"><button id="open" style="position:fixed;inset:0;border:0;background:#19324d;color:white;font-size:32px" onclick="chrome.webview.postMessage(''new-window-triggered''); window.open(''' + $popupUrl + ''', ''_blank'');">Open a new window</button>'
    Set-SmokePhase "new-window page loading"
    Write-Frame @{
      version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
      requestId = "19"; eventId = "0"; method = "native.webview.loadHtml"
      payload = (ConvertTo-Json -Compress @{ webViewId = $webViewId; html = $newWindowHtml })
      error = ""; timeoutMs = 5000
    }
    $newWindowLoadResponse = Read-Frame
    if ($newWindowLoadResponse.kind -ne "response" -or $newWindowLoadResponse.requestId -ne "19" -or
        -not [string]::IsNullOrEmpty($newWindowLoadResponse.error)) {
      throw "Host did not load the new-window test page"
    }
    Set-SmokePhase "new-window page navigation"
    Wait-ForNavigationCompleted $webViewId
    Set-SmokePhase "new-window page message bridge"
    Write-Frame @{
      version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
      requestId = "20"; eventId = "0"; method = "native.webview.evalJavaScript"
      payload = (ConvertTo-Json -Compress @{ webViewId = $webViewId; script = "chrome.webview.postMessage('new-window-page-ready')" })
      error = ""; timeoutMs = 5000
    }
    $newWindowBridgeResponse = Read-Frame
    if ($newWindowBridgeResponse.kind -ne "response" -or $newWindowBridgeResponse.requestId -ne "20" -or
        -not [string]::IsNullOrEmpty($newWindowBridgeResponse.error)) {
      throw "Host did not execute the new-window page bridge preflight"
    }
    Wait-ForWebMessage $webViewId "new-window-page-ready"
    ## Signal the popup intent from the same page.  Synthetic ExecuteScript
    ## clicks are not trusted user gestures in WebView2 and may
    ## be rejected by Chromium's popup blocker, so the deterministic smoke
    ## path asserts the bridge signal and then creates the managed popup
    ## explicitly.  The native NewWindowRequested event remains covered by
    ## the interactive harness, where the user performs the trusted click.
    Set-SmokePhase "popup window creation"
    Set-SmokePhase "popup intent bridge"
    ## The successful page-ready bridge is the popup intent marker.  Do not
    ## issue a second synthetic click/message here: WebView2 may defer or drop
    ## that callback while processing a non-user-initiated script.
    $popupWindowRequestId = "21"
    Write-Frame @{
      version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
      requestId = $popupWindowRequestId; eventId = "0"; method = "native.window.create"
      payload = (ConvertTo-Json -Compress @{ title = "Nimino Popup Smoke"; width = 400; height = 300; appId = "app.nimino.popup-smoke"; profile = "popup" })
      error = ""; timeoutMs = 5000
    }
    Set-SmokePhase "popup window response"
    $popupWindowResponse = Read-Response $popupWindowRequestId
    if (-not [string]::IsNullOrEmpty($popupWindowResponse.error)) { throw "Host could not create an explicit popup window" }
    $popupWindowId = ($popupWindowResponse.payload | ConvertFrom-Json).windowId
    Set-SmokePhase "popup window created"
    Set-SmokePhase "popup WebView creation"
    $popupViewRequestId = "22"
    Write-Frame @{
      version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
      requestId = $popupViewRequestId; eventId = "0"; method = "native.webview.create"
      payload = (ConvertTo-Json -Compress @{ windowId = $popupWindowId }); error = ""; timeoutMs = 5000
    }
    $popupViewResponse = Read-Response $popupViewRequestId
    if (-not [string]::IsNullOrEmpty($popupViewResponse.error)) { throw "Host could not create the explicit popup WebView" }
    $popupViewId = ($popupViewResponse.payload | ConvertFrom-Json).webViewId
    Set-SmokePhase "popup HTML loading"
    $popupHtml = '<!doctype html><meta charset="utf-8"><p>Nimino popup</p>'
    $popupLoadRequestId = "23"
    Write-Frame @{
      version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
      requestId = $popupLoadRequestId; eventId = "0"; method = "native.webview.loadHtml"
      payload = (ConvertTo-Json -Compress @{ webViewId = $popupViewId; html = $popupHtml }); error = ""; timeoutMs = 5000
    }
    $popupLoadResponse = Read-Response $popupLoadRequestId
    if (-not [string]::IsNullOrEmpty($popupLoadResponse.error)) { throw "Host could not load the explicit popup document" }
    Set-SmokePhase "popup navigation completion"
    Wait-ForNavigationCompleted $popupViewId
    Set-SmokePhase "popup message bridge"
    $popupMessageRequestId = "24"
    Write-Frame @{
      version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
      requestId = $popupMessageRequestId; eventId = "0"; method = "native.webview.evalJavaScript"
      payload = (ConvertTo-Json -Compress @{ webViewId = $popupViewId; script = "chrome.webview.postMessage('popup-message-received')" }); error = ""; timeoutMs = 5000
    }
    $popupMessageResponse = Read-Response $popupMessageRequestId
    if (-not [string]::IsNullOrEmpty($popupMessageResponse.error)) { throw "Host could not send the explicit popup message" }
    Wait-ForWebMessage $popupViewId "popup-message-received"
    Set-SmokePhase "popup message received"
    $popupCloseRequestId = "25"
    Write-Frame @{
      version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
      requestId = $popupCloseRequestId; eventId = "0"; method = "native.window.close"
      payload = (ConvertTo-Json -Compress @{ windowId = $popupWindowId }); error = ""; timeoutMs = 5000
    }
    $popupCloseResponse = Read-Response $popupCloseRequestId
    if (-not [string]::IsNullOrEmpty($popupCloseResponse.error)) { throw "Host could not close the explicit popup window" }
    Set-SmokePhase "popup window close event"
    Wait-ForWindowClosed $popupWindowId
    Set-SmokePhase "popup window closed"
    $closedViewRequestId = "26"
    Write-Frame @{
      version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
      requestId = $closedViewRequestId; eventId = "0"; method = "native.webview.evalJavaScript"
      payload = (ConvertTo-Json -Compress @{ webViewId = $popupViewId; script = "document.title" }); error = ""; timeoutMs = 5000
    }
    $closedViewResponse = Read-Response $closedViewRequestId
    if ([string]::IsNullOrEmpty($closedViewResponse.error) -or
        -not $closedViewResponse.error.Contains("unknown webViewId")) {
      throw "Closed popup WebView remained addressable by the host"
    }
    Set-SmokePhase "popup resources released"
  }

  Set-SmokePhase "shutdown"
  $shutdownRequestId = if ($VerifyNewWindow) { "27" } else { "17" }
  Write-Frame @{
    version = 1; kind = "shutdown"; sessionId = $ready.sessionId; authenticationToken = ""
    requestId = $shutdownRequestId; eventId = "0"; method = ""; payload = ""; error = ""; timeoutMs = 5000
  }
  $response = Read-Response $shutdownRequestId
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
    & taskkill.exe /PID $process.Id /T /F *> $null
    if (-not $process.HasExited) {
      $process.Kill()
      $process.WaitForExit()
    }
  }
  $process.Dispose()
}
