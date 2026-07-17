# ADR-0003: M1 WSL IPCは起動済みWindows hostの標準入出力を使う

- 状態: Accepted
- 日付: 2026-07-17

## 文脈

WSLのNimアプリはWindows GUIを直接作らず、`nimino-wsl-host.exe`へ要求する。候補にはTCP loopback、AF_UNIX bridge、Named Pipe、Hyper-V socketがある。WSL2の既定NATではLinuxからWindows hostへ接続するときhost gateway IPが必要で、`127.0.0.1`が使えるのはmirrored networkingの場合だけである。[WSL networking](https://learn.microsoft.com/en-us/windows/wsl/networking)

外部hostからの接続は必ず拒否し、M1は環境差と管理者権限への依存を避ける必要がある。

## 決定

WSL clientはWindows Interopで`nimino-wsl-host.exe`を子プロセスとして起動し、継承した`stdin`/`stdout`を唯一の双方向制御チャネルにする。これは列挙候補に加えて採用するtransportである。

- stdoutは長さprefix付きバイナリframe専用、stderrは診断専用である。
- Windows hostのmain threadがWin32/WebView2 STAとnative objectを所有する。UI開始前は設定requestを同期処理し、開始後はWin32 timerから`PeekNamedPipe`で継承stdinを非ブロッキングpollする。Nim reader threadからnative objectへ触れないため、UI thread所有権とstdout frame順序を保てる。
- M2の非同期 native 操作は、UI timerが完了済み Future をpollして元request IDへresponseを書き戻す。完了 callback や worker threadがstdoutへ直接書かないため、frame書込みとnative objectの所有者は引き続きUI threadだけである。
- M2のWebView文字列メッセージはhost adapterがUI thread上でqueueへ記録し、同じ timer が`native.webview.message` eventとして書き出す。clientはresponse待機中のeventを内部queueへ保存するため、eventがresponseより先に届いてもrequest/response整合性を失わない。
- M2のナビゲーション完了も同じqueue/polling経路を使い、`native.webview.navigationCompleted` eventとしてURLと成功可否を送る。WebView callbackからstdoutへ直接書かない。
- M2のナビゲーション開始は`native.webview.navigationStarting` eventとして同じ経路で通知する。これは観測専用であり、WSL clientの任意callbackによる同期中止はまだ実装しない。詳細な選択肢とスパイクはADR-0005提案で管理する。
- M2のbasic native errorは`native.webview.error` eventとして`kind`、`operation`、`platformCode`、`detail`を送る。これは認証情報をログへ書かない制約を変えず、同一アプリケーション内のIPC payloadである。
- M2の新規Window要求はnative側で暗黙作成せず拒否し、`native.webview.newWindowRequested` eventとしてURLだけを通知する。WSL clientから開く先を同期決定する方式はADR-0005提案の範囲である。
- M3の`-d:niminoWsl` core buildはLinux GTK/WebKitGTK FFIをコンパイル対象から除外し、通常の`newApp`でこのclientを選ぶ。これによりWSL binaryがLinux WebView共有ライブラリを要求したり、WSLgをfallbackにしたりしない。coreはhost executableを配布物の隣接/PATHから見つけ、開発・CIだけ`NIMINO_WSL_HOST_EXE`で上書きできる。
- `WSL_INTEROP`環境ではclientは`cmd.exe /D /S /C`経由でWindows hostを起動する。`cmd.exe`をWSL UNC current directoryから起動すると診断がstdoutへ混入するため、Windowsローカルに対応する`/mnt/c/Windows`または`/mnt/c`をchild working directoryにする。
- clientはOS CSPRNGで32 byte tokenを作る。Windows Interop child専用の`NIMINO_WSL_HOST_TOKEN`環境変数に設定し、既存の`WSLENV`を保ったまま同名を追加してWindows hostへだけ転送する。tokenは最初の`hello`にも含め、hostは環境値とconstant-time比較する。hostはhandshake timeout内に認証されない要求を処理しない。
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

Windows Interop childへの環境伝播は同一Windowsユーザーの任意processによる環境観測まで防ぐ認証境界ではない。親子が専有する継承stdio handleと組み合わせ、外部listenerを作らないことが主たる接続面の防御である。

## 帰結

TCP等を追加する場合も、protocol codecとtransport interfaceを分ける。Windows Interopを無効にしたWSLは`unsupported`であり、WSLgを代替GUIとして自動選択しない。
