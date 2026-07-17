# ADR-0003: M1 WSL IPCは起動済みWindows hostの標準入出力を使う

- 状態: Accepted
- 日付: 2026-07-17

## 文脈

WSLのNimアプリはWindows GUIを直接作らず、`nimino-wsl-host.exe`へ要求する。候補にはTCP loopback、AF_UNIX bridge、Named Pipe、Hyper-V socketがある。WSL2の既定NATではLinuxからWindows hostへ接続するときhost gateway IPが必要で、`127.0.0.1`が使えるのはmirrored networkingの場合だけである。[WSL networking](https://learn.microsoft.com/en-us/windows/wsl/networking)

外部hostからの接続は必ず拒否し、M1は環境差と管理者権限への依存を避ける必要がある。

## 決定

WSL clientはWindows Interopで`nimino-wsl-host.exe`を子プロセスとして起動し、継承した`stdin`/`stdout`を唯一の双方向制御チャネルにする。これは列挙候補に加えて採用するtransportである。

- stdoutは長さprefix付きバイナリframe専用、stderrは診断専用である。
- clientはOS CSPRNGで32 byte tokenを作り、最初の`hello`にprotocol versionと共に送る。hostはhandshake timeout内に認証されない要求を処理しない。
- frameにはversion、session ID、request ID、event ID、method、payload、response/error、timeout、cancel、heartbeatを定義する。
- 最大frame長とdecoder errorを定め、token/cookie/認証情報をstdout/stderr/logへ出さない。
- 1 hostは1 client、1 sessionだけを扱う。EOF、shutdown、handshake timeoutでWindowを閉じ、native resourceを解放する。
- listenerを開かないため、外部ネットワークhostも別clientも接続面を持たない。

WSLはWindows executableを起動でき、pipe/redirectionを使える。[WSLからWindows toolsを実行する公式資料](https://learn.microsoft.com/en-us/windows/wsl/filesystems#run-windows-tools-from-linux)

## 比較

| 方式 | WSL環境差 | 外部接続拒否 | M1判断 |
| --- | --- | --- | --- |
| 起動host stdio | 小さい。Windows Interopのみ | listenerなしで構造的に満たす | 採用 |
| TCP | NATではhost gateway、mirroredのみlocalhost。Firewall設定が必要 | bind/Firewallを誤ると公開される | 後続候補 |
| AF_UNIX + bridge | DrvFS/WSL2実装差とbridgeが必要 | path ACLは可能 | 不採用 |
| Named Pipe | WSL POSIX clientからはbridgeが必要 | 明示DACLなら強い | 不採用 |
| Hyper-V socket | WSLを一般VMとして扱う構成・管理者設定が必要 | 強い | 不採用 |

Windows Named Pipeを将来採用する場合は、[Named Pipe security](https://learn.microsoft.com/en-us/windows/win32/ipc/named-pipe-security-and-access-rights)に従い明示DACLを必須とする。AF_UNIXは[Windows/WSL interop](https://devblogs.microsoft.com/commandline/windowswsl-interop-with-af_unix/)の制約を満たす実機スパイク後にのみ再検討する。

## 帰結

TCP等を追加する場合も、protocol codecとtransport interfaceを分ける。Windows Interopを無効にしたWSLは`unsupported`であり、WSLgを代替GUIとして自動選択しない。
