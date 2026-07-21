# ADR-0014: nimino-pack desktop distribution metadata

## Status

Accepted — M6の正式packager前段としてplatform metadataを生成し、LinuxではDebian/RPM/AppImage archiveまで生成する。Windowsの署名済みinstallerは後続とする。

## Context

`nimino-pack`はURLまたはTOMLマニフェストから、Nimino hostを含むbundleを作る。以前のbundleは実行用manifestとhostだけであり、Linux desktop entry、Windows shortcut、アンインストール情報、package versionなどを、一貫して外部packagerへ渡せなかった。

[Pake](https://github.com/tw93/Pake)はURLをdesktop applicationとして包装し、releaseでWindows MSIとLinux AppImage/debを配布している。[TauriのWindows配布資料](https://v2.tauri.app/distribute/windows-installer/)はMSI/WiXまたはNSIS setupを、[Tauriの配布資料](https://v2.tauri.app/distribute/)はDebian、RPM、AppImage、Flatpakなどを扱う。Niminoはこれらのframeworkやruntimeを依存に加えず、将来のOS別packagerが必要な情報を消費できるようにする。

Linux desktop entryの`Exec`はDBus activationを使わないapplicationで必須であり、`TryExec`は実行可能性の判定に使われる。[Desktop Entry Specification](https://specifications.freedesktop.org/desktop-entry/latest-single/)と[Desktop Menu category registry](https://specifications.freedesktop.org/menu/latest/category-registry.html)に従う必要がある。

## Decision

- `nimino-pack`が配布表示情報を所有し、`nimino-core`へURL包装やinstaller固有の処理を入れない。
- manifestに任意の`[package]`を追加する。`version`はSemVer形式、`homepage`はHTTP(S)、`categories`はDesktop Entry registryの許可値へ検証する。既存manifestとの互換性のため、version `0.1.0`、description `name`、category `Network`を既定値とする。
- Linuxでは`<id>.desktop`と`nimino-linux-package.json`を出力する。desktop entryは正式な配置root `/opt/nimino/<id>`を示し、リモートiconを`Icon`へ入れない。ネットワーク取得をdesktop shellの起動時に要求しないためである。
- Windowsでは`nimino-windows-installer.json`とper-user PowerShell導入／削除templateを出力する。導入先は`%LOCALAPPDATA%\\Nimino\\<id>`、shortcutはStart Menu、登録先はHKCUのUninstall (ARP) とする。WebView2 Evergreen Runtimeが必要なことをmetadataに明記する。
- Debian/RPM archiveとchecksum固定のamd64 AppImageは`package-linux`で生成・内容検証する。AppImageの依存ライブラリ同梱、署名、更新情報は未実装である。
- MSI、code signing、Flatpakはこの段階で生成しない。Windows NSISは別ADRのDocker生成経路で実装済みだが、対象OSでの実機検証・署名は後続とする。Windowsのper-user PowerShell templateも引き続き提供する。

## Consequences

- bundle consumerはアプリ表示名・version・publisher・homepage・category・entry pointを、Nim sourceを再解釈せずに取得できる。
- Windows導入templateは実行可能な配布契約の雛形だが、Docker内でPowerShell、Start Menu、registryを実行・確認するものではない。Windows runner上のinstaller smokeと、署名済みinstaller作成は別M6作業になる。
- Linux desktop entryはmetadataとして検査し、Debian/RPM/AppImage archiveにも同じlayoutを含める。実際の`/opt`配置、icon theme integration、desktop database更新、署名は別packagerの責務である。
- `make pack-test`がmanifest contractを、`make pack-cli-test`がmetadataとtemplateの内容を、`make pack-archive-test`がLinux tar.gz／Windows zip archiveを検証する。いずれもDockerコンテナ内のNim toolchainを使う。
