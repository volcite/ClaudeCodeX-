#!/bin/bash
# ============================================================
# start-claude-remote.sh
#
# Claude Code の remote-control を起動し、
# リモート接続用URLを返却するスクリプト
#
# 使い方:
#   ./start-claude-remote.sh
#   ./start-claude-remote.sh --name "My Project"
#   ./start-claude-remote.sh --name "My Project" --timeout 45 --capacity 8
#
# 出力（JSON）:
#   { "status": "success", "url": "https://..." }
# ============================================================

set -e

# ─── 非インタラクティブSSH環境でも PATH を通す ───
source ~/.bashrc 2>/dev/null || source ~/.bash_profile 2>/dev/null || true
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

# ─── デフォルト設定 ───
SESSION_NAME=""
TIMEOUT=30
CAPACITY=32
VERBOSE=false
USE_TMUX=true
TMUX_SESSION_PREFIX="claude-rc"

# ─── 引数パース ───
while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--name)     SESSION_NAME="$2";  shift 2 ;;
    -t|--timeout)  TIMEOUT="$2";       shift 2 ;;
    -c|--capacity) CAPACITY="$2";      shift 2 ;;
    -v|--verbose)  VERBOSE=true;       shift   ;;
    --no-tmux)     USE_TMUX=false;     shift   ;;
    --help)
      cat << 'HELP'
Usage: start-claude-remote.sh [OPTIONS]

Options:
  -n, --name NAME       セッション名（省略時は自動生成）
  -t, --timeout SEC     URL取得の待機秒数（デフォルト: 30）
  -c, --capacity N      最大同時セッション数（デフォルト: 32）
  -v, --verbose         詳細ログ出力
  --no-tmux             tmuxを使わずnohupで起動
  --help                このヘルプを表示
HELP
      exit 0
      ;;
    *) echo "{\"status\":\"error\",\"message\":\"Unknown option: $1\"}" >&2; exit 1 ;;
  esac
done

# ─── セッション名の自動生成 ───
if [ -z "$SESSION_NAME" ]; then
  SESSION_NAME="rc-$(date +%s)"
fi

TMUX_NAME="${TMUX_SESSION_PREFIX}-${SESSION_NAME}"
LOG_FILE="/tmp/claude-${TMUX_NAME}-$$.log"

# ─── ユーティリティ関数 ───
json_success() {
  cat << EOF
$1
EOF
}

json_error() {
  cat << EOF
{
  "status": "error",
  "message": "$1",
  "troubleshooting": [
    "claude --version でCLIの存在を確認",
    "claude auth status で認証状態を確認",
    "claude auth login で再認証"
  ]
}
EOF
}

log() {
  if [ "$VERBOSE" = true ]; then
    echo "[$(date +%H:%M:%S)] $1" >&2
  fi
}

# ─── Step 1: claude コマンドの場所を特定 ───
log "Checking claude CLI..."

CLAUDE_CMD=$(which claude 2>/dev/null)
if [ -z "$CLAUDE_CMD" ]; then
  # NVM 経由でインストールされた claude を探す
  NVM_CLAUDE=$(ls "$HOME/.nvm/versions/node/"*/bin/claude 2>/dev/null | tail -1)
  for candidate in \
    "$NVM_CLAUDE" \
    "$HOME/.local/bin/claude" \
    "$HOME/.npm-global/bin/claude" \
    "/usr/local/bin/claude" \
    "/usr/bin/claude"; do
    [ -n "$candidate" ] && [ -x "$candidate" ] && CLAUDE_CMD="$candidate" && break
  done
fi

if [ -z "$CLAUDE_CMD" ]; then
  json_error "claude コマンドが見つかりません。インストール・PATHを確認してください。"
  exit 1
fi

log "Found claude at: $CLAUDE_CMD"

# ─── Step 2: Claude Code のツール権限を事前許可 ───
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
if [ ! -f "$CLAUDE_SETTINGS" ]; then
  log "Creating Claude settings with tool permissions..."
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

# ─── Step 3: 既存セッションの確認 ───
if [ "$USE_TMUX" = true ] && command -v tmux &> /dev/null; then
  if tmux has-session -t "$TMUX_NAME" 2>/dev/null; then
    log "Existing tmux session found: $TMUX_NAME"

    # 既存セッションのログからURLを取得
    EXISTING_LOG=$(find /tmp -name "claude-${TMUX_NAME}-*" -type f 2>/dev/null | head -1)
    if [ -n "$EXISTING_LOG" ]; then
      EXISTING_URL=$(grep -oE 'https?://[^ ]+' "$EXISTING_LOG" 2>/dev/null | head -1)
      if [ -n "$EXISTING_URL" ]; then
        LOG_FILE="$EXISTING_LOG"
        json_success "$EXISTING_URL"
        exit 0
      fi
    fi

    # URLが取れない場合は既存セッションを終了して再起動
    log "Could not retrieve URL from existing session. Restarting..."
    tmux kill-session -t "$TMUX_NAME" 2>/dev/null
    sleep 1
  fi
fi

# ─── Step 4: claude remote-control の起動 ───
log "Starting claude remote-control..."

# コマンド構築
CLAUDE_ARGS="remote-control --name \"${SESSION_NAME}\" --capacity ${CAPACITY}"
if [ "$VERBOSE" = true ]; then
  CLAUDE_ARGS="${CLAUDE_ARGS} --verbose"
fi

if [ "$USE_TMUX" = true ] && command -v tmux &> /dev/null; then
  # === tmux モード（推奨: SSH切断しても生存） ===
  log "Using tmux mode"

  # NVM環境をtmux内でも引き継ぐ
  tmux new-session -d -s "$TMUX_NAME" \
    "exec bash -c 'source ~/.bashrc 2>/dev/null || true; export NVM_DIR=\"\${NVM_DIR:-\$HOME/.nvm}\"; [ -s \"\$NVM_DIR/nvm.sh\" ] && source \"\$NVM_DIR/nvm.sh\"; ${CLAUDE_CMD} ${CLAUDE_ARGS} 2>&1 | tee ${LOG_FILE}'"

else
  # === nohup モード（tmux未インストール時のフォールバック） ===
  log "Using nohup mode (tmux not available)"
  USE_TMUX=false

  nohup bash -c "source ~/.bashrc 2>/dev/null || true; export NVM_DIR=\"\${NVM_DIR:-\$HOME/.nvm}\"; [ -s \"\$NVM_DIR/nvm.sh\" ] && source \"\$NVM_DIR/nvm.sh\"; ${CLAUDE_CMD} ${CLAUDE_ARGS}" > "$LOG_FILE" 2>&1 &
  CLAUDE_PID=$!
  disown "$CLAUDE_PID" 2>/dev/null
  log "Started with PID: $CLAUDE_PID"
fi

# ─── Step 5: URLの出現を待機 ───
log "Waiting for URL (timeout: ${TIMEOUT}s)..."

for i in $(seq 1 "$TIMEOUT"); do
  sleep 1

  if [ -f "$LOG_FILE" ]; then
    # URLを抽出
    URL=$(grep -oE 'https?://[^ ]+' "$LOG_FILE" 2>/dev/null | head -1)
    if [ -n "$URL" ]; then
      log "URL found after ${i}s"
      json_success "$URL"
      exit 0
    fi

    # エラー検出
    if grep -qiE 'error|unauthorized|not authenticated|ENOENT|command not found' "$LOG_FILE" 2>/dev/null; then
      ERROR_MSG=$(grep -iE 'error|unauthorized|not authenticated|ENOENT' "$LOG_FILE" | head -1 | tr -d '"')
      log "Error detected: $ERROR_MSG"

      # クリーンアップ
      if [ "$USE_TMUX" = true ]; then
        tmux kill-session -t "$TMUX_NAME" 2>/dev/null
      elif [ -n "${CLAUDE_PID:-}" ]; then
        kill "$CLAUDE_PID" 2>/dev/null
      fi

      json_error "Claude起動エラー: ${ERROR_MSG}"
      exit 1
    fi
  fi

  log "Waiting... (${i}/${TIMEOUT})"
done

# ─── タイムアウト ───
log "Timeout reached"

# ログの末尾を取得（デバッグ用）
LAST_OUTPUT=""
if [ -f "$LOG_FILE" ]; then
  LAST_OUTPUT=$(tail -5 "$LOG_FILE" 2>/dev/null | tr '\n' ' ' | tr -d '"')
fi

# クリーンアップ
if [ "$USE_TMUX" = true ]; then
  tmux kill-session -t "$TMUX_NAME" 2>/dev/null
elif [ -n "${CLAUDE_PID:-}" ]; then
  kill "$CLAUDE_PID" 2>/dev/null
fi

json_error "タイムアウト（${TIMEOUT}秒）: URLが生成されませんでした。ログ: ${LAST_OUTPUT}"
exit 1
