# ADR-0006: M3 RPC registryはUI threadの明示tickでFutureを回収する

- 状態: Proposed
- 日付: 2026-07-17

## 文脈

RPC handlerはNim `Future`で非同期完了でき、request IDごとにtimeout/cancelを処理する必要がある。Future callbackへregistryを閉じ込めると、ARCではregistry→Future→callbackの循環や、Window破棄後callbackの寿命が複雑になる。別のasync loopやworker threadがWebViewへresponseを書くことも、UI thread所有権に反する。

## 提案

`RpcRegistry`はactive Futureとdeadlineを所有し、UI thread上の`tick()`が次を行う。

1. 完了Futureをresponseへ変換してregistryから除去する。
2. deadline超過requestをtimeout responseへ変換して除去する。
3. cancel済みrequestやtimeout済みrequestの遅延完了を無視する。

registry自身はGUIを知らず、App/Window integrationがWindows timerおよびLinux GLib sourceからtickを呼ぶ。WSL hostも既存Win32 timerで同じ責務を持つ。callback内で同期的にFutureを待たず、別のasync event loopを作らない。

## 未完了の受入条件

- WindowsとLinuxのUI loopでtimeout/async responseを実行確認する。
- Window close時にpending requestをcancelし、遅延Futureがresponseを送らないことを確認する。
- WSLのclient/host異常終了時にもrequest tableとnative resourceを解放する。
- `tick()`の頻度、timeout精度、UI負荷を記録する。

このADRがAcceptedになるまで、registryは単体利用可能な基盤であり、App/Window RPCを実装済みとは扱わない。
