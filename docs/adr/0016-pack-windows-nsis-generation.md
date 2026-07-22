# ADR-0016: nimino-pack Windows NSIS generation

## Status

Accepted — Docker内のDebian `nsis` packageでper-user NSIS setupを、`wixl`（msitools）でper-user MSIをクロス生成する。

## Context

`nimino pack --out`はWindowsのper-user install root、Start Menu shortcut、ARP registry entry、WebView2 Evergreen Runtime要件を含む`nimino-windows-installer.json`を生成する。しかしmetadataとPowerShell templateだけでは、配布用のWindows setup EXEにならない。

NSISはWindows installer/uninstallerをscriptから作るtoolであり、`File /r`、`WriteUninstaller`、registry、shortcutを扱える。[NSIS Users Manual](https://nsis.sourceforge.io/Docs/) [NSIS File reference](https://nsis.sourceforge.io/Reference/File) [NSIS WriteUninstaller reference](https://nsis.sourceforge.io/Reference/WriteUninstaller) Debian stableはNSIS 3.11-1を配布し、Windows installer作成用packageとして保守している。[Debian nsis package](https://packages.debian.org/stable/nsis)

MSIにはWiX等のtoolchainに加え、Windows Installer databaseとICEによるWindows側validationが必要である。Debianの`wixl`はWiX互換の生成器で、Docker内で再現可能なMSI databaseを生成できる。一方、Windows Installerの実機install/upgrade/uninstallおよびICE検査は別のWindows CI境界として扱う。[Debian wixl manual](https://manpages.debian.org/trixie/wixl/wixl.1.en.html)

## Decision

- `nimino package-windows <bundle> --format nsis --out <directory>`を追加する。出力は`<id>-<version>-setup.exe`と、監査用の同名`.nsi`である。
- `makensis`はDocker image内のDebian `nsis` packageを使用する。NSIS packageはDocker image構築時にAPTが解決するため、Nim・NSIS・WiXをローカルへ導入しない。
- NSIS scriptは`RequestExecutionLevel user`と`SetShellVarContext current`を使い、`%LOCALAPPDATA%\\Nimino\\<id>`、HKCUのUninstall key、current userのStart Menu shortcutだけを操作する。管理者権限、全ユーザー導入、code signing、WebView2 Runtime同梱は扱わない。
- Start Menu shortcutには生成したPropertyStore helperで`System.AppUserModel.ID`と
  `System.AppUserModel.ToastActivatorCLSID`を設定する。AUMIDはmanifestの`id`と一致させ、
  Toast activation CLSIDはアプリIDから安定導出する。per-user `CLSID\{guid}\LocalServer32`
  は`nimino-host.exe -Embedding --manifest ...`へ登録し、Win32 hostの
  `INotificationActivationCallback` class factoryが終了済みアプリのactivationを受ける。
  COM callbackと実行中WinRT `Activated` callbackは同じcore APIへ届ける。
- bundle外からのscript注入を避けるため、Windows metadataのschema、per-user layout、launcher、manifest、任意iconのファイル名を検証する。表示文字列はNSISのquoted stringとしてescapeする。
- `nimino package-windows <bundle> --format msi --out <directory>`は、bundleトップレベルのファイル、per-user directory tree、安定したProduct/Component GUIDを含むWix descriptorを生成し、Docker内の`wixl --arch x64`でMSIへ変換する。descriptorは成果物として残さず、生成後は`msiinfo`/`msiextract`で構造を検査する。
- MSIはWiX互換サブセットのper-user databaseに限定し、Start Menu shortcut、ARP registry、stable UpgradeCode/MajorUpgrade、deep-link/Toast registryを含める。管理者導入、インストーラーUI、コード署名、Windows Installer ICE、Windows実機のinstall/upgrade/uninstall testは別のWindows実機CIが整うまでリリース条件に含めない。

## Consequences

- `make pack-windows-test`はLinux Docker上でNSIS scriptとMSIを生成し、NSIS出力がPE (`MZ`) であること、per-user install/shortcut/ARP/uninstaller記述、MSIのFile/Registry/Shortcut/Upgrade tableとbundleファイル一覧を検証する。
- Docker testはWindows setupを実行しない。実際のWindowsでのinstall、uninstall、upgrade、shortcut起動、WebView2 runtime検出、Defender/SmartScreen挙動、code signingは未検証であり、リリース前にWindows実機CIと署名手順を追加する必要がある。
