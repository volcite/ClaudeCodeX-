#!/bin/bash
# ========================================
# 記事データをn8n Webhookに送信するスクリプト
# giveaway_note_draft.json または giveaway_bonus_draft.json を
# 章ごとの配列形式に変換してWebhookに送信する
#
# 使い方:
#   bash scripts/publish_article.sh note    # Note記事を送信
#   bash scripts/publish_article.sh bonus   # 追加特典を送信
# ========================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# .env読み込み
if [ -f "$PROJECT_ROOT/.env" ]; then
  set -a
  source "$PROJECT_ROOT/.env"
  set +a
fi

GIVEAWAY_WEBHOOK_URL="${GIVEAWAY_WEBHOOK_URL:-}"
if [ -z "$GIVEAWAY_WEBHOOK_URL" ]; then
  echo "エラー: GIVEAWAY_WEBHOOK_URL が .env に設定されていません。"
  exit 1
fi

TYPE="${1:-note}"

case "$TYPE" in
  note)
    INPUT_FILE="$PROJECT_ROOT/giveaway/data/giveaway_note_draft.json"
    ;;
  bonus)
    INPUT_FILE="$PROJECT_ROOT/giveaway/data/giveaway_bonus_draft.json"
    ;;
  *)
    echo "エラー: 引数は 'note' または 'bonus' を指定してください。"
    exit 1
    ;;
esac

if [ ! -f "$INPUT_FILE" ]; then
  echo "エラー: $INPUT_FILE が見つかりません。"
  exit 1
fi

echo "=========================================="
echo "記事Webhook送信: $TYPE"
echo "入力: $INPUT_FILE"
echo "送信先: $GIVEAWAY_WEBHOOK_URL"
echo "=========================================="

# Webhook送信
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$GIVEAWAY_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d @"$INPUT_FILE")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

echo "HTTPステータス: $HTTP_CODE"

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
  echo "送信成功"
  echo "$BODY" | head -5
else
  echo "送信失敗"
  echo "$BODY" | head -10
  exit 1
fi
