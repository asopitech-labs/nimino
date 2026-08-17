# 0021. CLI の導入時にホストを配置し、pack がそれを探す

## 状態

採用

## 文脈

`nimino pack <url> --out <dir>` は `--host` を必須にしていた。バンドルは自分のホスト実行ファイルを同梱するため、pack はどれを入れるかを知る必要がある。

そのため利用者は、リリースアーカイブを展開したうえで、その中の実行ファイルへの相対パスを毎回書いていた。

```bash
nimble install https://github.com/asopitech-labs/nimino
curl -LO .../nimino-core-0.2.4-windows-x64.zip
unzip nimino-core-0.2.4-windows-x64.zip
nimino pack https://example.com --out dist/app \
  --host ./nimino-core-0.2.4-windows-x64/nimino-host.exe
```

CLI を入れてもホストは付いてこず、アーカイブの展開先とバージョン番号が毎回の入力に現れる。ローカルで一度動かしてみたいだけの利用者にとって、この三行は本質的な入力ではない。

ホストを `nimino_core` の `bin` として宣言する案は採らない。`nimble install` はソースを取得してコンパイルする機構であり、そこにホストを乗せると、ライブラリとして `nimino_core` を使いたいだけの利用者にも GTK 4/WebKitGTK 6.0 のビルド環境を要求することになる。クロスコンパイルした Windows ホストは Linux 上の `nimble install` では得られないため、そもそも同じ経路に乗らない。

一方で nimble には `after install` フックがあり、インストールの最後に任意の処理を実行できる。ネットワーク取得も、`~/.nimble/bin` へのファイル配置もできる。ホストをソースからビルドするのではなく、リリース済みのバイナリを取得して置く経路はここに乗る。

## 決定

二段構えにする。

**CLI の導入時にホストを配置する。** ルートマニフェストの `after install` で、同じバージョンのリリースアーカイブからホストを取得し、`nimble` の bin ディレクトリへ `nimino-host`（Windows では `nimino-host.exe`）として置く。ビルドはしない。取得できない場合はインストールを失敗させず、警告を出して続行する。ホストなしでも `pack --json` によるマニフェスト検証は動くためである。

**pack は `--host` を省略できる。** 省略された場合、次の順に探し、先に見つかったものを使う。

1. `NIMINO_HOST` 環境変数が指す実行ファイル
2. `PATH` 上の `nimino-host`（Windows 向けを作る場合は `nimino-host.exe`）
3. カレントディレクトリ直下に展開された `nimino-core-*` ディレクトリの中のホスト

`--host` が指定された場合は常にそれを使い、探索は行わない。

どこにも見つからなければ、探した場所を挙げて失敗する。黙って空のバンドルを作らない。

```
nimino pack: no host executable found; pass --host, set NIMINO_HOST, or unpack
a nimino-core archive into the working directory
```

## 根拠

**フックでの配置を「ライブラリと同じ扱い」にしない。** 置くのはビルド済みバイナリであり、コンパイルは走らない。`nimino_core` をライブラリとして使う利用者は、これまでどおり GUI スタックのビルド環境を要求されない。CLI を入れた利用者だけが、CLI が必要とする実行ファイルを受け取る。配布の境界は変わっていない。

**取得失敗をインストールの失敗にしない。** ネットワークのない環境や、リリース資産が未公開のバージョンでも CLI 自体は入る。ホストが要る操作を実行したときに、そこで初めて明示的に失敗する。

**探索順で `PATH` を `nimino-core-*` より先にする理由。** フックが置いた `~/.nimble/bin/nimino-host` は `PATH` 上にある。作業ディレクトリに古いアーカイブを展開したまま別バージョンの CLI を使った場合、意図しない組み合わせになるのを避ける。ディレクトリの中身を使いたい場合は `--host` で明示する。

**`NIMINO_HOST` を最優先にする理由。** CI が複数のホストを使い分ける場合、ディレクトリ構成に依存せず切り替えられる。`build_site_release.sh` のように Linux と Windows のホストを一度の実行で扱う箇所は、環境変数のほうが明示的である。

**探索を暗黙のビルドにしない。** 見つからなかったときに、ホストを勝手にビルドすることはしない。pack はビルドツールではなく、渡されたホストを詰めるパッケージャである。公開済みのバイナリを取得することはあるが、ソースをコンパイルする経路は持たない。

## クロスターゲットのホスト

Windows や macOS 向けのバンドルを Linux 上で作る場合、必要なのはそのプラットフォームのホストである。フックが置くのは実行環境向けのものだけなので、探索だけでは足りない。

pack は、生成対象のホストが見つからない場合に、同じバージョンのリリースアーカイブから取得する。取得したものは `~/.cache/nimino/hosts/<version>/<platform>/` へ置き、次回以降は再取得しない。取得は明示的な操作の結果としてのみ行い、進行状況を標準エラーへ書く。

対象プラットフォームは `--targets` から決まる。`nsis` と `msi` は Windows、`app` と `dmg` は macOS、それ以外は実行環境と同じプラットフォームである。専用のオプションは設けない。生成する配布物の種類が分かれば、必要なホストも決まるためである。

配布するホストは三つである。

| プラットフォーム | アーカイブ | ビルド元 |
| --- | --- | --- |
| Linux x86_64 | `nimino-core-<version>-linux-x86_64.tar.gz` | 固定 Docker イメージ |
| Windows x64 | `nimino-core-<version>-windows-x64.zip` | MinGW クロスビルド |
| macOS arm64 | `nimino-core-<version>-macos-arm64.tar.gz` | GitHub-hosted macOS ランナー |

macOS のホストは Cocoa と WKWebView を要するため Linux からはクロスビルドできない。リリースワークフローへ macOS ジョブを足し、そこでビルドしたものを artifact 経由で集約する。CI は既に `macos-15` ランナーで参照スイートを実行しており、同じ経路に乗る。

x86_64 の macOS ホストは配布しない。Apple は 2023 年に Apple Silicon への移行を完了しており、現行の販売機種に Intel Mac はない。必要になった場合は `--host` で明示できる。

## 帰結

利用者から見た最短の手順は次のようになる。

```bash
nimble install https://github.com/asopitech-labs/nimino
nimino pack https://example.com --out dist/app
```

配布物まで一度に作る場合も同じ形になる。必要なホストは `--targets` から決まる。

```bash
nimino pack https://example.com --out dist/app --targets nsis,msi
```

`--host` を書いている既存の呼び出しは、そのまま動く。CI スクリプトは明示指定を続ける。

探索結果は `--json` の出力に含めない。バンドルに入ったホストの素性は `nimino-sbom.cdx.json` が持つ。
