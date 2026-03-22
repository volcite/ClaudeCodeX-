#!/bin/bash
# 作業ディレクトリを x-automation 直下に移動
cd "$(dirname "$0")/.."

echo "Starting: Analyst..."
claude -p "$(cat .claude/agents/analyst.md)"
