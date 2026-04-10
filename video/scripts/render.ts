import "dotenv/config";
import fs from "fs";
import path from "path";
import { bundle } from "@remotion/bundler";
import { renderMedia, selectComposition } from "@remotion/renderer";
import type { Manuscript } from "../src/NarrationVideo/types";

const FPS = 30;

async function render(manuscriptPath: string): Promise<string> {
  const manuscript: Manuscript = JSON.parse(
    fs.readFileSync(manuscriptPath, "utf-8"),
  );

  const totalDurationSec = manuscript.scenes.reduce(
    (sum, scene) => sum + scene.durationSec,
    0,
  );
  const durationInFrames = Math.round(totalDurationSec * FPS);

  console.log(`Rendering "${manuscript.title}"`);
  console.log(`  Scenes: ${manuscript.scenes.length}`);
  console.log(`  Duration: ${totalDurationSec}s (${durationInFrames} frames)`);

  // Bundle the Remotion project
  console.log("Bundling...");
  const bundleLocation = await bundle({
    entryPoint: path.resolve("src/index.ts"),
    publicDir: path.resolve("public"),
  });

  // Select composition
  const composition = await selectComposition({
    serveUrl: bundleLocation,
    id: "NarrationVideo",
    inputProps: { manuscript },
  });

  // Override duration based on manuscript
  composition.durationInFrames = durationInFrames;
  composition.fps = FPS;
  composition.width = 1280;
  composition.height = 720;

  // Render
  const outputPath = path.resolve("out/video.mp4");
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });

  console.log("Rendering video...");
  await renderMedia({
    composition,
    serveUrl: bundleLocation,
    codec: "h264",
    outputLocation: outputPath,
    inputProps: { manuscript },
    enforceAudioTrack: true,
  });

  console.log(`Rendered: ${outputPath}`);
  return outputPath;
}

// CLI entry
const inputPath = process.argv[2] || "input/manuscript.json";
render(inputPath).catch((err) => {
  console.error("Failed:", err);
  process.exit(1);
});
