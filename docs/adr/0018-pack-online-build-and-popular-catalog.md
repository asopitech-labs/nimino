# ADR 0018: nimino-pack のオンラインビルドとPopular Packages

## Context

Pakeは初心者向け導線として、既成のPopular Packagesをダウンロードする方法と、GitHub Actionsでローカル開発環境なしにビルドする方法を案内している。Niminoでも、Nim・Nimble・Dockerを利用者のローカルへ要求せず、`nimino-pack`を利用できる導線を提供する。

## Decision

- `nimino-pack`に、検証済み配布物を指すPopular Packagesカタログを追加する。各エントリは名前、アプリID、対象URLまたはmanifest、対象OS、リリース番号、SHA-256、署名・生成元を明示する。
- `.github/workflows/nimino-pack-online.yml`の`workflow_dispatch`をオンラインビルドの標準入口とする。入力はURLまたはmanifest、名前、ID、対象OS、配布形式、アイコンを受け取り、固定digestのNimino Dockerイメージ内で`nimino-pack`を実行してartifactとchecksum/SBOMを保存する。DockerイメージにはNim、GTK 4、WebKitGTK 6.0、packaging toolchainを含め、利用者へGTK/WebKitGTKの手動導入を要求しない。Windows実機セットアップは`make setup`からWebView2 Evergreen RuntimeのPowerShell導入を呼び出す。
- オンラインビルドはリポジトリ所有者のActions権限とGitHubのartifact保持期間に従う。任意の秘密情報、WSLホスト、ローカルファイル、開発者マシンの資格情報をworkflowへ渡さない。
- 未実装の配布形式や依存閉包を成功扱いにしない。MSI、署名済み更新、macOS、WebKitGTK依存を閉包したAppImageは、対応条件を満たすまでworkflowで明示的に失敗させる。
- Popular Packagesは第三者サイトを暗黙に信頼せず、Niminoのrelease metadata、checksum、署名検証を通過したartifactだけを表示する。

## Acceptance criteria

1. `workflow_dispatch`だけで、ローカルツール未導入の利用者が対象artifactを取得できる。
2. 同じ入力とtoolchain digestから再ビルドでき、checksum/SBOMがartifactに含まれる。
3. unsupportedなOS・形式・依存閉包は失敗として表示される。
4. カタログの各artifactにchecksum、生成commit、対応OS、`make setup`または固定Docker imageが準備したWebView2/GTKの情報を表示する。
