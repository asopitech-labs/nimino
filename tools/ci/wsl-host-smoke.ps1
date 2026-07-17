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
    $read = $process.StandardOutput.BaseStream.Read($buffer, $offset, $count - $offset)
    if ($read -le 0) {
      throw "Host stdout ended before a complete frame was received"
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

try {
  Write-Frame @{
    version = 1; kind = "hello"; sessionId = ""; authenticationToken = $token
    requestId = "1"; eventId = "0"; method = ""; payload = ""; error = ""; timeoutMs = 5000
  }
  $ready = Read-Frame
  if ($ready.kind -ne "ready" -or [string]::IsNullOrEmpty($ready.sessionId)) {
    throw "Host did not return a valid ready message"
  }

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

  Write-Frame @{
    version = 1; kind = "shutdown"; sessionId = $ready.sessionId; authenticationToken = ""
    requestId = "4"; eventId = "0"; method = ""; payload = ""; error = ""; timeoutMs = 5000
  }
  $response = Read-Frame
  if ($response.kind -ne "response" -or $response.requestId -ne "4" -or
      $response.sessionId -ne $ready.sessionId -or -not [string]::IsNullOrEmpty($response.error)) {
    throw "Host did not acknowledge shutdown"
  }

  if (-not $process.WaitForExit(5000)) {
    throw "Host did not exit after shutdown"
  }
  if ($process.ExitCode -ne 0) {
    throw "Host exited with a non-zero status"
  }
  Write-Output "WSL host handshake smoke passed"
}
finally {
  if (-not $process.HasExited) {
    $process.Kill()
    $process.WaitForExit()
  }
  $process.Dispose()
}
