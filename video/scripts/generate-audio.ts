import "dotenv/config";
import fs from "fs";
import path from "path";
import { execSync } from "child_process";
import type { Manuscript } from "../src/NarrationVideo/types";

const FISH_AUDIO_API_KEY = process.env.FISH_AUDIO_API_KEY;
const FISH_AUDIO_VOICE_ID = process.env.FISH_AUDIO_VOICE_ID;

if (!FISH_AUDIO_API_KEY) {
  throw new Error("FISH_AUDIO_API_KEY is not set in .env");
}
if (!FISH_AUDIO_VOICE_ID) {
  throw new Error("FISH_AUDIO_VOICE_ID is not set in .env");
}

const FISH_AUDIO_URL = "https://api.fish.audio/v1/tts";

async function generateAudio(text: string, outputPath: string): Promise<void> {
  const response = await fetch(FISH_AUDIO_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${FISH_AUDIO_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      text,
      reference_id: FISH_AUDIO_VOICE_ID,
      format: "mp3",
      speed: 1.7,
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`FishAudio API error: ${response.status} ${errorText}`);
  }

  const arrayBuffer = await response.arrayBuffer();
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, Buffer.from(arrayBuffer));
  console.log(`  Saved: ${outputPath}`);
}

function getAudioDuration(filePath: string): number {
  try {
    // Use ffprobe to get audio duration
    const result = execSync(
      `ffprobe -v quiet -show_entries format=duration -of csv=p=0 "${filePath}"`,
      { encoding: "utf-8" },
    );
    return parseFloat(result.trim());
  } catch {
    console.warn(`  Could not detect duration for ${filePath}, using default`);
    return 5;
  }
}

async function generateAllAudio(manuscriptPath: string): Promise<void> {
  const manuscript: Manuscript = JSON.parse(
    fs.readFileSync(manuscriptPath, "utf-8"),
  );

  console.log(`Generating audio for ${manuscript.scenes.length} scenes...`);

  for (const scene of manuscript.scenes) {
    console.log(`Scene ${scene.id}: "${scene.narration.slice(0, 30)}..."`);
    const outputPath = path.resolve(`public/audio/${scene.id}.mp3`);
    await generateAudio(scene.narration, outputPath);

    // Adjust durationSec based on actual audio length
    const audioDuration = getAudioDuration(outputPath);
    const newDuration = Math.ceil(audioDuration); // no padding between scenes
    if (newDuration !== scene.durationSec) {
      console.log(`  Duration adjusted: ${scene.durationSec}s → ${newDuration}s`);
      scene.durationSec = newDuration;
    }

    // Rate limiting
    await new Promise((r) => setTimeout(r, 1000));
  }

  // Save updated manuscript with adjusted durations
  fs.writeFileSync(manuscriptPath, JSON.stringify(manuscript, null, 2), "utf-8");
  console.log("All audio generated. Manuscript updated with actual durations.");
}

// CLI entry
const inputPath = process.argv[2] || "input/manuscript.json";
generateAllAudio(inputPath).catch((err) => {
  console.error("Failed:", err);
  process.exit(1);
});
