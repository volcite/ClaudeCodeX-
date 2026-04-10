#!/bin/bash
# ========================================
# Playwright + Chromium 環境構築スクリプト
# Note自動公開に必要な依存関係をインストールする
# 初回のみ実行すればOK
# ========================================
set -euo pipefail

echo "=========================================="
echo "Playwright 環境構築"
echo "=========================================="

# Python3 確認
if ! command -v python3 &>/dev/null; then
  echo "エラー: python3 が見つかりません。"
  exit 1
fi

# pip3 が無ければインストール
if ! command -v pip3 &>/dev/null; then
  echo "[0/4] pip3 をインストール..."
  apt-get update -qq && apt-get install -y -qq python3-pip 2>/dev/null || {
    echo "pip3 が見つかりません。python3 -m pip を試みます..."
  }
fi

# pip install playwright
echo "[1/4] Playwright パッケージをインストール..."
if command -v pip3 &>/dev/null; then
  pip3 install playwright
else
  python3 -m pip install playwright
fi

# Chromium ブラウザ + 依存ライブラリを一括インストール
echo "[2/3] Chromium ブラウザ + 依存ライブラリをインストール..."
playwright install chromium --with-deps

# 日本語フォントのインストール
echo "[3/3] 日本語フォントをインストール..."
apt-get update -qq && apt-get install -y -qq fonts-noto-cjk fonts-noto-cjk-extra 2>/dev/null || {
  echo "警告: 日本語フォントのインストールに失敗しました（root権限が必要です）"
}

echo ""
echo "=========================================="
echo "セットアップ完了"
echo ""
echo "次のステップ:"
echo "  1. Noteのログインセッションを保存:"
echo "     python3 scripts/save_note_cookies.py"
echo "  2. 動作テスト:"
echo "     python3 playwright/note_publisher.py"
echo "=========================================="
