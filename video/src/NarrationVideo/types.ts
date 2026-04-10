export interface Scene {
  id: number;
  imagePrompt: string;
  narration: string;
  durationSec: number;
}

export interface Manuscript {
  title: string;
  scenes: Scene[];
  bgm: string | null;
  artStyle?: string;
}
