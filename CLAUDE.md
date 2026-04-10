# X Automation System

## 概要
Xアカウントを完全自律運用するマルチエージェントシステム。9つの専門エージェントが連携し、**朝8:00・夕19:00の2投稿**を毎日自動生成・公開する。加えて**週次でX記事（Note記事）を自動制作**する。

## パイプライン構成

### 日次パイプライン（毎日）
```
[テーマ差し込み（随時、n8n経由）]
  ↓
pipeline_inject.sh → post/data/injected_topic.json（2-3日間有効）

[毎朝7:00 n8n起動]
  ↓
差し込みテーマチェック → post/data/pipeline_context.json に injection 情報付与
  ↓
Researcher → post/data/trends.json           （X API検索・Web検索・競合分析）
  ↓
Planner[morning] → post/data/content_plan.json  （朝スロット企画 ※差し込みテーマ優先）
  ↓
Writer → post/data/draft.json               （500文字以上の下書き）
  ↓
Editor → post/data/approved_post.json       （11点品質チェック）
  ↓
Webhook → n8n → X投稿（8:00）→ slots_used 更新

  ↓（同日、夕スロット繰り返し）
Planner[evening] → Writer → Editor → Webhook（19:00）

[30分ごと n8n起動]
  ↓
n8n: リプライ取得 → pipeline_reply.sh → Webhook → n8nがランダム間隔で返信
```

### 週次記事パイプライン（週1回）
```
[週1回 n8n起動]
  ↓
pipeline_article.sh
  ↓
STEP 1: バズ記事リサーチ（先週分、SocialData API）
  ※ article/output/ に7日以内の report-*.json と analysis-*.md があれば
    リサーチをスキップして既存データを再利用（API節約）
  → article/output/report-{日時}.json
  → article/output/analysis-{日時}.md
  ↓
STEP 2: 分析履歴の蓄積（過去1ヶ月分保持）
  → data/article_analysis_history.json
  ↓
STEP 3: article_planner（20テーマ候補立案＆上位5本選定）
  読込: 分析結果 + 分析履歴 + trends.json + knowledge_stock + persona
  → data/article_theme_candidates.json（candidates: 20件, selected: 5件）
  ↓
STEP 4-5: 選定5本をループで執筆＆Webhook送信
  for rank in 1..5:
    selected[rank-1] → data/article_plan.json
    article_writer → data/article_draft.json（3000文字以上）
                   → data/article_drafts/article_draft_{rank}.json に複製
    Webhook → n8n → Note記事公開（rank/total 付き）
  ↓
STEP 6: ナレッジストック使用カウント更新（選定5本分まとめて）
```

## 手動実行コマンド
| やりたいこと | コマンド |
|---|---|
| 初回セットアップ | `/x-setup` |
| リサーチャー単体 | `/x-researcher` |
| プランナー単体 | `/x-planner` |
| ライター単体 | `/x-writer` |
| エディター単体 | `/x-editor` |
| アナリスト実行 | `/x-analyst` |
| コミュニティ管理 | `/x-community-manager` |
| 画像プロンプト生成 | `/x-creative` |
| 文体ガイド更新 | `/writing-style-clone` |
| ストーリー投稿作成 | `/storytelling-writer` |
| X運用メンター | `/x-mentor` |
| ナレッジ登録 | `/x-knowledge` |
| ナレッジ追加(CLI) | `bash scripts/pipeline_knowledge.sh '{"topic":"テーマ","content":"内容","category":"philosophy"}'` |
| ナレッジ一覧 | `bash scripts/pipeline_knowledge.sh list` |
| テーマ差し込み | `bash scripts/pipeline_inject.sh '{"topic":"テーマ","details":"詳細","source_url":"URL","duration_days":3}'` |
| 朝パイプライン手動実行 | `bash scripts/pipeline_morning.sh` |
| リプライ返信手動実行 | `bash scripts/pipeline_reply.sh <replies.json>` |
| 分析パイプライン実行 | `bash scripts/pipeline_analysis.sh` |
| 記事をWebhook送信(Note) | `bash scripts/publish_article.sh note` |
| 記事をWebhook送信(特典) | `bash scripts/publish_article.sh bonus` |
| **プレゼント企画パイプライン** | `bash giveaway/scripts/pipeline.sh` |
| **X記事制作パイプライン** | `bash scripts/pipeline_article.sh` |
| X記事制作（リサーチ省略） | `bash scripts/pipeline_article.sh --skip-research` |
| X記事制作（閾値変更） | `bash scripts/pipeline_article.sh --min-faves 500` |
| X記事リサーチ単体 | `bash scripts/pipeline_article_research.sh --min-faves 1000 --verbose` |
| X記事リサーチ+分析 | `bash scripts/pipeline_article_research.sh --min-faves 1000 --analyze --verbose` |
| X記事分析のみ | `bash scripts/pipeline_article_research.sh --analyze-only --category AI` |

## 主要データファイル（agents が読み書きする）

| ファイル | 役割 | 更新者 |
|---|---|---|
| `data/persona.md` | アカウントペルソナ・競合・検索キーワード（共有） | x-setup / 手動 |
| `data/style_guide.md` | 文体ルール・禁止表現（共有） | style_cloner |
| `data/strategy.md` | 投稿戦略・インサイト（共有） | analyst |
| `data/knowledge_stock.json` | オーナーの思想・哲学・体験ストック（共有） | pipeline_knowledge.sh / x-knowledge |
| `post/data/pipeline_context.json` | 実行スロット情報（morning/evening） | pipeline_morning.sh |
| `post/data/trends.json` | 当日リサーチ結果 | researcher |
| `post/data/weekly_plan.json` | 週次テーマカレンダー | planner（月曜のみ） |
| `post/data/content_plan.json` | 当日コンテンツ企画 | planner |
| `post/data/draft.json` | ライター下書き | writer / storytelling |
| `post/data/approved_post.json` | 承認済み最終投稿 | editor |
| `post/data/visual_prompt.json` | 画像プロンプト | creative |
| `post/data/analytics.json` | 投稿成績データ | analyst |
| `post/data/research_history.json` | 過去30件のリサーチ履歴 | pipeline_morning.sh |
| `post/data/input_metrics.json` | n8nから受け取るメトリクス | n8n連携 |
| `post/data/input_mentions.json` | n8nから受け取るリプライ | n8n連携 |
| `post/data/reactive_replies.json` | 生成した返信 | community_manager |
| `post/data/reply_counter.json` | 日次返信カウンター（上限150件/日, 15件/回） | pipeline_reply.sh |
| `post/data/injected_topic.json` | 差し込みテーマ（n8nから特定テーマを2-3日間投稿に反映） | pipeline_inject.sh / n8n連携 |
| `data/article_analysis_history.json` | バズ記事分析の蓄積（過去1ヶ月分保持） | pipeline_article.sh |
| `data/article_theme_candidates.json` | 20テーマ候補＋選定5本の企画（週次） | article_planner |
| `data/article_plan.json` | 現在執筆中の単一プラン（selected[N]を展開したもの） | pipeline_article.sh |
| `data/article_draft.json` | 現在執筆中の記事下書き（3000文字以上） | article_writer |
| `data/article_drafts/article_draft_{1..5}.json` | 週次5本のランク別ドラフト保存先 | pipeline_article.sh |
| `article/output/report-{日時}.md` | X記事リサーチレポート（サマリー+TOP20+全文） | x-article-researcher.js |
| `article/output/report-{日時}.json` | X記事リサーチJSONデータ | x-article-researcher.js |
| `article/output/analysis-{日時}.md` | X記事分析レポート（パターン分析・統計） | x-article-analyzer.js |
| `article/cache/articles/{tweetId}.json` | 記事キャッシュ（2回目以降のコスト削減） | x-article-researcher.js |
| `giveaway/config.json` | プレゼント企画設定 | 手動 |
| `giveaway/data/giveaway_research.json` | プレゼント企画調査結果 | giveaway_researcher |
| `giveaway/data/giveaway_plan.json` | プレゼント企画設計 | giveaway_planner |
| `giveaway/data/giveaway_note_draft.json` | プレゼント企画Note記事下書き | giveaway_note_writer |
| `giveaway/data/giveaway_bonus_draft.json` | 引用RT特典コンテンツ下書き | giveaway_bonus_writer |
| `giveaway/data/giveaway_x_posts.json` | プレゼント企画X投稿5本 | giveaway_x_writer |
| `giveaway/data/giveaway_note_result.json` | Note公開結果（URL等） | pipeline |
| `giveaway/resources/affiliate_guide.md` | アフィリエイトガイド | 手動 |

## 絶対ルール（全エージェント共通）

- **ハルシネーション禁止**: 最新情報解説型の投稿では出典URLが存在する情報のみ使用
- **絵文字・ハッシュタグ禁止**: 投稿本文に一切使用しない
- **500文字以上**: 全投稿を必ず500文字以上にする
- **です・ます調統一**: 「しかし」→「でも」、「したがって」→「だから」
- **スロット意識**: morning=教育型・フォロワー獲得、evening=共感系・エンゲージメント

## スロット別コンテンツ方針

| slot | 優先スタイル | 優先CTA | 目標 |
|---|---|---|---|
| morning | 最新情報解説型・教育型 | follow / save | リーチ拡大・フォロワー獲得 |
| evening | 共感ストーリー型・カジュアル報告型 | reply / retweet | ファン化・いいね・RT |

## .env 設定項目
```
WEBHOOK_URL=https://your-n8n.com/webhook/morning-post
REPLY_WEBHOOK_URL=https://your-n8n.com/webhook/reply-handler
ARTICLE_WEBHOOK_URL=https://your-n8n.com/webhook/article-handler  # X記事パイプライン用（メール通知）
GIVEAWAY_WEBHOOK_URL=https://your-n8n.com/webhook/giveaway-content  # プレゼント企画用
X_BEARER_TOKEN=your_x_api_bearer_token
SOCIALDATA_API_KEY=your_socialdata_api_key  # X記事リサーチ用（https://socialdata.tools）
```

## 参考リソース（エージェントが参照するリファレンス）
- `.claude/skills/writing-style-clone/assets/x_post_sample.md` — 5タイプの投稿文体サンプル
- `.claude/skills/writing-style-clone/references/style_guide.md` — 文体ルール詳細
- `.claude/skills/storytelling-writer/references/emotion_triggers.md` — 感情トリガー一覧
- `.claude/skills/x-mentor/references/writing-workshop.md` — Hook/Thread/選題の執筆フレームワーク
- `.claude/skills/x-mentor/references/algorithm-niche.md` — Xアルゴリズム権重・AI/tech戦略
- `.claude/skills/x-mentor/references/growth-monetization.md` — 成長エンジン・収益化パス
- `.claude/skills/x-mentor/references/quality-analytics.md` — 品質チェックリスト・反パターン
- `.claude/skills/x-mentor/references/mental-models-heuristics.md` — 6メンタルモデル・10ヒューリスティック
