#!/usr/bin/env node
// =============================================================================
// X Article Analyzer - 収集したX記事を分析し、記事作成に活用するツール
// =============================================================================
// 使い方:
//   node x-article-analyzer.js <json-report-path> [options]
//
// オプション:
//   --top <number>           分析対象のTOP件数 (デフォルト: 50)
//   --category <keyword>     カテゴリキーワードでフィルタ (例: AI, プログラミング)
//   --output <path>          分析レポート出力パス
//   --format <md|json>       出力フォーマット (デフォルト: md)
// =============================================================================

const fs = require("fs");
const path = require("path");

// =============================================================================
// CLI引数パース
// =============================================================================
function parseArgs(argv) {
  const args = argv.slice(2);
  const config = {
    inputPath: null,
    top: 50,
    category: null,
    output: null,
    format: "md",
  };

  for (let i = 0; i < args.length; i++) {
    if (args[i].startsWith("--")) {
      switch (args[i]) {
        case "--top":
          config.top = parseInt(args[++i], 10);
          break;
        case "--category":
          config.category = args[++i];
          break;
        case "--output":
          config.output = args[++i];
          break;
        case "--format":
          config.format = args[++i];
          break;
        case "--help":
          printHelp();
          process.exit(0);
      }
    } else if (!config.inputPath) {
      config.inputPath = args[i];
    }
  }

  if (!config.inputPath) {
    // 最新のJSONレポートを自動検出
    const outputDir = path.join(__dirname, "output");
    if (fs.existsSync(outputDir)) {
      const files = fs
        .readdirSync(outputDir)
        .filter((f) => f.endsWith(".json") && f.startsWith("report-"))
        .sort()
        .reverse();
      if (files.length > 0) {
        config.inputPath = path.join(outputDir, files[0]);
      }
    }
  }

  if (!config.inputPath) {
    console.error("エラー: 入力JSONファイルが見つかりません。");
    console.error("  node x-article-analyzer.js <json-report-path>");
    process.exit(1);
  }

  if (!config.output) {
    const timestamp = new Date()
      .toISOString()
      .replace(/[:.]/g, "-")
      .slice(0, 19);
    config.output = path.join(
      __dirname,
      "output",
      `analysis-${timestamp}.md`
    );
  }

  return config;
}

function printHelp() {
  console.log(`
X Article Analyzer - 収集したX記事を分析するツール

使い方:
  node x-article-analyzer.js <json-report-path> [options]
  node x-article-analyzer.js (最新のレポートを自動検出)

オプション:
  --top <number>           分析対象のTOP件数 (デフォルト: 50)
  --category <keyword>     カテゴリキーワードでフィルタ (例: AI, プログラミング)
  --output <path>          分析レポート出力パス
  --format <md|json>       出力フォーマット (デフォルト: md)
  --help                   ヘルプを表示

例:
  node x-article-analyzer.js ./output/report-2026-04-07.json
  node x-article-analyzer.js --category AI --top 20
`);
}

// =============================================================================
// 分析ロジック
// =============================================================================

// タイトル分析
function analyzeTitles(articles) {
  const titleLengths = articles
    .filter((a) => a.title)
    .map((a) => a.title.length);

  const avgLength =
    titleLengths.length > 0
      ? Math.round(
          titleLengths.reduce((s, l) => s + l, 0) / titleLengths.length
        )
      : 0;
  const minLength = titleLengths.length > 0 ? Math.min(...titleLengths) : 0;
  const maxLength = titleLengths.length > 0 ? Math.max(...titleLengths) : 0;

  // タイトルのパターン分析
  const patterns = {
    questionMark: 0, // ？を含む
    numbers: 0, // 数字を含む
    howTo: 0, // ～方法、やり方
    list: 0, // ○選、○つ
    negative: 0, // ～しない、やめた
    bracket: 0, // 【】を含む
    exclamation: 0, // ！を含む
  };

  for (const a of articles) {
    if (!a.title) continue;
    const t = a.title;
    if (/[？?]/.test(t)) patterns.questionMark++;
    if (/\d/.test(t)) patterns.numbers++;
    if (/方法|やり方|仕方|コツ|ステップ/.test(t)) patterns.howTo++;
    if (/\d+選|\d+つ|\d+個/.test(t)) patterns.list++;
    if (/しない|やめた|やらない|不要|禁止/.test(t)) patterns.negative++;
    if (/[【】\[\]]/.test(t)) patterns.bracket++;
    if (/[！!]/.test(t)) patterns.exclamation++;
  }

  return {
    avgLength,
    minLength,
    maxLength,
    patterns,
    total: articles.filter((a) => a.title).length,
  };
}

// 本文構造の分析
function analyzeStructure(articles) {
  const withText = articles.filter((a) => a.fullText && a.fullText.length > 0);

  if (withText.length === 0) {
    return {
      avgTextLength: 0,
      avgHeadingCount: 0,
      textLengthDistribution: {},
      headingCountDistribution: {},
    };
  }

  const textLengths = withText.map((a) => a.textLength || a.fullText.length);
  const headingCounts = withText.map(
    (a) => a.headingCount || (a.fullText.match(/^#{1,4}\s/gm) || []).length
  );

  const avgTextLength = Math.round(
    textLengths.reduce((s, l) => s + l, 0) / textLengths.length
  );
  const avgHeadingCount = (
    headingCounts.reduce((s, c) => s + c, 0) / headingCounts.length
  ).toFixed(1);

  // 文字数の分布
  const textLengthDistribution = {
    "~1000": textLengths.filter((l) => l <= 1000).length,
    "1001~3000": textLengths.filter((l) => l > 1000 && l <= 3000).length,
    "3001~5000": textLengths.filter((l) => l > 3000 && l <= 5000).length,
    "5001~10000": textLengths.filter((l) => l > 5000 && l <= 10000).length,
    "10001~": textLengths.filter((l) => l > 10000).length,
  };

  // 見出し数の分布
  const headingCountDistribution = {
    "0": headingCounts.filter((c) => c === 0).length,
    "1~3": headingCounts.filter((c) => c >= 1 && c <= 3).length,
    "4~7": headingCounts.filter((c) => c >= 4 && c <= 7).length,
    "8~15": headingCounts.filter((c) => c >= 8 && c <= 15).length,
    "16~": headingCounts.filter((c) => c >= 16).length,
  };

  return {
    avgTextLength,
    avgHeadingCount,
    textLengthDistribution,
    headingCountDistribution,
    count: withText.length,
  };
}

// エンゲージメント分析
function analyzeEngagement(articles) {
  if (articles.length === 0) return {};

  const metrics = ["likes", "retweets", "bookmarks", "views"];
  const result = {};

  for (const metric of metrics) {
    const values = articles.map((a) => a.engagement[metric] || 0);
    const nonZero = values.filter((v) => v > 0);

    result[metric] = {
      total: values.reduce((s, v) => s + v, 0),
      avg: Math.round(values.reduce((s, v) => s + v, 0) / values.length),
      max: Math.max(...values),
      min: Math.min(...nonZero.length > 0 ? nonZero : [0]),
      median: sortedMedian(values),
    };
  }

  // いいね vs ブックマーク比率
  const bmRatios = articles
    .filter(
      (a) => a.engagement.likes > 0 && a.engagement.bookmarks > 0
    )
    .map((a) => a.engagement.bookmarks / a.engagement.likes);

  if (bmRatios.length > 0) {
    result.bookmarkToLikeRatio = (
      bmRatios.reduce((s, r) => s + r, 0) / bmRatios.length
    ).toFixed(3);
  }

  // フォロワー数 vs いいね数の相関（簡易）
  const followerLikeData = articles.map((a) => ({
    followers: a.author.followersCount,
    likes: a.engagement.likes,
  }));

  // フォロワー少なくても伸びてる記事
  const smallAccountBigHits = followerLikeData.filter(
    (d) => d.followers < 5000 && d.likes > 2000
  );

  result.smallAccountBigHits = smallAccountBigHits.length;

  return result;
}

function sortedMedian(arr) {
  const sorted = [...arr].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 !== 0
    ? sorted[mid]
    : Math.round((sorted[mid - 1] + sorted[mid]) / 2);
}

// 冒頭テキスト（リード文）の分析
function analyzeOpenings(articles) {
  const openings = articles
    .filter((a) => a.fullText && a.fullText.length > 100)
    .map((a) => {
      // 最初の段落（見出しを除く）
      const lines = a.fullText.split("\n").filter((l) => l.trim());
      const firstParagraph = lines.find((l) => !l.startsWith("#")) || "";
      return {
        title: a.title,
        opening: firstParagraph.slice(0, 200),
        likes: a.engagement.likes,
      };
    });

  // 冒頭パターンの分類
  const patterns = {
    question: 0, // 問いかけ
    story: 0, // ストーリー・体験談
    statement: 0, // 断定・主張
    data: 0, // データ・数字
    address: 0, // 読者への呼びかけ
  };

  for (const o of openings) {
    const text = o.opening;
    if (/[？?]/.test(text.slice(0, 100))) patterns.question++;
    if (/私|僕|自分|体験|経験|やってみ/.test(text)) patterns.story++;
    if (/です[。！]|ます[。！]|だ[。！]/.test(text.slice(0, 50)))
      patterns.statement++;
    if (/\d+[%％万円件]/.test(text)) patterns.data++;
    if (/あなた|皆さん|みんな|読者/.test(text)) patterns.address++;
  }

  return {
    patterns,
    topOpenings: openings.slice(0, 10),
    total: openings.length,
  };
}

// カテゴリ（キーワード）分類
function categorizeArticles(articles) {
  const categories = {
    "AI・機械学習": /AI|人工知能|ChatGPT|GPT|Claude|Gemini|LLM|機械学習|ディープラーニング|生成AI|プロンプト/i,
    "プログラミング": /プログラミング|コード|エンジニア|開発|Python|JavaScript|React|Next\.js|TypeScript|GitHub/i,
    "ビジネス・副業": /副業|ビジネス|収入|稼|マネタイズ|起業|フリーランス|転職|年収/,
    "マーケティング・SNS": /マーケティング|SNS|Twitter|X|インスタ|YouTube|フォロワー|集客|バズ/i,
    "ライフスタイル": /生活|習慣|健康|睡眠|運動|食事|メンタル|時間管理/,
    "投資・金融": /投資|株|仮想通貨|FX|NISA|資産|節約|お金|金融/,
    "デザイン": /デザイン|UI|UX|Figma|フォント|配色|Canva/i,
    "ライティング": /ライティング|文章|記事|ブログ|コピー|SEO/i,
  };

  const result = {};
  for (const [cat, regex] of Object.entries(categories)) {
    result[cat] = articles.filter((a) => {
      const searchText = `${a.title || ""} ${a.previewText || ""} ${(a.fullText || "").slice(0, 500)}`;
      return regex.test(searchText);
    });
  }

  // 未分類
  const categorized = new Set();
  for (const arts of Object.values(result)) {
    for (const a of arts) categorized.add(a.tweetId);
  }
  result["その他"] = articles.filter((a) => !categorized.has(a.tweetId));

  return result;
}

// トップ著者分析
function analyzeAuthors(articles) {
  const authorMap = new Map();

  for (const a of articles) {
    const key = a.author.screenName;
    if (!authorMap.has(key)) {
      authorMap.set(key, {
        name: a.author.name,
        screenName: a.author.screenName,
        followersCount: a.author.followersCount,
        articleCount: 0,
        totalLikes: 0,
        totalViews: 0,
      });
    }
    const author = authorMap.get(key);
    author.articleCount++;
    author.totalLikes += a.engagement.likes;
    author.totalViews += a.engagement.views || 0;
  }

  return Array.from(authorMap.values())
    .sort((a, b) => b.totalLikes - a.totalLikes)
    .slice(0, 20);
}

// =============================================================================
// レポート生成
// =============================================================================
function generateAnalysisReport(articles, config) {
  const lines = [];

  // カテゴリフィルタ
  let filteredArticles = articles;
  if (config.category) {
    const regex = new RegExp(config.category, "i");
    filteredArticles = articles.filter((a) => {
      const text = `${a.title || ""} ${a.previewText || ""} ${(a.fullText || "").slice(0, 1000)}`;
      return regex.test(text);
    });
  }

  const target = filteredArticles.slice(0, config.top);

  lines.push("# X記事分析レポート");
  lines.push("");
  lines.push(`**生成日時:** ${new Date().toLocaleString("ja-JP")}`);
  lines.push(`**データソース:** ${config.inputPath}`);
  lines.push(`**分析対象:** ${target.length}件${config.category ? ` (フィルタ: "${config.category}")` : ""}`);
  lines.push("");

  // ===== エンゲージメント分析 =====
  lines.push("## 1. エンゲージメント分析");
  lines.push("");

  const engStats = analyzeEngagement(target);
  lines.push("| 指標 | 合計 | 平均 | 中央値 | 最大 |");
  lines.push("|------|------|------|--------|------|");
  for (const [key, label] of [
    ["likes", "いいね"],
    ["retweets", "RT"],
    ["bookmarks", "ブックマーク"],
    ["views", "閲覧数"],
  ]) {
    if (engStats[key]) {
      const s = engStats[key];
      lines.push(
        `| ${label} | ${s.total.toLocaleString()} | ${s.avg.toLocaleString()} | ${s.median.toLocaleString()} | ${s.max.toLocaleString()} |`
      );
    }
  }
  lines.push("");

  if (engStats.bookmarkToLikeRatio) {
    lines.push(
      `**ブックマーク/いいね比率（平均）:** ${engStats.bookmarkToLikeRatio}`
    );
    lines.push(
      `→ ブックマーク率が高い記事 = 「保存して後で読みたい」と思われる有益な記事`
    );
    lines.push("");
  }

  if (engStats.smallAccountBigHits > 0) {
    lines.push(
      `**フォロワー5,000未満でいいね2,000以上:** ${engStats.smallAccountBigHits}件`
    );
    lines.push(`→ フォロワーが少なくてもX記事は伸ばせる証拠`);
    lines.push("");
  }

  // ===== タイトル分析 =====
  lines.push("## 2. タイトル分析");
  lines.push("");

  const titleStats = analyzeTitles(target);
  lines.push(
    `**タイトル文字数:** 平均${titleStats.avgLength}文字 (最短${titleStats.minLength} / 最長${titleStats.maxLength})`
  );
  lines.push("");
  lines.push("**タイトルパターン出現率:**");
  lines.push("");
  lines.push("| パターン | 件数 | 割合 |");
  lines.push("|---------|------|------|");

  const patternLabels = {
    questionMark: "疑問形（？）",
    numbers: "数字を含む",
    howTo: "ハウツー系",
    list: "リスト系（○選）",
    negative: "否定系",
    bracket: "【】括弧",
    exclamation: "感嘆符（！）",
  };

  for (const [key, label] of Object.entries(patternLabels)) {
    const count = titleStats.patterns[key];
    const pct = titleStats.total > 0
      ? ((count / titleStats.total) * 100).toFixed(1)
      : "0";
    lines.push(`| ${label} | ${count} | ${pct}% |`);
  }
  lines.push("");

  // ===== 本文構造分析 =====
  lines.push("## 3. 本文構造分析");
  lines.push("");

  const structStats = analyzeStructure(target);
  lines.push(
    `**平均文字数:** ${structStats.avgTextLength.toLocaleString()}文字`
  );
  lines.push(`**平均見出し数:** ${structStats.avgHeadingCount}個`);
  lines.push("");

  lines.push("**文字数分布:**");
  lines.push("");
  lines.push("| 文字数 | 件数 |");
  lines.push("|--------|------|");
  for (const [range, count] of Object.entries(
    structStats.textLengthDistribution || {}
  )) {
    lines.push(`| ${range} | ${count} |`);
  }
  lines.push("");

  lines.push("**見出し数分布:**");
  lines.push("");
  lines.push("| 見出し数 | 件数 |");
  lines.push("|---------|------|");
  for (const [range, count] of Object.entries(
    structStats.headingCountDistribution || {}
  )) {
    lines.push(`| ${range} | ${count} |`);
  }
  lines.push("");

  // ===== 冒頭パターン分析 =====
  lines.push("## 4. 冒頭（リード文）分析");
  lines.push("");

  const openingStats = analyzeOpenings(target);
  lines.push("**冒頭のパターン:**");
  lines.push("");
  lines.push("| パターン | 件数 |");
  lines.push("|---------|------|");

  const openingLabels = {
    question: "問いかけ",
    story: "ストーリー・体験談",
    statement: "断定・主張",
    data: "データ・数字提示",
    address: "読者への呼びかけ",
  };

  for (const [key, label] of Object.entries(openingLabels)) {
    lines.push(`| ${label} | ${openingStats.patterns[key]} |`);
  }
  lines.push("");

  lines.push("**TOP記事の冒頭テキスト:**");
  lines.push("");

  for (const o of openingStats.topOpenings.slice(0, 5)) {
    lines.push(`- **${o.title}** (いいね: ${o.likes.toLocaleString()})`);
    lines.push(`  > ${o.opening}...`);
    lines.push("");
  }

  // ===== カテゴリ分類 =====
  lines.push("## 5. カテゴリ分類");
  lines.push("");

  const categories = categorizeArticles(target);
  lines.push("| カテゴリ | 件数 | 平均いいね |");
  lines.push("|---------|------|----------|");

  for (const [cat, arts] of Object.entries(categories)) {
    if (arts.length === 0) continue;
    const avgLikes = Math.round(
      arts.reduce((s, a) => s + a.engagement.likes, 0) / arts.length
    );
    lines.push(
      `| ${cat} | ${arts.length} | ${avgLikes.toLocaleString()} |`
    );
  }
  lines.push("");

  // ===== トップ著者 =====
  lines.push("## 6. トップ著者");
  lines.push("");
  lines.push("| # | 著者 | 記事数 | 合計いいね | フォロワー |");
  lines.push("|---|------|--------|----------|----------|");

  const topAuthors = analyzeAuthors(target);
  for (let i = 0; i < Math.min(topAuthors.length, 10); i++) {
    const a = topAuthors[i];
    lines.push(
      `| ${i + 1} | ${a.name} (@${a.screenName}) | ${a.articleCount} | ${a.totalLikes.toLocaleString()} | ${a.followersCount.toLocaleString()} |`
    );
  }
  lines.push("");

  // ===== バズ記事の共通パターンまとめ =====
  lines.push("## 7. バズ記事の共通パターン（分析サマリー）");
  lines.push("");
  lines.push("以下は上記データから導き出される傾向です:");
  lines.push("");

  // タイトルの傾向
  const topPattern = Object.entries(titleStats.patterns).sort(
    (a, b) => b[1] - a[1]
  )[0];
  lines.push(
    `1. **タイトル:** 平均${titleStats.avgLength}文字。最も多いパターンは「${patternLabels[topPattern[0]]}」(${topPattern[1]}件)`
  );

  // 本文の傾向
  lines.push(
    `2. **本文量:** 平均${structStats.avgTextLength.toLocaleString()}文字、見出し平均${structStats.avgHeadingCount}個`
  );

  // エンゲージメントの傾向
  if (engStats.bookmarkToLikeRatio) {
    lines.push(
      `3. **保存率:** BM/いいね比率 = ${engStats.bookmarkToLikeRatio}（この数値が高いほど有益と判断されている）`
    );
  }

  // 冒頭の傾向
  const topOpening = Object.entries(openingStats.patterns).sort(
    (a, b) => b[1] - a[1]
  )[0];
  lines.push(
    `4. **冒頭:** 最も多いパターンは「${openingLabels[topOpening[0]]}」(${topOpening[1]}件)`
  );

  lines.push("");
  lines.push("---");
  lines.push("");
  lines.push(
    "*このレポートはx-article-analyzerにより自動生成されました。*"
  );

  return lines.join("\n");
}

// =============================================================================
// メイン処理
// =============================================================================
function main() {
  const config = parseArgs(process.argv);

  console.log("=== X記事分析ツール ===");
  console.log(`入力: ${config.inputPath}`);

  // JSONデータ読み込み
  const rawData = fs.readFileSync(config.inputPath, "utf-8");
  const data = JSON.parse(rawData);

  const articles = data.articles || [];
  console.log(`記事数: ${articles.length}件`);

  if (articles.length === 0) {
    console.error("分析対象の記事がありません。");
    process.exit(1);
  }

  // レポート生成
  const report = generateAnalysisReport(articles, config);

  // 出力
  fs.mkdirSync(path.dirname(config.output), { recursive: true });
  fs.writeFileSync(config.output, report, "utf-8");
  console.log(`分析レポート出力: ${config.output}`);
  console.log("=== 完了 ===");
}

main();
