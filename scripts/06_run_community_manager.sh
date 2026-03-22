#!/bin/bash
# 作業ディレクトリを x-automation 直下に移動
cd "$(dirname "$0")/.."

echo "Starting: Community Manager..."
claude -p "$(cat .claude/agents/community_manager.md)"
