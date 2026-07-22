# nimino-pack

## CLI

URLを直接指定して包装できます。

```bash
nimino pack https://discord.com/app \
  --deep-link discord \
  --icon https://discord.com/icon.png \
  --out dist/discord \
  --host nimino-host
```

`--name`、`--id`、`--profile`は任意です。省略するとURLから安定した名前・IDを生成し、Window設定、既定プロファイル、パッケージメタデータも同じ生成器で補います。

ローカルの静的サイトも入力にできます。ディレクトリ指定ではルートの
`index.html`をエントリとしてツリー全体を`assets/`へ同梱します。単一HTML
ファイルは既定ではそのファイルだけを同梱し、Pake互換の`--use-local-file`
を付けると同じディレクトリのサブツリーを再帰的に同梱します。

```bash
nimino pack ./dist --name LocalApp --out build/local-bundle --host nimino-host
nimino pack ./site/index.html --use-local-file --out build/site-bundle --host nimino-host
```

URL指定でも`--width`、`--height`、`--resizable`、`--fullscreen`、`--maximize`、
`--always-on-top`、`--hide-window-decorations`、`--hide-title-bar`、`--user-agent`、`--allow-permission`、
`--enable-drag-drop`、`--inject-css`、`--inject-js`、`--allow-url`、`--external-url`を指定できます。複雑な設定はTOMLへ移せます。
Windowタイトルは`--title`で変更できます。Pake形式のJSON設定ファイルも読み込めます。

```json
{"url":"https://example.com","name":"Example","identifier":"app.example.desktop","title":"Example","width":1200,"height":800,"incognito":true}
```

```bash
nimino pack --config pake.json --out dist/example --host nimino-host
```

`--user-agent`はWindows WebView2の`ICoreWebView2Settings2`とLinux WebKitGTKの
`WebKitSettings`へ適用します。`--proxy-url`はLinuxのWebKitNetworkSession、Windows WebView2の
`ICoreWebView2EnvironmentOptions`、macOS 14+のWKWebViewデータストアへ構築時に適用します。
macOSでは`http://`または`socks5://`のみ利用でき、起動後の変更はできません。`--incognito`は
Linuxのephemeral NetworkSession、Windows WebView2の`ICoreWebView2ControllerOptions`、
macOSのnon-persistent data storeへ適用します。WSL hostもWindows側へ設定を中継します。
`--zoom`は25〜500%でWebView2 Controller/WebKitGTKへ適用し、`--ignore-certificate-errors`は
明示指定時だけWebView2の追加ブラウザ引数またはWebKitGTKのTLS policyを変更します。後者は
開発・検証用途に限定し、本番配布では指定しないでください。
`--multi-instance`を指定しない場合はアプリID単位で単一インスタンスを取得し、指定した場合だけ
複数プロセスを許可します。Windows/Linux/WSLで同じ制御を行い、ロック取得失敗は明示エラーです。
ドラッグ＆ドロップは`--enable-drag-drop`で明示的に有効化し、`window.onFileDrop`へ絶対パスの配列を
通知します。未指定時はWebViewの標準ドロップ処理を維持します。
未知のオプションもエラー終了し、設定を黙って捨てることはありません。

既存のTOMLマニフェストも利用できます。

```bash
nimino pack discord.toml --out dist/discord --host nimino-host
# Pake互換の明示的な設定ファイル表記
nimino pack --config discord.toml --out dist/discord --host nimino-host
```

bundle生成と配布物生成を一度に行う場合は`--targets`を使います。MacOSターゲットは
このリポジトリでは扱わず、Windows/Linuxの指定だけを受け付けます。

```bash
nimino pack https://example.com --out dist/example --host nimino-host \
  --targets deb,rpm,nsis,msi --json
```

YouTube、Gmail、Google Analyticsのready-made installerは、`v*`タグで起動する
[`Nimino Site Release`](../../.github/workflows/nimino-site-release.yml)が3アプリ分の
Linux `.deb`/`.rpm`とWindows NSIS `.exe`/`.msi`を生成し、GitHub Releaseへ添付します。
READMEのGalleryまたは[Releases](https://github.com/asopitech-labs/nimino/releases)
からinstallerを取得してください。名前付きsite aliasやsite-specific manifestは提供しません。

Windows NSIS/MSI installerは、WebView2 Evergreen Runtimeの有無を確認します。未導入の場合だけ
Microsoft Bootstrapperをダウンロードして導入するため、利用者はinstallerを1回実行するだけです。
初回導入時はインターネット接続が必要です。`WebView2Loader.dll`はWindows bundleへ同梱します。

開発環境の修復や手動確認では、READMEに掲載したSHA-256検証付きbootstrapコマンドを使用できます。

```powershell
$u='https://github.com/asopitech-labs/nimino/releases/download/v0.1.1/Nimino-WebView2-Setup.ps1'; $p=Join-Path $env:TEMP 'Nimino-WebView2-Setup.ps1'; Invoke-WebRequest -UseBasicParsing -Uri $u -OutFile $p; if ((Get-FileHash -Algorithm SHA256 $p).Hash -ne 'FBB373CC34D49F8B1FBA0792363103455EEE30608D16F7BBD32E78197E1D6F8A') { throw 'WebView2 setup script SHA-256 mismatch' }; Set-ExecutionPolicy -Scope Process Bypass; & $p
```


`--out`を使う場合は、実行可能hostを同梱して独立bundleにするため`--host <nimino-host>`が必須です。
省略した場合は、検証済みマニフェストJSONを標準出力へ出力します。URL直接入力では`--name`と`--id`は不要です。`--icon`は任意のアイコンURLまたはパスとして指定でき、既存のローカルファイルは生成物へコピーしてファイル名をマニフェストへ記録します。`--icon`を省略したURL入力では`https?://<host>/favicon.ico`を最大8 MiB・3秒以内で取得し、存在する場合だけ`favicon.ico`として同梱します。HTTP(S)または`data:`アイコンはpack時に最大8 MiBまで取得し、bundle直下へステージングします。取得できない明示URLや空・過大なpayloadは成功扱いにしません。`[injection]`のローカルCSS/JavaScriptも生成物へ同梱し、参照をファイル名へ正規化します。Window設定やパッケージ情報はURLから生成され、ナビゲーションの既定値はコアの同一サイト＋認証遷移ポリシーです。サイト固有のルールが必要な場合だけTOMLマニフェストで上書きします。生成物の機械処理が必要な場合は`--json`を付けるとmanifest path・bundle directory・local entry・artifactsをJSONで標準出力へ返します。

PakeのCLI包装フローを参考にしているが、生成物はNimino hostと`nimino-core`を使用し、Pake/Tauriを実行時依存にしません。

## Online build and Popular Packages

Pakeの初心者向け導線に合わせ、GitHub Actions `workflow_dispatch`によるオンラインビルドを`.github/workflows/nimino-pack-online.yml`へ追加しました。固定Docker toolchain内で汎用`nimino-host`をビルドし、URLからbundleとDebian/RPM/NSIS/MSI artifact、checksum、SBOMを生成します。利用者のローカルへNim/Nimble/Dockerを要求しません。未実装の形式や依存閉包は成功扱いにせず、対応条件が満たされるまでworkflowを失敗させます。詳細は[ADR 0018](../adr/0018-pack-online-build-and-popular-catalog.md)を参照してください。

静的catalogの読み込みとrelease検証は公開pack APIとして利用できます。

```nim
import nimino_pack

let catalog = loadPopularPackageCatalog("catalog/popular-packages.json")
let selected = catalog.value.findPopularPackage("example-linux-amd64")
let verified = verifyPopularPackageRelease(
  selected.value,
  artifactPath = "Example_amd64.deb",
  sbomPath = "Example.cdx.json",
  trustedKey = PopularTrustedKey(
    keyId: "nimino-release-2026",
    publicKeyPath: "trusted/nimino-release-2026.pub"
  )
)
```

`catalog/popular-packages.json`はソースツリーの開発用空catalogです。サイトリリースworkflowはrelease assetから`popular-packages.json`と`nimino-popular-packages.pub`を生成します。生成には`NIMINO_POPULAR_CATALOG_SECRET_KEY`、`NIMINO_POPULAR_CATALOG_PUBLIC_KEY`、`NIMINO_POPULAR_CATALOG_KEY_ID`のGitHub Actions secretsが必要で、未設定ならreleaseを成功扱いにしません。online build workflowは秘密鍵を扱いません。

## 配布メタデータ

TOMLマニフェストでは任意の`[package]`で配布表示用の情報を指定できます。

```toml
name = "Discord"
id = "app.nimino.discord"
url = "https://discord.com/app"

[package]
version = "1.0.0"
description = "Discord desktop client"
publisher = "Example, Inc."
homepage = "https://discord.com"
categories = ["Network", "Utility"]

[deepLink]
schemes = ["myapp", "myapp+secure"]
```

Window/WebView/runtime制御は次のセクションで指定できます。

```toml
[window]
fullscreen = true
maximized = false
always-on-top = true
hide-window-decorations = false
enable-drag-drop = false

[webview]
user-agent = "Example/1.0"
proxy-url = "http://127.0.0.1:8080" # macOS 14+ / Linux / Windows native host
incognito = false                  # macOS / Linux / Windows native host

[runtime]
show-system-tray = true
start-to-tray = true
hide-on-close = true
multi-window = true
multi-instance = false
```

`proxy-url`と`incognito`はLinux native host、Windows WebView2 host、macOS 14+ WKWebView hostで
実装済みです。Windows/macOSではWebView環境・データストア生成時に適用され、起動後に変更できません。
macOSのプロキシ指定がある`.app`は`LSMinimumSystemVersion=14.0`になり、カメラ/マイク権限を指定した
`.app`にはInfo.plistの利用目的文字列と対応するコード署名entitlementsを同梱します。WSL hostは
認証済みIPCで同じ設定をWindows側へ転送します。設定を無視して通常セッションへフォールバックしません。
`enable-drag-drop`を有効にした場合、Windowsは`WM_DROPFILES`、LinuxはGTK4 `GtkDropTarget`を使い、
WSLは認証済みイベントとしてパスを中継します。

`window.hide-title-bar = true`はmacOSのtitle-bar overlay（traffic light buttonsは維持）として適用されます。
他のプラットフォームでは、未対応設定を成功扱いせずhost起動時に拒否します。

`version`は`major.minor.patch`形式（任意のSemVer prerelease/build suffix付き）、`homepage`はHTTP(S) URL、`categories`はDesktop Entry category registryの許可値に検証します。省略時は`version = "0.1.0"`、`description = name`、`categories = ["Network"]`になります。

`[deepLink] schemes`はOSがアプリを起動するURL schemeを明示します。schemeはRFC 3986形式へ正規化（小文字化・重複除去）し、`http`、`https`、`file`、`mailto`などの予約schemeは拒否します。これは`nimino-core.registerCustomProtocol`のWebView内部resource schemeとは別機能です。schemeを指定すると、Linux Desktop Entryへ標準の`MimeType=x-scheme-handler/<scheme>`、WindowsではHKCUのper-user URL Protocol、macOSでは`Contents/Info.plist`の`CFBundleURLTypes`を登録します。

`--out`を指定したbundleには、既存のhost・マニフェスト・起動scriptに加えて、次の配布メタデータを生成します。

| ファイル | 用途 |
| --- | --- |
| `<id>.desktop` | Linux Desktop Entry。正式な配置先を`/opt/nimino/<id>`として`Exec`・`TryExec`・ローカル`Icon`を示し、deep link指定時は`x-scheme-handler/*`を登録する |
| `nimino-linux-package.json` | Linuxパッケージ作成器へ渡す、install root・entry point・desktop entryの機械可読な入力 |
| `nimino-windows-installer.json` | Windows installer作成器へ渡す、per-user root、Start Menu shortcut、ARP登録、WebView2 Evergreen要件の入力 |
| `register-windows-shortcut.ps1` | Start Menu shortcutへ`System.AppUserModel.ID`と`System.AppUserModel.ToastActivatorCLSID`を設定するPowerShell/PropertyStore helper |
| `install-windows.ps1` | `%LOCALAPPDATA%\\Nimino\\<id>`へコピーし、Start Menu shortcutとHKCUの「アプリと機能」情報を登録するtemplate |
| `uninstall-windows.ps1` | 上記shortcut・HKCU登録・install rootを除去するtemplate |

`<id>.desktop`はreverse-DNS形式のアプリIDをファイル名に使います。`Icon`はbundleに同梱できるローカルアイコンだけを参照します。リモートURLの`--icon`は実行時に取得しないため、desktop entryの`Icon`へ書き込みません。パッケージャーはローカルアイコンを所定のicon directoryに配置する場合、生成metadataと同じアプリIDを使ってdesktop entryを調整する必要があります。

署名済みMSI、WebView2 Runtimeの検出・Bootstrapper導入は、後続の署名工程を除きNSIS/MSI
packagerへ実装済みです。`install-windows.ps1`はWindows PowerShellで実行するtemplateであり、
このリポジトリのDocker検証では実機実行しません。

### Windows NSIS setup

bundleを生成した後、Docker内でper-user NSIS setupを生成できます。

```bash
nimino package-windows dist/discord --format nsis --out dist/packages
```

`<id>-<version>-setup.exe`に加え、同じ内容を監査できる`.nsi` scriptを出力します。setupは`%LOCALAPPDATA%\\Nimino\\<id>`、HKCUのUninstall registry entry、current userのStart Menu shortcutを対象にし、未導入時はWebView2 Evergreen Bootstrapperを取得します。管理者権限、全ユーザー導入、WebView2 Runtime本体の同梱、code signing、Windows実機でのinstall/uninstall/upgrade検証は含みません。

`[deepLink] schemes`を指定した場合、NSISは各schemeの`URL Protocol`と`shell\\open\\command`をHKCUへ登録します。コマンドライン引数は生成launcherからhostへ転送されるため、OSから渡されたURIをアプリ側で受け取れます。PowerShell templateも同じ登録を行い、uninstall時は自アプリのcommand登録と一致する場合だけ削除します。

Windows通知のAUMIDはmanifestの`id`と同一に固定し、NSISおよび`install-windows.ps1`がStart Menu shortcutの`System.AppUserModel.ID`と`System.AppUserModel.ToastActivatorCLSID`へ設定します。`INotificationActivationCallback`のCOM local-serverをWindows hostへ実装し、実行中プロセスのWinRT `Activated` callbackと終了済みプロセスのCOM activationを同じ`onNotificationActivated` APIへ届けます。installerはper-user `CLSID\\{ToastActivatorCLSID}\\LocalServer32`を登録し、uninstall時は自プロセスのcommandと一致する場合だけ削除します。Docker cross-buildはCOM ABIと生成registryを検査しますが、Toast表示とShellからの終了済みプロセス起動はWindows GUI実機で別途確認します。

### Windows MSI setup

```bash
nimino package-windows dist/discord --format msi --out dist/packages
```

`<id>-<version>.msi`をDocker内のDebian `wixl`（msitools）で生成します。per-userの`%LOCALAPPDATA%\\Nimino\\<id>`へbundleのトップレベルファイルを配置し、Start Menu shortcut、HKCUのARP情報、deep-link registry、Toast COM LocalServerを含むWindows Installer databaseです。安定したUpgradeCodeと`MajorUpgrade`を生成するため同じ製品IDの上書き更新・ダウングレード拒否を定義します。生成物は`msiextract`/`msiinfo`で検査できます。WiX互換サブセットのため、管理者導入、UI、コード署名、Windows実機のinstall/upgrade/uninstallは別release gateです。
deep link指定時はMSIにも同じHKCU URL Protocol registry rowsを含めます。

### Linux archive

bundleを生成した後、Docker内でDebianまたはRPM archiveを生成できます。

```bash
nimino package-linux dist/discord --format deb --out dist/packages \
  --arch amd64 --maintainer 'Example <packaging@example.invalid>'

nimino package-linux dist/discord --format rpm --out dist/packages \
  --arch amd64 --license Proprietary
```

`deb`は`/opt/nimino/<id>`と`/usr/share/applications/<id>.desktop`を含む`.deb`を、`rpm`は同じlayoutの`.rpm`を作ります。`--arch`は`amd64`または`arm64`で、bundle内host binaryと一致させる必要があります。Debianには`--maintainer`、RPMには`--license`が必須です。RPMは現時点で`major.minor.patch` release versionだけを受け付けます。

Debian control metadataには`libgtk-4-1`と`libwebkitgtk-6.0-4`、RPM specには`gtk4`と
`webkitgtk6.0`をruntime依存として記録します。`apt`/`dnf`が依存を解決するため、利用者へ
GTK/WebKitGTKの手動導入を要求しません。依存名は対象ディストリビューションの標準パッケージ
名に固定しています。別名しか提供しないディストリビューションでは、パッケージマネージャーが
依存解決エラーを表示するため、未導入のままインストール成功とは扱いません。

```bash
nimino package-linux dist/discord --format appimage --out dist/packages --arch amd64
```

`appimage`はDocker内の固定toolchainでAppDirとdependency closureを生成します。生成前に固定build tool、GTK 4/WebKitGTK 6.0のpkg-config module、GLib schema、GIO/GdkPixbuf module、WebKitGPU/Network/Web process、injected bundle、`bwrap`、`xdg-dbus-proxy`を検査します。ELF依存検査には`lddtree`を要求し、`ldd`で利用者提供hostを実行しません。toolまたはruntime assetがなければ、CLIは`AppImage package generation is unavailable:`で始まる固定エラーを返し、`.AppImage`を残しません。

preflight後は依存ライブラリのAppDirへのcopy、RPATH、WebKitGTK補助process、GIO/GdkPixbuf resourcesを再配置して`appimagetool`へ渡します。署名、update information、配布先runtimeでのsandbox起動test、同梱ライセンスとSBOMは別のrelease gateです。

Flatpak build contextは次で生成できます。

```bash
nimino package-linux dist/discord --format flatpak --out dist/packages
```

`<id>-<version>-flatpak/`に、bundleを`bundle/` sourceとして参照するGNOME Platform/SDK 49 manifestを生成します。`make pack-flatpak-test`は専用privileged Compose serviceで`flatpak-builder`→OSTree repo→`.flatpak` exportまで検証します。runtimeの署名とclean target環境でのinstall/run/uninstallはrelease gateです。

### macOS application bundle / DMG

macOS上では、生成済みbundleからApplication bundleまたはDMGを作成できます。

```bash
nimino package-macos dist/discord --format app --out dist/packages
nimino package-macos dist/discord --format dmg --out dist/packages
nimino package-macos dist/discord --format app --out dist/packages \
  --arch arm64 --sign-identity 'Developer ID Application: Example'
nimino package-macos dist/discord --format dmg --out dist/packages \
  --sign-identity 'Developer ID Application: Example' --notary-profile 'nimino-release'
```

`Contents/Info.plist`にはmanifestのbundle ID、version、deep-link URL scheme、camera/microphone権限用途説明を記録し、Mach-O host、manifest、assetsを`Contents/MacOS`と`Contents/Resources`へ配置します。指定アイコンは`.icns`に限定し、`--arch`でhostが要求アーキテクチャを含むことを検証します。DMGは`hdiutil create`で生成します。`--sign-identity`を指定しない場合は未署名bundleを生成し、指定時だけ`codesign --deep --options runtime`を実行します。`--notary-profile`を指定した場合は、署名済みDMGを`xcrun notarytool submit --wait`へ送り、成功後に`xcrun stapler staple`を実行します。notary profile、Apple証明書、実機Gatekeeper確認はrelease環境で行います。

## 固定された検証手順

ローカルへNimを導入せず、次のMakeターゲットをDocker経由で実行します。

```bash
make pack-test
make pack-cli-test
make pack-linux-test
make pack-appimage-guardrails
make pack-windows-test
make pack-macos-test
make pack-archive-test
```

`pack-test`はマニフェスト値の解析・検証、`pack-cli-test`はbundleとplatform metadata、`pack-linux-test`はDebian/RPMとFlatpak context、`pack-flatpak-test`はGNOME 49からの実bundle export、`pack-appimage-guardrails`は未解決依存と不完全なAppImage生成の拒否、`pack-windows-test`はNSIS setup EXEとMSI databaseのクロス生成・構造、`pack-archive-test`は生成bundleからLinux tar.gzとWindows zipを作れることを検査します。CLIを使う検査はDockerコンテナ内で実行します。
