---
name: x-community-manager
description: 自分の投稿に届いたリプライへの自動返信を生成するスキル。
---

# X Community Manager

自分の投稿に届いたリプライに対する返信を自動生成します。

## パイプライン実行
```
bash post/scripts/pipeline_reply.sh <リプライJSON>
```
n8nから30分ごとに呼び出され、返信JSONをWebhookで返却します。

## 手動実行
`/x-community-manager` でエージェントを起動してください。
`post/data/input_mentions.json` にリプライデータを配置してから実行します。

## シャドウバン対策
- 日次上限: 150件、1回あたり上限: 15件（`data/reply_counter.json` で管理）
- n8n側で返信間隔を1-3分ランダムに設定
- confidence が低い返信は自動スキップ（無理に返信しない）
