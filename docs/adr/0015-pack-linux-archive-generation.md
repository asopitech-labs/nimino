# ADR-0015: nimino-pack Linux archive generation

## Status

Accepted — Docker内でDebian/RPM archiveを生成し、AppImageは必要toolの固定エラーまでをM6の現時点の範囲とする。

## Context

`nimino pack`はbundleと`nimino-linux-package.json`、desktop entryを生成するが、前段のmetadataだけでは配布用archiveにならない。TauriもLinuxでDebian、RPM、AppImageなどの複数形式を扱う。[Tauri distribution](https://v2.tauri.app/distribute/) 

AppImageはAppDir rootに`AppRun`、一つのdesktop file、対応するiconを必要とし、`appimagetool`がAppDirからruntimeとfilesystem imageを組み立てる。[AppDir specification](https://docs.appimage.org/reference/appdir.html) さらにAppImageはアプリの必要なresourceと依存ライブラリをpackager側で用意しなければ実行可能性を保証できない。[AppImage software overview](https://docs.appimage.org/introduction/software-overview.html)

現在の開発imageには`dpkg-deb`だけがあり、`rpmbuild`、`desktop-file-validate`、`appimagetool`はないことをDocker内で確認した。`rpm`と`desktop-file-utils`はDebian packageとしてimageへ追加できる。前者はRPM packaging team、後者はDebian freedesktop.org maintainersが保守する。[Debian rpm package](https://packages.debian.org/stable/rpm) [Debian desktop-file-utils](https://packages.debian.org/stable/desktop-file-utils)

## Decision

- `nimino package-linux <bundle> --format deb|rpm|appimage --out <directory>`を`nimino-pack`のCLIとして追加する。入力はTOMLではなく、検証済みbundle内の`nimino-linux-package.json`とdesktop entryである。
- `deb`は`dpkg-deb`で`/opt/nimino/<id>`と`/usr/share/applications/<id>.desktop`を含むarchiveを生成する。Debian controlに必要な`--maintainer`を明示入力とする。
- `rpm`は`rpmbuild`で同じlayoutを生成する。RPM specに必要な`--license`を明示入力とする。初期実装はrelease version (`major.minor.patch`)だけを許可し、prerelease/build versionのRPM変換は別作業にする。
- 生成前に`desktop-file-validate`を必須にし、不正なmetadataをarchiveへ入れない。対応architectureは`amd64`と`arm64`で、callerがhost binaryと一致する値を指定する。
- AppImageは`appimagetool`がDocker imageにない場合、固定された`unsupportedFeature`エラーにする。未検証・未checksum固定のAppImage binaryをDockerfileへ導入しない。tool導入、AppDir作成、GTK/WebKitGTK依存のbundle、FUSE/runtime互換性、署名は別ADRと実機testを必要とする。

## Consequences

- `make pack-linux-test`はDockerだけでCLI、desktop validation、Debian/RPMの生成とarchive contentsを確認する。ホストにNim、rpmbuild、dpkg-debを導入しない。
- Debian/RPM archiveは署名しない。配布repository、GPG key管理、SBOM、license policy、postinst/prerm、uninstall実機testは後続M6の責務である。
- AppImageの固定エラーは「AppImageが実装済み」を意味しない。toolを追加する時は、release version・SHA-256・license・保守者・AppDir dependency closureをこのADRへ追記してからDocker imageを更新する。
