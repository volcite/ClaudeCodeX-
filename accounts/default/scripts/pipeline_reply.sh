#!/bin/bash
# ========================================
# リプライ返信パイプライン
# n8nから30分ごとに呼び出される
# 自分の投稿に届いたリプライへの返信を生成してWebhookで返す
#
# 使い方:
#   echo '<JSON>' | bash scripts/pipeline_reply.sh    ← n8nからstdinで渡す
#   bash scripts/pipeline_reply.sh <JSONファイルパス>  ← ファイルで渡す
#
# 生成した返信をWebhookで返却 → n8n側でランダム間隔をあけて投稿
# ========================================

# 非インタラクティブSSH環境でも PATH を通す
source ~/.bashrc 2>/dev/null || source ~/.bash_profile 2>/dev/null || true
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

# claude コマンドの場所を特定
CLAUDE_CMD=$(which claude 2>/dev/null)
if [ -z "$CLAUDE_CMD" ]; then
  NVM_CLAUDE=$(ls "$HOME/.nvm/versions/node/"*/bin/claude 2>/dev/null | tail -1)
  for candidate in "$NVM_CLAUDE" "$HOME/.local/bin/claude" "$HOME/.npm-global/bin/claude" "/usr/local/bin/claude" "/usr/bin/claude"; do
    [ -n "$candidate" ] && [ -x "$candidate" ] && CLAUDE_CMD="$candidate" && break
  done
fi
if [ -z "$CLAUDE_CMD" ]; then
  echo "エラー: claude コマンドが見つかりません。インストール・PATHを確認してください。"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

LOG_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/pipeline_reply_$(date +%Y%m%d_%H%M%S).log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "========== リプライ返信パイプライン開始 =========="

# .envファイル読み込み
if [ -f "$PROJECT_DIR/.env" ]; then
  export $(grep -v '^#' "$PROJECT_DIR/.env" | xargs)
else
  log "警告: .envファイルが見つかりません"
fi

if [ -z "$REPLY_WEBHOOK_URL" ]; then
  log "エラー: REPLY_WEBHOOK_URLが設定されていません。.envファイルに追加してください。"
  exit 1
fi

# 入力: stdinまたはファイル引数からJSONを受け取る
INPUT_FILE="post/data/input_mentions.json"

if [ -n "$1" ] && [ -f "$1" ]; then
  # ファイル引数モード
  cp "$1" "$INPUT_FILE"
  log "入力: ファイル ($1)"
elif [ ! -t 0 ]; then
  # stdinモード（echo '...' | bash scripts/pipeline_reply.sh）
  cat > "$INPUT_FILE"
  log "入力: stdin"
else
  log "エラー: JSONデータをstdinまたはファイル引数で渡してください。"
  log "使い方: echo '<JSON>' | bash scripts/pipeline_reply.sh"
  log "    or: bash scripts/pipeline_reply.sh <JSONファイルパス>"
  exit 1
fi

# リプライ件数を確認
REPLY_COUNT=$(jq 'length' "$INPUT_FILE" 2>/dev/null || echo "0")
if [ "$REPLY_COUNT" = "0" ]; then
  log "新着リプライなし。スキップします。"
  exit 0
fi
log "新着リプライ: ${REPLY_COUNT}件"

# 日次上限チェック（1日150件まで、1回あたり最大15件）
DAILY_LIMIT=150
PER_RUN_LIMIT=15
TODAY=$(date +%Y-%m-%d)
COUNTER_FILE="$PROJECT_DIR/post/data/reply_counter.json"

# カウンターファイル初期化 or リセット
if [ ! -f "$COUNTER_FILE" ]; then
  echo "{\"date\": \"$TODAY\", \"count\": 0}" > "$COUNTER_FILE"
fi

COUNTER_DATE=$(jq -r '.date' "$COUNTER_FILE" 2>/dev/null || echo "")
if [ "$COUNTER_DATE" != "$TODAY" ]; then
  echo "{\"date\": \"$TODAY\", \"count\": 0}" > "$COUNTER_FILE"
fi

CURRENT_COUNT=$(jq -r '.count' "$COUNTER_FILE" 2>/dev/null || echo "0")
REMAINING=$((DAILY_LIMIT - CURRENT_COUNT))

if [ "$REMAINING" -le 0 ]; then
  log "日次上限（${DAILY_LIMIT}件）に達しています。スキップします。"
  exit 0
fi

# 1回あたりの上限と残予算の小さい方を採用
if [ "$REMAINING" -gt "$PER_RUN_LIMIT" ]; then
  BUDGET="$PER_RUN_LIMIT"
else
  BUDGET="$REMAINING"
fi
log "本日の残予算: ${REMAINING}件, 今回の上限: ${BUDGET}件"

# コミュニティマネージャーを実行
log "コミュニティマネージャー実行中... (入力: ${REPLY_COUNT}件, 予算: ${BUDGET}件)"
REPLY_OUTPUT_FILE="post/data/reactive_replies.json"

if CM_BUDGET="$BUDGET" CM_INPUT_FILE="post/data/input_mentions.json" \
   "$CLAUDE_CMD" -p "$(awk '/^---$/{n++; next} n>=2' .claude/agents/community_manager.md)" > /dev/null 2>> "$LOG_FILE"; then
  log "コミュニティマネージャー完了 ✅"
else
  log "コミュニティマネージャー失敗 ❌"
  exit 1
fi

# 出力ファイル確認
if [ ! -f "$REPLY_OUTPUT_FILE" ] || [ ! -s "$REPLY_OUTPUT_FILE" ]; then
  log "エラー: 返信出力ファイルが空です"
  exit 1
fi

# 結果集計
if command -v jq &> /dev/null; then
  GENERATED=$(jq '.replies | length' "$REPLY_OUTPUT_FILE" 2>/dev/null || echo "0")
  SKIPPED=$(jq '.skipped | length' "$REPLY_OUTPUT_FILE" 2>/dev/null || echo "0")
  FLAGGED=$(jq '.flagged | length' "$REPLY_OUTPUT_FILE" 2>/dev/null || echo "0")
  log "結果: 返信${GENERATED}件, スキップ${SKIPPED}件, 要注意${FLAGGED}件"
else
  GENERATED="0"
fi

if [ "$GENERATED" = "0" ]; then
  log "送信対象の返信が0件です。終了します。"
  exit 0
fi

# カウンター更新
NEW_COUNT=$((CURRENT_COUNT + GENERATED))
echo "{\"date\": \"$TODAY\", \"count\": $NEW_COUNT}" > "$COUNTER_FILE"
log "カウンター更新: ${CURRENT_COUNT} → ${NEW_COUNT} / ${DAILY_LIMIT}"

# n8n Webhook に送信
log "n8n Webhook送信中..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "$REPLY_WEBHOOK_URL" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d @"$REPLY_OUTPUT_FILE")

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
  log "n8n Webhook送信完了 ✅ (HTTP $HTTP_CODE)"
else
  log "n8n Webhook送信失敗 ❌ (HTTP $HTTP_CODE)"
fi

log "========== リプライ返信パイプライン終了 =========="
