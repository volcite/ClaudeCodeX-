import "dotenv/config";
import fs from "fs";
import path from "path";
import type { Manuscript } from "../src/NarrationVideo/types";

const GEMINI_API_KEY = process.env.GOOGLE_AI_API_KEY;
if (!GEMINI_API_KEY) {
  throw new Error("GOOGLE_AI_API_KEY is not set in .env");
}

// NanoBanana 2 = Gemini 2.5 Flash Image
const GEMINI_IMAGE_URL = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent?key=${GEMINI_API_KEY}`;

async function generateImage(
  prompt: string,
  artStyle: string,
  outputPath: string,
): Promise<void> {
  const fullPrompt = `Generate an image in ${artStyle} style. The image should be in 1280x720 landscape format, high quality, detailed. Maintain consistent ${artStyle} style throughout. IMPORTANT: Do NOT include any text, letters, numbers, words, labels, or captions in the image. Express all concepts purely through illustrations, icons, shapes, arrows, and colors only:\n\n${prompt}`;

  const MAX_ATTEMPTS = 3;
  let lastError: unknown = null;

  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    try {
      const response = await fetch(GEMINI_IMAGE_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ parts: [{ text: fullPrompt }] }],
          generationConfig: {
            responseModalities: ["IMAGE", "TEXT"],
            imageConfig: {
              aspectRatio: "16:9",
            },
          },
        }),
      });

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(
          `Gemini Image API error: ${response.status} ${errorText}`,
        );
      }

      const data = await response.json();
      const parts = data?.candidates?.[0]?.content?.parts ?? [];

      for (const part of parts) {
        if (part.inlineData) {
          const imageBuffer = Buffer.from(part.inlineData.data, "base64");
          fs.mkdirSync(path.dirname(outputPath), { recursive: true });
          fs.writeFileSync(outputPath, imageBuffer);
          console.log(`  Saved: ${outputPath}`);
          return;
        }
      }

      // No inlineData found — Gemini sometimes returns only text parts.
      const textParts = parts
        .map((p: { text?: string }) => p.text)
        .filter(Boolean)
        .join(" ")
        .slice(0, 200);
      throw new Error(
        `No image data in response${textParts ? ` (text: ${textParts})` : ""}`,
      );
    } catch (err) {
      lastError = err;
      const message = err instanceof Error ? err.message : String(err);
      if (attempt < MAX_ATTEMPTS) {
        const waitMs = 3000 * attempt;
        console.log(
          `  Attempt ${attempt}/${MAX_ATTEMPTS} failed: ${message}. Retrying in ${waitMs}ms...`,
        );
        await new Promise((r) => setTimeout(r, waitMs));
      }
    }
  }

  throw lastError instanceof Error
    ? lastError
    : new Error("Image generation failed after retries");
}

async function generateAllImages(manuscriptPath: string): Promise<void> {
  const manuscript: Manuscript = JSON.parse(
    fs.readFileSync(manuscriptPath, "utf-8"),
  );

  const artStyle = manuscript.artStyle || "photorealistic";
  console.log(`Generating ${manuscript.scenes.length} images (${artStyle})...`);

  for (const scene of manuscript.scenes) {
    console.log(`Scene ${scene.id}: ${scene.imagePrompt.slice(0, 60)}...`);
    const outputPath = path.resolve(`public/scenes/${scene.id}.png`);
    await generateImage(scene.imagePrompt, artStyle, outputPath);
    // Rate limiting: wait 2 seconds between requests
    await new Promise((r) => setTimeout(r, 2000));
  }

  console.log("All images generated.");
}

// CLI entry
const inputPath = process.argv[2] || "input/manuscript.json";
generateAllImages(inputPath).catch((err) => {
  console.error("Failed:", err);
  process.exit(1);
});
