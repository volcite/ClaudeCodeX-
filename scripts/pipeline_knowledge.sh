#!/bin/bash
# ========================================
# ナレッジストック管理スクリプト
# オーナーの思想・哲学・体験をストックに登録・管理する
#
# 使い方:
#   # 追加
#   bash scripts/pipeline_knowledge.sh '{"topic":"テーマ","content":"内容","category":"philosophy"}'
#   echo '{"topic":"テーマ","content":"内容"}' | bash scripts/pipeline_knowledge.sh
#
#   # 一覧
#   bash scripts/pipeline_knowledge.sh list
#   bash scripts/pipeline_knowledge.sh list --category philosophy
#
#   # アーカイブ（非表示にする）
#   bash scripts/pipeline_knowledge.sh archive k_20260326_001
#
#   # 使用回数リセット
#   bash scripts/pipeline_knowledge.sh reset k_20260326_001
# ========================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

STOCK_FILE="data/knowledge_stock.json"

# ストックファイルが無ければ初期化
if [ ! -f "$STOCK_FILE" ]; then
  echo '{"last_updated": null, "items": []}' > "$STOCK_FILE"
fi

# サブコマンド判定
SUBCMD="${1:-}"

# --- list サブコマンド ---
if [ "$SUBCMD" = "list" ]; then
  FILTER_CAT="${3:-}"
  node -e "
const fs = require('fs');
const data = JSON.parse(fs.readFileSync('$STOCK_FILE', 'utf-8'));
const filterCat = process.argv[1] || '';

let items = data.items.filter(i => i.status === 'active');
if (filterCat) {
  items = items.filter(i => i.category === filterCat);
}

if (items.length === 0) {
  console.log('ストックが空です');
  process.exit(0);
}

console.log('=== ナレッジストック（active: ' + items.length + '件） ===\n');
items.forEach(item => {
  console.log('[' + item.id + '] ' + item.category.toUpperCase());
  console.log('  topic: ' + item.topic);
  console.log('  使用: ' + item.usage_count + '/' + item.max_usage + '回');
  console.log('  優先度: ' + item.priority);
  console.log('');
});
" "$FILTER_CAT"
  exit 0
fi

# --- archive サブコマンド ---
if [ "$SUBCMD" = "archive" ]; then
  TARGET_ID="${2:-}"
  if [ -z "$TARGET_ID" ]; then
    echo "エラー: アーカイブするアイテムのIDを指定してください"
    exit 1
  fi
  node -e "
const fs = require('fs');
const data = JSON.parse(fs.readFileSync('$STOCK_FILE', 'utf-8'));
const targetId = process.argv[1];
const item = data.items.find(i => i.id === targetId);
if (!item) {
  console.error('エラー: ID ' + targetId + ' が見つかりません');
  process.exit(1);
}
item.status = 'archived';
data.last_updated = new Date().toISOString();
fs.writeFileSync('$STOCK_FILE', JSON.stringify(data, null, 2), 'utf-8');
console.log('アーカイブしました: ' + item.topic);
" "$TARGET_ID"
  exit 0
fi

# --- reset サブコマンド ---
if [ "$SUBCMD" = "reset" ]; then
  TARGET_ID="${2:-}"
  if [ -z "$TARGET_ID" ]; then
    echo "エラー: リセットするアイテムのIDを指定してください"
    exit 1
  fi
  node -e "
const fs = require('fs');
const data = JSON.parse(fs.readFileSync('$STOCK_FILE', 'utf-8'));
const targetId = process.argv[1];
const item = data.items.find(i => i.id === targetId);
if (!item) {
  console.error('エラー: ID ' + targetId + ' が見つかりません');
  process.exit(1);
}
item.usage_count = 0;
item.last_used_at = null;
item.status = 'active';
data.last_updated = new Date().toISOString();
fs.writeFileSync('$STOCK_FILE', JSON.stringify(data, null, 2), 'utf-8');
console.log('リセットしました: ' + item.topic);
" "$TARGET_ID"
  exit 0
fi

# --- 追加（デフォルト動作） ---
# 入力の取得（引数 or stdin）
if echo "$SUBCMD" | grep -q '^{'; then
  INPUT_JSON="$SUBCMD"
elif [ -z "$SUBCMD" ]; then
  INPUT_JSON=$(cat)
else
  echo "エラー: 不明なサブコマンド: $SUBCMD"
  echo "使い方:"
  echo "  追加: bash scripts/pipeline_knowledge.sh '{\"topic\":\"...\",\"content\":\"...\",\"category\":\"philosophy\"}'"
  echo "  一覧: bash scripts/pipeline_knowledge.sh list"
  echo "  アーカイブ: bash scripts/pipeline_knowledge.sh archive <ID>"
  echo "  リセット: bash scripts/pipeline_knowledge.sh reset <ID>"
  exit 1
fi

if [ -z "$INPUT_JSON" ]; then
  echo "エラー: ナレッジ情報のJSONを引数またはstdinで渡してください"
  exit 1
fi

TODAY=$(date +%Y-%m-%d)

node -e "
const fs = require('fs');
const input = JSON.parse(process.argv[1]);
const today = process.argv[2];

if (!input.topic) {
  console.error('エラー: topic フィールドは必須です');
  process.exit(1);
}
if (!input.content) {
  console.error('エラー: content フィールドは必須です');
  process.exit(1);
}

// カテゴリのバリデーション
const validCategories = ['philosophy', 'experience', 'quote'];
const category = input.category || 'philosophy';
if (!validCategories.includes(category)) {
  console.error('エラー: category は philosophy / experience / quote のいずれかを指定してください');
  process.exit(1);
}

// ストック読み込み
const data = JSON.parse(fs.readFileSync('$STOCK_FILE', 'utf-8'));

// ID生成（日付 + 連番）
const todayItems = data.items.filter(i => i.id.startsWith('k_' + today.replace(/-/g, '')));
const seq = String(todayItems.length + 1).padStart(3, '0');
const id = 'k_' + today.replace(/-/g, '') + '_' + seq;

const newItem = {
  id: id,
  created_at: today,
  category: category,
  priority: input.priority || 'medium',
  topic: input.topic,
  content: input.content,
  source_urls: input.source_urls || [],
  tags: input.tags || [],
  usage_count: 0,
  max_usage: input.max_usage || 3,
  last_used_at: null,
  status: 'active',
  slot_affinity: input.slot_affinity || 'both'
};

data.items.push(newItem);
data.last_updated = new Date().toISOString();
fs.writeFileSync('$STOCK_FILE', JSON.stringify(data, null, 2), 'utf-8');

console.log(JSON.stringify(newItem, null, 2));
console.log('');
console.log('ナレッジを登録しました: ' + newItem.topic);
console.log('ID: ' + newItem.id);
console.log('カテゴリ: ' + newItem.category);
console.log('最大使用回数: ' + newItem.max_usage + '回');
" "$INPUT_JSON" "$TODAY"
