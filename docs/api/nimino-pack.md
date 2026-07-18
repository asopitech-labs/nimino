# nimino-pack

## CLI

URLを直接指定して包装できます。

```bash
nimino pack https://discord.com/app \
  --name Discord \
  --id app.nimino.discord \
  --out dist/discord \
  --host nimino-host
```

既存のTOMLマニフェストも利用できます。

```bash
nimino pack discord.toml --out dist/discord --host nimino-host
```

`--out`を省略した場合は、検証済みマニフェストJSONを標準出力へ出力します。URL直接入力では`--name`と`--id`が必須で、Window設定・ナビゲーション・権限・注入設定はマニフェスト形式で指定します。

PakeのCLI包装フローを参考にしているが、生成物はNimino hostと`nimino-core`を使用し、Pake/Tauriを実行時依存にしません。
