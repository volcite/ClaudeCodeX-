# X記事リサーチ スキル

ユーザーの指示に基づいて、SocialData APIを使ったX記事の自動リサーチを実行します。

## 実行手順

1. ユーザーの指示から以下のパラメータを判断してください:
   - いいね数の最小値（指定がなければ1000）
   - RT数の最小値（指定がなければ0）
   - 対象期間（指定がなければ直近1ヶ月）
   - 言語フィルタ（指定がなければ日本語のみ: ja）

2. 以下のシェルスクリプトを実行してください:

```bash
bash scripts/pipeline_article_research.sh --min-faves {いいね数} --min-retweets {RT数} --since {開始日} --until {終了日} --lang {言語} --verbose
```

3. 分析も同時に行う場合は `--analyze` を付けてください:

```bash
bash scripts/pipeline_article_research.sh --min-faves {いいね数} --since {開始日} --until {終了日} --analyze --verbose
```

4. 実行完了後、`article/output/` ディレクトリに生成されたMarkdownレポートを読み込み、ユーザーにサマリーを報告してください。

## 使用例

ユーザー: 「X記事をリサーチして。いいね1,000以上、直近1ヶ月分。」
→ `bash scripts/pipeline_article_research.sh --min-faves 1000 --verbose`

ユーザー: 「AI系のバズ記事を調べて、いいね500以上で3ヶ月分」
→ `bash scripts/pipeline_article_research.sh --min-faves 500 --since 2026-01-07 --until 2026-04-07 --analyze --category AI --verbose`

ユーザー: 「前回のデータをAI系だけ分析して」
→ `bash scripts/pipeline_article_research.sh --analyze-only --category AI`

## 注意事項

- 環境変数 `SOCIALDATA_API_KEY` が設定されている必要があります
- 初回実行時はAPIコールが多くなりますが、2回目以降はキャッシュが効きます
- コストは1件あたり約0.03円（$0.0002）です
