# ADR 0018: nimino-pack のオンラインビルドとPopular Packages

## Context

Pakeは初心者向け導線として、既成のPopular Packagesをダウンロードする方法と、GitHub Actionsでローカル開発環境なしにビルドする方法を案内している。Niminoでも、Nim・Nimble・Dockerを利用者のローカルへ要求せず、`nimino-pack`を利用できる導線を提供する。

## Decision

- `nimino-pack`に、検証済み配布物を指すPopular Packagesカタログを追加する。各エントリは名前、アプリID、対象URLまたはmanifest、対象OS、リリース番号、SHA-256、署名・生成元を明示する。
- YouTube、Gmail、Google Analyticsのready-made installerは、別の`.github/workflows/nimino-site-release.yml`で各URLから生成する。各アプリのLinux `.deb`/`.rpm`とWindows NSIS `.exe`/MSIを作り、SBOMと`SHA256SUMS`をGitHub Releaseへ添付する。名前付きsite aliasや専用manifestは持たない。
- `.github/workflows/nimino-pack-online.yml`の`workflow_dispatch`をオンラインビルドの標準入口とする。入力はURLまたはmanifest、対象OS、配布形式、アイコンを受け取り、名前・IDは任意の上書き値とする。省略時は`nimino-pack`がURLから生成する。固定digestのNimino Dockerイメージ内で実行してartifactとchecksum/SBOMを保存する。DockerイメージにはNim、GTK 4、WebKitGTK 6.0、packaging toolchainを含め、利用者へGTK/WebKitGTKの手動導入を要求しない。Windows実機セットアップは`make setup`からWebView2 Evergreen RuntimeのPowerShell導入を呼び出す。
- オンラインビルドはリポジトリ所有者のActions権限とGitHubのartifact保持期間に従う。任意の秘密情報、WSLホスト、ローカルファイル、開発者マシンの資格情報をworkflowへ渡さない。
- 未実装の配布形式や依存閉包を成功扱いにしない。MSI、署名済み更新、macOS、WebKitGTK依存を閉包したAppImageは、対応条件を満たすまでworkflowで明示的に失敗させる。
- Popular Packagesは第三者サイトを暗黙に信頼せず、Niminoのrelease metadata、checksum、署名検証を通過したartifactだけを表示する。

### Catalog verification boundary

- `catalog/popular-packages.json`をschema version付きの静的catalogとする。署名済みreleaseがまだない間は空配列を正しい状態とし、未検証artifactを例示目的で登録しない。
- 各entryはwebsite、app ID、version、target/architecture/format、version付きGitHub Release URL、artifact SHA-256/size、SBOM URL/SHA-256、生成repository、40桁commit、workflow path、run IDを必須とする。`latest/download`は生成元を一意に固定できないため許可しない。
- 署名対象はartifactだけではなく、上記metadataを改行区切りで正規化した`nimino-popular-package-v1` statementとする。これにより、署名済みartifactを別URL・別commit・別workflowの成果物として再掲する置換を検出する。
- 検証鍵はcatalog内の`keyId`だけを信用せず、呼び出し側が別経路で信頼した公開鍵との一致を必須にする。秘密鍵はrepository、Docker image、通常のonline build workflowへ保存・注入しない。
- 公開pack APIはcatalogを厳格に読み込み、未知field、重複slug、未対応format、信頼外repository/workflow、不正checksum/signatureを拒否する。release検証ではローカルartifactとSBOMのSHA-256/sizeを照合した後にminisign署名を検証する。
- 署名検証には、Tauri updaterのminisign公開鍵照合を参考に、Debianの`minisign` packageを固定Docker toolchainへ追加する。minisignはISC licenseで、upstreamとDebian stable packageの保守状況を確認する。[upstream license](https://github.com/jedisct1/minisign/blob/master/LICENSE) [Debian package](https://packages.debian.org/stable/misc/minisign)
- `sha256sum`または`minisign`が利用できない環境は未対応を明示し、署名検証を省略して成功扱いしない。

## Acceptance criteria

1. `workflow_dispatch`だけで、ローカルツール未導入の利用者が対象artifactを取得できる。
2. 同じ入力とtoolchain digestから再ビルドでき、checksum/SBOMがartifactに含まれる。
3. unsupportedなOS・形式・依存閉包は失敗として表示される。
4. カタログの各artifactにchecksum、生成commit、対応OS、`make setup`または固定Docker imageが準備したWebView2/GTKの情報を表示する。
5. catalog entryのmetadata改変、artifact/SBOM改変、信頼鍵の不一致、署名tool不足をすべて失敗として区別する。
