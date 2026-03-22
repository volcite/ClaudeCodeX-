#!/bin/bash
# ========================================
# 朝のコンテンツ制作パイプライン（一括実行）
# n8nから毎朝7:00にこのスクリプトを1本叩くだけでOK
# ========================================
set -e

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

log "========== パイプライン開始 =========="

# ステップ1: リサーチャー（自律Web検索）
log "STEP 1/5: リサーチャー実行中..."
if claude -p "$(cat .claude/agents/researcher.md)" >> "$LOG_FILE" 2>&1; then
  log "STEP 1/5: リサーチャー完了 ✅"
  # リサーチデータ（競合分析・トレンド）を履歴に蓄積
  if [ ! -f data/research_history.json ]; then
    echo "[]" > data/research_history.json
  fi
  if [ -f data/trends.json ] && command -v jq &> /dev/null; then
    jq '. += [input]' data/research_history.json data/trends.json > data/temp_rh.json && mv data/temp_rh.json data/research_history.json
    
    LEN=$(jq 'length' data/research_history.json 2>/dev/null || echo "0")
    if [ "$LEN" -gt 30 ]; then
      # 直近30件を超えた古いデータを抽出
      jq '.[:-30]' data/research_history.json > data/temp_old.json
      # 新しいファイルには直近30件だけを残す
      jq '.[-30:]' data/research_history.json > data/temp_rh.json && mv data/temp_rh.json data/research_history.json
      
      if [ ! -f data/research_history_archive.json ]; then
        echo "[]" > data/research_history_archive.json
      fi
      
      # アーカイブ用ファイルに古いデータを追記
      jq '. + input' data/research_history_archive.json data/temp_old.json > data/temp_arc.json && mv data/temp_arc.json data/research_history_archive.json
      rm -f data/temp_old.json
      
      log "リサーチデータを蓄積し、古いデータを research_history_archive.json に退避しました（直近30件保持）"
    else
      log "リサーチデータを research_history.json に蓄積しました"
    fi
  fi
else
  log "STEP 1/5: リサーチャー失敗 ❌"
  exit 1
fi

# ステップ2: プランナー
log "STEP 2/5: プランナー実行中..."
if claude -p "$(cat .claude/agents/planner.md)" >> "$LOG_FILE" 2>&1; then
  log "STEP 2/5: プランナー完了 ✅"
else
  log "STEP 2/5: プランナー失敗 ❌"
  exit 1
fi

# ステップ3: ライター
log "STEP 3/5: ライター実行中..."
if claude -p "$(cat .claude/agents/writer.md)" >> "$LOG_FILE" 2>&1; then
  log "STEP 3/5: ライター完了 ✅"
else
  log "STEP 3/5: ライター失敗 ❌"
  exit 1
fi

# ステップ4: エディター（品質チェック → approved_post.json へ保存）
log "STEP 4/5: エディター実行中..."
if claude -p "$(cat .claude/agents/editor.md)" >> "$LOG_FILE" 2>&1; then
  log "STEP 4/5: エディター完了 ✅"
else
  log "STEP 4/5: エディター失敗 ❌"
  exit 1
fi

# 承認チェック
if command -v jq &> /dev/null; then
  APPROVED=$(jq -r '.approved' data/approved_post.json 2>/dev/null || echo "false")
  if [ "$APPROVED" = "true" ]; then
    log "投稿承認済み ✅ 19:00の自動投稿キューに格納されました"
    # posts/ に日付付きでアーカイブ
    cp data/approved_post.json "posts/$(date +%Y-%m-%d).json"
  else
    log "投稿差し戻し ⚠️ エディターからのフィードバックを確認してください"
    log "========== パイプライン終了（差し戻し） =========="
    exit 0
  fi
else
  log "jq未インストール: 承認ステータスの自動チェックをスキップしました"
fi

# ステップ5: n8n Webhook送信（承認済みの場合のみ）
log "STEP 5/5: n8n Webhook送信中..."

# .envファイルからWEBHOOK_URLを読み込む
if [ -f ".env" ]; then
  export $(grep -v '^#' .env | xargs)
else
  log "警告: .envファイルが見つかりません"
fi

# WEBHOOK_URLが未設定の場合のエラー処理
if [ -z "$WEBHOOK_URL" ]; then
  log "エラー: WEBHOOK_URLが設定されていません。.envファイルを確認してください。"
  exit 1
fi

if command -v jq &> /dev/null; then
  POST_CONTENT=$(jq -r '.final_content' data/approved_post.json)
  # JSON内のdate（YYYY-MM-DD HH:MM:00）のハイフンをスラッシュに変換（YYYY/MM/DD HH:MM:00）
  RAW_DATE=$(jq -r '.date' data/approved_post.json)
  SCHEDULED_TIME=$(echo "$RAW_DATE" | tr '-' '/')
  IMAGE_PROMPT=$(jq -r '.image_prompt // ""' data/approved_post.json)

  # Webhook送信（UTF-8対応）
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
    log "STEP 5/5: n8n Webhook送信完了 ✅ (HTTP $HTTP_CODE)"
  else
    log "STEP 5/5: n8n Webhook送信失敗 ❌ (HTTP $HTTP_CODE)"
  fi
else
  log "jq未インストール: Webhook送信をスキップしました"
fi

log "========== パイプライン終了 =========="
