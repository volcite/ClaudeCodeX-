# X記事分析 スキル

収集済みのX記事データを分析し、バズ記事の共通パターンを抽出します。

## 実行手順

1. ユーザーの指示から以下のパラメータを判断してください:
   - 分析対象の件数（指定がなければTOP50）
   - カテゴリキーワード（AI、プログラミング、ビジネスなど）
   - 入力JSONファイル（指定がなければ最新のレポートを自動検出）

2. 以下のシェルスクリプトを実行してください:

```bash
bash scripts/pipeline_article_research.sh --analyze-only --top {件数} --category {カテゴリ}
```

3. 生成された分析レポートをユーザーに報告してください。以下の観点でサマリーを提供:
   - エンゲージメントの傾向
   - タイトルの共通パターン
   - 本文の構造（文字数、見出し数）
   - 冒頭の書き出しパターン
   - カテゴリ別の傾向

4. ユーザーが記事作成を希望する場合は、分析結果に基づいて記事の構成案を提案してください。

## 使用例

ユーザー: 「収集したX記事を分析して」
→ `bash scripts/pipeline_article_research.sh --analyze-only`

ユーザー: 「AI系の記事だけ分析して」
→ `bash scripts/pipeline_article_research.sh --analyze-only --category AI`

ユーザー: 「TOP20の記事を深掘りして」
→ `bash scripts/pipeline_article_research.sh --analyze-only --top 20`
