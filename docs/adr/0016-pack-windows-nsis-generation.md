# ADR-0016: nimino-pack Windows NSIS generation

## Status

Accepted — Docker内のDebian `nsis` packageでper-user NSIS setupをクロス生成する。MSIは未対応とする。

## Context

`nimino pack --out`はWindowsのper-user install root、Start Menu shortcut、ARP registry entry、WebView2 Evergreen Runtime要件を含む`nimino-windows-installer.json`を生成する。しかしmetadataとPowerShell templateだけでは、配布用のWindows setup EXEにならない。

NSISはWindows installer/uninstallerをscriptから作るtoolであり、`File /r`、`WriteUninstaller`、registry、shortcutを扱える。[NSIS Users Manual](https://nsis.sourceforge.io/Docs/) [NSIS File reference](https://nsis.sourceforge.io/Reference/File) [NSIS WriteUninstaller reference](https://nsis.sourceforge.io/Reference/WriteUninstaller) Debian stableはNSIS 3.11-1を配布し、Windows installer作成用packageとして保守している。[Debian nsis package](https://packages.debian.org/stable/nsis)

MSIにはWiX等のtoolchainに加え、Windows Installer databaseとICEによるWindows側validationが必要である。現行Docker imageには固定したWiX toolchainもWindows Installer validation環境もない。WiXのCLIにはMSI validation commandが存在するが、未検証のtool導入だけでMSIを生成済みと扱わない。[WiX MSI command reference](https://docs.firegiant.com/wix/tools/wixexe/)

## Decision

- `nimino package-windows <bundle> --format nsis --out <directory>`を追加する。出力は`<id>-<version>-setup.exe`と、監査用の同名`.nsi`である。
- `makensis`はDocker image内のDebian `nsis` packageを使用する。NSIS packageはDocker image構築時にAPTが解決するため、Nim・NSIS・WiXをローカルへ導入しない。
- NSIS scriptは`RequestExecutionLevel user`と`SetShellVarContext current`を使い、`%LOCALAPPDATA%\\Nimino\\<id>`、HKCUのUninstall key、current userのStart Menu shortcutだけを操作する。管理者権限、全ユーザー導入、code signing、WebView2 Runtime同梱は扱わない。
- bundle外からのscript注入を避けるため、Windows metadataのschema、per-user layout、launcher、manifest、任意iconのファイル名を検証する。表示文字列はNSISのquoted stringとしてescapeする。
- `--format msi`は固定された`unsupportedFeature`エラーにする。WiXのversion/license/保守、Docker導入、Windows Installer ICE、Windows実機のinstall/upgrade/uninstall testがそろうまでMSI生成を追加しない。

## Consequences

- `make pack-windows-test`はLinux Docker上でNSIS scriptをcompileし、出力がPE (`MZ`) であること、per-user install/shortcut/ARP/uninstaller記述、MSI未対応エラーを検証する。
- Docker testはWindows setupを実行しない。実際のWindowsでのinstall、uninstall、upgrade、shortcut起動、WebView2 runtime検出、Defender/SmartScreen挙動、code signingは未検証であり、リリース前にWindows実機CIと署名手順を追加する必要がある。
