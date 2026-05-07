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

// Mock Easing functions
const Easing = {
  in: (fn) => (t) => fn(t),
  out: (fn) => (t) => 1 - fn(1 - t),
  quad: (t) => t * t,
  cubic: (t) => t * t * t,
};

function getScrollPosition(f, totalFrames, cmdCount) {
  const p1 = totalFrames * 0.30;
  const p2 = totalFrames * 0.55;
  const p3 = totalFrames * 0.85;

  if (f <= p1) {
    const t = f / p1;
    const eased = Easing.in(Easing.quad)(t);
    return eased * cmdCount * 2;
  } else if (f <= p2) {
    const t = (f - p1) / (p2 - p1);
    const eased = Easing.out(Easing.cubic)(t);
    const startPos = cmdCount * 2;
    const endPos = startPos + cmdCount * 0.4;
    return startPos + (endPos - startPos) * eased;
  } else if (f <= p3) {
    const t = (f - p2) / (p3 - p2);
    const startPos = cmdCount * 2 + cmdCount * 0.4;
    return startPos + t * cmdCount * 0.5;
  } else {
    const t = (f - p3) / (totalFrames - p3);
    const eased = Easing.out(Easing.quad)(t);
    const startPos = cmdCount * 2 + cmdCount * 0.9;
    return startPos + eased * cmdCount * 0.1;
  }
}

function getScrollSpeed(f, totalFrames, cmdCount) {
  const delta = 0.5;
  const pos1 = getScrollPosition(Math.max(0, f - delta), totalFrames, cmdCount);
  const pos2 = getScrollPosition(Math.min(totalFrames, f + delta), totalFrames, cmdCount);
  return Math.abs(pos2 - pos1) / (delta * 2);
}

const totalFrames = 300;
const cmdCount = COMMANDS.length;
const ticks = [];
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

console.log(ticks.filter(t => isNaN(t.frame) || isNaN(t.speed) || t.frame < 0 || t.speed < 0));
