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

URL指定でも`--width`、`--height`、`--resizable`、`--allow-permission`、`--inject-css`、
`--inject-js`、`--allow-url`、`--external-url`を指定できます。複雑な設定はTOMLへ移せます。

Pake固有の`--proxy-url`、`--user-agent`、`--incognito`、`--multi-instance`、
`--multi-window`、`--start-to-tray`などは、対応する`nimino-core`の公開APIがないため
CLIで受け付けません。未知のオプションはエラー終了し、設定を黙って捨てることはありません。
Niminoで利用できる同等制御は、明示的なnavigation/permission policy、profile、injection、
Window APIとして提供します。

既存のTOMLマニフェストも利用できます。

```bash
nimino pack discord.toml --out dist/discord --host nimino-host
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


`--out`を省略した場合は、検証済みマニフェストJSONを標準出力へ出力します。URL直接入力では`--name`と`--id`は不要です。`--icon`は任意のアイコンURLまたはパスとして指定でき、既存のローカルファイルは生成物へコピーしてファイル名をマニフェストへ記録します。`[injection]`のローカルCSS/JavaScriptも生成物へ同梱し、参照をファイル名へ正規化します。Window設定やパッケージ情報はURLから生成され、ナビゲーションの既定値はコアの同一サイト＋認証遷移ポリシーです。サイト固有のルールが必要な場合だけTOMLマニフェストで上書きします。

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

`catalog/popular-packages.json`は署名済みreleaseが存在するまで空です。entryはversion付きGitHub Release URL、artifact SHA-256/size、SBOM SHA-256、生成commit/workflow/run ID、および正規化statementのminisign署名を必須とします。公開鍵はcatalogと同じ入力から暗黙採用せず、呼び出し側が別経路で信頼した鍵を渡します。通常のonline build workflowは秘密鍵を扱わず、そのartifactはrelease署名が完了するまでcatalogへ登録しません。

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

`version`は`major.minor.patch`形式（任意のSemVer prerelease/build suffix付き）、`homepage`はHTTP(S) URL、`categories`はDesktop Entry category registryの許可値に検証します。省略時は`version = "0.1.0"`、`description = name`、`categories = ["Network"]`になります。

`[deepLink] schemes`はOSがアプリを起動するURL schemeを明示します。schemeはRFC 3986形式へ正規化（小文字化・重複除去）し、`http`、`https`、`file`、`mailto`などの予約schemeは拒否します。これは`nimino-core.registerCustomProtocol`のWebView内部resource schemeとは別機能です。schemeを指定すると、Linux Desktop Entryへ標準の`MimeType=x-scheme-handler/<scheme>`を追加し、WindowsではHKCUの`Software\\Classes\\<scheme>`へper-user URL Protocolを登録します。

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

## 固定された検証手順

ローカルへNimを導入せず、次のMakeターゲットをDocker経由で実行します。

```bash
make pack-test
make pack-cli-test
make pack-linux-test
make pack-appimage-guardrails
make pack-windows-test
make pack-archive-test
```

`pack-test`はマニフェスト値の解析・検証、`pack-cli-test`はbundleとplatform metadata、`pack-linux-test`はDebian/RPMとFlatpak context、`pack-flatpak-test`はGNOME 49からの実bundle export、`pack-appimage-guardrails`は未解決依存と不完全なAppImage生成の拒否、`pack-windows-test`はNSIS setup EXEとMSI databaseのクロス生成・構造、`pack-archive-test`は生成bundleからLinux tar.gzとWindows zipを作れることを検査します。CLIを使う検査はDockerコンテナ内で実行します。
