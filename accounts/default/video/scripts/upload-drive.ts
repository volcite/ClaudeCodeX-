import "dotenv/config";
import fs from "fs";
import path from "path";
import readline from "readline";
import { google } from "googleapis";
import type { Manuscript } from "../src/NarrationVideo/types";

const FOLDER_ID = process.env.GOOGLE_DRIVE_FOLDER_ID;
if (!FOLDER_ID) {
  throw new Error("GOOGLE_DRIVE_FOLDER_ID is not set in .env");
}

const REDIRECT_URI = "http://localhost:3456";
const TOKEN_PATH = path.resolve("credentials/oauth-token.json");

function prompt(question: string): Promise<string> {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer.trim());
    });
  });
}

async function getOAuth2Client() {
  const credPath = path.resolve("credentials/oauth-credentials.json");
  if (!fs.existsSync(credPath)) {
    throw new Error(
      `OAuth credentials not found at ${credPath}\n` +
        "1. Go to Google Cloud Console → APIs & Services → Credentials\n" +
        "2. Create OAuth 2.0 Client ID (Desktop app)\n" +
        "3. Download JSON and save as credentials/oauth-credentials.json",
    );
  }

  const cred = JSON.parse(fs.readFileSync(credPath, "utf-8"));
  const { client_id, client_secret } = cred.installed || cred.web;

  const oauth2Client = new google.auth.OAuth2(
    client_id,
    client_secret,
    REDIRECT_URI,
  );

  // Reuse saved token if available
  if (fs.existsSync(TOKEN_PATH)) {
    const token = JSON.parse(fs.readFileSync(TOKEN_PATH, "utf-8"));
    oauth2Client.setCredentials(token);

    // Check if token needs refresh
    if (token.expiry_date && token.expiry_date < Date.now()) {
      console.log("Refreshing access token...");
      const { credentials } = await oauth2Client.refreshAccessToken();
      oauth2Client.setCredentials(credentials);
      fs.writeFileSync(TOKEN_PATH, JSON.stringify(credentials, null, 2));
    }

    return oauth2Client;
  }

  // First-time auth: manual code entry
  const authUrl = oauth2Client.generateAuthUrl({
    access_type: "offline",
    scope: ["https://www.googleapis.com/auth/drive.file"],
    prompt: "consent",
  });

  console.log("\n=== Google Drive Authentication ===");
  console.log("Open the following URL in your browser:\n");
  console.log(authUrl);
  console.log(
    "\nAfter authorizing, you'll be redirected to a page that won't load.",
  );
  console.log(
    "Copy the FULL URL from the browser address bar (it contains ?code=...).\n",
  );

  // Accept code from env var, CLI arg (--code=xxx), or stdin prompt
  let code = process.env.GOOGLE_AUTH_CODE || "";
  for (const arg of process.argv) {
    if (arg.startsWith("--code=")) {
      code = arg.slice(7);
    }
  }
  if (!code) {
    const input = await prompt("Paste the redirect URL or code here: ");
    // Extract code from full URL or use as-is
    try {
      const url = new URL(input);
      code = url.searchParams.get("code") || input;
    } catch {
      code = input;
    }
  }

  const { tokens } = await oauth2Client.getToken(code);
  oauth2Client.setCredentials(tokens);

  // Save token for future use
  fs.writeFileSync(TOKEN_PATH, JSON.stringify(tokens, null, 2));
  console.log("Token saved. Future uploads will not require re-auth.\n");

  return oauth2Client;
}

async function uploadToDrive(
  videoPath: string,
  manuscriptPath?: string,
): Promise<void> {
  const auth = await getOAuth2Client();
  const drive = google.drive({ version: "v3", auth });

  let fileName = `video_${Date.now()}.mp4`;
  if (manuscriptPath && fs.existsSync(manuscriptPath)) {
    const manuscript: Manuscript = JSON.parse(
      fs.readFileSync(manuscriptPath, "utf-8"),
    );
    fileName = `${manuscript.title}_${Date.now()}.mp4`;
  }

  console.log(`Uploading ${videoPath} as "${fileName}"...`);

  const folderId = FOLDER_ID as string;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const res: any = await drive.files.create({
    requestBody: {
      name: fileName,
      parents: [folderId],
    },
    media: {
      mimeType: "video/mp4",
      body: fs.createReadStream(videoPath),
    },
    fields: "id, name, webViewLink",
  });

  console.log(`Uploaded: ${res.data.name}`);
  console.log(`  File ID: ${res.data.id}`);
  console.log(`  Link: ${res.data.webViewLink}`);
}

// CLI entry
const videoPath = process.argv[2] || "out/video.mp4";
const manuscriptPath = process.argv[3] || "input/manuscript.json";

if (!fs.existsSync(videoPath)) {
  console.error(`Video file not found: ${videoPath}`);
  process.exit(1);
}

uploadToDrive(videoPath, manuscriptPath).catch((err) => {
  console.error("Failed:", err);
  process.exit(1);
});
