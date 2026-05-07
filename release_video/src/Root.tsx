import "./index.css";
import { Composition } from "remotion";
import { MainComposition } from "./MainComposition";
import { ReleaseVideoShort } from "./ReleaseVideo/ReleaseVideoShort";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="MainComposition"
        component={MainComposition}
        durationInFrames={30 * 50}
        fps={30}
        width={1920}
        height={1080}
      />
      <Composition
        id="ReleaseVideoShort"
        component={ReleaseVideoShort}
        durationInFrames={30 * 19}
        fps={30}
        width={1920}
        height={1080}
      />
    </>
  );
};
