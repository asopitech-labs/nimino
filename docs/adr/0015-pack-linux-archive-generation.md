# ADR-0015: nimino-pack Linux archive generation

## Status

Accepted — Docker内でDebian/RPM archiveと、checksum固定の公式toolによるamd64 AppImageを生成する。

## Context

`nimino pack`はbundleと`nimino-linux-package.json`、desktop entryを生成するが、前段のmetadataだけでは配布用archiveにならない。TauriもLinuxでDebian、RPM、AppImageなどの複数形式を扱う。[Tauri distribution](https://v2.tauri.app/distribute/) 

AppImageはAppDir rootに`AppRun`、一つのdesktop file、対応するiconを必要とし、`appimagetool`がAppDirからruntimeとfilesystem imageを組み立てる。[AppDir specification](https://docs.appimage.org/reference/appdir.html) さらにAppImageはアプリの必要なresourceと依存ライブラリをpackager側で用意しなければ実行可能性を保証できない。[AppImage software overview](https://docs.appimage.org/introduction/software-overview.html)

当初の開発imageには`dpkg-deb`だけがあり、`rpmbuild`、`desktop-file-validate`、`appimagetool`はなかった。`rpm`、`desktop-file-utils`、`squashfs-tools`はDebian packageとしてimageへ追加する。前者はRPM packaging team、後者はDebian freedesktop.org maintainersが保守する。[Debian rpm package](https://packages.debian.org/stable/rpm) [Debian desktop-file-utils](https://packages.debian.org/stable/desktop-file-utils)

AppImage公式のversioned release `1.9.1`にはx86_64 assetとGitHub Release APIのSHA-256 digestがある。AppImage source repositoryはMIT licenseだが、同ライセンスは生成されるAppImageのcontentへ適用されない。[appimagetool release 1.9.1](https://github.com/AppImage/appimagetool/releases/tag/1.9.1) [appimagetool license](https://github.com/AppImage/appimagetool/blob/1.9.1/LICENSE)

## Decision

- `nimino package-linux <bundle> --format deb|rpm|appimage --out <directory>`を`nimino-pack`のCLIとして追加する。入力はTOMLではなく、検証済みbundle内の`nimino-linux-package.json`とdesktop entryである。
- `deb`は`dpkg-deb`で`/opt/nimino/<id>`と`/usr/share/applications/<id>.desktop`を含むarchiveを生成する。Debian controlに必要な`--maintainer`を明示入力とする。
- `rpm`は`rpmbuild`で同じlayoutを生成する。RPM specに必要な`--license`を明示入力とする。初期実装はrelease version (`major.minor.patch`)だけを許可し、prerelease/build versionのRPM変換は別作業にする。
- 生成前に`desktop-file-validate`を必須にし、不正なmetadataをarchiveへ入れない。対応architectureは`amd64`と`arm64`で、callerがhost binaryと一致する値を指定する。
- Docker imageは公式release `1.9.1`の`appimagetool-x86_64.AppImage`をversioned URLから取得し、SHA-256 `ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0` を照合してから配置する。tool自身はAppImageのため、Docker内では`APPIMAGE_EXTRACT_AND_RUN=1`で自己展開して実行する。AppDirがELFからarchitectureを推測できないため、wrapperは`ARCH=x86_64`を固定する。
- `appimage`はローカルiconを持つbundleだけを受け付け、AppDir rootに`AppRun`、書き換え済みdesktop entry、iconを配置する。bundleは`usr/lib/nimino/<id>`、起動器は`usr/bin/<id>`へ配置し、portableな相対パスで起動する。`amd64`以外は固定`unsupportedFeature`エラーにする。
- `copyDir`で失われる実行権限は入力bundleから明示的に復元する。これにより`AppRun`からlauncher、host binaryまで実行できる。
- tool/format生成を検証しても、GTK/WebKitGTK等のdependency closure、FUSE/runtime互換性、署名、update informationは未実装である。これらは別ADRと配布先実機testを必要とする。

## Consequences

- `make pack-linux-test`はDockerだけでCLI、desktop validation、Debian/RPMの生成とarchive contents、AppImageの生成、自己展開、AppRun・launcher・hostの実行権限と起動chainを確認する。ホストにNim、rpmbuild、dpkg-deb、appimagetoolを導入しない。
- Debian/RPM archiveは署名しない。配布repository、GPG key管理、SBOM、license policy、postinst/prerm、uninstall実機testは後続M6の責務である。
- AppImageを生成できることは、依存ライブラリが同梱された完全にポータブルなAppImageを意味しない。dependency closureを実装する時は、同梱対象、各ライブラリのlicense、system libraryとの境界、配布先実機testをこのADRへ追記する。
