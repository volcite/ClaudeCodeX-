import "./index.css";
import { Composition } from "remotion";
import {
  NarrationVideo,
  calculateNarrationVideoMetadata,
} from "./NarrationVideo";
import type { Manuscript } from "./NarrationVideo/types";

const defaultManuscript: Manuscript = {
  title: "サンプル動画",
  scenes: [
    {
      id: 1,
      imagePrompt: "A cute Shiba Inu walking on a cobblestone street",
      narration: "ある晴れた日、柴犬のコロはヨーロッパの街を訪れました。",
      durationSec: 5,
    },
    {
      id: 2,
      imagePrompt: "A Shiba Inu looking at a bakery window",
      narration: "美味しそうなパン屋さんを見つけて、思わず足を止めます。",
      durationSec: 5,
    },
  ],
  bgm: "background",
};

const narrationMeta = calculateNarrationVideoMetadata(defaultManuscript);

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="NarrationVideo"
        component={NarrationVideo as React.FC}
        durationInFrames={narrationMeta.durationInFrames}
        fps={narrationMeta.fps}
        width={narrationMeta.width}
        height={narrationMeta.height}
        defaultProps={{ manuscript: defaultManuscript }}
      />
    </>
  );
};
