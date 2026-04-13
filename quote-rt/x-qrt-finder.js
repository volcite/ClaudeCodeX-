#!/usr/bin/env node
// =============================================================================
// X Quote RT Finder - 今日のバズ投稿を検索して引用RT候補を取得
// =============================================================================
// 使い方:
//   node x-qrt-finder.js [options]
//
// オプション:
//   --min-faves <number>   最小いいね数 (デフォルト: 50)
//   --max <number>         最大取得候補数 (デフォルト: 10)
//   --output <path>        出力JSONパス (デフォルト: ./data/candidates.json)
//   --verbose              詳細ログ出力
// =============================================================================

const https = require("https");
const fs = require("fs");
const path = require("path");

// =============================================================================
// 安全フィルター: 炎上・政治・宗教・誹謗中傷を除外するキーワード
// =============================================================================
const SAFETY_BLACKLIST = [
  // 政治
  "自民党", "民主党", "維新の会", "公明党", "共産党", "れいわ", "参政党",
  "選挙", "国会議員", "内閣", "首相", "総理大臣", "衆議院", "参議院",
  "政権交代", "与党", "野党", "岸田", "石破", "菅", "安倍",
  // 宗教
  "統一教会", "創価学会", "エホバの証人", "オウム", "宗教法人",
  "信仰", "礼拝", "洗脳", "カルト",
  // 炎上・誹謗中傷・ヘイト
  "炎上", "誹謗中傷", "ヘイトスピーチ", "差別発言", "差別主義",
  "レイシスト", "差別的", "侮辱", "暴言", "バッシング",
  // 明らかに不適切な表現
  "死ね", "消えろ", "殺す", "ぶっ殺",
];

// 検索クエリ一覧（ペルソナに合わせたニッチ）
// 今日の日付で絞り込む
function buildSearchQueries(sinceDate, untilDate, minFaves) {
  return [
    // 日本語: AI/自動化/n8n系
    `(AI OR Claude OR n8n OR 生成AI OR 自動化 OR ChatGPT OR "Claude Code") min_faves:${minFaves} -filter:replies lang:ja since:${sinceDate} until:${untilDate}`,
    // 日本語: マーケティング/コンテンツ販売系
    `(マーケティング OR コンテンツ販売 OR "SNS運用" OR フリーランス OR "Note") min_faves:${minFaves} -filter:replies lang:ja since:${sinceDate} until:${untilDate}`,
    // 英語: 影響力のある公式アカウント
    `(from:claudeai OR from:n8n_io OR from:AnthropicAI OR from:OpenAI) min_faves:${minFaves} -filter:replies since:${sinceDate} until:${untilDate}`,
  ];
}

// =============================================================================
// .env 読み込み
// =============================================================================
function loadEnv() {
  const envPath = path.join(__dirname, "..", ".env");
  if (fs.existsSync(envPath)) {
    const lines = fs.readFileSync(envPath, "utf-8").split("\n");
    for (const line of lines) {
      const m = line.match(/^([A-Z0-9_]+)="?([^"#\n]*)"?\s*$/);
      if (m && !process.env[m[1]]) {
        process.env[m[1]] = m[2].trim();
      }
    }
  }
}

// =============================================================================
// CLI引数パース
// =============================================================================
function parseArgs(argv) {
  const args = argv.slice(2);
  const config = {
    minFaves: 100,
    maxCandidates: 10,
    verbose: false,
    outputJson: path.join(__dirname, "data", "candidates.json"),
  };

  for (let i = 0; i < args.length; i++) {
    switch (args[i]) {
      case "--min-faves":
        config.minFaves = parseInt(args[++i], 10);
        break;
      case "--max":
        config.maxCandidates = parseInt(args[++i], 10);
        break;
      case "--output":
        config.outputJson = args[++i];
        break;
      case "--verbose":
        config.verbose = true;
        break;
      case "--help":
        console.log(`
X Quote RT Finder

使い方:
  node x-qrt-finder.js [options]

オプション:
  --min-faves <number>   最小いいね数 (デフォルト: 50)
  --max <number>         最大候補数 (デフォルト: 10)
  --output <path>        出力JSONパス
  --verbose              詳細ログ
        `);
        process.exit(0);
    }
  }
  return config;
}

// =============================================================================
// ユーティリティ
// =============================================================================
function formatDate(date) {
  return date.toISOString().slice(0, 10);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function getTweetUrl(tweet) {
  const username =
    tweet.user?.screen_name ||
    tweet.author?.username ||
    tweet.author_id ||
    "unknown";
  const id = tweet.id_str || tweet.id || "";
  return `https://twitter.com/${username}/status/${id}`;
}

// =============================================================================
// ロガー
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
}

// =============================================================================
// SocialData API クライアント（軽量版）
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

  // ツイート検索（最大 maxResults 件で打ち切り）
  async searchTweets(query, maxResults = 50) {
    const allTweets = [];
    let cursor = null;
    let page = 0;

    this.logger.debug(`検索クエリ: ${query}`);

    do {
      page++;
      const params = { query };
      if (cursor) params.cursor = cursor;

      try {
        const response = await this.request("/twitter/search", params);
        const tweets = response.tweets || [];
        allTweets.push(...tweets);
        cursor = response.next_cursor || null;

        this.logger.debug(
          `  ページ${page}: ${tweets.length}件取得 (累計: ${allTweets.length}件)`
        );

        if (allTweets.length >= maxResults) {
          this.logger.debug(`  上限(${maxResults})到達、検索終了`);
          break;
        }

        if (cursor) await sleep(300);
      } catch (e) {
        if (e.message === "RATE_LIMIT") {
          this.logger.info("  レートリミット → 5秒待機...");
          await sleep(5000);
          continue;
        }
        if (e.message === "INSUFFICIENT_BALANCE") {
          this.logger.info(
            `  残高不足 - ${allTweets.length}件取得済みのデータで続行`
          );
          break;
        }
        if (
          e.message.includes("ECONNRESET") ||
          e.message.includes("ENOTFOUND") ||
          e.message.includes("timeout")
        ) {
          this.logger.info(`  ネットワークエラー: ${e.message} → リトライ...`);
          await sleep(3000);
          continue;
        }
        this.logger.error(`検索エラー: ${e.message}`);
        break;
      }
    } while (cursor);

    return allTweets;
  }
}

// =============================================================================
// 安全チェック
// =============================================================================
function isSafe(tweet) {
  const text = (tweet.full_text || tweet.text || "").toLowerCase();
  const authorHandle = (
    tweet.user?.screen_name ||
    tweet.author?.username ||
    ""
  ).toLowerCase();

  // 自分自身の投稿は除外
  if (authorHandle === "ai_yorozuya") return false;

  // RTは除外（引用RTの引用RTにならないよう）
  if (tweet.retweeted_status) return false;
  if (text.startsWith("rt @")) return false;

  // 安全ブラックリストチェック
  for (const keyword of SAFETY_BLACKLIST) {
    if (text.includes(keyword.toLowerCase())) {
      return false;
    }
  }

  return true;
}

// =============================================================================
// ツイートの正規化
// =============================================================================
function normalizeTweet(tweet) {
  const username =
    tweet.user?.screen_name || tweet.author?.username || "unknown";
  const displayName =
    tweet.user?.name || tweet.author?.name || username;
  const id = tweet.id_str || String(tweet.id || "");
  const text = tweet.full_text || tweet.text || "";
  const likes = tweet.favorite_count || tweet.public_metrics?.like_count || 0;
  const retweets =
    tweet.retweet_count || tweet.public_metrics?.retweet_count || 0;
  const replies =
    tweet.reply_count || tweet.public_metrics?.reply_count || 0;
  const createdAt = tweet.created_at || "";

  return {
    id,
    tweet_url: `https://twitter.com/${username}/status/${id}`,
    author_handle: `@${username}`,
    author_name: displayName,
    text,
    likes,
    retweets,
    replies,
    created_at: createdAt,
  };
}

// =============================================================================
// メイン処理
// =============================================================================
async function main() {
  loadEnv();

  const config = parseArgs(process.argv);
  const logger = new Logger(config.verbose);

  const apiKey = process.env.SOCIALDATA_API_KEY;
  if (!apiKey) {
    logger.error("SOCIALDATA_API_KEY が設定されていません（.env を確認）");
    process.exit(1);
  }

  // 今日の日付範囲（JST → UTC は -9h だが、SocialData は日付文字列で対応）
  const today = new Date();
  const sinceDate = formatDate(today);
  const tomorrow = new Date(today);
  tomorrow.setDate(today.getDate() + 1);
  const untilDate = formatDate(tomorrow);

  logger.info(`=== X Quote RT Finder ===`);
  logger.info(`対象日: ${sinceDate}`);
  logger.info(`最小いいね: ${config.minFaves}`);
  logger.info(`最大候補数: ${config.maxCandidates}`);

  const client = new SocialDataClient(apiKey, logger);
  const queries = buildSearchQueries(sinceDate, untilDate, config.minFaves);
  const allTweets = new Map(); // id → tweet (重複排除)

  for (let i = 0; i < queries.length; i++) {
    logger.info(`\n[検索 ${i + 1}/${queries.length}]`);
    logger.info(queries[i]);

    try {
      const tweets = await client.searchTweets(queries[i], 50);
      logger.info(`  取得: ${tweets.length}件`);

      for (const tweet of tweets) {
        const normalized = normalizeTweet(tweet);
        if (!allTweets.has(normalized.id)) {
          allTweets.set(normalized.id, { raw: tweet, normalized });
        }
      }
    } catch (e) {
      logger.error(`検索${i + 1}でエラー: ${e.message}`);
    }

    if (i < queries.length - 1) await sleep(500);
  }

  logger.info(`\n取得合計: ${allTweets.size}件（重複排除済み）`);

  // 安全フィルター適用
  const safeTweets = [];
  let unsafeCount = 0;

  for (const { raw, normalized } of allTweets.values()) {
    if (isSafe(raw)) {
      safeTweets.push(normalized);
    } else {
      unsafeCount++;
      logger.debug(`除外: ${normalized.tweet_url} (安全フィルター)`);
    }
  }

  logger.info(`安全フィルター後: ${safeTweets.length}件（除外: ${unsafeCount}件）`);

  // いいね数で降順ソート → 上位 maxCandidates 件
  safeTweets.sort((a, b) => b.likes - a.likes);
  const candidates = safeTweets.slice(0, config.maxCandidates);

  logger.info(`候補数: ${candidates.length}件`);
  if (config.verbose) {
    for (const c of candidates) {
      logger.debug(`  ♥${c.likes} ${c.author_handle} ${c.tweet_url}`);
    }
  }

  // 出力先ディレクトリ作成
  const outputDir = path.dirname(config.outputJson);
  fs.mkdirSync(outputDir, { recursive: true });

  const output = {
    date: sinceDate,
    fetched_at: new Date().toISOString(),
    min_faves: config.minFaves,
    total_fetched: allTweets.size,
    total_safe: safeTweets.length,
    candidates,
  };

  fs.writeFileSync(config.outputJson, JSON.stringify(output, null, 2), "utf-8");
  logger.info(`\n保存完了: ${config.outputJson}`);
  logger.info(`APIリクエスト数: ${client.requestCount}件`);

  if (candidates.length === 0) {
    logger.info("候補が0件のため、引用RTはスキップされます");
    process.exit(2); // 候補なしの場合は終了コード2
  }

  process.exit(0);
}

main().catch((e) => {
  console.error("致命的エラー:", e.message);
  process.exit(1);
});
