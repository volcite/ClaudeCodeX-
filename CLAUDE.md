# X Automation System（マルチアカウント構成）

## リポジトリ構造

```
ClaudeCodeX-/
  .claude/          ← 共通エージェント・スキル・ルール（全アカウントで共有）
  shared/
    article/        ← x-article-researcher.js, x-article-analyzer.js
    quote-rt/       ← x-qrt-finder.js
    scripts/        ← extract_buzz_insights.js
  accounts/
    default/        ← デフォルトアカウント（CLAUDE.md・data・scripts等）
    <account2>/     ← 追加アカウントはここに作成
```

## 各アカウントの詳細
各アカウントの CLAUDE.md を参照してください。

- [accounts/default/CLAUDE.md](accounts/default/CLAUDE.md)

## 新しいアカウントを追加する手順
1. `accounts/<account_name>/` を作成し、`accounts/default/` の構造をコピー
2. `data/persona.md`, `data/style_guide.md`, `data/knowledge_sources/` をアカウント別に編集
3. `.env` に新アカウントの Webhook URL・API キーを設定
4. n8n で `accounts/<account_name>/scripts/pipeline_morning.sh` を呼び出すように設定
