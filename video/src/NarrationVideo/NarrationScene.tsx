import React from "react";
import {
  AbsoluteFill,
  Img,
  Audio,
  useCurrentFrame,
  useVideoConfig,
  interpolate,
  staticFile,
} from "remotion";
import type { Scene } from "./types";

const FADE_FRAMES = 3;

export const NarrationScene: React.FC<{ scene: Scene }> = ({ scene }) => {
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();

  const opacity = interpolate(
    frame,
    [0, FADE_FRAMES, durationInFrames - FADE_FRAMES, durationInFrames],
    [0, 1, 1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  const subtitleOpacity = interpolate(
    frame,
    [FADE_FRAMES, FADE_FRAMES + 10],
    [0, 1],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  return (
    <AbsoluteFill style={{ opacity, backgroundColor: "#0a0a2e" }}>
      <div style={{ width: "100%", height: "80%", overflow: "hidden" }}>
        <Img
          src={staticFile(`scenes/${scene.id}.png`)}
          style={{
            width: "100%",
            height: "100%",
            objectFit: "contain",
          }}
        />
      </div>
      <Audio src={staticFile(`audio/${scene.id}.mp3`)} />
      <div
        style={{
          position: "absolute",
          bottom: 0,
          left: 0,
          right: 0,
          height: "20%",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          backgroundColor: "rgba(16, 16, 48, 0.95)",
          borderTop: "3px solid #00ffcc",
          boxShadow: "0 -4px 12px rgba(0, 255, 204, 0.3)",
          opacity: subtitleOpacity,
        }}
      >
        <div
          style={{
            color: "#ffffff",
            fontSize: 24,
            fontFamily:
              '"DotGothic16", "Noto Sans JP", "Hiragino Kaku Gothic ProN", monospace',
            fontWeight: 700,
            padding: "0 40px",
            maxWidth: "90%",
            textAlign: "center",
            lineHeight: 1.4,
            letterSpacing: "0.04em",
          }}
        >
          {scene.narration}
        </div>
      </div>
    </AbsoluteFill>
  );
};
