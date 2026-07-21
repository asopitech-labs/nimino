# ADR-0006: M3 RPC registryはUI threadの明示tickでFutureを回収する

- 状態: Accepted
- 日付: 2026-07-17

## 文脈

RPC handlerはNim `Future`で非同期完了でき、request IDごとにtimeout/cancelを処理する必要がある。Future callbackへregistryを閉じ込めると、ARCではregistry→Future→callbackの循環や、Window破棄後callbackの寿命が複雑になる。別のasync loopやworker threadがWebViewへresponseを書くことも、UI thread所有権に反する。

## 提案

`RpcRegistry`はactive Futureとdeadlineを所有し、UI thread上の`tick()`が次を行う。

1. 完了Futureをresponseへ変換してregistryから除去する。
2. deadline超過requestをtimeout responseへ変換して除去する。
3. cancel済みrequestやtimeout済みrequestの遅延完了を無視する。

registry自身はGUIを知らず、App/Window integrationがWindows timerおよびLinux GLib sourceからtickを呼ぶ。WSL hostも既存Win32 timerで同じ責務を持つ。WSL clientはchild stdoutをバッファなしのPOSIX file descriptorで読み、最大10msの`select`待機後にもtickを呼ぶ。これにより、Streamの先読みバッファとpollの不整合を避け、host eventが来ない間にもdeadlineを進める。callback内で同期的にFutureを待たず、別のasync event loopを作らない。

## 実装状況と未完了の受入条件

LinuxではGLib timeout source（10ms）から`tick()`を実行し、core facadeを通じた実WebViewの同期request/response/notification往復、通知で完了するFuture、timeout responseを確認済みである。Windowsは同じtimer接続をx64クロスコンパイル済みだが、通常Windows coreのRuntime実行は未確認である。WSLではcoreがhost eventをWindow registryへ渡し、responseをhost評価requestへ中継することを認証済みfake hostとWindows WebView2 Runtimeで確認済みである。

- Window close時にpending requestを終了し、遅延Futureがresponseを送らないことを、fake WSL hostが送る`native.window.closed` callbackとregistry単体testで確認済みである。前者はWindow callback→registry close→`onClosed`内の遅延Future完了を、後者はclose後のFuture完了がsinkへ二重返信しないことを検査する。Windows Runtimeは必要としない。
- WSLのclient/host異常終了時にもrequest tableとnative resourceを解放する。
- `tick()`の頻度、timeout精度、UI負荷を記録する。

この決定はWSL経路のasync timeoutを実装済みとするが、Window close時のcancelと通常Windows coreのRuntime検証を完了済みとは扱わない。
