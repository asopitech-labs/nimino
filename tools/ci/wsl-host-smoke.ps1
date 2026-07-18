param(
  [Parameter(Mandatory = $true)]
  [string]$HostExecutable
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
$script:smokePhase = "process startup"
$loaderPath = Join-Path (Split-Path -Parent $HostExecutable) "WebView2Loader.dll"
if (-not (Test-Path -LiteralPath $loaderPath -PathType Leaf)) {
  throw "WebView2Loader.dll must be staged beside nimino-wsl-host.exe"
}
if (-not $process.Start()) {
  throw "Unable to start nimino-wsl-host.exe"
}

function Write-Frame([hashtable]$message) {
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
      throw "Host stdout timed out before a complete frame was received"
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

function Read-Frame {
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

function Wait-ForNavigationCompleted([string]$webViewId) {
  for ($attempt = 0; $attempt -lt 8; $attempt++) {
    $message = Read-Frame
    if ($message.kind -eq "event" -and $message.method -eq "native.webview.error") {
      throw "WebView reported an error: $($message.error)"
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

try {
  $script:smokePhase = "handshake"
  Write-Frame @{
    version = 1; kind = "hello"; sessionId = ""; authenticationToken = $token
    requestId = "1"; eventId = "0"; method = ""; payload = ""; error = ""; timeoutMs = 5000
  }
  $ready = Read-Frame
  if ($ready.kind -ne "ready" -or [string]::IsNullOrEmpty($ready.sessionId)) {
    throw "Host did not return a valid ready message"
  }

  $script:smokePhase = "window creation"
  $windowRequest = @{
    version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
    requestId = "2"; eventId = "0"; method = "native.window.create"
    payload = '{"title":"WSL smoke","width":800,"height":600}'; error = ""; timeoutMs = 5000
  }
  Write-Frame $windowRequest
  $windowResponse = Read-Frame
  if ($windowResponse.kind -ne "response" -or $windowResponse.requestId -ne "2" -or
      -not [string]::IsNullOrEmpty($windowResponse.error)) {
    throw "Host did not create a window"
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

  $script:smokePhase = "HTML loading"
  Write-Frame @{
    version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
    requestId = "4"; eventId = "0"; method = "native.webview.loadHtml"
    payload = (ConvertTo-Json -Compress @{ webViewId = $webViewId; html = "<title>Nimino WebView2 Runtime Smoke</title><main>ready</main>" })
    error = ""; timeoutMs = 5000
  }
  $loadResponse = Read-Frame
  if ($loadResponse.kind -ne "response" -or $loadResponse.requestId -ne "4" -or
      -not [string]::IsNullOrEmpty($loadResponse.error)) {
    throw "Host did not start WebView HTML loading"
  }
  $script:smokePhase = "navigation completion"
  Wait-ForNavigationCompleted $webViewId

  $script:smokePhase = "JavaScript evaluation"
  Write-Frame @{
    version = 1; kind = "request"; sessionId = $ready.sessionId; authenticationToken = ""
    requestId = "5"; eventId = "0"; method = "native.webview.evalJavaScript"
    payload = (ConvertTo-Json -Compress @{ webViewId = $webViewId; script = "document.title" })
    error = ""; timeoutMs = 5000
  }
  $evaluation = Read-Frame
  if ($evaluation.kind -ne "response" -or $evaluation.requestId -ne "5" -or
      -not [string]::IsNullOrEmpty($evaluation.error)) {
    throw "Host did not evaluate JavaScript in the WebView"
  }
  $scriptResult = ($evaluation.payload | ConvertFrom-Json).result | ConvertFrom-Json
  if ($scriptResult -ne "Nimino WebView2 Runtime Smoke") {
    throw "WebView JavaScript result did not match the loaded document title"
  }

  $script:smokePhase = "shutdown"
  Write-Frame @{
    version = 1; kind = "shutdown"; sessionId = $ready.sessionId; authenticationToken = ""
    requestId = "6"; eventId = "0"; method = ""; payload = ""; error = ""; timeoutMs = 5000
  }
  $response = Read-Frame
  if ($response.kind -ne "response" -or $response.requestId -ne "6" -or
      $response.sessionId -ne $ready.sessionId -or -not [string]::IsNullOrEmpty($response.error)) {
    throw "Host did not acknowledge shutdown"
  }

  if (-not $process.WaitForExit(5000)) {
    throw "Host did not exit after shutdown"
  }
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
