# ADR-0008: URL RPC bridgeをdocument-startで登録する

- 状態: Accepted
- 日付: 2026-07-18

## 文脈

M3のRPC bridgeをナビゲーション完了後にJavaScript評価で注入すると、URL文書の
最初期scriptは`window.nimino`を観測できない。WebView2の
`AddScriptToExecuteOnDocumentCreated`とWebKitGTKの`WebKitUserScript`はこの順序を
解決できるが、登録したscriptは以後のナビゲーションやframeにも適用され得る。
origin制限なしにRPC bootstrapを登録すると、別originのコンテンツへWindowの
明示許可リストを公開することになる。

## 決定

`nimino-native`に、Viewが`pending`の間だけ一つのdocument-start scriptを設定できる
低水準primitiveを置く。Windows backendはWebView2登録の非同期完了を待ってから
最初の保留中読込を開始し、Linux backendはWebKitGTK user-content managerへ
document-start user scriptを登録する。

`nimino-core`はViewが`pending`の間の最初の対象`loadUrl`前にだけRPC bootstrapを設定する。生成したscriptは
実行時に次を検査する。

- `http`/`https`: 初回URLのscheme、host、非既定portで正規化したoriginと
  `location.origin`が一致すること。
- `data:`: originがopaqueなので、`location.href`が初回URLと完全一致すること。
- `about:`: bridgeを登録しないこと。特に`about:blank`は親originを継承し得るため、
  URL一致で信頼境界を作れない。
- それ以外のscheme: bridgeを登録しないこと。

最初に成功した設定後、bridgeは置換しない。別originとcross-origin frameではbootstrapを
初期化せず、RPCを公開しない。

## 帰結

- 許可されたURLの最初期scriptから、Windows、Linux、WSLで同じRPC surfaceを利用できる。
- native層はURL policyを所有せず、coreが安全境界を所有する。
- これはM4のnavigation policy、OAuth popup、permission policyを代替しない。
  WSLの同期ナビゲーション判断は引き続き[ADR-0005](0005-wsl-navigation-policy.md)の
  スパイク対象である。
- 将来、初回とは異なる許可originへbridgeを拡張する場合は、scriptの削除・置換、
  WebView2/GTKのframe意味論、WSL host中継を全ターゲットで検証してこのADRを更新する。

## 検証

- `make core-linux-rpc-url-smoke`はWebKitGTKの`data:`文書内inline scriptからRPCを呼ぶ。
- `make wsl-core-rpc-url-smoke`はWindows WebView2 Runtime上の同等WSL経路を呼ぶ。
- `make wsl-host-smoke`はhostのdocument-start scriptがHTML inline scriptより先に実行されることを確認する。
