#!/bin/bash
# ========================================
# プレゼント企画: 調査 → 企画設計 → Note記事執筆 → Note公開 パイプライン
# Phase 1: Xトレンド・Note/Brain・最新情報の調査
# Phase 2: テーマ選定 & 企画設計
# Phase 3: Note記事の執筆
# Phase 4: PlaywrightでNote自動公開
# Phase 5: 引用RT特典コンテンツの執筆
# Phase 6: X投稿5本の執筆
# Phase 7: Webhook予約送信（n8n経由で予約投稿）
# 出力: giveaway_research/plan/note_draft/note_result/bonus_draft/x_posts.json
# ========================================
set -euo pipefail

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
  echo "エラー: claude コマンドが見つかりません。"
  exit 1
fi

cd "$(dirname "$0")/../.."
echo "=========================================="
echo "プレゼント企画: 調査 & 企画設計パイプライン開始"
echo "日時: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================="

# ──────────────────────────────────────────
# Phase 1: 調査（Step 1-3）
# ──────────────────────────────────────────

# 通常リサーチャーのキャッシュ確認
if [ -f "post/data/trends.json" ]; then
  TRENDS_DATE=$(python3 -c "import json; d=json.load(open('post/data/trends.json')); print(d.get('date',''))" 2>/dev/null || echo "")
  TODAY=$(date +%Y-%m-%d)
  if [ "$TRENDS_DATE" = "$TODAY" ]; then
    echo "[Cache] 本日の trends.json を検出（${TRENDS_DATE}）→ Giveaway Researcher がジャンル・競合データを再利用します"
  else
    echo "[Cache] trends.json は古いデータ（${TRENDS_DATE}）→ 全クエリ実行します"
  fi
else
  echo "[Cache] trends.json なし → 全クエリ実行します"
fi

RESEARCH_PROMPT=$(awk '/^---$/{n++; next} n>=2' .claude/agents/giveaway_researcher.md)

echo ""
echo "[Phase 1] Giveaway Researcher 起動（Step 1-3: トレンド調査・Note/Brain調査・最新情報リサーチ）..."
echo ""
"$CLAUDE_CMD" -p --model claude-sonnet-4-6 --max-tokens 16000 "$RESEARCH_PROMPT"

# 調査出力の検証
if [ ! -f "giveaway/data/giveaway_research.json" ]; then
  echo "エラー: giveaway/data/giveaway_research.json が生成されませんでした。"
  exit 1
fi

THEME_COUNT=$(python3 -c "import json; d=json.load(open('giveaway/data/giveaway_research.json')); print(len(d.get('theme_candidates', [])))" 2>/dev/null || echo '0')
echo ""
echo "=========================================="
echo "Phase 1 完了: giveaway/data/giveaway_research.json 生成済み"
echo "テーマ候補数: ${THEME_COUNT}"
echo "=========================================="

if [ "$THEME_COUNT" = "0" ]; then
  echo "エラー: テーマ候補が0件です。調査結果を確認してください。"
  exit 1
fi

# ──────────────────────────────────────────
# Phase 2: テーマ選定 & 企画設計（Step 4）
# ──────────────────────────────────────────
PLANNER_PROMPT=$(awk '/^---$/{n++; next} n>=2' .claude/agents/giveaway_planner.md)

echo ""
echo "[Phase 2] Giveaway Planner 起動（Step 4: テーマ選定 & 企画設計）..."
echo ""
"$CLAUDE_CMD" -p --model claude-sonnet-4-6 --max-tokens 16000 "$PLANNER_PROMPT"

# 企画出力の検証
if [ ! -f "giveaway/data/giveaway_plan.json" ]; then
  echo "エラー: giveaway/data/giveaway_plan.json が生成されませんでした。"
  exit 1
fi

echo ""
echo "=========================================="
echo "Phase 2 完了: giveaway/data/giveaway_plan.json 生成済み"
echo ""
python3 -c "
import json
d = json.load(open('giveaway/data/giveaway_plan.json'))
print(f\"テーマ: {d.get('theme', '不明')}\")
print(f\"Note記事: {d.get('note_article', {}).get('title', '不明')}\")
print(f\"特典: {d.get('bonus', {}).get('title', '不明')}\")
s = d.get('schedule', {})
print(f\"公開日: {s.get('main_post', '不明')}\")
print(f\"終了日: {s.get('close', '不明')}\")
" 2>/dev/null || echo "(詳細表示に失敗)"
echo "=========================================="

# ──────────────────────────────────────────
# Phase 3: Note記事の執筆（Step 6）
# ──────────────────────────────────────────
NOTE_WRITER_PROMPT=$(awk '/^---$/{n++; next} n>=2' .claude/agents/giveaway_note_writer.md)

echo ""
echo "[Phase 3] Giveaway Note Writer 起動（Note記事の執筆）..."
echo ""
"$CLAUDE_CMD" -p --model claude-sonnet-4-6 --max-tokens 32000 "$NOTE_WRITER_PROMPT"

# Note記事出力の検証
if [ ! -f "giveaway/data/giveaway_note_draft.json" ]; then
  echo "エラー: giveaway/data/giveaway_note_draft.json が生成されませんでした。"
  exit 1
fi

echo ""
echo "=========================================="
echo "Phase 3 完了: giveaway/data/giveaway_note_draft.json 生成済み"
echo ""
python3 -c "
import json
d = json.load(open('giveaway/data/giveaway_note_draft.json'))
print(f\"タイトル: {d.get('note_title', '不明')}\")
print(f\"文字数: {d.get('char_count', 0)}文字\")
sections = d.get('sections', [])
print(f\"セクション数: {len(sections)}\")
for s in sections:
    print(f\"  - {s.get('heading', '?')}: {s.get('char_count', 0)}文字\")
images = d.get('image_placeholders', [])
print(f\"画像プレースホルダー: {len(images)}枚\")
qc = d.get('quality_check', {})
passed = all(qc.values()) if qc else False
print(f\"品質チェック: {'全項目パス' if passed else '要確認'}\")
" 2>/dev/null || echo "(詳細表示に失敗)"
echo "=========================================="

# ──────────────────────────────────────────
# Phase 3.5: 画像生成（サムネイル + 記事内画像）
# ──────────────────────────────────────────
echo ""
echo "[Phase 3.5] 画像生成（Gemini API）..."
echo ""

source .env 2>/dev/null || true

if [ -z "$GEMINI_API_KEY" ]; then
  echo "警告: GEMINI_API_KEY が未設定です。画像生成をスキップします。"
  echo "  .env に GEMINI_API_KEY=your_key を追加してください。"
else
  python3 giveaway/scripts/generate_images.py

  if [ -f "giveaway/data/images/manifest.json" ]; then
    python3 -c "
import json
m = json.load(open('giveaway/data/images/manifest.json'))
imgs = m.get('images', [])
ok = sum(1 for i in imgs if i['success'])
print(f'画像生成: {ok}/{len(imgs)} 枚成功')
for i in imgs:
    status = 'OK' if i['success'] else 'FAIL'
    print(f'  [{status}] {i[\"type\"]}')
" 2>/dev/null || echo "(詳細表示に失敗)"
  fi
fi

echo ""
echo "=========================================="
echo "Phase 3.5 完了: 画像生成"
echo "=========================================="

# ──────────────────────────────────────────
# Phase 4: PlaywrightでNote自動公開
# ──────────────────────────────────────────
echo ""
echo "[Phase 4] Note自動公開（Playwright）..."
echo ""

# Playwright/cookiesの事前チェック
if ! python3 -c "import playwright" 2>/dev/null; then
  echo "エラー: Playwright がインストールされていません。"
  echo "  bash scripts/setup_playwright.sh を実行してください。"
  exit 1
fi

if [ ! -f "config/note_cookies.json" ]; then
  echo "エラー: config/note_cookies.json が見つかりません。"
  echo "  python3 scripts/save_note_cookies.py でログインセッションを保存してください。"
  exit 1
fi

python3 playwright/note_publisher.py

# 公開結果の検証
if [ ! -f "giveaway/data/giveaway_note_result.json" ]; then
  echo "エラー: giveaway/data/giveaway_note_result.json が生成されませんでした。"
  exit 1
fi

NOTE_URL=$(python3 -c "import json; print(json.load(open('giveaway/data/giveaway_note_result.json')).get('note_url', '不明'))" 2>/dev/null || echo "不明")
echo ""
echo "=========================================="
echo "Phase 4 完了: Note記事を公開しました"
echo "URL: ${NOTE_URL}"
echo "=========================================="
# ──────────────────────────────────────────
# Phase 5: 引用RT特典コンテンツの執筆
# ──────────────────────────────────────────
BONUS_PROMPT=$(awk '/^---$/{n++; next} n>=2' .claude/agents/giveaway_bonus_writer.md)

echo ""
echo "[Phase 5] Giveaway Bonus Writer 起動（引用RT特典の執筆）..."
echo ""
"$CLAUDE_CMD" -p --model claude-sonnet-4-6 --max-tokens 16000 "$BONUS_PROMPT"

# 特典出力の検証
if [ ! -f "giveaway/data/giveaway_bonus_draft.json" ]; then
  echo "エラー: giveaway/data/giveaway_bonus_draft.json が生成されませんでした。"
  exit 1
fi

echo ""
echo "=========================================="
echo "Phase 5 完了: giveaway/data/giveaway_bonus_draft.json 生成済み"
echo ""
python3 -c "
import json
d = json.load(open('giveaway/data/giveaway_bonus_draft.json'))
print(f\"特典タイトル: {d.get('bonus_title', '不明')}\")
print(f\"形式: {d.get('bonus_format', '不明')}\")
print(f\"文字数: {d.get('char_count', 0)}文字\")
sections = d.get('sections', [])
print(f\"セクション数: {len(sections)}\")
for s in sections:
    print(f\"  - {s.get('heading', '?')}: {s.get('char_count', 0)}文字\")
" 2>/dev/null || echo "(詳細表示に失敗)"
echo "=========================================="

# ──────────────────────────────────────────
# Phase 5.5: 特典ドキュメントをWebhook送信
# ──────────────────────────────────────────
echo ""
echo "[Phase 5.5] 特典ドキュメントをWebhook送信..."
echo ""

source .env 2>/dev/null || true

if [ -z "$WEBHOOK_URL" ]; then
  echo "警告: WEBHOOK_URLが未設定のため特典送信をスキップします。"
else
  BONUS_PAYLOAD=$(python3 -c "
import json
bonus = json.load(open('giveaway/data/giveaway_bonus_draft.json'))
plan = json.load(open('giveaway/data/giveaway_plan.json'))
payload = {
    'type': 'giveaway_bonus',
    'campaign_id': bonus.get('campaign_id', ''),
    'bonus_title': bonus.get('bonus_title', ''),
    'bonus_format': bonus.get('bonus_format', ''),
    'bonus_body': bonus.get('bonus_body', ''),
    'char_count': bonus.get('char_count', 0),
    'theme': plan.get('theme', ''),
    'reply_keyword': plan.get('reply_keyword', ''),
    'note_url': ''
}
# note_resultがあればURLを付与
try:
    note = json.load(open('giveaway/data/giveaway_note_result.json'))
    payload['note_url'] = note.get('note_url', '')
except: pass
print(json.dumps({'data': [payload]}, ensure_ascii=False))
" 2>/dev/null)

  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json; charset=utf-8" \
    -d "$BONUS_PAYLOAD")

  if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
    echo "  特典ドキュメント送信完了 (HTTP ${HTTP_CODE})"
  else
    echo "  特典ドキュメント送信失敗 (HTTP ${HTTP_CODE})"
  fi
fi

echo ""
echo "=========================================="
echo "Phase 5.5 完了: 特典ドキュメント送信済み"
echo "=========================================="

# ──────────────────────────────────────────
# Phase 6: X投稿5本の執筆
# ──────────────────────────────────────────
X_WRITER_PROMPT=$(awk '/^---$/{n++; next} n>=2' .claude/agents/giveaway_x_writer.md)

echo ""
echo "[Phase 6] Giveaway X Writer 起動（X投稿5本の執筆）..."
echo ""
"$CLAUDE_CMD" -p --model claude-sonnet-4-6 --max-tokens 16000 "$X_WRITER_PROMPT"

# X投稿出力の検証
if [ ! -f "giveaway/data/giveaway_x_posts.json" ]; then
  echo "エラー: giveaway/data/giveaway_x_posts.json が生成されませんでした。"
  exit 1
fi

POST_COUNT=$(python3 -c "import json; d=json.load(open('giveaway/data/giveaway_x_posts.json')); print(len(d.get('posts', [])))" 2>/dev/null || echo '0')
echo ""
echo "=========================================="
echo "Phase 6 完了: giveaway/data/giveaway_x_posts.json 生成済み（${POST_COUNT}本）"
echo ""
python3 -c "
import json
d = json.load(open('giveaway/data/giveaway_x_posts.json'))
for p in d.get('posts', []):
    num = p.get('post_number', '?')
    label = p.get('label', '?')
    dt = p.get('scheduled_datetime', '?')
    cc = p.get('char_count', 0)
    preview = p.get('post_content', '')[:30].replace(chr(10), ' ')
    print(f'  #{num} [{label}] {dt} ({cc}文字) {preview}...')
" 2>/dev/null || echo "(詳細表示に失敗)"
echo "=========================================="

# ──────────────────────────────────────────
# Phase 7: Webhook予約送信（n8n経由で予約投稿）
# ──────────────────────────────────────────
echo ""
echo "[Phase 7] Webhook予約送信（n8nへ5本を予約登録）..."
echo ""

# .envからWEBHOOK_URLを読み込む
source .env 2>/dev/null || true

if [ -z "$WEBHOOK_URL" ]; then
  echo "エラー: WEBHOOK_URLが設定されていません。.envファイルを確認してください。"
  exit 1
fi

SEND_OK=0
SEND_FAIL=0

# サムネイル画像プロンプトの取得（メイン投稿に付与）
THUMB_PROMPT=""
if [ -f "giveaway/data/images/manifest.json" ]; then
  THUMB_PROMPT=$(python3 -c "
import json
m = json.load(open('giveaway/data/images/manifest.json'))
for img in m.get('images', []):
    if img.get('type') == 'thumbnail' and img.get('success'):
        print(img.get('prompt', '')); break
" 2>/dev/null || echo "")
fi

# キーワード・特典情報の取得（メイン投稿に付与）
REPLY_KEYWORD=""
BONUS_TITLE=""
NOTE_URL=""
if [ -f "giveaway/data/giveaway_plan.json" ]; then
  REPLY_KEYWORD=$(python3 -c "import json; print(json.load(open('giveaway/data/giveaway_plan.json')).get('reply_keyword', ''))" 2>/dev/null || echo "")
fi
if [ -f "giveaway/data/giveaway_bonus_draft.json" ]; then
  BONUS_TITLE=$(python3 -c "import json; print(json.load(open('giveaway/data/giveaway_bonus_draft.json')).get('bonus_title', ''))" 2>/dev/null || echo "")
fi
if [ -f "giveaway/data/giveaway_note_result.json" ]; then
  NOTE_URL=$(python3 -c "import json; print(json.load(open('giveaway/data/giveaway_note_result.json')).get('note_url', ''))" 2>/dev/null || echo "")
fi

# 5本の投稿を1件ずつWebhook送信
python3 -c "
import json, sys
d = json.load(open('giveaway/data/giveaway_x_posts.json'))
for p in d.get('posts', []):
    out = {
        'post_content': p['post_content'],
        'scheduled_datetime': p['scheduled_datetime'],
        'label': p['label'],
        'campaign_id': d.get('campaign_id', ''),
        'is_giveaway_tweet': p.get('is_giveaway_tweet', False)
    }
    print(json.dumps(out, ensure_ascii=False))
" 2>/dev/null | while IFS= read -r ITEM; do
  LABEL=$(echo "$ITEM" | python3 -c "import sys,json; print(json.load(sys.stdin)['label'])")
  DATETIME=$(echo "$ITEM" | python3 -c "import sys,json; print(json.load(sys.stdin)['scheduled_datetime'])")
  POST_CONTENT=$(echo "$ITEM" | python3 -c "import sys,json; print(json.load(sys.stdin)['post_content'])")
  CAMPAIGN_ID=$(echo "$ITEM" | python3 -c "import sys,json; print(json.load(sys.stdin)['campaign_id'])")
  IS_MAIN=$(echo "$ITEM" | python3 -c "import sys,json; d=json.load(sys.stdin); print('_main' if d.get('is_giveaway_tweet') else '')")

  # メイン投稿（投稿3）にはサムネイル画像プロンプト・キーワード・特典情報を付与
  IMG_PROMPT=""
  if [ -n "$IS_MAIN" ]; then
    IMG_PROMPT="$THUMB_PROMPT"
  fi

  # 日時フォーマット変換（YYYY-MM-DD HH:MM:SS → YYYY/MM/DD HH:MM:SS）
  SCHEDULED_TIME=$(echo "$DATETIME" | tr '-' '/')

  # メイン投稿にはn8nがリプライ検知に使うキーワード・特典情報を付与
  if [ -n "$IS_MAIN" ]; then
    PAYLOAD=$(jq -n \
      --arg post "$POST_CONTENT" \
      --arg date "$SCHEDULED_TIME" \
      --arg campaign_id "${CAMPAIGN_ID}${IS_MAIN}" \
      --arg image_prompt "$IMG_PROMPT" \
      --arg reply_keyword "$REPLY_KEYWORD" \
      --arg bonus_title "$BONUS_TITLE" \
      --arg note_url "$NOTE_URL" \
      '{"data": [{"post": $post, "date": $date, "image_prompt": $image_prompt, "campaign_id": $campaign_id, "reply_keyword": $reply_keyword, "bonus_title": $bonus_title, "note_url": $note_url}]}')
  else
    PAYLOAD=$(jq -n \
      --arg post "$POST_CONTENT" \
      --arg date "$SCHEDULED_TIME" \
      --arg campaign_id "${CAMPAIGN_ID}" \
      --arg image_prompt "" \
      '{"data": [{"post": $post, "date": $date, "image_prompt": $image_prompt, "campaign_id": $campaign_id}]}')
  fi

  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json; charset=utf-8" \
    -d "$PAYLOAD")

  if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
    echo "  [${LABEL}] ${DATETIME} → 送信完了 (HTTP ${HTTP_CODE})"
  else
    echo "  [${LABEL}] ${DATETIME} → 送信失敗 (HTTP ${HTTP_CODE})"
  fi

  sleep 1
done

echo ""
echo "=========================================="
echo "Phase 7 完了: Webhook予約送信"
echo "=========================================="

# ──────────────────────────────────────────
# 完了サマリー
# ──────────────────────────────────────────
echo ""
echo "=========================================="
echo "プレゼント企画パイプライン 全フェーズ完了"
echo "=========================================="
echo ""
python3 -c "
import json
plan = json.load(open('giveaway/data/giveaway_plan.json'))
note = json.load(open('giveaway/data/giveaway_note_result.json'))
bonus = json.load(open('giveaway/data/giveaway_bonus_draft.json'))
posts = json.load(open('giveaway/data/giveaway_x_posts.json'))
s = plan.get('schedule', {})
print(f\"企画ID:     {plan.get('campaign_id', '?')}\")
print(f\"テーマ:     {plan.get('theme', '?')}\")
print(f\"Note URL:   {note.get('note_url', '?')}\")
print(f\"特典:       {bonus.get('bonus_title', '?')}\")
print(f\"X投稿:      {len(posts.get('posts', []))}本 予約済み\")
print(f\"公開日:     {s.get('main_post', '?')}\")
print(f\"終了日:     {s.get('close', '?')}\")
" 2>/dev/null || echo "(サマリー表示に失敗)"
echo ""
