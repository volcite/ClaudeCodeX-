#!/bin/bash
# ========================================
# 能動的リプライパイプライン
# n8nから毎日12:00にこのスクリプトを叩く
# PROACTIVEモードでコミュニティマネージャーを起動し、
# インフルエンサーへの質の高いリプライを生成してn8nに送信する
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

log "========== 能動的リプライパイプライン開始 =========="

# .envファイルからREPLY_WEBHOOK_URLを読み込む
if [ -f ".env" ]; then
  export $(grep -v '^#' .env | xargs)
else
  log "警告: .envファイルが見つかりません"
fi

if [ -z "$REPLY_WEBHOOK_URL" ]; then
  log "エラー: REPLY_WEBHOOK_URLが設定されていません。.envファイルに追加してください。"
  log "例: REPLY_WEBHOOK_URL=https://your-n8n-instance/webhook/reply-handler"
  exit 1
fi

# data/trends.json が存在するか確認
if [ ! -f "data/trends.json" ]; then
  log "警告: data/trends.json が見つかりません。朝のパイプラインが先に実行されている必要があります。"
  exit 1
fi

# PROACTIVEモードでコミュニティマネージャーを実行
log "コミュニティマネージャー（PROACTIVEモード）実行中..."
REPLY_OUTPUT_FILE="data/proactive_replies.json"

if CM_MODE=proactive "$CLAUDE_CMD" -p "$(cat .claude/agents/community_manager.md)" > "$REPLY_OUTPUT_FILE" 2>> "$LOG_FILE"; then
  log "コミュニティマネージャー完了 ✅"
else
  log "コミュニティマネージャー失敗 ❌"
  exit 1
fi

# 出力ファイルの内容を確認
if [ ! -f "$REPLY_OUTPUT_FILE" ] || [ ! -s "$REPLY_OUTPUT_FILE" ]; then
  log "エラー: リプライ出力ファイルが空です"
  exit 1
fi

# n8n Webhook に送信
log "n8n Webhook送信中..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "$REPLY_WEBHOOK_URL" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d @"$REPLY_OUTPUT_FILE")

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
  log "n8n Webhook送信完了 ✅ (HTTP $HTTP_CODE)"

  # 送信したリプライ数をログに記録
  if command -v jq &> /dev/null; then
    REPLY_COUNT=$(jq '.target_replies | length' "$REPLY_OUTPUT_FILE" 2>/dev/null || echo "不明")
    log "生成されたリプライ数: ${REPLY_COUNT}件"
  fi
else
  log "n8n Webhook送信失敗 ❌ (HTTP $HTTP_CODE)"
fi

log "========== 能動的リプライパイプライン終了 =========="
