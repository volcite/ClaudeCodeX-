#!/bin/bash
# ========================================
# テーマ差し込みスクリプト
# n8nから呼び出して、特定テーマを今日〜数日間の投稿に差し込む
#
# 使い方:
#   bash scripts/pipeline_inject.sh '{"topic":"テーマ名","details":"詳細","source_url":"https://...","duration_days":3}'
#   echo '{"topic":"テーマ名"}' | bash scripts/pipeline_inject.sh
# ========================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# 入力の取得（引数 or stdin）
if [ -n "$1" ]; then
  INPUT_JSON="$1"
else
  INPUT_JSON=$(cat)
fi

if [ -z "$INPUT_JSON" ]; then
  echo "エラー: テーマ情報のJSONを引数またはstdinで渡してください"
  echo "例: bash scripts/pipeline_inject.sh '{\"topic\":\"テーマ名\",\"details\":\"詳細\",\"source_url\":\"https://...\",\"duration_days\":3}'"
  exit 1
fi

TODAY=$(date +%Y-%m-%d)

# Node.js で injected_topic.json を生成（jq/python不要）
node -e "
const fs = require('fs');
const input = JSON.parse(process.argv[1]);
const today = process.argv[2];

if (!input.topic) {
  console.error('エラー: topic フィールドは必須です');
  process.exit(1);
}

const output = {
  topic: input.topic,
  details: input.details || '',
  source_url: input.source_url || '',
  priority: input.priority || 'high',
  inject_date: today,
  duration_days: input.duration_days || 3,
  slots_used: [],
  status: 'active'
};

fs.writeFileSync('post/data/injected_topic.json', JSON.stringify(output, null, 2), 'utf-8');
console.log(JSON.stringify(output, null, 2));

// 有効期限を計算
const endDate = new Date(today);
endDate.setDate(endDate.getDate() + output.duration_days - 1);
const endStr = endDate.toISOString().split('T')[0];

console.log('');
console.log('差し込みテーマを登録しました: ' + output.topic);
console.log('有効期間: ' + today + ' から ' + endStr);
console.log('次回のパイプライン実行時に反映されます');
" "$INPUT_JSON" "$TODAY"
