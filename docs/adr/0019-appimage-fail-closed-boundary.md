# ADR-0019: AppImage fail-closed dependency boundary

## Status

Accepted — 固定dependency closureとWebKitGTK補助process再配置を行い、不完全なAppImageはfail-closedで拒否する。

## Context

旧AppImage経路はAppDir、AppRun、desktop entry、iconとbundleを`appimagetool`へ渡していたが、GTK/WebKitGTKを同梱していなかった。構造上正しいAppImageを生成できても、GTK/WebKitGTKのない配布先で起動できないため、M6成果物として成功扱いできない。

NiminoのLinux FFIは`libgtk-4.so.1`、`libwebkitgtk-6.0.so.4`、GLib/GIO/GObjectをNimの`dynlib`で開く。実際にビルドしたhostの`DT_NEEDED`にはこれらが現れないため、host ELFだけを走査するlinuxdeployの通常経路では依存を発見できない。WebKitGTK 6.0はさらに`WebKitGPUProcess`、`WebKitNetworkProcess`、`WebKitWebProcess`、injected bundle、sandbox用`bwrap`と`xdg-dbus-proxy`を必要とする。

Tauriはlinuxdeploy、GTK plugin、任意のGStreamer pluginを使い、WebKitGTK 4.1の補助processを明示コピーする。しかし参照実装のGTK pluginはGTK 3を固定し、NiminoのGTK 4/WebKitGTK 6.0 layoutやGPU processをそのまま扱えない。Pakeもこの処理をTauriへ委譲し、strip、GdkPixbuf loader、FUSE、WebKit process pathを既知の失敗要因としている。

## Decision

- `nimino package-linux ... --format appimage`はAppDir、依存ライブラリ、RPATH、WebKitGTK補助processを構築し、`appimagetool`で成果物を生成する。閉包未完成時は成果物を残さず失敗する。
- build toolは`appimagetool`、`linuxdeploy`、`patchelf`、`lddtree`、`pkg-config`、`glib-compile-schemas`、`gdk-pixbuf-query-loaders`、`gio-querymodules`、`bwrap`、`xdg-dbus-proxy`を固定契約とする。不足時は不足名を含む`unsupportedFeature`を返す。
- pkg-config moduleは`gtk4`、`webkitgtk-6.0`、`gio-2.0`、`gdk-pixbuf-2.0`を固定する。moduleが返す絶対pathからlibrary、schema、GIO/GdkPixbuf module/cache、WebKitGTK補助processを検査し、推測したdistribution pathへ黙ってfallbackしない。
- ELF preflightは`lddtree`で既知のsystem assetだけを静的に調べる。利用者提供hostへ`ldd`を実行しない。検査command失敗、空report、`not found`、必須dependency未報告はすべて失敗とする。
- preflight後もAppDirへのcopy、RPATHまたはloader環境、WebKitGTK埋め込みpathの安全な再配置を検証し、失敗時は固定`ioFailure`／`unsupportedFeature`を返す。sandbox有効runtime test、ライセンス/SBOM、署名は配布release gateとして別途検証する。
- 構造検査、dependency parser、実GUI runtimeは別ハーネスとし、production codeへtest hostやtimeout成功条件を入れない。
- linuxdeploy等をDockerへ追加する変更では、version/commit、SHA-256、license、保守状況を本ADRへ追記する。Tauriの`master`/`continuous`取得をコピーしない。

## Consequences

- `make pack-appimage-guardrails`は未解決dependency reportとCLI fail-closed動作を検証する。実ELFの配布先起動は別のrelease smokeで検証する。
- 既に構造だけを検査していたAppImage smokeは完成度の根拠にしない。Debian/RPM/Flatpak context検査から分離する。
- AppImageのrelease gateには、固定されたLinux build root、明示的なGTK/WebKit dependency seed、WebKitGTK 6.0補助processとsandbox helper、GIO/GdkPixbuf resources、clean target runtimeでの自動終了GUI test、同梱license/SBOM、署名が必要である。
- GStreamer pluginとcodecの同梱範囲はmedia/WebRTC/WebAudio要件とlicenseを別途決める。それまではAppImageを汎用Webアプリ配布物として有効化しない。
