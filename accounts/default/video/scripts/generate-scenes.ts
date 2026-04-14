import "dotenv/config";
import fs from "fs";
import path from "path";

const GEMINI_API_KEY = process.env.GOOGLE_AI_API_KEY;
if (!GEMINI_API_KEY) {
  throw new Error("GOOGLE_AI_API_KEY is not set in .env");
}

const GEMINI_TEXT_URL = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${GEMINI_API_KEY}`;

function buildSystemPrompt(artStyle: string): string {
  return `あなたは図解動画のディレクターです。
ユーザーから投稿の原稿テキストを受け取り、図解スタイルの解説動画用のシーン構成をJSON形式で出力してください。

指定された画風: ${artStyle}

## 図解動画の方針
この動画は「初心者でも理解できる、視覚的にわかりやすい図解動画」です。
原稿に専門用語や技術的な概念が含まれている場合は、噛み砕いて初心者向けに言い換えてください。
「つまり〜ということです」「簡単に言うと〜」のように補足を入れて、前提知識がなくても理解できるナレーションにしてください。
各シーンは以下のような図解要素を中心に構成してください：
- フローチャート・ステップ図（手順やプロセスの説明）
- 比較表・ビフォーアフター（違いを明確に見せる）
- リスト・チェックリスト（ポイントの整理）
- 数字・統計の視覚化（大きな数字やグラフ的表現）
- 概念図・関係図（要素同士のつながり）

出力するJSONは以下の形式です。必ず有効なJSONのみを出力し、それ以外のテキストは含めないでください。

{
  "title": "動画タイトル",
  "scenes": [
    {
      "id": 1,
      "imagePrompt": "英語で画像生成AIに渡すプロンプト。1280x720の横長画像として適切な構図を指定。",
      "narration": "この場面で読み上げるナレーションテキスト（日本語）",
      "durationSec": 5
    }
  ],
  "bgm": "background",
  "artStyle": "${artStyle}"
}

ルール:
- scenesは3〜8個程度に分割してください
- imagePromptは英語で、図解・インフォグラフィック的な構図を指示してください
- imagePromptの冒頭に必ず「${artStyle} style,」を付けてください
- imagePromptには「infographic layout,」「diagram,」「visual explanation,」などの図解キーワードを含めてください
- imagePromptには「Leave the bottom 20% of the frame clear or simple (no important elements)」を含め、下部に字幕スペースを確保してください
- **画像に文字・テキスト・ラベル・数字は一切含めないでください**。「no text, no labels, no letters, no numbers, no words, no captions, purely visual」を必ず含めてください。概念はイラスト・アイコン・図形・矢印・色分けだけで表現してください
- 最初のシーン（id:1）もテキストなしのビジュアルのみで構成してください（タイトルテキストは不要。テーマを象徴するアイコンやイラストで表現）
- narrationは1シーン30文字〜80文字程度にしてください
- narrationの口調はカジュアルで親しみやすい口語にしてください。専門用語はそのまま使わず、初心者にもわかる平易な言葉に置き換えてください
- durationSecはnarrationの長さに応じて3〜8秒で調整してください
- bgmは "background" 固定としてください
- artStyleは "${artStyle}" 固定としてください
- idは1から連番にしてください`;
}

async function generateScenes(
  manuscriptText: string,
  artStyle: string,
): Promise<void> {
  console.log("Generating scenes from manuscript...");
  console.log(`Art style: ${artStyle}`);
  console.log(`Input: ${manuscriptText.slice(0, 100)}...`);

  const systemPrompt = buildSystemPrompt(artStyle);

  const response = await fetch(GEMINI_TEXT_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [
        {
          role: "user",
          parts: [
            {
              text: `${systemPrompt}\n\n--- 原稿 ---\n${manuscriptText}`,
            },
          ],
        },
      ],
      generationConfig: {
        temperature: 0.7,
        responseMimeType: "application/json",
      },
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Gemini API error: ${response.status} ${errorText}`);
  }

  const data = await response.json();
  const jsonText = data.candidates[0].content.parts[0].text;

  // Gemini may return invalid JSON — attempt to repair common issues
  let manuscript: Record<string, unknown>;
  try {
    manuscript = JSON.parse(jsonText);
  } catch {
    // Strip markdown fences, trailing commas, and control characters
    const cleaned = jsonText
      .replace(/```json\s*/g, "")
      .replace(/```\s*/g, "")
      .replace(/,\s*([}\]])/g, "$1")
      .replace(/[\x00-\x1F\x7F]/g, (c: string) =>
        c === "\n" || c === "\t" ? c : "",
      )
      .trim();
    manuscript = JSON.parse(cleaned);
  }

  // Validate structure
  if (!manuscript.title || !Array.isArray(manuscript.scenes)) {
    throw new Error("Invalid manuscript structure from Gemini");
  }

  for (const scene of manuscript.scenes) {
    if (
      !scene.id ||
      !scene.imagePrompt ||
      !scene.narration ||
      !scene.durationSec
    ) {
      throw new Error(`Invalid scene structure: ${JSON.stringify(scene)}`);
    }
  }

  // Ensure artStyle is saved
  manuscript.artStyle = artStyle;

  const outputPath = path.resolve("input/manuscript.json");
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, JSON.stringify(manuscript, null, 2), "utf-8");

  console.log(`Generated ${manuscript.scenes.length} scenes`);
  console.log(`Saved to ${outputPath}`);
}

// CLI entry
const input = process.argv[2];
const artStyle = process.argv[3] || "16-bit pixel art RPG game";

if (!input) {
  console.error(
    'Usage: npx tsx scripts/generate-scenes.ts <text or file> [artStyle]\n\nArt styles: photorealistic, watercolor, oil painting, anime, pixel art,\n            flat illustration, pencil sketch, 3D render, comic, ukiyo-e,\n            impressionist, cyberpunk, "studio ghibli", pastel, pop art,\n            minimalist, retro, gothic, steampunk, vaporwave',
  );
  process.exit(1);
}

const text = fs.existsSync(input) ? fs.readFileSync(input, "utf-8") : input;
generateScenes(text, artStyle).catch((err) => {
  console.error("Failed:", err);
  process.exit(1);
});
