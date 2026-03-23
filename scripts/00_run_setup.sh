#!/bin/bash
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

# 作業ディレクトリを x-automation 直下に移動
cd "$(dirname "$0")/.."

# 引数のチェック
if [ "$#" -lt 2 ]; then
  echo "エラー: 引数が不足しています。"
  echo "使用方法: bash scripts/00_run_setup.sh <Webhook_URL> <XアカウントID>"
  echo "実行例  : bash scripts/00_run_setup.sh https://hook.n8n.com/xxx @ai_yorozuya"
  exit 1
fi

WEBHOOK_URL="$1"
X_ID="$2"

echo "========================================="
echo " Starting: X-Automation Initial Setup"
echo " Webhook URL   : $WEBHOOK_URL"
echo " XアカウントID : $X_ID"
echo " サブエージェントを起動して初期化を実行します..."
echo "========================================="

# .env を書き込む（Claude の Write 権限外のため、シェルで直接処理）
echo "WEBHOOK_URL=\"${WEBHOOK_URL}\"" > .env
echo ".env を書き込みました: WEBHOOK_URL=${WEBHOOK_URL}"

# claudeコマンド（サブエージェント）を呼び出し、x-setup スキルを実行させる
"$CLAUDE_CMD" -p "x-setupスキルを実行してください。XアカウントIDは「${X_ID}」です。ユーザーに質問はせず、このIDをもとに全自動でWebリサーチと設定ファイルの初期化を完了させてください。"

echo "========================================="
echo " セットアップが終了しました"
echo "========================================="
