#!/bin/bash
# =============================================================================
# X記事リサーチ & 分析 シェルスクリプト
# =============================================================================
# 使い方:
#   ./research.sh                          # デフォルト（いいね1000以上、直近1ヶ月、日本語）
#   ./research.sh --min-faves 500          # いいね500以上
#   ./research.sh --analyze                # リサーチ後に自動で分析も実行
#   ./research.sh --analyze-only           # 分析のみ（既存データを使用）
#   ./research.sh --category AI            # 分析時にカテゴリ指定
#   ./research.sh --help                   # ヘルプ表示
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SHARED_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)/shared"
ARTICLE_DIR="${PROJECT_DIR}/article"
ENV_FILE="${PROJECT_DIR}/.env"

# 色付きログ
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${CYAN}[STEP]${NC} $1"; }

# =============================================================================
# ヘルプ
# =============================================================================
show_help() {
  cat <<'HELP'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  X記事リサーチ & 分析ツール
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

使い方:
  ./research.sh [オプション]

リサーチオプション:
  --min-faves <数値>       最小いいね数 (デフォルト: 1000)
  --min-retweets <数値>    最小RT数 (デフォルト: 0)
  --since <YYYY-MM-DD>     開始日 (デフォルト: 1ヶ月前)
  --until <YYYY-MM-DD>     終了日 (デフォルト: 今日)
  --lang <ja|all>          言語フィルタ (デフォルト: ja)
  --theme <keywords>       テーマキーワード (カンマ区切り、例: "AI,Claude,n8n")

分析オプション:
  --analyze                リサーチ後に分析も実行
  --analyze-only           分析のみ実行（既存データを使用）
  --category <キーワード>  カテゴリでフィルタ (例: AI, プログラミング)
  --top <数値>             分析対象の件数 (デフォルト: 50)

その他:
  --no-cache               キャッシュを無効化
  --from-cache             キャッシュ済みデータのみで処理 (API不要)
  --verbose                詳細ログ
  --help                   このヘルプを表示

実行例:
  ./research.sh                                    # 基本実行
  ./research.sh --min-faves 500 --analyze          # いいね500以上 + 分析
  ./research.sh --min-faves 5000 --lang all        # トップ記事、全言語
  ./research.sh --analyze-only --category AI       # AI記事だけ分析
  ./research.sh --theme "AI,Claude,n8n" --analyze  # テーマ指定 + 分析
  ./research.sh --since 2026-01-01 --until 2026-04-01 --analyze

HELP
}

# =============================================================================
# .envファイル読み込み
# =============================================================================
load_env() {
  if [[ -f "$ENV_FILE" ]]; then
    log_info ".envファイルを読み込み中..."
    while IFS= read -r line || [[ -n "$line" ]]; do
      # 前後の空白を除去
      line="${line#"${line%%[![:space:]]*}"}"
      line="${line%"${line##*[![:space:]]}"}"
      # コメント行と空行をスキップ
      [[ -z "$line" || "$line" == \#* ]] && continue
      # key=value を分割（最初の = で分割、値に = が含まれてもOK）
      local key="${line%%=*}"
      local value="${line#*=}"
      # クォートを除去
      value="${value%\"}"
      value="${value#\"}"
      value="${value%\'}"
      value="${value#\'}"
      export "$key=$value"
    done < "$ENV_FILE"
  fi
}

# =============================================================================
# APIキーチェック
# =============================================================================
check_api_key() {
  if [[ -z "${SOCIALDATA_API_KEY:-}" ]]; then
    log_error "SOCIALDATA_API_KEY が設定されていません。"
    echo ""
    echo "設定方法:"
    echo "  1. .envファイルに記載:  echo 'SOCIALDATA_API_KEY=your_key' > ${ENV_FILE}"
    echo "  2. 環境変数で設定:      export SOCIALDATA_API_KEY=your_key"
    echo ""
    echo "APIキーは https://socialdata.tools で取得できます。"
    exit 1
  fi
  log_info "APIキー: ...${SOCIALDATA_API_KEY: -8} (末尾8文字)"
}

# =============================================================================
# Node.jsチェック
# =============================================================================
check_node() {
  if ! command -v node &> /dev/null; then
    log_error "Node.jsがインストールされていません。"
    echo "https://nodejs.org からインストールしてください。"
    exit 1
  fi
  local node_version
  node_version=$(node --version)
  log_info "Node.js: ${node_version}"
}

# =============================================================================
# 最新のJSONレポートを検索
# =============================================================================
find_latest_json() {
  local output_dir="${ARTICLE_DIR}/output"
  if [[ ! -d "$output_dir" ]]; then
    echo ""
    return
  fi
  # 最新のreport-*.jsonを返す
  local latest
  latest=$(ls -t "${output_dir}"/report-*.json 2>/dev/null | head -1)
  echo "$latest"
}

# =============================================================================
# メイン処理
# =============================================================================
main() {
  # デフォルト値
  local min_faves=1000
  local min_retweets=0
  local since=""
  local until_date=""
  local lang="ja"
  local theme=""
  local do_analyze=false
  local analyze_only=false
  local category=""
  local top=50
  local no_cache=false
  local from_cache=false
  local verbose=false

  # 引数パース
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --min-faves)     min_faves="$2"; shift 2 ;;
      --min-retweets)  min_retweets="$2"; shift 2 ;;
      --since)         since="$2"; shift 2 ;;
      --until)         until_date="$2"; shift 2 ;;
      --lang)          lang="$2"; shift 2 ;;
      --theme)         theme="$2"; shift 2 ;;
      --analyze)       do_analyze=true; shift ;;
      --analyze-only)  analyze_only=true; shift ;;
      --category)      category="$2"; shift 2 ;;
      --top)           top="$2"; shift 2 ;;
      --no-cache)      no_cache=true; shift ;;
      --from-cache)    from_cache=true; shift ;;
      --verbose)       verbose=true; shift ;;
      --help|-h)       show_help; exit 0 ;;
      *)
        log_error "不明なオプション: $1"
        echo "  ./research.sh --help でヘルプを表示"
        exit 1
        ;;
    esac
  done

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  X記事リサーチ & 分析ツール"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  # 環境チェック
  load_env
  check_node

  # 分析のみ・キャッシュモードでなければAPIキーを確認
  if [[ "$analyze_only" == false && "$from_cache" == false ]]; then
    check_api_key
  fi

  echo ""

  # =========================================================================
  # リサーチ実行
  # =========================================================================
  local json_report=""

  if [[ "$analyze_only" == false ]]; then
    log_step "リサーチを開始します..."
    echo ""
    echo "  いいね数: ${min_faves}以上"
    echo "  RT数:     ${min_retweets}以上"
    echo "  期間:     ${since:-直近1ヶ月} 〜 ${until_date:-今日}"
    echo "  言語:     ${lang}"
    [[ -n "$theme" ]] && echo "  テーマ:   ${theme}"
    echo ""

    # コマンド組み立て
    local cmd="node \"${SHARED_DIR}/article/x-article-researcher.js\""
    cmd+=" --min-faves ${min_faves}"
    cmd+=" --min-retweets ${min_retweets}"
    cmd+=" --lang ${lang}"

    [[ -n "$theme" ]]      && cmd+=" --theme \"${theme}\""
    [[ -n "$since" ]]      && cmd+=" --since ${since}"
    [[ -n "$until_date" ]] && cmd+=" --until ${until_date}"
    [[ "$no_cache" == true ]]    && cmd+=" --no-cache"
    [[ "$from_cache" == true ]] && cmd+=" --from-cache"
    [[ "$verbose" == true ]]    && cmd+=" --verbose"

    # 実行
    local start_time
    start_time=$(date +%s)

    eval "$cmd"
    local exit_code=$?

    local end_time
    end_time=$(date +%s)
    local elapsed=$((end_time - start_time))

    echo ""
    if [[ $exit_code -eq 0 ]]; then
      log_info "リサーチ完了 (${elapsed}秒)"
    else
      log_error "リサーチ失敗 (exit code: ${exit_code})"
      exit $exit_code
    fi

    # 最新のJSONレポートを取得
    json_report=$(find_latest_json)
  fi

  # =========================================================================
  # 分析実行
  # =========================================================================
  if [[ "$do_analyze" == true || "$analyze_only" == true ]]; then
    echo ""
    log_step "分析を開始します..."

    # JSONレポートの特定
    if [[ -z "$json_report" ]]; then
      json_report=$(find_latest_json)
    fi

    if [[ -z "$json_report" ]]; then
      log_error "分析対象のJSONレポートが見つかりません。先にリサーチを実行してください。"
      exit 1
    fi

    log_info "分析対象: ${json_report}"

    # コマンド組み立て
    local analyze_cmd="node \"${SHARED_DIR}/article/x-article-analyzer.js\" \"${json_report}\""
    analyze_cmd+=" --top ${top}"

    [[ -n "$category" ]] && analyze_cmd+=" --category \"${category}\""

    # 実行
    eval "$analyze_cmd"
    local analyze_exit=$?

    echo ""
    if [[ $analyze_exit -eq 0 ]]; then
      log_info "分析完了"
    else
      log_error "分析失敗 (exit code: ${analyze_exit})"
      exit $analyze_exit
    fi
  fi

  # =========================================================================
  # 完了メッセージ
  # =========================================================================
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log_info "全処理完了"
  echo ""
  echo "  出力ディレクトリ: ${ARTICLE_DIR}/output/"
  if [[ -d "${ARTICLE_DIR}/output" ]]; then
    echo ""
    echo "  生成ファイル:"
    ls -1t "${ARTICLE_DIR}/output/" 2>/dev/null | head -5 | while read -r f; do
      echo "    - output/${f}"
    done
  fi
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

main "$@"
