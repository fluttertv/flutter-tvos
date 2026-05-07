import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";

export const Background: React.FC = () => {
  const frame = useCurrentFrame();
  
  // Subtle animation for the gradient
  const shift = interpolate(Math.sin(frame / 50), [-1, 1], [0, 10]);

  return (
    <AbsoluteFill
      style={{
        background: `radial-gradient(circle at ${50 + shift}% ${50 + shift}%, #1a1a1a 0%, #000000 100%)`,
      }}
    />
  );
};
