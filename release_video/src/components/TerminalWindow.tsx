import React from "react";
import { AbsoluteFill } from "remotion";

export const TerminalWindow: React.FC<{ children: React.ReactNode }> = ({
  children,
}) => {
  return (
    <AbsoluteFill
      style={{
        justifyContent: "center",
        alignItems: "center",
        backgroundColor: "#0d1117", // Dark background
      }}
    >
      <div
        style={{
          width: "80%",
          height: "60%",
          backgroundColor: "#161b22", // Slightly lighter for terminal body
          borderRadius: 16,
          boxShadow: "0px 20px 50px rgba(0, 0, 0, 0.5)",
          display: "flex",
          flexDirection: "column",
          overflow: "hidden",
          border: "1px solid #30363d",
        }}
      >
        {/* Terminal Header */}
        <div
          style={{
            height: 40,
            backgroundColor: "#21262d",
            display: "flex",
            alignItems: "center",
            padding: "0 16px",
            borderBottom: "1px solid #30363d",
          }}
        >
          <div
            style={{ width: 12, height: 12, borderRadius: "50%", backgroundColor: "#ff5f56", marginRight: 8 }}
          />
          <div
            style={{ width: 12, height: 12, borderRadius: "50%", backgroundColor: "#ffbd2e", marginRight: 8 }}
          />
          <div
            style={{ width: 12, height: 12, borderRadius: "50%", backgroundColor: "#27c93f" }}
          />
        </div>
        {/* Terminal Content */}
        <div style={{ flex: 1, padding: 24, display: "flex", flexDirection: "column", fontFamily: "'JetBrains Mono', monospace", color: "#c9d1d9", fontSize: 32 }}>
          {children}
        </div>
      </div>
    </AbsoluteFill>
  );
};
