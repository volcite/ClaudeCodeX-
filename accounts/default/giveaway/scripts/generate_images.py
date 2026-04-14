#!/usr/bin/env python3
"""
プレゼント企画の画像を Gemini API で自動生成するスクリプト。
giveaway_note_draft.json の image_placeholders + サムネイルを生成し、
giveaway/data/images/ に保存する。

使い方:
  python3 giveaway/scripts/generate_images.py

前提:
  - .env に GEMINI_API_KEY が設定済み
  - giveaway/data/giveaway_note_draft.json が存在する

出力:
  - giveaway/data/images/thumbnail.png
  - giveaway/data/images/section_1.png, section_2.png, ...
  - giveaway/data/images/manifest.json (生成結果一覧)
"""

import base64
import json
import os
import sys
import time
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError

GIVEAWAY_DIR = Path(__file__).resolve().parent.parent  # giveaway/
PROJECT_ROOT = GIVEAWAY_DIR.parent                      # project root
DATA_DIR = GIVEAWAY_DIR / "data"
IMAGES_DIR = DATA_DIR / "images"
DRAFT_PATH = DATA_DIR / "giveaway_note_draft.json"
PLAN_PATH = DATA_DIR / "giveaway_plan.json"
MANIFEST_PATH = IMAGES_DIR / "manifest.json"

DEFAULT_GEMINI_MODEL = "gemini-2.5-flash-image"
GEMINI_API_BASE = "https://generativelanguage.googleapis.com/v1beta/models"


def load_env():
    """プロジェクトの .env から環境変数を読み込む"""
    env_path = PROJECT_ROOT / ".env"
    if env_path.exists():
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    key, _, value = line.partition("=")
                    os.environ.setdefault(key.strip(), value.strip())


def get_api_key():
    api_key = os.environ.get("GEMINI_API_KEY", "")
    if not api_key:
        print("エラー: GEMINI_API_KEY が設定されていません。")
        print("  .env に GEMINI_API_KEY=your_key を追加してください。")
        sys.exit(1)
    return api_key


def load_draft():
    if not DRAFT_PATH.exists():
        print(f"エラー: {DRAFT_PATH} が見つかりません。")
        sys.exit(1)
    with open(DRAFT_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def load_plan():
    if not PLAN_PATH.exists():
        return {}
    with open(PLAN_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def build_thumbnail_prompt(draft, plan):
    """サムネイル画像用のプロンプトを生成"""
    title = draft.get("note_title", "")
    theme = plan.get("theme", draft.get("theme", ""))

    return (
        f"Create a clean, modern, professional blog thumbnail image. "
        f"The theme is: '{theme}'. "
        f"Style: minimalist tech/business design with a gradient background. "
        f"Use cool blue and purple tones. "
        f"Include abstract geometric shapes or icons related to AI, automation, and technology. "
        f"Do NOT include any text or letters in the image. "
        f"The image should be eye-catching and suitable for a Japanese tech blog article. "
        f"Aspect ratio: 16:9, high quality."
    )


def build_section_image_prompt(placeholder):
    """セクション画像用のプロンプトを生成"""
    description = placeholder.get("description", "")
    img_type = placeholder.get("type", "concept")

    type_instructions = {
        "diagram": "Create a clean, simple diagram or flowchart illustration. ",
        "screenshot": "Create a clean UI mockup or interface illustration. ",
        "infographic": "Create a clean, data-visualization style infographic illustration. ",
        "concept": "Create a clean, modern concept illustration. ",
        "thumbnail": "Create a clean, modern thumbnail illustration. ",
    }

    base_instruction = type_instructions.get(img_type, type_instructions["concept"])

    return (
        f"{base_instruction}"
        f"Subject: {description}. "
        f"Style: flat design, minimalist, professional, tech-themed. "
        f"Color palette: blue, purple, and white tones. "
        f"Do NOT include any text, letters, or Japanese characters in the image. "
        f"High quality, suitable for a blog article."
    )


def get_gemini_model():
    """環境変数またはデフォルトからGeminiモデル名を取得"""
    return os.environ.get("GEMINI_IMAGE_MODEL", DEFAULT_GEMINI_MODEL)


def generate_image(api_key, prompt, output_path, retries=2):
    """Gemini API で画像を生成して保存する"""
    model = get_gemini_model()
    url = f"{GEMINI_API_BASE}/{model}:generateContent?key={api_key}"

    payload = json.dumps({
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {
            "responseModalities": ["IMAGE", "TEXT"],
        },
    }).encode("utf-8")

    headers = {"Content-Type": "application/json"}

    for attempt in range(retries + 1):
        try:
            req = Request(url, data=payload, headers=headers, method="POST")
            with urlopen(req, timeout=120) as resp:
                result = json.loads(resp.read().decode("utf-8"))

            # レスポンスから画像データを抽出
            candidates = result.get("candidates", [])
            if not candidates:
                print(f"  警告: 画像生成の候補が空です（attempt {attempt + 1}）")
                if attempt < retries:
                    time.sleep(3)
                    continue
                return False

            parts = candidates[0].get("content", {}).get("parts", [])
            for part in parts:
                inline_data = part.get("inlineData", {})
                if inline_data.get("mimeType", "").startswith("image/"):
                    image_bytes = base64.b64decode(inline_data["data"])
                    output_path.parent.mkdir(parents=True, exist_ok=True)
                    with open(output_path, "wb") as f:
                        f.write(image_bytes)
                    return True

            print(f"  警告: レスポンスに画像データが含まれていません（attempt {attempt + 1}）")
            if attempt < retries:
                time.sleep(3)
                continue
            return False

        except HTTPError as e:
            body = e.read().decode("utf-8", errors="replace") if e.fp else ""
            print(f"  API エラー (HTTP {e.code}): {body[:200]}")
            if e.code == 429:
                wait = 10 * (attempt + 1)
                print(f"  レートリミット。{wait}秒待機...")
                time.sleep(wait)
            elif attempt < retries:
                time.sleep(3)
            else:
                return False
        except Exception as e:
            print(f"  エラー: {e}")
            if attempt < retries:
                time.sleep(3)
            else:
                return False

    return False


def main():
    print("=" * 50)
    print("プレゼント企画 画像生成スクリプト")
    print("=" * 50)

    load_env()
    api_key = get_api_key()
    model = get_gemini_model()
    print(f"使用モデル: {model}")
    draft = load_draft()
    plan = load_plan()

    IMAGES_DIR.mkdir(parents=True, exist_ok=True)

    manifest = {
        "campaign_id": draft.get("campaign_id", ""),
        "generated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "images": [],
    }

    # ──────────────────────────────────────
    # 1. サムネイル画像の生成（必須）
    # ──────────────────────────────────────
    print("\n[1] サムネイル画像を生成中...")
    thumb_prompt = build_thumbnail_prompt(draft, plan)
    thumb_path = IMAGES_DIR / "thumbnail.png"
    print(f"  プロンプト: {thumb_prompt[:80]}...")

    if generate_image(api_key, thumb_prompt, thumb_path):
        size_kb = thumb_path.stat().st_size / 1024
        print(f"  → 保存完了: {thumb_path} ({size_kb:.0f}KB)")
        manifest["images"].append({
            "type": "thumbnail",
            "path": str(thumb_path),
            "prompt": thumb_prompt,
            "success": True,
        })
    else:
        print("  → サムネイル生成に失敗しました")
        manifest["images"].append({
            "type": "thumbnail",
            "path": "",
            "prompt": thumb_prompt,
            "success": False,
        })

    time.sleep(3)

    # ──────────────────────────────────────
    # 2. セクション画像の生成（プレースホルダーがある場合）
    # ──────────────────────────────────────
    placeholders = draft.get("image_placeholders", [])
    if placeholders:
        print(f"\n[2] セクション画像を生成中（{len(placeholders)}枚）...")
        for i, ph in enumerate(placeholders, 1):
            img_path = IMAGES_DIR / f"section_{i}.png"
            prompt = build_section_image_prompt(ph)
            position = ph.get("position", f"section_{i}")
            print(f"\n  [{i}/{len(placeholders)}] {position}")
            print(f"  プロンプト: {prompt[:80]}...")

            if generate_image(api_key, prompt, img_path):
                size_kb = img_path.stat().st_size / 1024
                print(f"  → 保存完了: {img_path} ({size_kb:.0f}KB)")
                manifest["images"].append({
                    "type": ph.get("type", "concept"),
                    "position": position,
                    "path": str(img_path),
                    "prompt": prompt,
                    "success": True,
                })
            else:
                print(f"  → 生成失敗")
                manifest["images"].append({
                    "type": ph.get("type", "concept"),
                    "position": position,
                    "path": "",
                    "prompt": prompt,
                    "success": False,
                })

            time.sleep(5)  # レートリミット対策
    else:
        print("\n[2] セクション画像のプレースホルダーなし（スキップ）")

    # ──────────────────────────────────────
    # 3. マニフェスト保存
    # ──────────────────────────────────────
    with open(MANIFEST_PATH, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)

    success_count = sum(1 for img in manifest["images"] if img["success"])
    total_count = len(manifest["images"])

    print("\n" + "=" * 50)
    print(f"画像生成完了: {success_count}/{total_count} 枚成功")
    print(f"保存先: {IMAGES_DIR}")
    print(f"マニフェスト: {MANIFEST_PATH}")
    print("=" * 50)


if __name__ == "__main__":
    main()
