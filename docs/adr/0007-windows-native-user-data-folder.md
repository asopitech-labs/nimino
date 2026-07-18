# ADR-0007: Windows native backendは書込み可能な既定User Data Folderを明示する

- 状態: Accepted
- 日付: 2026-07-18

## 文脈

WebView2の`CreateCoreWebView2EnvironmentWithOptions`にUser Data Folder（UDF）を
指定しない場合、Runtimeはhost executableの配置に基づく既定位置を使用する。WSLから
起動したWindows hostは`\\wsl.localhost\...`の共有パスに配置されるため、この既定UDFの
作成が`E_ACCESSDENIED`で失敗した。LoaderおよびEvergreen Runtimeの導入有無とは別の
問題である。

WebView2公式仕様は`E_ACCESSDENIED`をUDF作成時のアクセス拒否として定義し、Win32では
書込み可能なカスタムUDFを指定することを推奨している。

## 決定

`nimino-native`のWindows private backendは、公開profile APIを追加せず、最低限の
フォールバックとして次のローカルパスを`CreateCoreWebView2EnvironmentWithOptions`へ渡す。

```text
%LOCALAPPDATA%\Nimino\Native\<実行ファイル名>
```

- `LOCALAPPDATA`が取得不能、またはディレクトリ作成に失敗した場合は、`osError`の
  `webview.userDataFolder` を返す。
- UDFはWindowsローカルストレージにのみ置き、WSL共有・ネットワークパスには置かない。
- これはネイティブ層の起動可能性を保証するためのフォールバックであり、プロファイル、
  Cookie分離、保存領域ポリシーを表現しない。

## 帰結

- Windows native と WSL host は、書込み不能なexe配置でもWebView2 Environmentを
  作成できる。
- 実行ファイル名だけを分離キーに使うため、アプリID・profileごとの保存領域には
  不十分である。M4で`nimino-core`がアプリID/profileから決定したUDFをWindows backendへ
  明示指定できる構成へ拡張し、このフォールバックへ依存しない。
- UDFにはCookie、cache、permission等が含まれ得るため、パスや内容をhostのstdout、
  stderr、プロトコルログへ出力しない。

## 根拠

- [Manage user data folders](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/user-data-folder)
- [CreateCoreWebView2EnvironmentWithOptions](https://learn.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/webview2-idl)
