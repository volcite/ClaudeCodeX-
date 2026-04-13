#!/bin/bash
# ========================================
# 引用RTパイプライン
# n8nから定期的に呼び出して今日のバズ投稿を引用RT
# ========================================
# 使い方: bash scripts/pipeline_quote_rt.sh [--min-faves 50]
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

# Claude Code のツール権限を事前許可
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
if [ ! -f "$CLAUDE_SETTINGS" ]; then
  mkdir -p "$HOME/.claude"
  cat > "$CLAUDE_SETTINGS" << 'SETTINGS_EOF'
{
  "permissions": {
    "allow": [
      "Read(*)",
      "Write(*)",
      "Glob(*)",
      "WebSearch(*)",
      "WebFetch(*)",
      "Bash(*)"
    ],
    "deny": []
  }
}
SETTINGS_EOF
fi

# 作業ディレクトリ設定
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

LOG_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/quote_rt_$(date +%Y%m%d_%H%M%S).log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# .env 読み込み
if [ -f "$PROJECT_DIR/.env" ]; then
  set -a
  source "$PROJECT_DIR/.env"
  set +a
fi

# jq がなければ python3 で代替
if ! command -v jq &> /dev/null; then
  if command -v python3 &> /dev/null; then
    log "警告: jq が未インストールのため python3 で代替します"
    jq() {
      python3 -c "
import sys, json

args = sys.argv[1:]
raw = '-r' in args
args = [a for a in args if a != '-r']
null_input = '-n' in args
args = [a for a in args if a != '-n']

filter_expr = args[0] if args else '.'
files = args[1:] if not null_input else []

# --arg / --argjson 処理
named_args = {}
clean_args = []
i = 0
while i < len(filter_expr.split()):
  clean_args.append(filter_expr)
  break

extra_args = {}
i = 0
while i < len(args):
  if args[i] == '--arg' and i+2 < len(args):
    extra_args[args[i+1]] = args[i+2]
    i += 3
  elif args[i] == '--argjson' and i+2 < len(args):
    extra_args[args[i+1]] = json.loads(args[i+2])
    i += 3
  else:
    i += 1

if null_input:
  data = None
elif files:
  with open(files[0]) as f:
    data = json.load(f)
else:
  data = json.load(sys.stdin)

# シンプルなフィルタのみサポート
expr = filter_expr
if expr == '.':
  result = data
elif expr.startswith('.') and '[' not in expr and ',' not in expr:
  keys = expr.lstrip('.').split('.')
  result = data
  for k in keys:
    if k and result is not None:
      result = result.get(k) if isinstance(result, dict) else None
else:
  # jq -n パターン（JSON構築）
  import re
  # 'null' リテラル
  if expr.strip() == 'null':
    result = None
  elif expr.strip().startswith('{'):
    # --arg で渡された値を使って辞書構築（簡易版）
    result = extra_args
  else:
    result = data

if raw and isinstance(result, str):
  print(result)
elif result is None:
  print('null')
else:
  print(json.dumps(result, ensure_ascii=False))
" "$@"
    }
    export -f jq
  else
    log "エラー: jq も python3 も見つかりません"
    exit 1
  fi
fi

# =============================================================================
# CLI引数パース
# =============================================================================
MIN_FAVES=100
for arg in "$@"; do
  case "$arg" in
    --min-faves)
      shift
      MIN_FAVES="$1"
      ;;
  esac
done

# 引数を直接パースする（=形式にも対応）
for arg in "$@"; do
  case "$arg" in
    --min-faves=*)
      MIN_FAVES="${arg#*=}"
      ;;
  esac
done

log "=========================================="
log "引用RTパイプライン 開始"
log "最小いいね数: ${MIN_FAVES}"
log "=========================================="

# =============================================================================
# STEP 1: バズ投稿の検索
# =============================================================================
log "[STEP 1] バズ投稿を検索中..."

mkdir -p "$PROJECT_DIR/quote-rt/data"

if node "$PROJECT_DIR/quote-rt/x-qrt-finder.js" --min-faves "$MIN_FAVES" >> "$LOG_FILE" 2>&1; then
  FINDER_EXIT=$?
else
  FINDER_EXIT=$?
fi

# 終了コード 2 = 候補なし（正常終了）
if [ "$FINDER_EXIT" -eq 2 ]; then
  log "[STEP 1] 候補が0件のため、引用RTをスキップします ⏭️"
  exit 0
fi

if [ "$FINDER_EXIT" -ne 0 ]; then
  log "[STEP 1] バズ投稿の検索に失敗しました ❌ (exit: $FINDER_EXIT)"
  exit 1
fi

# candidates.json の確認
CANDIDATE_COUNT=$(node -e "
const fs = require('fs');
try {
  const data = JSON.parse(fs.readFileSync('quote-rt/data/candidates.json', 'utf-8'));
  console.log(data.candidates ? data.candidates.length : 0);
} catch(e) { console.log(0); }
" 2>/dev/null || echo "0")

log "[STEP 1] 候補数: ${CANDIDATE_COUNT}件 ✅"

if [ "$CANDIDATE_COUNT" -eq 0 ]; then
  log "[STEP 1] 候補が0件のため、引用RTをスキップします ⏭️"
  exit 0
fi

# =============================================================================
# STEP 2: 引用RTライターで文章生成
# =============================================================================
log "[STEP 2] 引用RTライター実行中..."

if "$CLAUDE_CMD" -p "$(awk '/^---$/{n++; next} n>=2' .claude/agents/qrt_writer.md)" >> "$LOG_FILE" 2>&1; then
  log "[STEP 2] 引用RTライター完了 ✅"
else
  log "[STEP 2] 引用RTライター失敗 ❌"
  exit 1
fi

# result.json の確認
RESULT_FILE="$PROJECT_DIR/quote-rt/data/result.json"

if [ ! -f "$RESULT_FILE" ]; then
  log "[STEP 2] result.json が生成されませんでした ❌"
  exit 1
fi

APPROVED_COUNT=$(node -e "
const fs = require('fs');
try {
  const data = JSON.parse(fs.readFileSync('quote-rt/data/result.json', 'utf-8'));
  console.log(data.approved_count || 0);
} catch(e) { console.log(0); }
" 2>/dev/null || echo "0")

if [ "$APPROVED_COUNT" -eq 0 ]; then
  REJECTION=$(node -e "
const fs = require('fs');
try {
  const data = JSON.parse(fs.readFileSync('quote-rt/data/result.json', 'utf-8'));
  console.log(data.rejection_reason || '理由不明');
} catch(e) { console.log('ファイル読み込みエラー'); }
" 2>/dev/null || echo "")
  log "[STEP 2] 引用RT候補が0件のためスキップします ⚠️ 理由: ${REJECTION}"
  exit 0
fi

log "[STEP 2] 承認済み: ${APPROVED_COUNT}件 ✅"

# =============================================================================
# STEP 3: n8n Webhook 送信（最大3件ループ）
# =============================================================================
log "[STEP 3] Webhook送信中（${APPROVED_COUNT}件 一括）..."

if [ -z "$QUOTE_RT_WEBHOOK_URL" ]; then
  log "[STEP 3] QUOTE_RT_WEBHOOK_URL が設定されていません ❌ (.env を確認してください)"
  exit 1
fi

# results 配列をそのまま data フィールドに詰めて一括送信
# シェル変数経由だと日本語が文字化けするため、ファイル経由で渡す
PAYLOAD_FILE="$PROJECT_DIR/quote-rt/data/payload_tmp.json"

node -e "
const fs = require('fs');
const data = JSON.parse(fs.readFileSync('quote-rt/data/result.json', 'utf-8'));
const payload = {
  data: data.results.map(r => ({
    tweet_id: r.tweet_id,
    tweet_url: r.tweet_url,
    post_text: r.post_text,
    original_author: r.original_author,
    original_likes: r.original_likes
  }))
};
fs.writeFileSync(process.argv[1], JSON.stringify(payload), 'utf-8');
" "$PAYLOAD_FILE" 2>/dev/null

if [ ! -f "$PAYLOAD_FILE" ]; then
  log "[STEP 3] ペイロードの生成に失敗しました ❌"
  exit 1
fi

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "$QUOTE_RT_WEBHOOK_URL" \
  -H "Content-Type: application/json; charset=utf-8" \
  --data-binary "@${PAYLOAD_FILE}")

rm -f "$PAYLOAD_FILE"

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
  log "[STEP 3] n8n Webhook送信完了 ✅ (HTTP $HTTP_CODE) ${APPROVED_COUNT}件を一括送信"
else
  log "[STEP 3] n8n Webhook送信失敗 ❌ (HTTP $HTTP_CODE)"
  exit 1
fi

log "=========================================="
log "引用RTパイプライン 完了 ✅"
log "=========================================="
