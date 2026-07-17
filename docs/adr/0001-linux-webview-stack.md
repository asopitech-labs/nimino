# ADR-0001: LinuxはGTK 4 + WebKitGTK 6.0を使用する

- 状態: Accepted
- 日付: 2026-07-17

## 文脈

Linux backendにはGTK、GLib、WebKitGTKを直接使う。GTK 3 + WebKitGTK 4.1とGTK 4 + WebKitGTK 6.0は別のAPI世代であり、GTK container APIを混在させることはできない。

## 決定

M1のLinux基準を**GTK 4、WebKitGTK 6.0、libsoup 3**に固定する。`pkg-config` packageは`gtk4`および`webkitgtk-6.0`を用いる。GTK 3/`webkit2gtk-4.0`/`webkit2gtk-4.1`互換層は作らない。

## 根拠

WebKit公式の[WebKitGTK 6.0 migration guide](https://webkitgtk.org/reference/webkit2gtk/2.39.1/migrating-to-webkitgtk-6.0.html)は、6.0がGTK 4/libsoup 3を使い、旧4.0/4.1がGTK 3であることを示している。単一世代へ固定する方が、薄いFFIと共通テストを小さく保てる。

## 帰結

- Windowは`gtk_window_set_child`で`WebKitWebView`を配置し、GTKのレイアウトにリサイズを委ねる。
- JavaScript実行は非推奨の`webkit_web_view_run_javascript`でなく、`webkit_web_view_evaluate_javascript`/`_finish`を使う。
- Docker/CIのLinux imageにはGTK 4、WebKitGTK 6.0、libsoup 3開発パッケージが必要である。
- 古いLTSディストリビューションで6.0が利用不能なら、M1 Linuxターゲットではない。互換要求が発生した場合は新ADRで再判断する。
