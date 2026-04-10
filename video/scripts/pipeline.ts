import "dotenv/config";
import { execSync } from "child_process";
import fs from "fs";

function run(command: string): void {
  console.log(`\n${"=".repeat(60)}`);
  console.log(`> ${command}`);
  console.log("=".repeat(60));
  execSync(command, { stdio: "inherit" });
}

async function pipeline(): Promise<void> {
  const input = process.argv[2];
  const artStyle = process.argv[3] || "photorealistic";

  if (!input) {
    console.error(
      "Usage: npx tsx scripts/pipeline.ts <manuscript text or file> [artStyle]",
    );
    console.error(
      "\nArt styles: photorealistic, watercolor, oil painting, anime, pixel art,",
    );
    console.error(
      '            flat illustration, pencil sketch, 3D render, comic, ukiyo-e,',
    );
    console.error(
      '            impressionist, cyberpunk, "studio ghibli", pastel, pop art',
    );
    process.exit(1);
  }

  console.log(`Art style: ${artStyle}`);
  const manuscriptPath = "input/manuscript.json";

  // Step 1: Generate scenes from manuscript
  console.log("\n[Step 1/5] Generating scenes...");
  if (fs.existsSync(input) && input.endsWith(".json")) {
    fs.copyFileSync(input, manuscriptPath);
    console.log("Using existing manuscript JSON.");
  } else {
    const arg = fs.existsSync(input) ? input : `"${input}"`;
    run(`npx tsx scripts/generate-scenes.ts ${arg} "${artStyle}"`);
  }

  // Step 2: Generate images
  console.log("\n[Step 2/5] Generating images...");
  run(`npx tsx scripts/generate-images.ts ${manuscriptPath}`);

  // Step 3: Generate audio
  console.log("\n[Step 3/5] Generating audio...");
  run(`npx tsx scripts/generate-audio.ts ${manuscriptPath}`);

  // Step 4: Render video
  console.log("\n[Step 4/5] Rendering video...");
  run(`npx tsx scripts/render.ts ${manuscriptPath}`);

  // Step 5: Upload to GCS
  console.log("\n[Step 5/5] Uploading to GCS...");
  run(`npx tsx scripts/upload-gcs.ts out/video.mp4 ${manuscriptPath}`);

  console.log("\n" + "=".repeat(60));
  console.log("Pipeline completed!");
  console.log("=".repeat(60));
}

pipeline().catch((err) => {
  console.error("Pipeline failed:", err);
  process.exit(1);
});
