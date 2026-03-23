#!/bin/bash
# ========================================
# X投稿分析パイプライン（n8nから呼び出し用）
# 使い方: ./pipeline_analysis.sh <分析データJSONのファイルパス>
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
[ -z "$CLAUDE_CMD" ] && echo "エラー: claude コマンドが見つかりません。" && exit 1

# 引数チェック
if [ -z "$1" ]; then
  echo "エラー: 分析対象のデータファイル（JSON）のパスを指定してください。"
  echo "使用例: ./pipeline_analysis.sh /tmp/metrics_20260320.json"
  exit 1
fi

METRICS_FILE="$1"

if [ ! -f "$METRICS_FILE" ]; then
  echo "エラー: 指定されたファイルが見つかりません: $METRICS_FILE"
  exit 1
fi

# 作業ディレクトリを x-automation 直下に移動
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

LOG_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/pipeline_analysis_$(date +%Y%m%d_%H%M%S).log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "========== 分析パイプライン開始 =========="
log "入力データ: $METRICS_FILE"

# データを input_metrics.json として一時コピー（アナリストが読み込みやすいように）
cp "$METRICS_FILE" "$PROJECT_DIR/data/input_metrics.json"

# アナリストエージェントの実行
log "アナリスト（データ分析・戦略更新）実行中..."

if "$CLAUDE_CMD" -p "$(cat .claude/agents/analyst.md)" >> "$LOG_FILE" 2>&1; then
  log "アナリスト完了 ✅"
  log "分析結果が data/analytics.json と data/strategy.md に反映されました。"
  
  # コンテキスト膨張を防ぐため、posts配列を最大30件にし、古いものはアーカイブに退避
  if command -v jq &> /dev/null; then
    LEN=$(jq '.posts | length' data/analytics.json 2>/dev/null || echo "0")
    if [ "$LEN" -gt 30 ]; then
      jq '.posts[:-30]' data/analytics.json > data/temp_old_posts.json
      jq '.posts |= .[-30:]' data/analytics.json > data/temp_analytics.json && mv data/temp_analytics.json data/analytics.json
      
      if [ ! -f data/analytics_archive.json ]; then
        echo "[]" > data/analytics_archive.json
      fi
      
      jq '. + input' data/analytics_archive.json data/temp_old_posts.json > data/temp_arc.json && mv data/temp_arc.json data/analytics_archive.json
      rm -f data/temp_old_posts.json
      
      log "過去の分析データを analytics_archive.json に退避しました（直近30件保持）"
    fi
  fi
else
  log "アナリスト失敗 ❌"
  exit 1
fi

log "========== 分析パイプライン終了 =========="
