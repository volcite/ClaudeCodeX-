#!/bin/bash
# ========================================
# 解説動画生成パイプライン
# 承認済み投稿テキストからRemotionで動画を生成し、GCSにアップロード
#
# 使い方:
#   bash scripts/pipeline_video.sh
#   → post/data/approved_post.json の final_content を元に動画を生成
#   → 成功時: data/video_result.json にGCS URLを出力
# ========================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VIDEO_DIR="$PROJECT_DIR/video"

# ログ関数（pipeline_morning.sh から呼ばれる場合はそちらのlogが優先）
if ! type log &>/dev/null; then
  log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
  }
fi

# 前提チェック
if [ ! -f "$PROJECT_DIR/post/data/approved_post.json" ]; then
  log "エラー: post/data/approved_post.json が見つかりません"
  exit 1
fi

# ffprobe が未インストールなら自動インストール
if ! command -v ffprobe &>/dev/null; then
  log "[VIDEO] ffprobe が見つかりません。ffmpeg をインストール中..."
  apt-get update -qq && apt-get install -y -qq ffmpeg 2>&1 | tail -1
fi

if [ ! -d "$VIDEO_DIR/node_modules" ]; then
  log "[VIDEO] npm install を実行中..."
  cd "$VIDEO_DIR" && npm install
  cd "$PROJECT_DIR"
fi

# .env を video/ ディレクトリにシンボリックリンク（なければコピー）
if [ ! -f "$VIDEO_DIR/.env" ]; then
  if [ -f "$PROJECT_DIR/.env" ]; then
    cp "$PROJECT_DIR/.env" "$VIDEO_DIR/.env"
  fi
fi

# 承認済み投稿テキストを取得（jqがなければnodeで代替）
if command -v jq &>/dev/null; then
  POST_CONTENT=$(jq -r '.final_content' "$PROJECT_DIR/post/data/approved_post.json")
else
  POST_CONTENT=$(node -e "const fs=require('fs');const d=JSON.parse(fs.readFileSync(process.argv[1],'utf-8'));process.stdout.write(d.final_content||'')" "$PROJECT_DIR/post/data/approved_post.json")
fi

if [ -z "$POST_CONTENT" ] || [ "$POST_CONTENT" = "null" ]; then
  log "エラー: approved_post.json に final_content がありません"
  exit 1
fi

log "[VIDEO] 解説動画生成を開始します..."
log "[VIDEO] 投稿テキスト: ${POST_CONTENT:0:80}..."

cd "$VIDEO_DIR"

# テキストをファイル経由で渡す（CLI引数の長さ制限・改行問題を回避）
mkdir -p input
echo "$POST_CONTENT" > input/post_content.txt

# Step 1: シーン生成（投稿テキストからmanuscript.jsonを生成）
log "[VIDEO] Step 1/5: シーン生成中（Gemini）..."
if npx tsx scripts/generate-scenes.ts input/post_content.txt "flat illustration" 2>&1; then
  log "[VIDEO] Step 1/5: シーン生成完了 ✅"
else
  log "[VIDEO] Step 1/5: シーン生成失敗 ❌"
  cd "$PROJECT_DIR"
  exit 1
fi

# Step 2: 画像生成
log "[VIDEO] Step 2/5: 画像生成中（Gemini Image）..."
if npx tsx scripts/generate-images.ts input/manuscript.json 2>&1; then
  log "[VIDEO] Step 2/5: 画像生成完了 ✅"
else
  log "[VIDEO] Step 2/5: 画像生成失敗 ❌"
  cd "$PROJECT_DIR"
  exit 1
fi

# Step 3: 音声生成
log "[VIDEO] Step 3/5: 音声生成中（Fish Audio TTS）..."
if npx tsx scripts/generate-audio.ts input/manuscript.json 2>&1; then
  log "[VIDEO] Step 3/5: 音声生成完了 ✅"
else
  log "[VIDEO] Step 3/5: 音声生成失敗 ❌"
  cd "$PROJECT_DIR"
  exit 1
fi

# Step 4: 動画レンダリング
log "[VIDEO] Step 4/5: 動画レンダリング中（Remotion）..."
if npx tsx scripts/render.ts input/manuscript.json 2>&1; then
  log "[VIDEO] Step 4/5: 動画レンダリング完了 ✅"
else
  log "[VIDEO] Step 4/5: 動画レンダリング失敗 ❌"
  cd "$PROJECT_DIR"
  exit 1
fi

# Step 5: GCSにアップロード
log "[VIDEO] Step 5/5: GCSにアップロード中..."
if npx tsx scripts/upload-gcs.ts out/video.mp4 input/manuscript.json 2>&1; then
  log "[VIDEO] Step 5/5: GCSアップロード完了 ✅"
else
  log "[VIDEO] Step 5/5: GCSアップロード失敗 ❌"
  cd "$PROJECT_DIR"
  exit 1
fi

# URLを取得してdata/video_result.jsonに保存
VIDEO_URL=""
if [ -f "out/video_url.txt" ]; then
  VIDEO_URL=$(cat out/video_url.txt)
fi

cd "$PROJECT_DIR"

if [ -n "$VIDEO_URL" ]; then
  # video_result.json を作成（GCS情報を含む）
  node -e "
const fs = require('fs');
const gcsInfoPath = process.argv[2] + '/out/gcs_result.json';
let gcsInfo = {};
if (fs.existsSync(gcsInfoPath)) {
  gcsInfo = JSON.parse(fs.readFileSync(gcsInfoPath, 'utf-8'));
}
const result = {
  video_url: process.argv[1],
  bucket_name: gcsInfo.bucket_name || '',
  object_name: gcsInfo.object_name || '',
  file_size: gcsInfo.file_size || 0,
  generated_at: new Date().toISOString(),
  status: 'success'
};
fs.writeFileSync('data/video_result.json', JSON.stringify(result, null, 2), 'utf-8');
" "$VIDEO_URL" "$VIDEO_DIR"
  log "[VIDEO] 動画生成完了 ✅ URL: $VIDEO_URL"
  log "[VIDEO] 結果を data/video_result.json に保存しました"

  # 素材ファイルを削除（GCSにアップロード済みのため不要）
  rm -rf "$VIDEO_DIR/public/scenes" "$VIDEO_DIR/public/audio" "$VIDEO_DIR/out" "$VIDEO_DIR/input"
  log "[VIDEO] 素材ファイルを削除しました"
else
  log "[VIDEO] 警告: GCS URLを取得できませんでした"
  echo '{"video_url": "", "status": "url_missing"}' > data/video_result.json
  exit 1
fi
