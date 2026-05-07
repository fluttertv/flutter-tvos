import React from "react";
import { AbsoluteFill, Sequence, useVideoConfig, spring, useCurrentFrame, interpolate } from "remotion";
import { loadFont as loadInter } from "@remotion/google-fonts/Inter";

loadInter();

// Electric Mint: #00FFCC
// San Francisco blue to purple: #007AFF to #5856D6
// Deep Obsidian: #0B0B0C

const TitleCollide: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const progressF = spring({ frame: frame - 10, fps, config: { damping: 12 } });
  const progressT = spring({ frame: frame - 10, fps, config: { damping: 12 } });

  const translateXF = interpolate(progressF, [0, 1], [-500, -200]);
  const translateXT = interpolate(progressT, [0, 1], [500, 100]);
  const opacity = interpolate(frame, [0, 20], [0, 1]);

  return (
    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", backgroundColor: "#0B0B0C", color: "white" }}>
      <div style={{ position: "absolute", transform: `translateX(${translateXF}px)`, opacity }}>
        <span style={{ fontSize: 160, fontWeight: "bold", background: "linear-gradient(to right, #007AFF, #5856D6)", WebkitBackgroundClip: "text", WebkitTextFillColor: "transparent" }}>FLUTTER</span>
      </div>
      <div style={{ position: "absolute", transform: `translateX(${translateXT}px)`, opacity }}>
        <span style={{ fontSize: 160, fontWeight: "bold", color: "#00FFCC" }}>TVOS</span>
      </div>
    </AbsoluteFill>
  );
};

const WheelCommand: React.FC<{ targetCommand: string; label: string }> = ({ targetCommand, label }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // Picker rotation
  const rotateProgress = spring({ frame, fps, config: { damping: 12, mass: 1, stiffness: 100 } });
  const wheelY = interpolate(rotateProgress, [0, 1], [400, 0]);
  const wheelBlur = interpolate(rotateProgress, [0, 1], [20, 0]);
  
  // Tvos badge snap
  const badgeSnap = spring({ frame: frame - 30, fps, config: { damping: 14 } });
  const badgeX = interpolate(badgeSnap, [0, 1], [300, 0]);
  const badgeScale = interpolate(badgeSnap, [0, 1], [2, 1]);

  // Dropdown expansion
  const dropdownExpand = spring({ frame: frame - 60, fps, config: { damping: 12 } });
  const dropdownHeight = interpolate(dropdownExpand, [0, 1], [0, 200]);
  const dropdownOpacity = interpolate(dropdownExpand, [0, 1], [0, 1]);

  return (
    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", backgroundColor: "#0B0B0C" }}>
      {/* Picker */}
      <div style={{ transform: `translateY(${wheelY}px)`, filter: `blur(${wheelBlur}px)`, display: "flex", flexDirection: "column", alignItems: "center" }}>
        <div style={{ fontSize: 100, fontWeight: "bold", color: "white", display: "flex", gap: 20 }}>
          <span>flutter</span>
          <span style={{ transform: `translateX(${badgeX}px) scale(${badgeScale})`, color: "#00FFCC" }}>-tvos</span>
        </div>
        <div style={{ fontSize: 80, fontWeight: "bold", color: "#888", marginTop: 20 }}>
          {targetCommand}
        </div>
      </div>
      
      {/* Frosted Glass Dropdown */}
      <div style={{ position: "absolute", top: "65%", height: dropdownHeight, opacity: dropdownOpacity, overflow: "hidden", width: 600, background: "rgba(255,255,255,0.1)", backdropFilter: "blur(20px)", borderRadius: 30, display: "flex", justifyContent: "center", alignItems: "center", border: "1px solid rgba(255,255,255,0.2)" }}>
        <span style={{ fontSize: 50, color: "white", fontWeight: "600" }}>{label}</span>
      </div>
    </AbsoluteFill>
  );
};

const RemoteScene: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const flyIn = spring({ frame, fps, config: { damping: 14 } });
  const translateY = interpolate(flyIn, [0, 1], [800, 0]);
  const rotate = interpolate(flyIn, [0, 1], [45, 0]);

  return (
    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", backgroundColor: "#0B0B0C" }}>
      <div style={{ transform: `translateY(${translateY}px) rotate(${rotate}deg)`, width: 200, height: 600, background: "linear-gradient(145deg, #333, #111)", borderRadius: 100, boxShadow: "0 20px 50px rgba(0,0,0,0.8)", border: "2px solid #555", display: "flex", flexDirection: "column", alignItems: "center", padding: 20 }}>
        {/* Touchpad */}
        <div style={{ width: 160, height: 160, borderRadius: 80, background: "rgba(255,255,255,0.1)", boxShadow: "inset 0 0 20px #00FFCC", filter: "drop-shadow(0 0 10px #00FFCC)" }}></div>
        <div style={{ marginTop: 60, width: 40, height: 40, borderRadius: 20, background: "#444" }}></div>
        <div style={{ marginTop: 20, width: 40, height: 40, borderRadius: 20, background: "#444" }}></div>
      </div>
    </AbsoluteFill>
  );
};

const RapidFireText: React.FC<{ text: string }> = ({ text }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const scale = spring({ frame, fps, config: { damping: 12 } });
  
  return (
    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", backgroundColor: "#0B0B0C" }}>
      <div style={{ transform: `scale(${scale})`, fontSize: 100, fontWeight: "900", color: "#00FFCC", textAlign: "center", fontStyle: "italic" }}>
        {text}
      </div>
    </AbsoluteFill>
  );
}

const Ending: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  const slideIn = spring({ frame, fps, config: { damping: 14 } });
  const translateY = interpolate(slideIn, [0, 1], [500, 0]);

  return (
    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", backgroundColor: "#0B0B0C" }}>
      <div style={{ transform: `translateY(${translateY}px)`, width: 800, height: 400, background: "linear-gradient(135deg, #007AFF, #5856D6)", borderRadius: 40, display: "flex", flexDirection: "column", justifyContent: "center", alignItems: "center", boxShadow: "0 30px 60px rgba(0,0,0,0.5)", border: "2px solid rgba(255,255,255,0.2)" }}>
        <span style={{ fontSize: 60, color: "white", fontWeight: "bold" }}>flutter-tvos</span>
        <span style={{ fontSize: 30, color: "#00FFCC", marginTop: 20 }}>github.com/fluttertv/flutter-tvos</span>
      </div>
    </AbsoluteFill>
  );
}

export const MainComposition: React.FC = () => {
  const { fps } = useVideoConfig();

  return (
    <AbsoluteFill style={{ backgroundColor: "#0B0B0C", fontFamily: "Inter, sans-serif" }}>
      {/* 0-10s -> 300 frames */}
      <Sequence durationInFrames={fps * 10}>
        <TitleCollide />
      </Sequence>
      
      {/* 10-15s -> 150 frames */}
      <Sequence from={fps * 10} durationInFrames={fps * 5}>
        <WheelCommand targetCommand="doctor" label="System Check: ALL GREEN" />
      </Sequence>

      {/* 15-20s -> 150 frames */}
      <Sequence from={fps * 15} durationInFrames={fps * 5}>
        <WheelCommand targetCommand="pub get" label="Dependencies: SYNCED" />
      </Sequence>

      {/* 20-25s -> 150 frames */}
      <Sequence from={fps * 20} durationInFrames={fps * 5}>
        <WheelCommand targetCommand="run" label="Deploying to Apple TV..." />
      </Sequence>

      {/* 25-35s -> 300 frames */}
      <Sequence from={fps * 25} durationInFrames={fps * 10}>
        <RemoteScene />
      </Sequence>

      {/* 35-45s -> Rapid Fire Texts */}
      <Sequence from={fps * 35} durationInFrames={fps * 3}>
        <RapidFireText text="NATIVE PERFORMANCE" />
      </Sequence>
      <Sequence from={fps * 38} durationInFrames={fps * 3}>
        <RapidFireText text="SHARED CODEBASE" />
      </Sequence>
      <Sequence from={fps * 41} durationInFrames={fps * 4}>
        <RapidFireText text="BIG SCREEN EXPERIENCE" />
      </Sequence>

      {/* 45-50s -> Ending */}
      <Sequence from={fps * 45} durationInFrames={fps * 5}>
        <Ending />
      </Sequence>

    </AbsoluteFill>
  );
};
