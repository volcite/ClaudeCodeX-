#!/bin/bash
# ========================================
# X Automation 初期化スクリプト
# 新しいアカウントでセットアップするときに実行
# 使い方: bash scripts/init.sh
# ========================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo ""
echo "========================================"
echo " X Automation - 初期セットアップ"
echo "========================================"
echo ""

# ----------------------------------------
# Step 1: .env のセットアップ
# ----------------------------------------
if [ -f "$ROOT_DIR/.env" ]; then
  echo "[SKIP] .env はすでに存在します"
else
  cp "$ROOT_DIR/.env.example" "$ROOT_DIR/.env"
  echo "[OK]   .env を .env.example からコピーしました"
  echo "       $ROOT_DIR/.env を開いて各APIキー・Webhook URLを設定してください"
fi

# ----------------------------------------
# Step 2: 必須ディレクトリの作成
# ----------------------------------------
mkdir -p "$ROOT_DIR/data/article_drafts"
mkdir -p "$ROOT_DIR/data/knowledge_sources"
mkdir -p "$ROOT_DIR/post/data"
mkdir -p "$ROOT_DIR/post/history"
mkdir -p "$ROOT_DIR/article/cache/articles"
mkdir -p "$ROOT_DIR/article/output"
mkdir -p "$ROOT_DIR/giveaway/data"
mkdir -p "$ROOT_DIR/config"
mkdir -p "$ROOT_DIR/logs"
echo "[OK]   必須ディレクトリを作成しました"

# ----------------------------------------
# Step 3: data/persona.md の初期化
# ----------------------------------------
if [ -f "$ROOT_DIR/data/persona.md" ]; then
  echo "[SKIP] data/persona.md はすでに存在します"
else
  cp "$ROOT_DIR/data/persona.md.example" "$ROOT_DIR/data/persona.md"
  echo "[OK]   data/persona.md を example から作成しました（/x-setup で自動生成も可能）"
fi

# ----------------------------------------
# Step 4: data/style_guide.md の初期化
# ----------------------------------------
if [ -f "$ROOT_DIR/data/style_guide.md" ]; then
  echo "[SKIP] data/style_guide.md はすでに存在します"
else
  cp "$ROOT_DIR/data/style_guide.md.example" "$ROOT_DIR/data/style_guide.md"
  echo "[OK]   data/style_guide.md を example から作成しました（/writing-style-clone で自動生成も可能）"
fi

# ----------------------------------------
# Step 5: data/strategy.md の初期化
# ----------------------------------------
if [ -f "$ROOT_DIR/data/strategy.md" ]; then
  echo "[SKIP] data/strategy.md はすでに存在します"
else
  cat > "$ROOT_DIR/data/strategy.md" << 'EOF'
# 投稿戦略

## 基本方針
（/x-setup 実行後、ペルソナに合わせて更新してください）

## 投稿スケジュール
- 朝スロット: 毎日 8:00（教育型・リーチ重視）
- 夕スロット: 毎日 19:00（共感型・エンゲージメント重視）
- リプライ: 毎日 12:00（能動的エンゲージメント）

## 実績からのインサイト
（アナリストが自動更新します）

## 競合・市場トレンドからのインサイト
（アナリストが自動更新します）

## スロット別インサイト
（アナリストが自動更新します）
EOF
  echo "[OK]   data/strategy.md を初期化しました"
fi

# ----------------------------------------
# Step 6: data/knowledge_stock.json の初期化
# ----------------------------------------
if [ -f "$ROOT_DIR/data/knowledge_stock.json" ]; then
  echo "[SKIP] data/knowledge_stock.json はすでに存在します"
else
  cat > "$ROOT_DIR/data/knowledge_stock.json" << 'EOF'
{
  "last_updated": "",
  "items": []
}
EOF
  echo "[OK]   data/knowledge_stock.json を空の状態で初期化しました"
fi

# ----------------------------------------
# Step 7: post/data/ の初期ファイル作成
# ----------------------------------------
init_json() {
  local FILE="$1" CONTENT="$2"
  if [ ! -f "$FILE" ]; then
    echo "$CONTENT" > "$FILE"
    echo "[OK]   $(basename $FILE) を初期化しました"
  fi
}

init_json "$ROOT_DIR/post/data/reply_counter.json"     '{"date": "", "count": 0}'
init_json "$ROOT_DIR/post/data/research_history.json"  '[]'
init_json "$ROOT_DIR/post/data/weekly_plan.json"       '{}'
init_json "$ROOT_DIR/post/data/trends.json"            '{}'
init_json "$ROOT_DIR/post/data/content_plan.json"      '{}'
init_json "$ROOT_DIR/post/data/draft.json"             '{}'
init_json "$ROOT_DIR/post/data/approved_post.json"     '{}'
init_json "$ROOT_DIR/post/data/pipeline_context.json"  '{}'
init_json "$ROOT_DIR/post/data/reactive_replies.json"  '{"replies": []}'
init_json "$ROOT_DIR/post/data/input_mentions.json"    '[]'
init_json "$ROOT_DIR/post/data/injected_topic.json"    '{}'

# ----------------------------------------
# Step 8: data/ の記事・分析ファイル初期化
# ----------------------------------------
init_json "$ROOT_DIR/data/article_analysis_history.json" '{"items": []}'
init_json "$ROOT_DIR/data/article_plan.json"             '{}'
init_json "$ROOT_DIR/data/article_draft.json"            '{}'
init_json "$ROOT_DIR/data/article_theme_candidates.json" '{}'
init_json "$ROOT_DIR/data/buzz_insights.json"            '{}'

# ----------------------------------------
# Step 10: giveaway/config.json の初期化
# ----------------------------------------
if [ -f "$ROOT_DIR/giveaway/config.json" ]; then
  echo "[SKIP] giveaway/config.json はすでに存在します"
else
  cat > "$ROOT_DIR/giveaway/config.json" << 'EOF'
{
  "account_id": "",
  "note_url": "",
  "campaign_name": ""
}
EOF
  echo "[OK]   giveaway/config.json を初期化しました"
fi

# ----------------------------------------
# 完了メッセージ
# ----------------------------------------
echo ""
echo "========================================"
echo " セットアップ完了！次のステップ:"
echo "========================================"
echo ""
echo " 1. .env を編集して APIキー・Webhook URLを設定"
echo "    vi .env  または  code .env"
echo ""
echo " 2. Claude Code で /x-setup を実行"
echo "    → XアカウントIDを渡すと persona.md・style_guide.md を自動生成します"
echo ""
echo " 3. ナレッジを登録する（オプション）"
echo "    bash scripts/pipeline_knowledge.sh '{\"topic\":\"テーマ\",\"content\":\"内容\",\"category\":\"philosophy\"}'"
echo ""
echo " 4. パイプラインを手動実行してテスト"
echo "    bash scripts/pipeline_morning.sh"
echo ""
