#!/bin/bash
# ========================================
# 朝のコンテンツ制作パイプライン（一括実行）
# n8nから毎朝7:00にこのスクリプトを1本叩くだけでOK
# 朝スロット（8:00投稿）・夕スロット（19:00投稿）の2本を自動生成する
# ========================================
set -e

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

# 作業ディレクトリを x-automation 直下に移動
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

LOG_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/pipeline_$(date +%Y%m%d_%H%M%S).log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# .envファイルからWEBHOOK_URLを読み込む
if [ -f ".env" ]; then
  export $(grep -v '^#' .env | xargs)
else
  log "警告: .envファイルが見つかりません"
fi

if [ -z "$WEBHOOK_URL" ]; then
  log "エラー: WEBHOOK_URLが設定されていません。.envファイルを確認してください。"
  exit 1
fi

# 曜日判定（1=月曜）→ 週次カレンダー生成フラグ
DOW=$(date +%u)
WEEKLY_PLANNING="false"
if [ "$DOW" = "1" ]; then
  WEEKLY_PLANNING="true"
  log "本日は月曜日 → 週次コンテンツカレンダーを生成します"
fi

log "========== パイプライン開始（2スロット制） =========="

# ステップ1: リサーチャー（朝・夕共通。1回だけ実行）
log "STEP 1: リサーチャー実行中..."

# pipeline_context.json を初期化（リサーチャーが参照するため morning スロットで初期化）
echo "{\"slot\": \"morning\", \"post_time\": \"08:00\", \"weekly_planning\": $WEEKLY_PLANNING}" > data/pipeline_context.json

if "$CLAUDE_CMD" -p "$(cat .claude/agents/researcher.md)" >> "$LOG_FILE" 2>&1; then
  log "STEP 1: リサーチャー完了 ✅"
  # リサーチデータ（競合分析・トレンド）を履歴に蓄積
  if [ ! -f data/research_history.json ]; then
    echo "[]" > data/research_history.json
  fi
  if [ -f data/trends.json ] && command -v jq &> /dev/null; then
    jq '. += [input]' data/research_history.json data/trends.json > data/temp_rh.json && mv data/temp_rh.json data/research_history.json

    LEN=$(jq 'length' data/research_history.json 2>/dev/null || echo "0")
    if [ "$LEN" -gt 30 ]; then
      # 直近30件を超えた古いデータを退避
      jq '.[:-30]' data/research_history.json > data/temp_old.json
      jq '.[-30:]' data/research_history.json > data/temp_rh.json && mv data/temp_rh.json data/research_history.json

      if [ ! -f data/research_history_archive.json ]; then
        echo "[]" > data/research_history_archive.json
      fi

      jq '. + input' data/research_history_archive.json data/temp_old.json > data/temp_arc.json && mv data/temp_arc.json data/research_history_archive.json
      rm -f data/temp_old.json

      log "リサーチデータを蓄積し、古いデータを research_history_archive.json に退避しました（直近30件保持）"
    else
      log "リサーチデータを research_history.json に蓄積しました"
    fi
  fi
else
  log "STEP 1: リサーチャー失敗 ❌"
  exit 1
fi

# ========================================
# スロット別パイプライン関数
# 引数: $1=slot名(morning/evening), $2=投稿時刻(HH:MM)
# ========================================
run_slot() {
  local SLOT="$1"
  local POST_TIME="$2"

  log "========== ${SLOT}スロット開始（${POST_TIME}投稿） =========="

  # pipeline_context.json をスロット情報で更新（プランナーが参照する）
  echo "{\"slot\": \"$SLOT\", \"post_time\": \"$POST_TIME\", \"weekly_planning\": $WEEKLY_PLANNING}" > data/pipeline_context.json

  # プランナー
  log "[${SLOT}] プランナー実行中..."
  if "$CLAUDE_CMD" -p "$(cat .claude/agents/planner.md)" >> "$LOG_FILE" 2>&1; then
    log "[${SLOT}] プランナー完了 ✅"
  else
    log "[${SLOT}] プランナー失敗 ❌"
    return 1
  fi

  # ライター
  log "[${SLOT}] ライター実行中..."
  if "$CLAUDE_CMD" -p "$(cat .claude/agents/writer.md)" >> "$LOG_FILE" 2>&1; then
    log "[${SLOT}] ライター完了 ✅"
  else
    log "[${SLOT}] ライター失敗 ❌"
    return 1
  fi

  # エディター（品質チェック → approved_post.json へ保存）
  log "[${SLOT}] エディター実行中..."
  if "$CLAUDE_CMD" -p "$(cat .claude/agents/editor.md)" >> "$LOG_FILE" 2>&1; then
    log "[${SLOT}] エディター完了 ✅"
  else
    log "[${SLOT}] エディター失敗 ❌"
    return 1
  fi

  # 承認チェック & Webhook送信
  if ! command -v jq &> /dev/null; then
    log "[${SLOT}] jq未インストール: 承認チェック・Webhook送信をスキップ"
    return 0
  fi

  local APPROVED
  APPROVED=$(jq -r '.approved' data/approved_post.json 2>/dev/null || echo "false")

  if [ "$APPROVED" = "true" ]; then
    log "[${SLOT}] 投稿承認済み ✅ ${POST_TIME}の自動投稿キューに格納"
    # posts/ にスロット付きでアーカイブ
    cp data/approved_post.json "posts/$(date +%Y-%m-%d)_${SLOT}.json"

    # Webhook送信
    local POST_CONTENT RAW_DATE SCHEDULED_TIME IMAGE_PROMPT PAYLOAD HTTP_CODE
    POST_CONTENT=$(jq -r '.final_content' data/approved_post.json)
    RAW_DATE=$(jq -r '.date' data/approved_post.json)
    SCHEDULED_TIME=$(echo "$RAW_DATE" | tr '-' '/')
    IMAGE_PROMPT=$(jq -r '.image_prompt // ""' data/approved_post.json)

    PAYLOAD=$(jq -n \
      --arg post "$POST_CONTENT" \
      --arg date "$SCHEDULED_TIME" \
      --arg image_prompt "$IMAGE_PROMPT" \
      '{"data": [{"post": $post, "date": $date, "image_prompt": $image_prompt}]}')

    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
      -X POST "$WEBHOOK_URL" \
      -H "Content-Type: application/json; charset=utf-8" \
      -d "$PAYLOAD")

    if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
      log "[${SLOT}] n8n Webhook送信完了 ✅ (HTTP $HTTP_CODE)"
    else
      log "[${SLOT}] n8n Webhook送信失敗 ❌ (HTTP $HTTP_CODE)"
    fi
  else
    log "[${SLOT}] 投稿差し戻し ⚠️ エディターのフィードバックを確認してください"
  fi

  log "========== ${SLOT}スロット完了 =========="
}

# 朝スロット実行（8:00投稿）
# 月曜の場合、プランナーが weekly_plan.json を生成してから朝コンテンツを計画する
run_slot "morning" "08:00" || log "朝スロット失敗 ❌ 夕スロットに進みます"

# 夕スロット実行（19:00投稿）
run_slot "evening" "19:00" || log "夕スロット失敗 ❌"

log "========== パイプライン終了（2スロット完了） =========="
