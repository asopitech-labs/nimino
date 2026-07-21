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

これは**正式なOSパッケージを生成する機能ではありません**。MSI/NSIS、署名、`deb`/RPM/AppImage/Flatpak、WebView2 Runtimeの同梱・検出は、後続のプラットフォーム別packagerがこのmetadataを入力として実装する範囲です。`install-windows.ps1`もWindows PowerShellで実行するtemplateであり、このリポジトリのDocker検証では実機実行しません。

## 固定された検証手順

ローカルへNimを導入せず、次のMakeターゲットをDocker経由で実行します。

```bash
make pack-test
make pack-cli-test
make pack-archive-test
```

`pack-test`はマニフェスト値の解析・検証、`pack-cli-test`はbundleとplatform metadata、`pack-archive-test`は生成bundleからLinux tar.gzとWindows zipを作れることを検査します。最後の二つはCLI実行時のローカルicon・injection assetの存在も確認します。
