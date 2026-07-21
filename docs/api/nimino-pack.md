# nimino-pack

## CLI

URLを直接指定して包装できます。

```bash
nimino pack https://discord.com/app \
  --name Discord \
  --id app.nimino.discord \
  --icon https://discord.com/icon.png \
  --out dist/discord \
  --host nimino-host
```

既存のTOMLマニフェストも利用できます。

```bash
nimino pack discord.toml --out dist/discord --host nimino-host
```

`--out`を省略した場合は、検証済みマニフェストJSONを標準出力へ出力します。URL直接入力では`--name`と`--id`が必須です。`--icon`は任意のアイコンURLまたはパスとして指定でき、既存のローカルファイルは生成物へコピーしてファイル名をマニフェストへ記録します。`[injection]`のローカルCSS/JavaScriptも生成物へ同梱し、参照をファイル名へ正規化します。Window設定・ナビゲーション・権限・注入設定はマニフェスト形式で指定します。

PakeのCLI包装フローを参考にしているが、生成物はNimino hostと`nimino-core`を使用し、Pake/Tauriを実行時依存にしません。

## Online build and Popular Packages (planned goal)

Pakeの初心者向け導線に合わせ、検証済みartifactをchecksum・署名・生成元付きで示すPopular Packagesカタログと、GitHub Actions `workflow_dispatch`によるオンラインビルドを追加します。オンラインビルドは固定digestのDocker toolchain内で`nimino-pack`を実行し、利用者のローカルへNim/Nimble/Dockerを要求しません。未実装の形式や依存閉包は成功扱いにせず、対応条件が満たされるまでworkflowを失敗させます。詳細は[ADR 0018](../adr/0018-pack-online-build-and-popular-catalog.md)を参照してください。

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
```

`version`は`major.minor.patch`形式（任意のSemVer prerelease/build suffix付き）、`homepage`はHTTP(S) URL、`categories`はDesktop Entry category registryの許可値に検証します。省略時は`version = "0.1.0"`、`description = name`、`categories = ["Network"]`になります。

`--out`を指定したbundleには、既存のhost・マニフェスト・起動scriptに加えて、次の配布メタデータを生成します。

| ファイル | 用途 |
| --- | --- |
| `<id>.desktop` | Linux Desktop Entry。正式な配置先を`/opt/nimino/<id>`として`Exec`・`TryExec`・ローカル`Icon`を示す |
| `nimino-linux-package.json` | Linuxパッケージ作成器へ渡す、install root・entry point・desktop entryの機械可読な入力 |
| `nimino-windows-installer.json` | Windows installer作成器へ渡す、per-user root、Start Menu shortcut、ARP登録、WebView2 Evergreen要件の入力 |
| `install-windows.ps1` | `%LOCALAPPDATA%\\Nimino\\<id>`へコピーし、Start Menu shortcutとHKCUの「アプリと機能」情報を登録するtemplate |
| `uninstall-windows.ps1` | 上記shortcut・HKCU登録・install rootを除去するtemplate |

`<id>.desktop`はreverse-DNS形式のアプリIDをファイル名に使います。`Icon`はbundleに同梱できるローカルアイコンだけを参照します。リモートURLの`--icon`は実行時に取得しないため、desktop entryの`Icon`へ書き込みません。パッケージャーはローカルアイコンを所定のicon directoryに配置する場合、生成metadataと同じアプリIDを使ってdesktop entryを調整する必要があります。

署名済みMSI、WebView2 Runtimeの同梱・検出は、後続のプラットフォーム別packagerがこのmetadataを入力として実装する範囲です。NSIS setupは下記のDocker生成経路で実装済みです。`install-windows.ps1`はWindows PowerShellで実行するtemplateであり、このリポジトリのDocker検証では実機実行しません。

### Windows NSIS setup

bundleを生成した後、Docker内でper-user NSIS setupを生成できます。

```bash
nimino package-windows dist/discord --format nsis --out dist/packages
```

`<id>-<version>-setup.exe`に加え、同じ内容を監査できる`.nsi` scriptを出力します。setupは`%LOCALAPPDATA%\\Nimino\\<id>`、HKCUのUninstall registry entry、current userのStart Menu shortcutを対象にします。管理者権限、全ユーザー導入、WebView2 Runtime同梱、code signing、Windows実機でのinstall/uninstall/upgrade検証は含みません。

`--format msi`は現在、固定された未対応エラーになります。固定WiX toolchain、Windows Installer/ICE validation、Windows実機testを整備するまでMSIは生成しません。

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

AppImageはchecksum固定済みの公式`appimagetool`で、`AppRun`、移植可能なdesktop entry、対応icon、`usr/bin`起動器、bundle本体を含むType 2 AppImageを生成します。ローカルiconを同梱したbundleが必須で、現時点のDocker imageはx86_64 toolを使うため`--arch amd64`だけを受け付けます。生成時はDocker内でFUSEを使わずtoolを自己展開して実行しますが、配布先でのAppImage runtime/FUSE互換性は別途確認が必要です。

この段階ではNimino host、GTK、WebKitGTKなどの動的依存ライブラリのdependency closure、署名、update information、各ディストリビューション実機での起動確認は実装していません。bundleにはCycloneDX 1.6の`nimino-sbom.cdx.json`を生成しますが、これは依存関係の宣言であり、動的ライブラリの同梱や署名を保証しません。したがって「単一ファイルを配布できる」ことは保証しますが、「追加のsystem libraryなしで任意のLinux上で起動できる」ことは保証しません。

Flatpak build contextは次で生成できます。

```bash
nimino package-linux dist/discord --format flatpak --out dist/packages
```

`<id>-<version>-flatpak/`に、bundleを`bundle/` sourceとして参照する固定GNOME runtime/SDK manifestを生成します。`flatpak-builder`による実bundle生成、runtimeの署名、clean Flatpak環境でのinstall/run/uninstallは別SDK環境で検証します。

## 固定された検証手順

ローカルへNimを導入せず、次のMakeターゲットをDocker経由で実行します。

```bash
make pack-test
make pack-cli-test
make pack-linux-test
make pack-windows-test
make pack-archive-test
```

`pack-test`はマニフェスト値の解析・検証、`pack-cli-test`はbundleとplatform metadata、`pack-linux-test`はDebian/RPMの内容と、AppImageの生成・自己展開・起動器・amd64制約、`pack-windows-test`はNSIS setup EXEのクロス生成とMSI未対応エラー、`pack-archive-test`は生成bundleからLinux tar.gzとWindows zipを作れることを検査します。最後の四つはDockerコンテナ内で実行します。
