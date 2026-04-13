#!/bin/bash
# ========================================
# X記事（Note記事）制作パイプライン（週次実行）
# 1週間ごとにバズ記事を調査・分析し、20テーマ候補から5本を選定・執筆してWebhookで送信する
#
# フロー:
#   1. 先週バズったX記事をリサーチ（7日以内の既存データがあれば再利用）
#   2. リサーチデータを分析
#   3. 分析履歴を蓄積（過去1ヶ月分保持）
#   4. 20テーマ候補を洗い出し、上位5本を選定（article_planner）
#   5. 選定した5本を順番に執筆（article_writer × 5）
#   6. 5本すべてをWebhookでn8nに送信
#   7. ナレッジストック使用カウント更新
#
# 使い方:
#   bash scripts/pipeline_article.sh
#   bash scripts/pipeline_article.sh --skip-research    # リサーチをスキップ
#   bash scripts/pipeline_article.sh --min-faves 500    # いいね数の閾値を変更
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

# 作業ディレクトリ
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

ARTICLE_DIR="$PROJECT_DIR/article"

LOG_DIR="$PROJECT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/article_$(date +%Y%m%d_%H%M%S).log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

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
if files:
    with open(files[0]) as f:
        data = json.load(f)
elif not null_input:
    data = json.load(sys.stdin)
else:
    data = None
parts = filter_expr.lstrip('.').split('.') if filter_expr != '.' else []
result = data
for p in parts:
    if p and isinstance(result, dict):
        result = result.get(p)
if isinstance(result, str):
    print(result if raw else json.dumps(result))
elif result is None:
    print('null')
else:
    print(json.dumps(result, ensure_ascii=False))
" "$@"
    }
    export -f jq
  else
    log "エラー: jq も python3 も見つかりません。"
    exit 1
  fi
fi

# .envファイル読み込み
if [ -f ".env" ]; then
  export $(grep -v '^#' .env | xargs)
else
  log "警告: .envファイルが見つかりません"
fi

# ========================================
# 引数パース
# ========================================
SKIP_RESEARCH=false
MIN_FAVES=1000

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-research)  SKIP_RESEARCH=true; shift ;;
    --min-faves)      MIN_FAVES="$2"; shift 2 ;;
    --help|-h)
      echo "使い方: bash scripts/pipeline_article.sh [--skip-research] [--min-faves 500]"
      exit 0
      ;;
    *)
      log "不明なオプション: $1"
      exit 1
      ;;
  esac
done

log "========== X記事制作パイプライン開始 =========="

# ========================================
# STEP 1: バズ記事リサーチ（先週分）
# 7日以内の既存リサーチがあれば再実行をスキップしてAPIコストを節約
# ========================================

# 既存の report-*.json / analysis-*.md が7日以内にあるかチェック
FRESH_REPORT=""
FRESH_ANALYSIS=""
FRESH_AGE_DAYS=""
if [ -d "$ARTICLE_DIR/output" ]; then
  FRESH_CHECK=$(node -e "
const fs = require('fs');
const dir = '$ARTICLE_DIR/output';
try {
  const files = fs.readdirSync(dir);
  const reports = files.filter(f => /^report-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}\.json$/.test(f));
  const analyses = files.filter(f => /^analysis-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}\.md$/.test(f));
  if (reports.length === 0) { console.log(''); process.exit(0); }
  reports.sort((a, b) => b.localeCompare(a));
  const latestReport = reports[0];
  // 'report-YYYY-MM-DDTHH-MM-SS.json' から日付部分を抽出
  const dateStr = latestReport.slice(7, 17); // YYYY-MM-DD
  const reportDate = new Date(dateStr + 'T00:00:00Z');
  const now = new Date();
  const diffDays = (now.getTime() - reportDate.getTime()) / (1000 * 60 * 60 * 24);
  if (diffDays > 7) { console.log(''); process.exit(0); }
  // analysis は report と同一タイムスタンプを優先、なければ最新を使用
  const reportStem = latestReport.replace(/^report-/, '').replace(/\.json$/, '');
  const matchingAnalysis = analyses.find(a => a === 'analysis-' + reportStem + '.md');
  analyses.sort((a, b) => b.localeCompare(a));
  const latestAnalysis = matchingAnalysis || analyses[0] || '';
  if (!latestAnalysis) { console.log(''); process.exit(0); }
  console.log(latestReport + '|' + latestAnalysis + '|' + diffDays.toFixed(1));
} catch (e) {
  console.log('');
}
" 2>/dev/null)

  if [ -n "$FRESH_CHECK" ]; then
    FRESH_REPORT=$(echo "$FRESH_CHECK" | cut -d'|' -f1)
    FRESH_ANALYSIS=$(echo "$FRESH_CHECK" | cut -d'|' -f2)
    FRESH_AGE_DAYS=$(echo "$FRESH_CHECK" | cut -d'|' -f3)
  fi
fi

if [ "$SKIP_RESEARCH" = true ]; then
  log "[STEP 1] リサーチをスキップ（--skip-research）"
elif [ -n "$FRESH_REPORT" ]; then
  log "[STEP 1] 7日以内の既存リサーチを発見 ✅ リサーチをスキップ（API節約）"
  log "  既存レポート: ${FRESH_REPORT} (${FRESH_AGE_DAYS}日前)"
  log "  既存分析: ${FRESH_ANALYSIS}"
else
  log "[STEP 1] バズ記事リサーチ開始..."

  # 先週の日付範囲を算出
  SINCE_DATE=$(date -d "7 days ago" +%Y-%m-%d 2>/dev/null || date -v-7d +%Y-%m-%d 2>/dev/null)
  UNTIL_DATE=$(date +%Y-%m-%d)

  log "  期間: ${SINCE_DATE} 〜 ${UNTIL_DATE}"
  log "  いいね閾値: ${MIN_FAVES}以上"
  log "  言語: 全言語（日本語+海外）"

  if bash scripts/pipeline_article_research.sh \
    --min-faves "$MIN_FAVES" \
    --since "$SINCE_DATE" \
    --until "$UNTIL_DATE" \
    --lang all \
    --analyze \
    --verbose >> "$LOG_FILE" 2>&1; then
    log "[STEP 1] リサーチ＆分析完了 ✅"
  else
    log "[STEP 1] リサーチ失敗 ❌ 既存データで続行します"
  fi
fi

# ========================================
# STEP 2: 分析履歴の蓄積（過去1ヶ月分保持）
# ========================================
log "[STEP 2] 分析履歴を蓄積..."

HISTORY_FILE="data/article_analysis_history.json"
TODAY=$(date +%Y-%m-%d)
ONE_MONTH_AGO=$(date -d "30 days ago" +%Y-%m-%d 2>/dev/null || date -v-30d +%Y-%m-%d 2>/dev/null)

# 最新のanalysis-*.mdを検出
LATEST_ANALYSIS=$(ls -t "$ARTICLE_DIR"/output/analysis-*.md 2>/dev/null | head -1)

if [ -n "$LATEST_ANALYSIS" ]; then
  log "  最新分析: $LATEST_ANALYSIS"

  # 分析ファイルの内容を要約として保存
  ANALYSIS_CONTENT=$(cat "$LATEST_ANALYSIS")

  # 履歴ファイルの初期化（存在しなければ）
  if [ ! -f "$HISTORY_FILE" ]; then
    echo '{"entries": []}' > "$HISTORY_FILE"
  fi

  # 新しいエントリを追加し、1ヶ月以上古いエントリを削除
  node -e "
const fs = require('fs');
const history = JSON.parse(fs.readFileSync('$HISTORY_FILE', 'utf-8'));
const today = '$TODAY';
const oneMonthAgo = '$ONE_MONTH_AGO';
const analysisFile = '$(basename "$LATEST_ANALYSIS")';

// 同日のエントリが既にあれば上書き
history.entries = history.entries.filter(e => e.date !== today);

// 新しいエントリを追加
history.entries.push({
  date: today,
  analysis_file: analysisFile,
  analysis_path: '$LATEST_ANALYSIS'
});

// 1ヶ月以上古いエントリを削除
history.entries = history.entries.filter(e => e.date >= oneMonthAgo);

// 日付順にソート（新しい順）
history.entries.sort((a, b) => b.date.localeCompare(a.date));

history.last_updated = new Date().toISOString();
history.total_entries = history.entries.length;

fs.writeFileSync('$HISTORY_FILE', JSON.stringify(history, null, 2));
console.log('履歴更新完了: ' + history.entries.length + '件保持');
" >> "$LOG_FILE" 2>&1

  log "[STEP 2] 分析履歴蓄積完了 ✅"
else
  log "[STEP 2] 分析ファイルが見つかりません ⚠️ 既存の履歴で続行"
fi

# ========================================
# STEP 2.5: バズインサイト抽出（TOP50 BM率分析 → data/buzz_insights.json）
# ========================================
log "[STEP 2.5] バズインサイト抽出（いいね×BM率 分析）..."

if node scripts/extract_buzz_insights.js >> "$LOG_FILE" 2>&1; then
  log "[STEP 2.5] buzz_insights.json 更新完了 ✅"
else
  log "[STEP 2.5] バズインサイト抽出失敗 ⚠️ 既存データで続行"
fi

# ========================================
# STEP 3: 20テーマ候補立案＆上位5本選定（article_planner）
# ========================================
log "[STEP 3] 20テーマ候補立案＆上位5本選定開始..."

# 古い candidates を念のためバックアップ
if [ -f "data/article_theme_candidates.json" ]; then
  cp "data/article_theme_candidates.json" "data/article_theme_candidates.json.bak" 2>/dev/null || true
fi

if "$CLAUDE_CMD" -p "$(awk '/^---$/{n++; next} n>=2' .claude/agents/article_planner.md)" >> "$LOG_FILE" 2>&1; then
  if [ -f "data/article_theme_candidates.json" ]; then
    CANDIDATE_COUNT=$(jq -r '.candidates | length' data/article_theme_candidates.json)
    SELECTED_COUNT=$(jq -r '.selected | length' data/article_theme_candidates.json)
    log "[STEP 3] テーマ立案完了 ✅ 候補: ${CANDIDATE_COUNT}件 / 選定: ${SELECTED_COUNT}件"

    if [ "$SELECTED_COUNT" -lt 1 ]; then
      log "[STEP 3] selected 配列が空です ❌"
      exit 1
    fi
  else
    log "[STEP 3] article_theme_candidates.json が生成されませんでした ❌"
    exit 1
  fi
else
  log "[STEP 3] テーマ立案失敗 ❌"
  exit 1
fi

# ========================================
# STEP 3.5: 選定テーマを分析履歴に記録（翌週の重複回避用）
# ========================================
log "[STEP 3.5] 選定テーマを分析履歴に記録..."

node -e "
const fs = require('fs');
const candidates = JSON.parse(fs.readFileSync('data/article_theme_candidates.json', 'utf-8'));
const historyFile = '$HISTORY_FILE';
const history = JSON.parse(fs.readFileSync(historyFile, 'utf-8'));
const today = candidates.date || new Date().toISOString().slice(0, 10);

const selectedThemes = (candidates.selected || []).map(s => ({
  rank: s.rank,
  title: s.theme || s.title_draft || '',
  angle: s.angle || '',
  target_reader: s.target_reader || ''
}));

// STEP 2 で作成済みの今日のエントリに追記、なければ新規追加
const entry = history.entries.find(e => e.date === today);
if (entry) {
  entry.selected_themes = selectedThemes;
} else {
  history.entries.push({ date: today, selected_themes: selectedThemes });
}

history.last_updated = new Date().toISOString();
fs.writeFileSync(historyFile, JSON.stringify(history, null, 2));
console.log('selected_themes 保存完了: ' + selectedThemes.length + '件');
" >> "$LOG_FILE" 2>&1

log "[STEP 3.5] 選定テーマ記録完了 ✅"

# ========================================
# STEP 4 & 5: 選定した5本を順番に執筆＆Webhook送信
# ========================================
log "[STEP 4-5] 5本の記事執筆＆送信を開始..."

# ドラフト保存先ディレクトリ
DRAFTS_DIR="data/article_drafts"
mkdir -p "$DRAFTS_DIR"

SUCCESS_COUNT=0
FAIL_COUNT=0
TOTAL_SELECTED=$(jq -r '.selected | length' data/article_theme_candidates.json)

for ((i=0; i<TOTAL_SELECTED; i++)); do
  RANK=$((i+1))
  log "----- 記事 ${RANK}/${TOTAL_SELECTED} -----"

  # selected[i] を data/article_plan.json に展開（writer が読み込む単一プラン）
  node -e "
const fs = require('fs');
const candidates = JSON.parse(fs.readFileSync('data/article_theme_candidates.json', 'utf-8'));
const plan = candidates.selected[${i}];
if (!plan) {
  console.error('selected[${i}] が存在しません');
  process.exit(1);
}
// date フィールドを付与
plan.date = candidates.date || new Date().toISOString().slice(0, 10);
fs.writeFileSync('data/article_plan.json', JSON.stringify(plan, null, 2));
console.log('article_plan.json 更新: rank=' + (plan.rank || ${RANK}) + ' theme=' + (plan.theme || ''));
" >> "$LOG_FILE" 2>&1

  if [ ! -f "data/article_plan.json" ]; then
    log "  [STEP 4] article_plan.json 生成失敗 ❌ スキップ"
    FAIL_COUNT=$((FAIL_COUNT+1))
    continue
  fi

  PLAN_THEME=$(jq -r '.theme // "不明"' data/article_plan.json)
  log "  [STEP 4] 執筆開始: ${PLAN_THEME}"

  # 古い draft を削除（writer が新規作成するのを保証）
  rm -f data/article_draft.json

  if "$CLAUDE_CMD" -p "$(awk '/^---$/{n++; next} n>=2' .claude/agents/article_writer.md)" >> "$LOG_FILE" 2>&1; then
    if [ -f "data/article_draft.json" ]; then
      CHAR_COUNT=$(jq -r '.char_count // 0' data/article_draft.json)
      ARTICLE_TITLE=$(jq -r '.title // "無題"' data/article_draft.json)
      log "  [STEP 4] 執筆完了 ✅ ${ARTICLE_TITLE} (${CHAR_COUNT}文字)"

      # ランク別ドラフトとして保存
      DRAFT_FILE="${DRAFTS_DIR}/article_draft_${RANK}.json"
      cp "data/article_draft.json" "$DRAFT_FILE"
      log "  [STEP 4] 保存: ${DRAFT_FILE}"
    else
      log "  [STEP 4] article_draft.json が生成されませんでした ❌ スキップ"
      FAIL_COUNT=$((FAIL_COUNT+1))
      continue
    fi
  else
    log "  [STEP 4] 執筆失敗 ❌ スキップ"
    FAIL_COUNT=$((FAIL_COUNT+1))
    continue
  fi

  # Webhook送信
  if [ -z "$ARTICLE_WEBHOOK_URL" ]; then
    log "  [STEP 5] ARTICLE_WEBHOOK_URL 未設定 ⚠️ 送信スキップ"
    SUCCESS_COUNT=$((SUCCESS_COUNT+1))
  else
    WEBHOOK_PAYLOAD=$(node -e "
const fs = require('fs');
const draft = JSON.parse(fs.readFileSync('data/article_draft.json', 'utf-8'));
const payload = {
  title: draft.title || '',
  content: draft.article_content || '',
  subtitle: draft.subtitle || '',
  meta_description: draft.meta_description || '',
  char_count: draft.char_count || 0,
  date: draft.date || '',
  rank: ${RANK},
  total: ${TOTAL_SELECTED}
};
process.stdout.write(JSON.stringify(payload));
")

    HTTP_CODE=$(echo "$WEBHOOK_PAYLOAD" | curl -s -o /dev/null -w "%{http_code}" \
      -X POST "$ARTICLE_WEBHOOK_URL" \
      -H "Content-Type: application/json; charset=utf-8" \
      --data-binary @-)

    if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
      log "  [STEP 5] Webhook送信完了 ✅ (HTTP $HTTP_CODE)"
      SUCCESS_COUNT=$((SUCCESS_COUNT+1))
    else
      log "  [STEP 5] Webhook送信失敗 ❌ (HTTP $HTTP_CODE) ドラフトは ${DRAFT_FILE} に保存済み"
      FAIL_COUNT=$((FAIL_COUNT+1))
    fi
  fi
done

log "[STEP 4-5] 全記事処理完了: 成功 ${SUCCESS_COUNT}件 / 失敗 ${FAIL_COUNT}件"

# ========================================
# STEP 6: ナレッジストック使用カウント更新（選定5本分すべて）
# ========================================
if [ -f "data/article_theme_candidates.json" ] && [ -f "data/knowledge_stock.json" ]; then
  KNOWLEDGE_IDS=$(jq -r '.selected[].knowledge_used[]?.id // empty' data/article_theme_candidates.json 2>/dev/null | sort -u || echo "")

  if [ -n "$KNOWLEDGE_IDS" ]; then
    log "[STEP 6] ナレッジストック使用カウント更新..."

    echo "$KNOWLEDGE_IDS" | while read -r KID; do
      [ -z "$KID" ] && continue
      node -e "
const fs = require('fs');
const data = JSON.parse(fs.readFileSync('data/knowledge_stock.json', 'utf-8'));
const today = '${TODAY}';
const item = data.items.find(i => i.id === '${KID}');
if (item) {
  item.usage_count = (item.usage_count || 0) + 1;
  item.last_used_at = today;
  if (item.usage_count >= (item.max_usage || 5)) {
    item.status = 'retired';
  }
  fs.writeFileSync('data/knowledge_stock.json', JSON.stringify(data, null, 2));
  console.log('ナレッジ更新: ' + '${KID}' + ' (usage: ' + item.usage_count + ')');
}
" >> "$LOG_FILE" 2>&1
    done

    log "[STEP 6] ナレッジストック更新完了 ✅"
  fi
fi

# ========================================
# 完了
# ========================================
log "========== X記事制作パイプライン完了 =========="
log "  候補テーマ数: ${CANDIDATE_COUNT:-不明}"
log "  選定テーマ数: ${TOTAL_SELECTED:-不明}"
log "  送信成功: ${SUCCESS_COUNT}件 / 失敗: ${FAIL_COUNT}件"
log "  候補ファイル: data/article_theme_candidates.json"
log "  ドラフト保存先: ${DRAFTS_DIR}/article_draft_{1..${TOTAL_SELECTED}}.json"
log "  ログ: $LOG_FILE"
