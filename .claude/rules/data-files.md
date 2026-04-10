---
description: パイプラインで使用するデータファイルの仕様と責務
globs: data/*.json, data/*.md, post/data/*.json, giveaway/data/*.json
---

# データファイル仕様

各ファイルは特定のエージェントが書き込み、後続のエージェントが読み取るパイプライン構造。

## 共有データ（data/）
| ファイル | 役割 | 書き込み者 |
|---|---|---|
| `data/persona.md` | アカウントペルソナ・競合・検索キーワード | x-setup / 手動 |
| `data/style_guide.md` | 文体ルール・禁止表現 | style_cloner |
| `data/strategy.md` | 投稿戦略・インサイト | analyst |
| `data/knowledge_stock.json` | オーナーの思想・哲学・体験ストック | pipeline_knowledge.sh |

## 投稿パイプライン（post/data/）
| ファイル | 役割 | 書き込み者 |
|---|---|---|
| `post/data/pipeline_context.json` | 実行スロット情報（morning/evening） | pipeline_morning.sh |
| `post/data/trends.json` | 当日リサーチ結果 | researcher |
| `post/data/content_plan.json` | 当日コンテンツ企画 | planner |
| `post/data/draft.json` | ライター下書き | writer / storytelling |
| `post/data/approved_post.json` | 承認済み最終投稿 | editor |
| `post/data/injected_topic.json` | 差し込みテーマ（2-3日間有効） | pipeline_inject.sh |
