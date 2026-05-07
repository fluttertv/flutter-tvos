import React from "react";
import {
  AbsoluteFill,
  Sequence,
  Audio,
  useVideoConfig,
  spring,
  useCurrentFrame,
  interpolate,
  Easing,
  staticFile,
  Video,
} from "remotion";
import { loadFont as loadInter } from "@remotion/google-fonts/Inter";
import { loadFont as loadJetBrainsMono } from "@remotion/google-fonts/JetBrainsMono";

const { fontFamily: inter } = loadInter();
const { fontFamily: mono } = loadJetBrainsMono();

const BG = "#0d1117";
const CARD = "#161b22";
const BORDER = "#30363d";
const CYAN = "#22d3ee";
const WHITE = "#e6edf3";
const MUTED = "#8b949e";

const COMMANDS = [
  "doctor",
  "create my_app",
  "pub get",
  "run",
  "build tvos",
  "devices",
  "test",
  "clean",
  "analyze",
  "install tvos",
];

// ─── Scroll curve: quintic ease-out for a smooth fast-to-slow transition ───
function getScrollPosition(f: number, totalFrames: number, cmdCount: number): number {
  const t = f / totalFrames;
  
  // Quintic Ease-Out: starts extremely fast, decelerates very smoothly
  const eased = 1 - Math.pow(1 - t, 5);
  
  // Total scroll distance: 5 full loops + land on index 4 ("build tvos")
  const targetPos = cmdCount * 5 + 4; 
  return eased * targetPos;
}

// ─── Get scroll speed at a given frame (for blur + tick timing) ───
function getScrollSpeed(f: number, totalFrames: number, cmdCount: number): number {
  const delta = 0.5;
  const pos1 = getScrollPosition(Math.max(0, f - delta), totalFrames, cmdCount);
  const pos2 = getScrollPosition(Math.min(totalFrames, f + delta), totalFrames, cmdCount);
  return Math.abs(pos2 - pos1) / (delta * 2);
}

// ─── Intro ───
const Intro: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();

  const titleOpacity = interpolate(f, [0, 20], [0, 1], { extrapolateRight: "clamp" });
  const titleY = interpolate(f, [0, 20], [40, 0], {
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });
  const subtitleOpacity = interpolate(f, [20, 40], [0, 1], { extrapolateRight: "clamp" });
  const subtitleY = interpolate(f, [20, 40], [20, 0], {
    extrapolateRight: "clamp",
    easing: Easing.out(Easing.cubic),
  });
  const fadeOut = interpolate(f, [fps * 3.5 - 10, fps * 3.5], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill
      style={{
        backgroundColor: BG,
        justifyContent: "center",
        alignItems: "center",
        fontFamily: inter,
        opacity: fadeOut,
      }}
    >
      <div
        style={{
          position: "absolute",
          width: 900,
          height: 900,
          borderRadius: "50%",
          background: "radial-gradient(circle, rgba(34,211,238,0.06) 0%, transparent 70%)",
          top: "50%",
          left: "50%",
          transform: "translate(-50%,-50%)",
        }}
      />
      <div
        style={{
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          transform: `translateY(${titleY}px)`,
          opacity: titleOpacity,
        }}
      >
        <span style={{ fontSize: 130, fontWeight: 800, color: WHITE, lineHeight: 1.1, letterSpacing: -3 }}>
          Flutter.
        </span>
        <span style={{ fontSize: 130, fontWeight: 800, lineHeight: 1.1, letterSpacing: -3 }}>
          <span style={{ color: WHITE }}>Now on </span>
          <span style={{ color: CYAN }}>Apple TV.</span>
        </span>
      </div>
      <div
        style={{
          position: "absolute",
          bottom: 260,
          opacity: subtitleOpacity,
          transform: `translateY(${subtitleY}px)`,
          maxWidth: 800,
          textAlign: "center",
        }}
      >
        <p style={{ fontSize: 32, color: MUTED, lineHeight: 1.6, margin: 0 }}>
          Same commands. Same workflow. New platform.
        </p>
      </div>
    </AbsoluteFill>
  );
};

// ─── Command Slot with -tvos highlight ───
const Slot: React.FC<{
  command: string;
  isActive: boolean;
  yOffset: number;
  opacity: number;
  blur: number;
}> = ({ command, isActive, yOffset, opacity, blur }) => (
  <div
    style={{
      position: "absolute",
      top: "50%",
      left: "50%",
      transform: `translate(-50%,-50%) translateY(${yOffset}px) scale(${isActive ? 1.05 : 1})`,
      opacity,
      filter: blur > 0.5 ? `blur(${blur}px)` : isActive ? "drop-shadow(0px 0px 12px rgba(34,211,238,0.4))" : "none",
      display: "flex",
      alignItems: "center",
      gap: 24,
      width: 860,
    }}
  >
    <span
      style={{
        fontSize: isActive ? 52 : 34,
        fontFamily: mono,
        color: isActive ? CYAN : `${MUTED}88`,
        fontWeight: isActive ? 800 : 400,
        minWidth: 30,
      }}
    >
      $
    </span>
    <span
      style={{
        fontSize: isActive ? 52 : 34,
        fontFamily: mono,
        color: isActive ? `${MUTED}ee` : `${MUTED}44`,
        fontWeight: isActive ? 600 : 400,
        whiteSpace: "nowrap",
      }}
    >
      flutter
      <span
        style={{
          color: isActive ? CYAN : `${MUTED}66`,
          fontWeight: isActive ? 800 : 400,
        }}
      >
        -tvos
      </span>
      {" "}
      <span
        style={{
          color: isActive ? WHITE : `${MUTED}55`,
          fontWeight: isActive ? 700 : 400,
        }}
      >
        {command}
      </span>
    </span>
  </div>
);

// ─── Tick Sound Component ───
const TickSounds: React.FC<{ scrollScene: boolean }> = ({ scrollScene }) => {
  const { fps } = useVideoConfig();
  const totalFrames = fps * 10;
  const cmdCount = COMMANDS.length;

  // Pre-calculate tick frames: every time scroll crosses an integer boundary
  const ticks: { frame: number; speed: number }[] = [];
  let prevInt = -1;

  for (let f = 0; f < totalFrames; f++) {
    const pos = getScrollPosition(f, totalFrames, cmdCount);
    const currentInt = Math.floor(pos);
    if (currentInt !== prevInt && prevInt >= 0) {
      const speed = getScrollSpeed(f, totalFrames, cmdCount);
      ticks.push({ frame: f, speed });
    }
    prevInt = currentInt;
  }

  if (!scrollScene) return null;

  return (
    <>
      {ticks.map((tick, i) => {
        // Use quieter ticks during fast scroll, louder during slow
        const volume = interpolate(tick.speed, [0.05, 0.5], [0.8, 0.15], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
        });
        const isSlowTick = tick.speed < 0.15;
        return (
          <Sequence key={i} from={tick.frame} durationInFrames={1}>
            <Audio
              src={staticFile(isSlowTick ? "tick-low.wav" : "tick.wav")}
              volume={volume}
            />
          </Sequence>
        );
      })}
    </>
  );
};

// ─── Rolling Commands ───
const Rolling: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();

  const totalFrames = fps * 10;
  const cmdCount = COMMANDS.length;

  const scrollPos = getScrollPosition(f, totalFrames, cmdCount);
  const speed = getScrollSpeed(f, totalFrames, cmdCount);

  // Wrap for display
  const wrappedScroll = ((scrollPos % cmdCount) + cmdCount) % cmdCount;

  const sceneOpacity = interpolate(f, [0, 12], [0, 1], { extrapolateRight: "clamp" });
  const headerOpacity = interpolate(f, [0, 18], [0, 1], { extrapolateRight: "clamp" });

  return (
    <AbsoluteFill style={{ backgroundColor: BG, fontFamily: inter, opacity: sceneOpacity }}>
      {/* Glow */}
      <div
        style={{
          position: "absolute",
          width: 700,
          height: 700,
          borderRadius: "50%",
          background: "radial-gradient(circle, rgba(34,211,238,0.05) 0%, transparent 70%)",
          top: "50%",
          left: "50%",
          transform: "translate(-50%,-50%)",
        }}
      />

      {/* Header */}
      <div
        style={{
          position: "absolute",
          top: 80,
          left: 0,
          right: 0,
          opacity: headerOpacity,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          gap: 12,
        }}
      >
        <span style={{ fontSize: 48, fontWeight: 800, color: WHITE, letterSpacing: -1 }}>
          The commands you already know.
        </span>
      </div>

      {/* Terminal window */}
      <div
        style={{
          position: "absolute",
          top: "50%",
          left: "50%",
          transform: "translate(-50%,-42%)",
          width: 1050,
          height: 460,
          backgroundColor: CARD,
          borderRadius: 16,
          border: `1px solid ${BORDER}`,
          overflow: "hidden",
          boxShadow: "0 20px 60px rgba(0,0,0,0.5)",
        }}
      >
        {/* Header dots */}
        <div
          style={{
            height: 44,
            backgroundColor: "#21262d",
            display: "flex",
            alignItems: "center",
            padding: "0 16px",
            borderBottom: `1px solid ${BORDER}`,
            gap: 8,
          }}
        >
          <div style={{ width: 12, height: 12, borderRadius: "50%", backgroundColor: "#ff5f56" }} />
          <div style={{ width: 12, height: 12, borderRadius: "50%", backgroundColor: "#ffbd2e" }} />
          <div style={{ width: 12, height: 12, borderRadius: "50%", backgroundColor: "#27c93f" }} />
        </div>

        {/* Scroll area */}
        <div style={{ position: "relative", height: "calc(100% - 44px)", overflow: "hidden" }}>
          {/* Fade masks */}
          <div
            style={{
              position: "absolute",
              top: 0,
              left: 0,
              right: 0,
              height: 100,
              background: `linear-gradient(to bottom, ${CARD}, transparent)`,
              zIndex: 2,
            }}
          />
          <div
            style={{
              position: "absolute",
              bottom: 0,
              left: 0,
              right: 0,
              height: 100,
              background: `linear-gradient(to top, ${CARD}, transparent)`,
              zIndex: 2,
            }}
          />

          {/* Render commands in a virtual loop */}
          {Array.from({ length: cmdCount * 3 }).map((_, rawIdx) => {
            const i = rawIdx % cmdCount;
            const virtualIdx = rawIdx - cmdCount;
            const distFromActive = virtualIdx - wrappedScroll;

            if (Math.abs(distFromActive) > 3.5) return null;

            const yOffset = distFromActive * 85;
            const isActive = Math.abs(distFromActive) < 0.4;
            const opacity = interpolate(
              Math.abs(distFromActive),
              [0, 0.8, 2.8],
              [1, 0.5, 0],
              { extrapolateRight: "clamp" }
            );
            const itemBlur = isActive ? 0 : Math.min(speed * 3, 6) * Math.abs(distFromActive) * 0.4;

            return (
              <Slot
                key={rawIdx}
                command={COMMANDS[i]}
                isActive={isActive}
                yOffset={yOffset}
                opacity={opacity}
                blur={itemBlur}
              />
            );
          })}

          {/* Selection lines */}
          <div
            style={{
              position: "absolute",
              top: "50%",
              left: 50,
              right: 50,
              height: 1,
              transform: "translateY(32px)",
              background: `linear-gradient(to right, ${CYAN}30, transparent 60%)`,
              zIndex: 1,
            }}
          />
          <div
            style={{
              position: "absolute",
              top: "50%",
              left: 50,
              right: 50,
              height: 1,
              transform: "translateY(-32px)",
              background: `linear-gradient(to right, ${CYAN}30, transparent 60%)`,
              zIndex: 1,
            }}
          />
        </div>
      </div>

      {/* Tick sounds */}
      <TickSounds scrollScene />
    </AbsoluteFill>
  );
};

// ─── Ending: fluttertv.dev ───
const Ending: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();

  const titleSpring = spring({ frame: f, fps, config: { damping: 14, stiffness: 100 } });
  const titleScale = interpolate(titleSpring, [0, 1], [0.8, 1]);
  const titleOpacity = interpolate(titleSpring, [0, 1], [0, 1]);

  const urlSpring = spring({ frame: f - 20, fps, config: { damping: 12, stiffness: 120 } });
  const urlOpacity = interpolate(urlSpring, [0, 1], [0, 1]);
  const urlY = interpolate(urlSpring, [0, 1], [30, 0]);

  const glowIntensity = interpolate(Math.sin(f / 20), [-1, 1], [0.04, 0.1]);

  return (
    <AbsoluteFill
      style={{
        backgroundColor: BG,
        justifyContent: "center",
        alignItems: "center",
        fontFamily: inter,
      }}
    >
      <Audio src={staticFile("pop.wav")} volume={0.8} />
      <Audio src={staticFile("pop.wav")} volume={0.8} />
      <div
        style={{
          position: "absolute",
          width: 1200,
          height: 1200,
          borderRadius: "50%",
          background: `radial-gradient(circle, rgba(34,211,238,${glowIntensity}) 0%, transparent 55%)`,
          top: "50%",
          left: "50%",
          transform: "translate(-50%,-50%)",
        }}
      />
      <div
        style={{
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          gap: 0,
          transform: `scale(${titleScale})`,
          opacity: titleOpacity,
        }}
      >
        <span style={{ fontSize: 90, fontWeight: 800, color: WHITE, letterSpacing: -3, fontFamily: inter }}>
          flutter<span style={{ color: CYAN }}>tv</span>.dev
        </span>
      </div>
      <div
        style={{
          position: "absolute",
          bottom: "42%",
          opacity: urlOpacity,
          transform: `translateY(${urlY}px)`,
        }}
      >
        <span style={{ fontSize: 28, fontFamily: mono, color: MUTED }}>
          Flutter for Apple TV
        </span>
      </div>
    </AbsoluteFill>
  );
};

// ─── CRT Shutdown Effect ───
const CrtEffect: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();

  const shutdownStart = durationInFrames - 25;
  const progress = interpolate(frame, [shutdownStart, durationInFrames], [0, 1], {
    extrapolateLeft: "clamp",
  });

  if (frame < shutdownStart) return <>{children}</>;

  // Stage 1: Shrink height to a thin line (0 -> 0.7 progress)
  // Stage 2: Shrink width of that line to a point (0.7 -> 0.9 progress)
  // Stage 3: Point disappears (0.9 -> 1.0 progress)
  const scaleY = interpolate(progress, [0, 0.4], [1, 0.001], { extrapolateRight: "clamp" });
  const scaleX = interpolate(progress, [0.4, 0.7], [1, 0.001], { extrapolateRight: "clamp" });
  const brightness = interpolate(progress, [0, 0.4, 0.7], [1, 2, 5], { extrapolateRight: "clamp" });
  const opacity = interpolate(progress, [0.8, 1], [1, 0], { extrapolateRight: "clamp" });

  return (
    <AbsoluteFill style={{ backgroundColor: "black" }}>
      <AbsoluteFill
        style={{
          transform: `scaleX(${scaleX}) scaleY(${scaleY})`,
          filter: `brightness(${brightness})`,
          opacity,
        }}
      >
        {children}
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

// ─── CRT Static Effect ───
const CrtStatic: React.FC = () => {
  const frame = useCurrentFrame();

  // TV turn-on animation (0 to 10 frames)
  const turnOnProgress = interpolate(frame, [0, 10], [0, 1], {
    extrapolateRight: "clamp",
  });
  
  // Expand from a horizontal line
  const scaleY = interpolate(turnOnProgress, [0, 0.5, 1], [0.005, 0.005, 1]);
  const scaleX = interpolate(turnOnProgress, [0, 0.5, 1], [0.005, 1, 1]);
  const brightness = interpolate(turnOnProgress, [0, 0.5, 1], [8, 4, 2.5]);

  return (
    <AbsoluteFill
      style={{
        backgroundColor: "black",
        display: "flex",
        justifyContent: "center",
        alignItems: "center",
        overflow: "hidden",
      }}
    >
      <Video
        src={staticFile("static.mp4")}
        style={{
          width: "120%",
          height: "120%",
          objectFit: "cover",
          imageRendering: "pixelated",
          transform: `scaleX(${scaleX}) scaleY(${scaleY})`,
          filter: `brightness(${brightness}) contrast(1.5)`,
        }}
        muted
      />
    </AbsoluteFill>
  );
};

// ─── Main Composition: 19 seconds ───
export const ReleaseVideoShort: React.FC = () => {
  const { fps, durationInFrames } = useVideoConfig();

  return (
    <CrtEffect>
      <AbsoluteFill style={{ backgroundColor: BG, fontFamily: inter }}>
        {/* CRT Static Burst at the very beginning (0s-1s) */}
        <Sequence from={0} durationInFrames={Math.round(fps * 1)}>
          <CrtStatic />
          <Audio src={staticFile("static.wav")} volume={0.4} />
        </Sequence>

        {/* CRT Off Sound Trigger */}
        <Sequence from={durationInFrames - 25}>
          <Audio src={staticFile("crt_off.wav")} volume={1} />
        </Sequence>

        {/* 1s–5s: Intro */}
        <Sequence from={Math.round(fps * 1)} durationInFrames={Math.round(fps * 4)}>
          <Intro />
        </Sequence>

        {/* 5s–15s: Rolling Commands */}
        <Sequence from={Math.round(fps * 5)} durationInFrames={Math.round(fps * 10)}>
          <Rolling />
        </Sequence>

        {/* 15s–19s: Ending */}
        <Sequence from={Math.round(fps * 15)} durationInFrames={Math.round(fps * 4)}>
          <Ending />
        </Sequence>
      </AbsoluteFill>
    </CrtEffect>
  );
};
