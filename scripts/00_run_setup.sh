#!/bin/bash
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

# claudeコマンド（サブエージェント）を呼び出し、引数で渡された情報を指定して x-setup スキルを実行させる
claude -p "x-setupスキルを実行してください。設定するWebhook URLは「${WEBHOOK_URL}」、XアカウントIDは「${X_ID}」です。ユーザーに質問はせず、この情報を使って全自動でWebリサーチと設定ファイルの初期化を完了させてください。"

echo "========================================="
echo " セットアップが終了しました"
echo "========================================="
