import React from "react";
import { AbsoluteFill, Sequence } from "remotion";
import { NarrationScene } from "./NarrationScene";
import type { Manuscript } from "./types";

const FPS = 30;

export const NarrationVideo: React.FC<{ manuscript: Manuscript }> = ({
  manuscript,
}) => {
  let currentFrame = 0;

  return (
    <AbsoluteFill style={{ backgroundColor: "#000" }}>
      {manuscript.scenes.map((scene) => {
        const durationInFrames = Math.round(scene.durationSec * FPS);
        const from = currentFrame;
        currentFrame += durationInFrames;

        return (
          <Sequence
            key={scene.id}
            from={from}
            durationInFrames={durationInFrames}
          >
            <NarrationScene scene={scene} />
          </Sequence>
        );
      })}
    </AbsoluteFill>
  );
};

export function calculateNarrationVideoMetadata(manuscript: Manuscript) {
  const totalDurationSec = manuscript.scenes.reduce(
    (sum, scene) => sum + scene.durationSec,
    0,
  );
  return {
    durationInFrames: Math.round(totalDurationSec * FPS),
    fps: FPS,
    width: 1280,
    height: 720,
  };
}
