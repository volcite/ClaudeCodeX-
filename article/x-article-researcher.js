#!/usr/bin/env node
// =============================================================================
// X Article Researcher - SocialData API を使ったX記事自動リサーチツール
// =============================================================================
// 使い方:
//   node x-article-researcher.js [options]
//
// オプション:
//   --min-faves <number>     最小いいね数 (デフォルト: 1000)
//   --min-retweets <number>  最小RT数 (デフォルト: 0)
//   --since <YYYY-MM-DD>     開始日
//   --until <YYYY-MM-DD>     終了日
//   --lang <ja|all>          言語フィルタ (デフォルト: ja)
//   --output <path>          出力ファイルパス (デフォルト: ./output/report-{timestamp}.md)
//   --output-json <path>     JSON出力パス (デフォルト: ./output/report-{timestamp}.json)
//   --cache-dir <path>       キャッシュディレクトリ (デフォルト: ./cache)
//   --no-cache               キャッシュを無効化
//   --verbose                詳細ログ出力
// =============================================================================

const https = require("https");
const fs = require("fs");
const path = require("path");

// =============================================================================
// CLI引数パース
// =============================================================================
function parseArgs(argv) {
  const args = argv.slice(2);
  const config = {
    minFaves: 1000,
    minRetweets: 0,
    since: null,
    until: null,
    lang: "ja",
    theme: [],
    output: null,
    outputJson: null,
    cacheDir: path.join(__dirname, "cache"),
    useCache: true,
    fromCache: false,
    verbose: false,
  };

  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case "--min-faves":
        config.minFaves = parseInt(args[++i], 10);
        break;
      case "--min-retweets":
        config.minRetweets = parseInt(args[++i], 10);
        break;
      case "--since":
        config.since = args[++i];
        break;
      case "--until":
        config.until = args[++i];
        break;
      case "--lang":
        config.lang = args[++i];
        break;
      case "--theme":
        // カンマ区切りで複数キーワード指定可能: --theme "AI,Claude,n8n"
        config.theme = args[++i].split(",").map((s) => s.trim()).filter(Boolean);
        break;
      case "--output":
        config.output = args[++i];
        break;
      case "--output-json":
        config.outputJson = args[++i];
        break;
      case "--cache-dir":
        config.cacheDir = args[++i];
        break;
      case "--no-cache":
        config.useCache = false;
        break;
      case "--from-cache":
        config.fromCache = true;
        break;
      case "--verbose":
        config.verbose = true;
        break;
      case "--help":
        printHelp();
        process.exit(0);
    }
  }

  // デフォルト日付: since = 1ヶ月前, until = 今日
  if (!config.since) {
    const d = new Date();
    d.setMonth(d.getMonth() - 1);
    config.since = formatDate(d);
  }
  if (!config.until) {
    config.until = formatDate(new Date());
  }

  // デフォルト出力パス
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
  if (!config.output) {
    config.output = path.join(
      __dirname,
      "output",
      `report-${timestamp}.md`
    );
  }
  if (!config.outputJson) {
    config.outputJson = path.join(
      __dirname,
      "output",
      `report-${timestamp}.json`
    );
  }

  return config;
}

function printHelp() {
  console.log(`
X Article Researcher - SocialData API を使ったX記事自動リサーチツール

使い方:
  node x-article-researcher.js [options]

オプション:
  --min-faves <number>     最小いいね数 (デフォルト: 1000)
  --min-retweets <number>  最小RT数 (デフォルト: 0)
  --since <YYYY-MM-DD>     開始日 (デフォルト: 1ヶ月前)
  --until <YYYY-MM-DD>     終了日 (デフォルト: 今日)
  --lang <ja|all>          言語フィルタ (デフォルト: ja)
  --theme <keywords>       テーマキーワード (カンマ区切り、例: "AI,Claude,n8n")
  --output <path>          Markdownレポート出力パス
  --output-json <path>     JSON出力パス
  --cache-dir <path>       キャッシュディレクトリ (デフォルト: ./cache)
  --no-cache               キャッシュを無効化
  --from-cache             キャッシュ済みデータのみで処理 (API不要)
  --verbose                詳細ログ出力
  --help                   ヘルプを表示

環境変数:
  SOCIALDATA_API_KEY       SocialData APIキー (必須)

例:
  node x-article-researcher.js --min-faves 500 --since 2026-03-01 --until 2026-04-01
  node x-article-researcher.js --min-faves 5000 --lang all
  node x-article-researcher.js --theme "AI,Claude,n8n"
`);
}

function formatDate(date) {
  return date.toISOString().slice(0, 10);
}

// =============================================================================
// ログユーティリティ
// =============================================================================
class Logger {
  constructor(verbose = false) {
    this.verbose = verbose;
    this.startTime = Date.now();
  }

  info(msg) {
    const elapsed = ((Date.now() - this.startTime) / 1000).toFixed(1);
    console.log(`[${elapsed}s] ${msg}`);
  }

  debug(msg) {
    if (this.verbose) {
      const elapsed = ((Date.now() - this.startTime) / 1000).toFixed(1);
      console.log(`[${elapsed}s] [DEBUG] ${msg}`);
    }
  }

  error(msg) {
    const elapsed = ((Date.now() - this.startTime) / 1000).toFixed(1);
    console.error(`[${elapsed}s] [ERROR] ${msg}`);
  }

  progress(current, total, label) {
    const pct = ((current / total) * 100).toFixed(0);
    const elapsed = ((Date.now() - this.startTime) / 1000).toFixed(1);
    process.stdout.write(
      `\r[${elapsed}s] ${label}: ${current}/${total} (${pct}%)`
    );
    if (current === total) process.stdout.write("\n");
  }
}

// =============================================================================
// キャッシュマネージャー
// =============================================================================
class CacheManager {
  constructor(cacheDir, enabled = true) {
    this.cacheDir = cacheDir;
    this.enabled = enabled;
    this.hits = 0;
    this.misses = 0;
    if (enabled) {
      fs.mkdirSync(path.join(cacheDir, "articles"), { recursive: true });
      fs.mkdirSync(path.join(cacheDir, "search"), { recursive: true });
    }
  }

  getArticle(tweetId) {
    if (!this.enabled) return null;
    const filePath = path.join(this.cacheDir, "articles", `${tweetId}.json`);
    try {
      const data = fs.readFileSync(filePath, "utf-8");
      this.hits++;
      return JSON.parse(data);
    } catch {
      this.misses++;
      return null;
    }
  }

  setArticle(tweetId, data) {
    if (!this.enabled) return;
    const filePath = path.join(this.cacheDir, "articles", `${tweetId}.json`);
    fs.writeFileSync(filePath, JSON.stringify(data, null, 2), "utf-8");
  }

  getStats() {
    return { hits: this.hits, misses: this.misses };
  }
}

// =============================================================================
// SocialData API クライアント
// =============================================================================
class SocialDataClient {
  constructor(apiKey, logger) {
    this.apiKey = apiKey;
    this.baseUrl = "api.socialdata.tools";
    this.logger = logger;
    this.requestCount = 0;
  }

  async request(endpoint, params = {}) {
    this.requestCount++;
    const query = new URLSearchParams(params).toString();
    const urlPath = query ? `${endpoint}?${query}` : endpoint;

    return new Promise((resolve, reject) => {
      const options = {
        hostname: this.baseUrl,
        path: urlPath,
        method: "GET",
        headers: {
          Authorization: `Bearer ${this.apiKey}`,
          Accept: "application/json",
        },
      };

      const req = https.request(options, (res) => {
        let data = "";
        res.on("data", (chunk) => (data += chunk));
        res.on("end", () => {
          if (res.statusCode === 200) {
            try {
              resolve(JSON.parse(data));
            } catch (e) {
              reject(new Error(`JSON parse error: ${e.message}`));
            }
          } else if (res.statusCode === 429) {
            reject(new Error("RATE_LIMIT"));
          } else if (res.statusCode === 402) {
            reject(new Error("INSUFFICIENT_BALANCE"));
          } else {
            reject(
              new Error(`API error ${res.statusCode}: ${data.slice(0, 200)}`)
            );
          }
        });
      });

      req.on("error", reject);
      req.setTimeout(30000, () => {
        req.destroy();
        reject(new Error("Request timeout"));
      });
      req.end();
    });
  }

  // ツイート検索（ページネーション対応）
  async searchTweets(query, maxResults = 10000) {
    const allTweets = [];
    let cursor = null;
    let page = 0;

    this.logger.info(`検索クエリ: ${query}`);

    do {
      page++;
      const params = { query };
      if (cursor) {
        params.cursor = cursor;
      }

      try {
        const response = await this.request(
          "/twitter/search",
          params
        );

        const tweets = response.tweets || [];
        allTweets.push(...tweets);
        cursor = response.next_cursor || null;

        this.logger.info(
          `  ページ${page}: ${tweets.length}件取得 (累計: ${allTweets.length}件)`
        );

        if (allTweets.length >= maxResults) {
          this.logger.info(`  最大件数(${maxResults})に到達、検索を終了`);
          break;
        }

        // レートリミット対策
        if (cursor) {
          await sleep(200);
        }
      } catch (e) {
        if (e.message === "RATE_LIMIT") {
          this.logger.info("  レートリミット検出、5秒待機...");
          await sleep(5000);
          continue;
        }
        if (e.message === "INSUFFICIENT_BALANCE") {
          this.logger.info(`  残高不足 - ${allTweets.length}件取得済みのデータで続行します`);
          break;
        }
        if (e.message.includes("ECONNRESET") || e.message.includes("ENOTFOUND") || e.message.includes("ETIMEDOUT") || e.message.includes("timeout")) {
          this.logger.info(`  ネットワークエラー: ${e.message} → 5秒後にリトライ...`);
          await sleep(5000);
          continue;
        }
        throw e;
      }
    } while (cursor);

    return allTweets;
  }

  // 記事詳細取得（リトライ付き）
  async getArticle(tweetId, retries = 3) {
    try {
      const response = await this.request(
        `/twitter/article/${tweetId}`
      );
      return response;
    } catch (e) {
      if (e.message === "RATE_LIMIT") {
        await sleep(5000);
        return this.getArticle(tweetId, retries);
      }
      if (e.message === "INSUFFICIENT_BALANCE") {
        this.logger.info("  残高不足 - 記事詳細の取得をスキップします");
        return null;
      }
      // ネットワークエラーはリトライ
      if (retries > 0 && (e.message.includes("ECONNRESET") || e.message.includes("ENOTFOUND") || e.message.includes("ETIMEDOUT") || e.message.includes("timeout"))) {
        this.logger.debug(`  ネットワークエラー (${tweetId}): ${e.message} → リトライ残${retries - 1}回`);
        await sleep(3000);
        return this.getArticle(tweetId, retries - 1);
      }
      throw e;
    }
  }
}

// =============================================================================
// 日本語判定フィルタ
// =============================================================================
function containsJapanese(text) {
  if (!text) return false;
  // ひらがな: \u3040-\u309F
  // カタカナ: \u30A0-\u30FF
  // 漢字(CJK統合漢字): \u4E00-\u9FFF
  // カタカナ拡張: \u31F0-\u31FF
  // 半角カタカナ: \uFF65-\uFF9F
  return /[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FFF\u31F0-\u31FF\uFF65-\uFF9F]/.test(
    text
  );
}

function isJapaneseUser(tweet) {
  const user = tweet.user || {};
  const name = user.name || "";
  const description = user.description || "";
  const location = user.location || "";

  // 名前、自己紹介文、場所のいずれかに日本語が含まれているか
  return (
    containsJapanese(name) ||
    containsJapanese(description) ||
    containsJapanese(location)
  );
}

// =============================================================================
// Draft.js → Markdown 変換
// =============================================================================
function draftjsToMarkdown(blocks) {
  if (!blocks || !Array.isArray(blocks)) return "";

  const lines = [];

  for (const block of blocks) {
    const text = block.text || "";
    const type = block.type || "unstyled";
    const inlineStyleRanges = block.inlineStyleRanges || [];
    const entityRanges = block.entityRanges || [];

    let processedText = text;

    // インラインスタイルの適用（逆順で処理して位置ずれを防ぐ）
    const sortedStyles = [...inlineStyleRanges].sort(
      (a, b) => b.offset - a.offset
    );
    for (const style of sortedStyles) {
      const start = style.offset;
      const end = start + style.length;
      const target = processedText.slice(start, end);

      switch (style.style) {
        case "BOLD":
          processedText =
            processedText.slice(0, start) +
            `**${target}**` +
            processedText.slice(end);
          break;
        case "ITALIC":
          processedText =
            processedText.slice(0, start) +
            `*${target}*` +
            processedText.slice(end);
          break;
        case "CODE":
          processedText =
            processedText.slice(0, start) +
            `\`${target}\`` +
            processedText.slice(end);
          break;
        case "STRIKETHROUGH":
          processedText =
            processedText.slice(0, start) +
            `~~${target}~~` +
            processedText.slice(end);
          break;
      }
    }

    // ブロックタイプに応じた変換
    switch (type) {
      case "header-one":
        lines.push(`# ${processedText}`);
        break;
      case "header-two":
        lines.push(`## ${processedText}`);
        break;
      case "header-three":
        lines.push(`### ${processedText}`);
        break;
      case "header-four":
        lines.push(`#### ${processedText}`);
        break;
      case "blockquote":
        lines.push(`> ${processedText}`);
        break;
      case "unordered-list-item":
        lines.push(`- ${processedText}`);
        break;
      case "ordered-list-item":
        lines.push(`1. ${processedText}`);
        break;
      case "code-block":
        lines.push("```");
        lines.push(processedText);
        lines.push("```");
        break;
      case "atomic":
        // 画像やエンベッドなどのアトミックブロック
        if (processedText.trim()) {
          lines.push(processedText);
        }
        break;
      default:
        // unstyled
        lines.push(processedText);
        break;
    }
  }

  return lines.join("\n");
}

// =============================================================================
// 記事データ処理
// =============================================================================
function extractArticleData(tweet, articleDetail) {
  const user = tweet.user || {};
  const tweetId = tweet.id_str || tweet.id || "";

  // 記事詳細から情報を抽出
  let title = "";
  let fullText = "";
  let previewText = "";
  let thumbnailUrl = "";

  if (articleDetail) {
    // APIレスポンスは { ...tweet, article: { title, content_state, ... } } の構造
    const article = articleDetail.article || articleDetail;

    title = article.title || "";
    previewText = article.preview_text || article.subtitle || "";
    thumbnailUrl =
      article.cover_url ||
      article.cover_image?.media_url_https ||
      article.thumbnail_url ||
      "";

    // Draft.jsブロックからMarkdownへ変換
    // content_state.blocks にDraft.jsブロックが格納されている
    if (article.content_state?.blocks) {
      fullText = draftjsToMarkdown(article.content_state.blocks);
    } else if (article.content_blocks) {
      fullText = draftjsToMarkdown(article.content_blocks);
    } else if (article.content) {
      if (typeof article.content === "string") {
        fullText = article.content;
      } else if (article.content.blocks) {
        fullText = draftjsToMarkdown(article.content.blocks);
      }
    }

    // タイトルがない場合、ツイートテキストから取得を試みる
    if (!title && tweet.full_text) {
      title = tweet.full_text.split("\n")[0].slice(0, 100);
    }
  }

  // エンゲージメントデータ
  // 検索結果のメトリクスと記事詳細のメトリクスをマージ
  const tweetMetrics = {
    likes: tweet.favorite_count || 0,
    retweets: tweet.retweet_count || 0,
    replies: tweet.reply_count || 0,
    quotes: tweet.quote_count || 0,
    bookmarks: tweet.bookmark_count || 0,
    views: tweet.views_count || tweet.view_count || 0,
  };

  // 記事詳細のメトリクスがあればそちらを優先（最新値）
  if (articleDetail) {
    const am = articleDetail.metrics || articleDetail;
    if (am.favorite_count !== undefined)
      tweetMetrics.likes = am.favorite_count;
    if (am.retweet_count !== undefined)
      tweetMetrics.retweets = am.retweet_count;
    if (am.reply_count !== undefined) tweetMetrics.replies = am.reply_count;
    if (am.quote_count !== undefined) tweetMetrics.quotes = am.quote_count;
    if (am.bookmark_count !== undefined)
      tweetMetrics.bookmarks = am.bookmark_count;
    if (am.view_count !== undefined || am.views_count !== undefined)
      tweetMetrics.views = am.view_count || am.views_count || tweetMetrics.views;
  }

  return {
    tweetId,
    title,
    fullText,
    previewText,
    thumbnailUrl,
    tweetUrl: `https://x.com/${user.screen_name}/status/${tweetId}`,
    createdAt: tweet.tweet_created_at || tweet.created_at || "",
    author: {
      name: user.name || "",
      screenName: user.screen_name || "",
      followersCount: user.followers_count || 0,
      profileImageUrl: user.profile_image_url_https || "",
      description: user.description || "",
    },
    engagement: tweetMetrics,
    isJapanese: isJapaneseUser(tweet),
    textLength: fullText.length,
    headingCount: (fullText.match(/^#{1,4}\s/gm) || []).length,
  };
}

// 重複除去（タイトル+著者でユニーク化、いいね最大を残す）
function deduplicateArticles(articles) {
  const map = new Map();

  for (const article of articles) {
    const key = `${article.title}::${article.author.screenName}`;
    const existing = map.get(key);

    if (!existing || article.engagement.likes > existing.engagement.likes) {
      map.set(key, article);
    }
  }

  return Array.from(map.values());
}

// エンゲージメント降順ソート
function sortByEngagement(articles) {
  return articles.sort((a, b) => {
    // まずいいね数で降順
    if (b.engagement.likes !== a.engagement.likes) {
      return b.engagement.likes - a.engagement.likes;
    }
    // 同数ならブックマーク数
    if (b.engagement.bookmarks !== a.engagement.bookmarks) {
      return b.engagement.bookmarks - a.engagement.bookmarks;
    }
    // 同数なら閲覧数
    return (b.engagement.views || 0) - (a.engagement.views || 0);
  });
}

// =============================================================================
// レポート生成
// =============================================================================
function generateMarkdownReport(articles, config, stats) {
  const lines = [];

  lines.push("# X記事リサーチレポート");
  lines.push("");
  lines.push(`**生成日時:** ${new Date().toLocaleString("ja-JP")}`);
  lines.push(`**検索条件:** いいね${config.minFaves}以上 | ${config.since} 〜 ${config.until}`);
  lines.push(
    `**言語フィルタ:** ${config.lang === "ja" ? "日本語のみ" : "すべて"}`
  );
  if (config.theme && config.theme.length > 0) {
    lines.push(`**テーマ:** ${config.theme.join(", ")}`);
  }
  lines.push("");

  // サマリー
  lines.push("## サマリー");
  lines.push("");
  lines.push(`| 項目 | 値 |`);
  lines.push(`|------|-----|`);
  lines.push(`| 検索ヒット数 | ${stats.totalSearchResults}件 |`);
  lines.push(`| 日本語記事 | ${stats.japaneseCount}件 |`);
  lines.push(`| その他言語 | ${stats.otherCount}件 |`);
  lines.push(`| 重複除去後 | ${articles.length}件 |`);
  if (stats.themeMatched !== null) {
    lines.push(`| テーマ該当 | ${stats.themeMatched}件 |`);
  }
  lines.push(
    `| APIコール数 | ${stats.apiCalls}回 |`
  );
  lines.push(
    `| キャッシュヒット | ${stats.cacheHits}件 |`
  );
  lines.push(
    `| 推定コスト | $${stats.estimatedCost.toFixed(4)} (約${Math.ceil(stats.estimatedCost * 150)}円) |`
  );
  lines.push("");

  // エンゲージメント統計
  if (articles.length > 0) {
    const totalLikes = articles.reduce(
      (s, a) => s + a.engagement.likes,
      0
    );
    const totalViews = articles.reduce(
      (s, a) => s + (a.engagement.views || 0),
      0
    );
    const avgLikes = Math.round(totalLikes / articles.length);
    const avgViews = Math.round(totalViews / articles.length);
    const maxLikes = Math.max(...articles.map((a) => a.engagement.likes));
    const maxViews = Math.max(
      ...articles.map((a) => a.engagement.views || 0)
    );

    lines.push("## エンゲージメント統計");
    lines.push("");
    lines.push(`| 指標 | 合計 | 平均 | 最大 |`);
    lines.push(`|------|------|------|------|`);
    lines.push(
      `| いいね | ${totalLikes.toLocaleString()} | ${avgLikes.toLocaleString()} | ${maxLikes.toLocaleString()} |`
    );
    lines.push(
      `| 閲覧数 | ${totalViews.toLocaleString()} | ${avgViews.toLocaleString()} | ${maxViews.toLocaleString()} |`
    );
    lines.push("");
  }

  // TOP20 一覧
  lines.push("## TOP20 記事一覧");
  lines.push("");

  const top20 = articles.slice(0, 20);
  for (let i = 0; i < top20.length; i++) {
    const a = top20[i];
    lines.push(`### ${i + 1}. ${a.title || "(タイトルなし)"}`);
    lines.push("");
    lines.push(`- **著者:** ${a.author.name} (@${a.author.screenName}) | フォロワー: ${a.author.followersCount.toLocaleString()}`);
    lines.push(`- **URL:** ${a.tweetUrl}`);
    lines.push(`- **投稿日:** ${a.createdAt}`);
    lines.push(
      `- **いいね:** ${a.engagement.likes.toLocaleString()} | **RT:** ${a.engagement.retweets.toLocaleString()} | **BM:** ${a.engagement.bookmarks.toLocaleString()} | **閲覧:** ${(a.engagement.views || 0).toLocaleString()}`
    );
    lines.push(`- **文字数:** ${a.textLength.toLocaleString()} | **見出し数:** ${a.headingCount}`);
    if (a.previewText) {
      lines.push(`- **プレビュー:** ${a.previewText.slice(0, 150)}...`);
    }
    lines.push("");
  }

  // 全記事一覧（簡易）
  if (articles.length > 20) {
    lines.push("## 全記事一覧");
    lines.push("");
    lines.push(
      `| # | タイトル | 著者 | いいね | BM | 閲覧数 | 文字数 |`
    );
    lines.push(`|---|---------|------|--------|-----|--------|--------|`);

    for (let i = 0; i < articles.length; i++) {
      const a = articles[i];
      const shortTitle =
        (a.title || "(タイトルなし)").length > 40
          ? (a.title || "(タイトルなし)").slice(0, 40) + "..."
          : a.title || "(タイトルなし)";
      lines.push(
        `| ${i + 1} | [${shortTitle}](${a.tweetUrl}) | @${a.author.screenName} | ${a.engagement.likes.toLocaleString()} | ${a.engagement.bookmarks.toLocaleString()} | ${(a.engagement.views || 0).toLocaleString()} | ${a.textLength.toLocaleString()} |`
      );
    }
    lines.push("");
  }

  // 全記事の全文テキスト
  lines.push("---");
  lines.push("");
  lines.push("## 全記事の全文テキスト");
  lines.push("");

  for (let i = 0; i < articles.length; i++) {
    const a = articles[i];
    lines.push(`### [${i + 1}] ${a.title || "(タイトルなし)"}`);
    lines.push("");
    lines.push(`> 著者: ${a.author.name} (@${a.author.screenName}) | いいね: ${a.engagement.likes.toLocaleString()} | 閲覧: ${(a.engagement.views || 0).toLocaleString()}`);
    lines.push("");
    if (a.fullText) {
      lines.push(a.fullText);
    } else {
      lines.push("*(全文テキストを取得できませんでした)*");
    }
    lines.push("");
    lines.push("---");
    lines.push("");
  }

  return lines.join("\n");
}

// =============================================================================
// ユーティリティ
// =============================================================================
function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

// =============================================================================
// キャッシュからの復元処理
// =============================================================================
async function runFromCache(config, log) {
  log.info("=== キャッシュからの復元モード ===");

  const articlesDir = path.join(config.cacheDir, "articles");
  if (!fs.existsSync(articlesDir)) {
    log.error("キャッシュディレクトリが見つかりません。先にリサーチを実行してください。");
    process.exit(1);
  }

  const files = fs.readdirSync(articlesDir).filter((f) => f.endsWith(".json"));
  log.info(`キャッシュ済み記事: ${files.length}件`);

  if (files.length === 0) {
    log.info("キャッシュに記事がありません。");
    process.exit(0);
  }

  ensureDir(path.dirname(config.output));

  const articles = [];
  let jaCount = 0;
  let otherCount = 0;

  for (const file of files) {
    try {
      const data = JSON.parse(
        fs.readFileSync(path.join(articlesDir, file), "utf-8")
      );

      // キャッシュはAPIレスポンス全体を保存しているので、tweetデータとして扱う
      const tweet = data;
      const isJa = isJapaneseUser(tweet);

      if (isJa) jaCount++;
      else otherCount++;

      // 言語フィルタ
      if (config.lang === "ja" && !isJa) continue;

      // いいね数フィルタ
      if ((tweet.favorite_count || 0) < config.minFaves) continue;

      const article = extractArticleData(tweet, data);
      articles.push(article);
    } catch (e) {
      log.debug(`キャッシュ読み込みエラー (${file}): ${e.message}`);
    }
  }

  log.info(`言語判定: 日本語 ${jaCount}件 / その他 ${otherCount}件`);
  log.info(`いいね${config.minFaves}以上: ${articles.length}件`);

  // 重複除去 & ソート
  const uniqueArticles = deduplicateArticles(articles);
  let finalArticles = sortByEngagement(uniqueArticles);

  // テーマフィルタ
  if (config.theme.length > 0) {
    log.info(`テーマフィルタ: ${config.theme.join(", ")}`);

    const themePatterns = config.theme.map(
      (kw) => new RegExp(kw.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "i")
    );

    finalArticles = finalArticles.filter((a) => {
      const searchText = [
        a.title,
        a.previewText,
        a.fullText,
        a.author.name,
        a.author.description,
      ]
        .filter(Boolean)
        .join(" ");
      return themePatterns.some((re) => re.test(searchText));
    });

    log.info(`テーマ該当: ${finalArticles.length}件`);
  }

  // レポート出力
  const stats = {
    totalSearchResults: files.length,
    japaneseCount: jaCount,
    otherCount: otherCount,
    themeMatched: config.theme.length > 0 ? finalArticles.length : null,
    apiCalls: 0,
    cacheHits: files.length,
    estimatedCost: 0,
  };

  const report = generateMarkdownReport(finalArticles, config, stats);
  fs.writeFileSync(config.output, report, "utf-8");
  log.info(`Markdownレポート: ${config.output}`);

  const jsonOutput = {
    meta: {
      generatedAt: new Date().toISOString(),
      config: {
        minFaves: config.minFaves,
        since: config.since,
        until: config.until,
        lang: config.lang,
        theme: config.theme.length > 0 ? config.theme : null,
      },
      stats,
    },
    articles: finalArticles,
  };
  fs.writeFileSync(config.outputJson, JSON.stringify(jsonOutput, null, 2), "utf-8");
  log.info(`JSONデータ: ${config.outputJson}`);

  log.info("");
  log.info("=== 完了（キャッシュモード） ===");
  log.info(`レポート対象: ${finalArticles.length}件`);
  log.info(`APIコスト: $0（キャッシュのみ使用）`);
}

// =============================================================================
// メイン処理
// =============================================================================
async function main() {
  const config = parseArgs(process.argv);
  const log = new Logger(config.verbose);

  // --from-cache モード: キャッシュ済みデータのみで処理
  if (config.fromCache) {
    return await runFromCache(config, log);
  }

  // APIキーチェック
  const apiKey = process.env.SOCIALDATA_API_KEY;
  if (!apiKey) {
    console.error(
      "エラー: SOCIALDATA_API_KEY 環境変数が設定されていません。"
    );
    console.error(
      "  export SOCIALDATA_API_KEY=your_api_key_here"
    );
    console.error(
      "  SocialData API: https://socialdata.tools で取得できます。"
    );
    process.exit(1);
  }

  log.info("=== X記事リサーチツール 開始 ===");
  log.info(`条件: いいね${config.minFaves}以上 | ${config.since} 〜 ${config.until}`);

  // 初期化
  const client = new SocialDataClient(apiKey, log);
  const cache = new CacheManager(config.cacheDir, config.useCache);
  ensureDir(path.dirname(config.output));

  // =========================================================================
  // ステップ1: 検索クエリの構築と実行
  // =========================================================================
  log.info("");
  log.info("--- ステップ1: 記事検索 ---");

  let query = `url:x.com/i/article min_faves:${config.minFaves} -filter:replies`;

  if (config.minRetweets > 0) {
    query += ` min_retweets:${config.minRetweets}`;
  }
  query += ` since:${config.since} until:${config.until}`;

  const tweets = await client.searchTweets(query);
  log.info(`検索結果: ${tweets.length}件`);

  if (tweets.length === 0) {
    log.info("記事が見つかりませんでした。条件を変更してください。");
    process.exit(0);
  }

  // =========================================================================
  // ステップ2: 日本語判定フィルタ
  // =========================================================================
  log.info("");
  log.info("--- ステップ2: 日本語判定 ---");

  const japaneseTweets = [];
  const otherTweets = [];

  for (const tweet of tweets) {
    if (isJapaneseUser(tweet)) {
      japaneseTweets.push(tweet);
    } else {
      otherTweets.push(tweet);
    }
  }

  log.info(`日本語候補: ${japaneseTweets.length}件`);
  log.info(`その他: ${otherTweets.length}件`);

  // 対象となるツイートを決定
  const targetTweets =
    config.lang === "ja" ? japaneseTweets : tweets;
  log.info(
    `記事詳細取得対象: ${targetTweets.length}件 (${config.lang === "ja" ? "日本語のみ" : "全言語"})`
  );

  // =========================================================================
  // ステップ3: 記事詳細の取得
  // =========================================================================
  log.info("");
  log.info("--- ステップ3: 記事詳細取得 ---");

  const articles = [];
  let cacheHitCount = 0;
  let apiCallCount = 0;

  for (let i = 0; i < targetTweets.length; i++) {
    const tweet = targetTweets[i];
    const tweetId = tweet.id_str || tweet.id || "";

    if (!tweetId) {
      log.debug(`ツイートIDが取得できませんでした (index: ${i})`);
      continue;
    }

    // キャッシュチェック
    let articleDetail = cache.getArticle(tweetId);

    if (articleDetail) {
      cacheHitCount++;
      log.debug(`キャッシュヒット: ${tweetId}`);
    } else {
      // API呼び出し
      try {
        articleDetail = await client.getArticle(tweetId);
        cache.setArticle(tweetId, articleDetail);
        apiCallCount++;

        // レートリミット対策
        if (i % 10 === 0 && i > 0) {
          await sleep(100);
        }
      } catch (e) {
        log.debug(`記事詳細取得失敗 (${tweetId}): ${e.message}`);
        articleDetail = null;
      }
    }

    const article = extractArticleData(tweet, articleDetail);
    articles.push(article);

    log.progress(i + 1, targetTweets.length, "記事詳細取得");
  }

  log.info(`API呼び出し: ${apiCallCount}件 | キャッシュヒット: ${cacheHitCount}件`);

  // =========================================================================
  // ステップ4: 重複除去 & ソート
  // =========================================================================
  log.info("");
  log.info("--- ステップ4: 重複除去 & ソート ---");

  const uniqueArticles = deduplicateArticles(articles);
  const sortedArticles = sortByEngagement(uniqueArticles);

  log.info(`重複除去: ${articles.length}件 → ${sortedArticles.length}件`);

  // =========================================================================
  // ステップ4.5: テーマフィルタ（--theme指定時）
  // =========================================================================
  let finalArticles = sortedArticles;

  if (config.theme.length > 0) {
    log.info("");
    log.info(`--- テーマフィルタ: ${config.theme.join(", ")} ---`);

    const themePatterns = config.theme.map(
      (kw) => new RegExp(kw.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "i")
    );

    finalArticles = sortedArticles.filter((a) => {
      const searchText = [
        a.title,
        a.previewText,
        a.fullText,
        a.author.name,
        a.author.description,
      ]
        .filter(Boolean)
        .join(" ");

      return themePatterns.some((re) => re.test(searchText));
    });

    log.info(
      `テーマ該当: ${finalArticles.length}件 / ${sortedArticles.length}件`
    );
  }

  // =========================================================================
  // ステップ5: レポート出力
  // =========================================================================
  log.info("");
  log.info("--- ステップ5: レポート出力 ---");

  const totalApiCalls = client.requestCount;
  const estimatedCost = totalApiCalls * 0.0002;

  const stats = {
    totalSearchResults: tweets.length,
    japaneseCount: japaneseTweets.length,
    otherCount: otherTweets.length,
    themeMatched: config.theme.length > 0 ? finalArticles.length : null,
    apiCalls: totalApiCalls,
    cacheHits: cacheHitCount,
    estimatedCost,
  };

  // Markdownレポート
  const report = generateMarkdownReport(finalArticles, config, stats);
  fs.writeFileSync(config.output, report, "utf-8");
  log.info(`Markdownレポート: ${config.output}`);

  // JSONデータ
  const jsonOutput = {
    meta: {
      generatedAt: new Date().toISOString(),
      config: {
        minFaves: config.minFaves,
        minRetweets: config.minRetweets,
        since: config.since,
        until: config.until,
        lang: config.lang,
        theme: config.theme.length > 0 ? config.theme : null,
      },
      stats,
    },
    articles: finalArticles,
  };
  fs.writeFileSync(
    config.outputJson,
    JSON.stringify(jsonOutput, null, 2),
    "utf-8"
  );
  log.info(`JSONデータ: ${config.outputJson}`);

  // 完了サマリー
  log.info("");
  log.info("=== 完了 ===");
  log.info(`検索ヒット数: ${stats.totalSearchResults}件`);
  log.info(`日本語記事: ${stats.japaneseCount}件`);
  log.info(`その他言語: ${stats.otherCount}件`);
  if (config.theme.length > 0) {
    log.info(`テーマ: ${config.theme.join(", ")}`);
    log.info(`テーマ該当: ${finalArticles.length}件`);
  }
  log.info(`レポート対象: ${finalArticles.length}件`);
  log.info(`APIコール数: ${stats.apiCalls}回`);
  log.info(
    `推定コスト: $${stats.estimatedCost.toFixed(4)} (約${Math.ceil(stats.estimatedCost * 150)}円)`
  );
}

main().catch((e) => {
  console.error(`致命的エラー: ${e.message}`);
  if (e.stack) console.error(e.stack);
  process.exit(1);
});
