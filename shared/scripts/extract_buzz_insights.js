#!/usr/bin/env node
/**
 * extract_buzz_insights.js
 * 最新のreport-*.jsonからTOP50バズ記事を分析し、
 * article_plannerが参照するdata/buzz_insights.jsonを生成する
 *
 * 使い方:
 *   node scripts/extract_buzz_insights.js
 */

const fs = require('fs');
const path = require('path');

const PROJECT_DIR = path.resolve(__dirname, '..');
const ARTICLE_OUTPUT_DIR = path.join(PROJECT_DIR, 'article', 'output');
const INSIGHTS_FILE = path.join(PROJECT_DIR, 'data', 'buzz_insights.json');
const TOP_N = 50;
const HIGH_BM_RATIO = 2.0; // BM/いいね比がこれ以上を「高保存率記事」と定義

// --- 最新レポートを検出 ---
function findLatestReport() {
  const files = fs.readdirSync(ARTICLE_OUTPUT_DIR)
    .filter(f => /^report-\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}\.json$/.test(f))
    .sort((a, b) => b.localeCompare(a));
  if (files.length === 0) throw new Error('report-*.json が見つかりません: ' + ARTICLE_OUTPUT_DIR);
  return path.join(ARTICLE_OUTPUT_DIR, files[0]);
}

// --- カテゴリ判定 ---
function categorize(article) {
  const text = ((article.title || '') + ' ' + (article.fullText || '')).toLowerCase();
  if (/claude|anthropic/i.test(text)) return 'Claude';
  if (/chatgpt|openai|gpt-[0-9]/i.test(text)) return 'ChatGPT/OpenAI';
  if (/gemini|gemma|google/i.test(text)) return 'Google AI';
  if (/llm|large language/i.test(text)) return 'LLM全般';
  if (/n8n|workflow|automat/i.test(text)) return '自動化/ワークフロー';
  if (/agent|エージェント/i.test(text)) return 'AIエージェント';
  if (/second brain|knowledge base|obsidian|rag/i.test(text)) return '知識管理';
  if (/ai|生成ai|機械学習/i.test(text)) return 'AI全般';
  return 'その他';
}

// --- コンテンツタイプ推定 ---
function detectContentType(article) {
  const title = (article.title || '').toLowerCase();
  const text = (article.fullText || '').toLowerCase();
  if (/how (i|to|we)|ways to|steps?|guide|設定|手順|やり方|ハウツー|\d+ (ways|tips|steps|hooks|tools)/i.test(title)) return 'ハウツー';
  if (/vs\.?|versus|比較|compare/i.test(title)) return '比較';
  if (/failed|失敗|mistake|wrong/i.test(title)) return '失敗談';
  if (/i (built|made|created|gave|replaced)|やってみた|使ってみた|体験/i.test(title)) return '体験談';
  if (/why|なぜ|理由|philosophy|思想/i.test(title)) return '思想/哲学';
  if (/release|update|launched|発表|発売|登場/i.test(title)) return '最新情報';
  if (/list|ranking|top \d+|\d+選/i.test(title)) return 'リスト';
  return 'その他';
}

// --- メイン処理 ---
function main() {
  const reportPath = findLatestReport();
  console.log('レポート:', path.basename(reportPath));

  const raw = JSON.parse(fs.readFileSync(reportPath, 'utf-8'));
  const articles = raw.articles || raw.results || raw;
  if (!Array.isArray(articles) || articles.length === 0) {
    throw new Error('articles 配列が空です');
  }

  // TOP50（いいね降順）
  const top50 = [...articles]
    .sort((a, b) => (b.engagement?.likes || 0) - (a.engagement?.likes || 0))
    .slice(0, TOP_N);

  // TOP50（ブックマーク降順）— いいね順では落ちる高保存記事を拾う
  const top50ByBM = [...articles]
    .sort((a, b) => (b.engagement?.bookmarks || 0) - (a.engagement?.bookmarks || 0))
    .slice(0, TOP_N);

  // 分析対象 = いいね順TOP50 ∪ BM順TOP50（重複除去）
  const seen = new Set();
  const analysisPool = [...top50, ...top50ByBM].filter(a => {
    if (seen.has(a.tweetId)) return false;
    seen.add(a.tweetId);
    return true;
  });

  // 基本統計
  const totalLikes = top50.reduce((s, a) => s + (a.engagement?.likes || 0), 0);
  const totalBM = top50.reduce((s, a) => s + (a.engagement?.bookmarks || 0), 0);
  const avgBmRatio = totalLikes > 0 ? totalBM / totalLikes : 0;

  // 高保存率記事（BM/いいね >= HIGH_BM_RATIO）— analysisPool全体から抽出
  const highBmArticles = analysisPool
    .map(a => {
      const likes = a.engagement?.likes || 0;
      const bm = a.engagement?.bookmarks || 0;
      const bmRatio = likes > 0 ? bm / likes : 0;
      return { ...a, _bmRatio: bmRatio };
    })
    .filter(a => a._bmRatio >= HIGH_BM_RATIO)
    .sort((a, b) => b._bmRatio - a._bmRatio);

  // カテゴリ別集計
  const categoryStats = {};
  analysisPool.forEach(a => {
    const cat = categorize(a);
    if (!categoryStats[cat]) categoryStats[cat] = { count: 0, totalLikes: 0, totalBM: 0 };
    categoryStats[cat].count++;
    categoryStats[cat].totalLikes += (a.engagement?.likes || 0);
    categoryStats[cat].totalBM += (a.engagement?.bookmarks || 0);
  });
  Object.values(categoryStats).forEach(s => {
    s.avgLikes = s.count > 0 ? Math.round(s.totalLikes / s.count) : 0;
    s.avgBmRatio = s.totalLikes > 0 ? parseFloat((s.totalBM / s.totalLikes).toFixed(2)) : 0;
  });

  // コンテンツタイプ別集計
  const typeStats = {};
  analysisPool.forEach(a => {
    const type = detectContentType(a);
    if (!typeStats[type]) typeStats[type] = { count: 0, totalLikes: 0, totalBM: 0 };
    typeStats[type].count++;
    typeStats[type].totalLikes += (a.engagement?.likes || 0);
    typeStats[type].totalBM += (a.engagement?.bookmarks || 0);
  });
  Object.values(typeStats).forEach(s => {
    s.avgLikes = s.count > 0 ? Math.round(s.totalLikes / s.count) : 0;
    s.avgBmRatio = s.totalLikes > 0 ? parseFloat((s.totalBM / s.totalLikes).toFixed(2)) : 0;
  });

  // 海外ハウツー記事（英語 × ハウツー）
  const overseasHowto = analysisPool.filter(a =>
    !a.isJapanese && detectContentType(a) === 'ハウツー'
  ).sort((a, b) => (b.engagement?.bookmarks || 0) - (a.engagement?.bookmarks || 0));

  // 日本語高パフォーマンス記事
  const jpTopArticles = analysisPool
    .filter(a => a.isJapanese)
    .sort((a, b) => (b.engagement?.likes || 0) - (a.engagement?.likes || 0))
    .slice(0, 10);

  // 繰り返しバズっているキーワード（タイトルから）
  const titleWords = analysisPool
    .map(a => a.title || '')
    .join(' ')
    .toLowerCase()
    .split(/[\s\-:.,!?「」。、]+/)
    .filter(w => w.length >= 3)
    .reduce((acc, w) => { acc[w] = (acc[w] || 0) + 1; return acc; }, {});
  const buzzKeywords = Object.entries(titleWords)
    .filter(([w, c]) => c >= 2 && !/^(the|and|for|how|you|your|that|this|with|from|have|are|was|were|been|will|can|not|but)$/.test(w))
    .sort((a, b) => b[1] - a[1])
    .slice(0, 20)
    .map(([word, count]) => ({ word, count }));

  // アウトプット構築
  const insights = {
    generated_at: new Date().toISOString(),
    source_report: path.basename(reportPath),
    analysis_period: {
      top_n: TOP_N,
      total_articles_in_report: articles.length,
      analysis_pool_size: analysisPool.length,
      note: 'いいね順TOP50 ∪ ブックマーク順TOP50の和集合を分析対象とする',
    },
    summary: {
      avg_bm_ratio_top50: parseFloat(avgBmRatio.toFixed(2)),
      high_bm_articles_count: highBmArticles.length,
      overseas_howto_count: overseasHowto.length,
      jp_articles_count: analysisPool.filter(a => a.isJapanese).length,
    },
    high_bm_articles: highBmArticles.slice(0, 15).map(a => ({
      title: a.title,
      likes: a.engagement?.likes || 0,
      bookmarks: a.engagement?.bookmarks || 0,
      bm_ratio: parseFloat(a._bmRatio.toFixed(2)),
      content_type: detectContentType(a),
      category: categorize(a),
      is_japanese: !!a.isJapanese,
      preview: (a.previewText || a.fullText || '').slice(0, 200),
      url: a.tweetUrl || '',
    })),
    overseas_howto_articles: overseasHowto.slice(0, 10).map(a => ({
      title: a.title,
      likes: a.engagement?.likes || 0,
      bookmarks: a.engagement?.bookmarks || 0,
      bm_ratio: parseFloat(((a.engagement?.bookmarks || 0) / Math.max(a.engagement?.likes || 1, 1)).toFixed(2)),
      category: categorize(a),
      preview: (a.previewText || a.fullText || '').slice(0, 300),
      url: a.tweetUrl || '',
    })),
    jp_top_articles: jpTopArticles.map(a => ({
      title: a.title,
      likes: a.engagement?.likes || 0,
      bookmarks: a.engagement?.bookmarks || 0,
      bm_ratio: parseFloat(((a.engagement?.bookmarks || 0) / Math.max(a.engagement?.likes || 1, 1)).toFixed(2)),
      content_type: detectContentType(a),
      preview: (a.previewText || a.fullText || '').slice(0, 200),
    })),
    category_stats: Object.entries(categoryStats)
      .sort((a, b) => b[1].avgBmRatio - a[1].avgBmRatio)
      .map(([name, s]) => ({ category: name, ...s })),
    content_type_stats: Object.entries(typeStats)
      .sort((a, b) => b[1].avgBmRatio - a[1].avgBmRatio)
      .map(([name, s]) => ({ type: name, ...s })),
    buzz_keywords: buzzKeywords,
    planning_hints: generatePlanningHints(highBmArticles, overseasHowto, typeStats, categoryStats),
  };

  fs.writeFileSync(INSIGHTS_FILE, JSON.stringify(insights, null, 2));
  console.log('buzz_insights.json 更新完了');
  console.log('  高保存率記事:', insights.high_bm_articles.length + '件');
  console.log('  海外ハウツー:', insights.overseas_howto_articles.length + '件');
  console.log('  最高BM率記事:', insights.high_bm_articles[0]?.title?.slice(0, 50) + ' (' + insights.high_bm_articles[0]?.bm_ratio + 'x)');
}

// --- 企画ヒント生成 ---
function generatePlanningHints(highBmArticles, overseasHowto, typeStats, categoryStats) {
  const hints = [];

  // 最高BM率コンテンツタイプ
  const topType = Object.entries(typeStats).sort((a, b) => b[1].avgBmRatio - a[1].avgBmRatio)[0];
  if (topType) {
    hints.push({
      type: 'content_type',
      insight: `「${topType[0]}」型の記事が最もブックマーク率が高い（平均BM率 ${topType[1].avgBmRatio}x）`,
      action: `次の記事企画では「${topType[0]}」型を優先的に採用する`,
    });
  }

  // 海外ハウツーパターン
  if (overseasHowto.length > 0) {
    const topHowto = overseasHowto[0];
    const bm = topHowto.engagement?.bookmarks || topHowto.bookmarks || 0;
    hints.push({
      type: 'overseas_pattern',
      insight: `海外ハウツートップ: "${topHowto.title?.slice(0, 60)}" (BM: ${bm})`,
      action: 'このテーマ・構成を日本語に転用したテーマを検討する',
    });
  }

  // 高BM率カテゴリ
  const topCat = Object.entries(categoryStats).sort((a, b) => (b[1].avgBmRatio||0) - (a[1].avgBmRatio||0))[0];
  if (topCat) {
    hints.push({
      type: 'category',
      insight: `「${topCat[0]}」カテゴリが最もBM率が高い（${topCat[1].avgBmRatio || 0}x）`,
      action: `${topCat[0]}関連テーマを優先的に採用する`,
    });
  }

  // 数字タイトルの効果
  const numberedArticles = highBmArticles.filter(a => /\d+/.test(a.title || ''));
  if (numberedArticles.length >= 2) {
    const avgBm = numberedArticles.reduce((s, a) => s + (a.bm_ratio || a._bmRatio || 0), 0) / numberedArticles.length;
    hints.push({
      type: 'title_pattern',
      insight: `数字を含むタイトルの高保存率記事が${numberedArticles.length}件（平均BM率 ${avgBm.toFixed(1)}x）`,
      action: 'タイトルに「○個の」「○ステップ」「○分で」などの数字を積極的に入れる',
    });
  }

  return hints;
}

try {
  main();
} catch (e) {
  console.error('エラー:', e.message);
  process.exit(1);
}
