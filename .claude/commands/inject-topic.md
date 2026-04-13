テーマ差し込みを実行します。

ユーザーから以下の情報を確認してください:
1. **topic**: 差し込みたいテーマ（必須）
2. **details**: 詳細説明（任意）
3. **source_url**: 参考URL（任意）
4. **duration_days**: 有効日数（デフォルト: 3日）

確認後、以下のコマンドを実行:
```bash
bash post/scripts/pipeline_inject.sh '{"topic":"テーマ","details":"詳細","source_url":"URL","duration_days":3}'
```

実行結果と `post/data/injected_topic.json` の内容を報告してください。
