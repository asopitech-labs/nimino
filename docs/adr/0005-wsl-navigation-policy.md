# ADR-0005: WSLのナビゲーション開始policy伝達方式（提案）

- 状態: Accepted for host-local declarative rules; client callback remains deferred
- 日付: 2026-07-17

## 文脈

Windows/Linuxの`onNavigationStarting`はWebViewのUI callback中に同期的に
許可または中止を決める。WSL構成では、callbackがWindows host側にあり、任意の
Nim policyはWSL client側にある。既存のstdio transportはhostのWin32 timerが
frameを処理し、callbackからstdoutへ直接書かない。callback中にclient responseを
待つとUI threadを塞ぎ、nested message loopまたはIPCの相互待機を導入する。

現在のM2 hostは開始を`native.webview.navigationStarting` eventとして通知するだけで、
既定許可にする。この動作を`nimino-core`の透過navigation policyとして公開しては
ならない。

## 検討する選択肢

| 方式 | 利点 | リスク/不足 |
| --- | --- | --- |
| callback内でstdio responseを待つ | 任意Nim policyをそのまま使える | UI停止、nested loop、deadlock。採用しない |
| hostに宣言的allow/deny ruleを事前同期 | callbackを待たず安全 | 任意Nim関数を表現できない。URL policyとしては候補 |
| host→client decision RPCを別threadで処理 | 任意policyに近い | native object/UI thread所有権とframe順序の設計・実機検証が必要 |
| navigationを既定許可して後追い通知 | 実装が単純 | security policyとして不十分。観測eventに限定 |

## スパイクの受入条件

1. Windows WebView2 Runtimeを備えたWSL実機で、許可・拒否・timeout・client EOFを確認する。
2. native UI callbackからstdoutを書かず、UI threadが同期待機またはnested event loopをしない。
3. timeout、破損frame、client異常終了ではdeny-by-defaultとし、tokenをログ出力しない。
4. 同一requestのresponse/event順序、host終了、native resource解放をテストする。
5. `nimino-core`が公開するpolicyは選定後の全ターゲットで同じ安全な意味論を持つ。

## 暫定的な帰結

このADRがAcceptedになるまで、WSLでの開始eventは観測用途だけである。coreの
navigation policy実装とM3完了判定をこれに依存させない。

## スパイク結果（2026-07-18）

host-localな宣言的ruleを事前同期する方式を採用候補として実装した。
`native.webview.setNavigationRules`はUI loop開始前にWebView単位で一度だけ
`allow`/`deny`の文字列ruleを設定し、UI callback内で完全一致または末尾`**`の
prefix matchを評価する。denyが優先され、rule設定後の未一致URLはdenyとなる。
callbackはstdout、IPC response、nested event loopを待たないため、UI threadの
停止と相互待機を避けられる。

この方式は任意のWSL側Nim callbackを透過するものではない。`nimino-core`の
navigationPolicyへ昇格するには、次を追加検証する。

1. Windows WebView2 Runtimeで、許可・拒否・redirectの実遷移を確認する。
2. timeout、client EOF、host異常終了時にdeny-by-defaultとなる起動・再接続契約を確認する。
3. Linux nativeとWSL hostで同じpattern意味論を共通テストする。

`window.open`はJavaScript評価からの合成呼び出しではWebView2のユーザー操作要件で
抑止されるため、このhost smokeの対象外である。実クリックを伴う通常Windows GUI CIで
別途確認する。

`make wsl-host-abnormal-smoke`はhandshake直後にclient stdinを閉じ、hostが0終了して
ハングしないことを確認する。UI loop開始後のEOF、timeout後の再接続契約は未確認である。

その後、host callbackからWSL clientへ`native.webview.policyRequested` requestを送り、
coreのWindow navigationPolicyがallow/denyを同期応答する実装を追加した。timeout、EOF、
不正応答はdeny-by-defaultである。redirectの実遷移と再接続契約は引き続き別途検証する。
