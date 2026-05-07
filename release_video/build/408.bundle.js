"use strict";
(self["webpackChunkrelease_video"] = self["webpackChunkrelease_video"] || []).push([[408],{

/***/ 699
(__unused_webpack___webpack_module__, __unused_webpack___webpack_exports__, __webpack_require__) {

/* harmony import */ var mediabunny__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(4709);
/* harmony import */ var mediabunny__WEBPACK_IMPORTED_MODULE_1__ = __webpack_require__(1290);
/* harmony import */ var mediabunny__WEBPACK_IMPORTED_MODULE_2__ = __webpack_require__(2030);
/* harmony import */ var mediabunny__WEBPACK_IMPORTED_MODULE_3__ = __webpack_require__(388);
// src/components/parse-color.ts
var colorCache = new Map;
var parseColor = (color) => {
  const cached = colorCache.get(color);
  if (cached)
    return cached;
  const ctx = new OffscreenCanvas(1, 1).getContext("2d");
  ctx.fillStyle = color;
  ctx.fillRect(0, 0, 1, 1);
  const [r, g, b, a] = ctx.getImageData(0, 0, 1, 1).data;
  const result = [r, g, b, a];
  colorCache.set(color, result);
  return result;
};

// src/components/draw-peaks.ts
var CLIPPING_COLOR = "#FF7F50";
var drawBars = (canvas, peaks, color, volume, width) => {
  const ctx = canvas.getContext("2d");
  if (!ctx) {
    throw new Error("Failed to get canvas context");
  }
  const { height } = canvas;
  const w = canvas.width;
  ctx.clearRect(0, 0, w, height);
  if (volume === 0)
    return;
  const [r, g, b, a] = parseColor(color);
  const [cr, cg, cb, ca] = parseColor(CLIPPING_COLOR);
  const imageData = ctx.createImageData(w, height);
  const { data } = imageData;
  const numBars = width;
  for (let barIndex = 0;barIndex < numBars; barIndex++) {
    const x = barIndex;
    if (x >= w)
      break;
    const peakIndex = Math.floor(barIndex / numBars * peaks.length);
    const peak = peaks[peakIndex] || 0;
    const scaledPeak = peak * volume;
    const halfBar = Math.max(0, Math.min(height / 2, scaledPeak * height / 2));
    if (halfBar === 0)
      continue;
    const mid = height / 2;
    const barY = Math.round(mid - halfBar);
    const barEnd = Math.round(mid + halfBar);
    const isClipping = scaledPeak > 1;
    const clipTopEnd = isClipping ? Math.min(barY + 2, barEnd) : barY;
    const clipBotStart = isClipping ? Math.max(barEnd - 2, barY) : barEnd;
    for (let y = barY;y < clipTopEnd; y++) {
      const idx = (y * w + x) * 4;
      data[idx] = cr;
      data[idx + 1] = cg;
      data[idx + 2] = cb;
      data[idx + 3] = ca;
    }
    for (let y = clipTopEnd;y < clipBotStart; y++) {
      const idx = (y * w + x) * 4;
      data[idx] = r;
      data[idx + 1] = g;
      data[idx + 2] = b;
      data[idx + 3] = a;
    }
    for (let y = clipBotStart;y < barEnd; y++) {
      const idx = (y * w + x) * 4;
      data[idx] = cr;
      data[idx + 1] = cg;
      data[idx + 2] = cb;
      data[idx + 3] = ca;
    }
  }
  ctx.putImageData(imageData, 0, 0);
};

// src/components/load-waveform-peaks.ts


// src/components/waveform-peak-processor.ts
var emitWaveformProgress = ({
  completedPeaks,
  final,
  onProgress,
  peaks,
  totalPeaks
}) => {
  onProgress?.({
    peaks,
    completedPeaks,
    totalPeaks,
    final
  });
};
var createWaveformPeakProcessor = ({
  totalPeaks,
  samplesPerPeak,
  onProgress,
  progressIntervalInMs,
  now
}) => {
  const peaks = new Float32Array(totalPeaks);
  let peakIndex = 0;
  let peakMax = 0;
  let sampleInPeak = 0;
  let lastProgressAt = 0;
  let lastProgressPeak = 0;
  const emitProgress = (force) => {
    const timestamp = now();
    if (!force && peakIndex === lastProgressPeak && sampleInPeak === 0) {
      return;
    }
    if (!force && timestamp - lastProgressAt < progressIntervalInMs) {
      return;
    }
    lastProgressAt = timestamp;
    lastProgressPeak = peakIndex;
    emitWaveformProgress({
      peaks,
      completedPeaks: peakIndex,
      totalPeaks,
      final: force,
      onProgress
    });
  };
  return {
    peaks,
    processSampleChunk: (floats, channels) => {
      const frameCount = Math.floor(floats.length / Math.max(1, channels));
      for (let frame = 0;frame < frameCount; frame++) {
        let framePeak = 0;
        for (let channel = 0;channel < channels; channel++) {
          const sampleIndex = frame * channels + channel;
          const abs = Math.abs(floats[sampleIndex] ?? 0);
          if (abs > framePeak) {
            framePeak = abs;
          }
        }
        if (framePeak > peakMax) {
          peakMax = framePeak;
        }
        sampleInPeak++;
        if (sampleInPeak >= samplesPerPeak) {
          if (peakIndex < totalPeaks) {
            peaks[peakIndex] = peakMax;
          }
          peakIndex++;
          peakMax = 0;
          sampleInPeak = 0;
        }
      }
      emitProgress(false);
    },
    finalize: () => {
      if (sampleInPeak > 0 && peakIndex < totalPeaks) {
        peaks[peakIndex] = peakMax;
        peakIndex++;
      }
      emitProgress(true);
    }
  };
};

// src/components/load-waveform-peaks.ts
var TARGET_SAMPLE_RATE = 100;
var DEFAULT_PROGRESS_INTERVAL_IN_MS = 50;
var peaksCache = new Map;
async function loadWaveformPeaks(url, signal, options) {
  const cached = peaksCache.get(url);
  if (cached) {
    emitWaveformProgress({
      peaks: cached,
      completedPeaks: cached.length,
      totalPeaks: cached.length,
      final: true,
      onProgress: options?.onProgress
    });
    return cached;
  }
  const input = new mediabunny__WEBPACK_IMPORTED_MODULE_2__/* .Input */ .pd({
    formats: mediabunny__WEBPACK_IMPORTED_MODULE_1__/* .ALL_FORMATS */ .XE,
    source: new mediabunny__WEBPACK_IMPORTED_MODULE_0__/* .UrlSource */ .Ts(url)
  });
  try {
    const audioTrack = await input.getPrimaryAudioTrack();
    if (!audioTrack) {
      return new Float32Array(0);
    }
    if (await audioTrack.isLive()) {
      throw new Error("Live streams are not currently supported by Remotion. Sorry! Source: " + url);
    }
    if (await audioTrack.isRelativeToUnixEpoch()) {
      throw new Error("Streams with UNIX timestamps are not currently supported by Remotion. Sorry! Source: " + url);
    }
    const sampleRate = await audioTrack.getSampleRate();
    const durationInSeconds = await audioTrack.getDurationFromMetadata({ skipLiveWait: true }) ?? await audioTrack.computeDuration({ skipLiveWait: true });
    const totalPeaks = Math.ceil(durationInSeconds * TARGET_SAMPLE_RATE);
    const samplesPerPeak = Math.max(1, Math.floor(sampleRate / TARGET_SAMPLE_RATE));
    const sink = new mediabunny__WEBPACK_IMPORTED_MODULE_3__/* .AudioSampleSink */ .qw(audioTrack);
    const processor = createWaveformPeakProcessor({
      totalPeaks,
      samplesPerPeak,
      onProgress: options?.onProgress,
      progressIntervalInMs: options?.progressIntervalInMs ?? DEFAULT_PROGRESS_INTERVAL_IN_MS,
      now: () => Date.now()
    });
    for await (const sample of sink.samples()) {
      if (signal.aborted) {
        sample.close();
        return new Float32Array(0);
      }
      const bytesNeeded = sample.allocationSize({
        format: "f32",
        planeIndex: 0
      });
      const floats = new Float32Array(bytesNeeded / 4);
      sample.copyTo(floats, { format: "f32", planeIndex: 0 });
      const channels = Math.max(1, sample.numberOfChannels);
      sample.close();
      processor.processSampleChunk(floats, channels);
    }
    processor.finalize();
    const { peaks } = processor;
    peaksCache.set(url, peaks);
    return peaks;
  } finally {
    input.dispose();
  }
}

// src/components/looped-media-timeline.ts
var shouldTileLoopDisplay = (loopDisplay) => {
  return loopDisplay !== undefined && loopDisplay.numberOfTimes > 1;
};
var getLoopDisplayWidth = ({
  visualizationWidth,
  loopDisplay
}) => {
  if (!shouldTileLoopDisplay(loopDisplay)) {
    return visualizationWidth;
  }
  return visualizationWidth / loopDisplay.numberOfTimes;
};

// src/components/slice-waveform-peaks.ts
var sliceWaveformPeaks = ({
  durationInFrames,
  fps,
  peaks,
  playbackRate,
  startFrom
}) => {
  if (peaks.length === 0) {
    return peaks;
  }
  const startTimeInSeconds = startFrom / fps;
  const durationInSeconds = durationInFrames / fps * playbackRate;
  const startPeakIndex = Math.floor(startTimeInSeconds * TARGET_SAMPLE_RATE);
  const endPeakIndex = Math.ceil((startTimeInSeconds + durationInSeconds) * TARGET_SAMPLE_RATE);
  return peaks.subarray(Math.max(0, startPeakIndex), Math.min(peaks.length, endPeakIndex));
};

// src/audio-waveform-worker.ts
var canvas = null;
var currentController = null;
var latestRequestId = 0;
var postError = (requestId, error) => {
  const message = error instanceof Error ? error.message : "Failed to render waveform";
  const payload = {
    type: "error",
    requestId,
    message
  };
  self.postMessage(payload);
};
var drawPartialWaveform = (message, peaks) => {
  if (!canvas) {
    return;
  }
  const portionPeaks = sliceWaveformPeaks({
    durationInFrames: shouldTileLoopDisplay(message.loopDisplay) ? message.loopDisplay.durationInFrames : message.durationInFrames,
    fps: message.fps,
    peaks,
    playbackRate: message.playbackRate,
    startFrom: message.startFrom
  });
  if (!shouldTileLoopDisplay(message.loopDisplay)) {
    drawBars(canvas, portionPeaks, "rgba(255, 255, 255, 0.6)", message.volume, message.width);
    return;
  }
  const loopWidth = getLoopDisplayWidth({
    visualizationWidth: message.width,
    loopDisplay: message.loopDisplay
  });
  const targetCanvas = new OffscreenCanvas(Math.max(1, Math.ceil(loopWidth)), message.height);
  drawBars(targetCanvas, portionPeaks, "rgba(255, 255, 255, 0.6)", message.volume, targetCanvas.width);
  const ctx = canvas.getContext("2d");
  if (!ctx) {
    throw new Error("Failed to get canvas context");
  }
  const pattern = ctx.createPattern(targetCanvas, "repeat-x");
  if (!pattern) {
    return;
  }
  pattern.setTransform(new DOMMatrix().scaleSelf(loopWidth / targetCanvas.width, 1));
  ctx.clearRect(0, 0, message.width, message.height);
  ctx.fillStyle = pattern;
  ctx.fillRect(0, 0, message.width, message.height);
};
var renderWaveform = async (message) => {
  if (!canvas) {
    postError(message.requestId, new Error("Waveform canvas not initialized"));
    return;
  }
  const controller = new AbortController;
  currentController?.abort();
  currentController = controller;
  latestRequestId = message.requestId;
  try {
    canvas.width = message.width;
    canvas.height = message.height;
    const peaks = await loadWaveformPeaks(message.src, controller.signal, {
      onProgress: ({ peaks: nextPeaks }) => {
        if (controller.signal.aborted || latestRequestId !== message.requestId) {
          return;
        }
        drawPartialWaveform(message, nextPeaks);
      }
    });
    if (controller.signal.aborted || latestRequestId !== message.requestId) {
      return;
    }
    drawPartialWaveform(message, peaks);
  } catch (error) {
    if (controller.signal.aborted || latestRequestId !== message.requestId) {
      return;
    }
    postError(message.requestId, error);
  }
};
self.addEventListener("message", (event) => {
  const message = event.data;
  if (message.type === "init") {
    canvas = message.canvas;
    return;
  }
  if (message.type === "dispose") {
    currentController?.abort();
    currentController = null;
    canvas = null;
    return;
  }
  renderWaveform(message);
});


/***/ },

/***/ 1299
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   Im: () => (/* binding */ aacFrequencyTable),
/* harmony export */   Ti: () => (/* binding */ aacChannelMap),
/* harmony export */   zF: () => (/* binding */ parseAacAudioSpecificConfig)
/* harmony export */ });
/* unused harmony exports buildAacAudioSpecificConfig, buildAdtsHeaderTemplate, writeAdtsFrameLength */
/* unused harmony import specifier */ var Bitstream;
/* harmony import */ var _bitstream_js__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(1390);
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

const aacFrequencyTable = [
    96000, 88200, 64000, 48000, 44100, 32000,
    24000, 22050, 16000, 12000, 11025, 8000, 7350,
];
const aacChannelMap = [-1, 1, 2, 3, 4, 5, 6, 8];
const parseAacAudioSpecificConfig = (bytes) => {
    if (!bytes || bytes.byteLength < 2) {
        throw new TypeError('AAC description must be at least 2 bytes long.');
    }
    const bitstream = new _bitstream_js__WEBPACK_IMPORTED_MODULE_0__/* .Bitstream */ ._(bytes);
    let objectType = bitstream.readBits(5);
    if (objectType === 31) {
        objectType = 32 + bitstream.readBits(6);
    }
    const frequencyIndex = bitstream.readBits(4);
    let sampleRate = null;
    if (frequencyIndex === 15) {
        sampleRate = bitstream.readBits(24);
    }
    else {
        if (frequencyIndex < aacFrequencyTable.length) {
            sampleRate = aacFrequencyTable[frequencyIndex];
        }
    }
    const channelConfiguration = bitstream.readBits(4);
    let numberOfChannels = null;
    if (channelConfiguration >= 1 && channelConfiguration <= 7) {
        numberOfChannels = aacChannelMap[channelConfiguration];
    }
    return {
        objectType,
        frequencyIndex,
        sampleRate,
        channelConfiguration,
        numberOfChannels,
    };
};
const buildAacAudioSpecificConfig = (config) => {
    let frequencyIndex = aacFrequencyTable.indexOf(config.sampleRate);
    let customSampleRate = null;
    if (frequencyIndex === -1) {
        frequencyIndex = 15;
        customSampleRate = config.sampleRate;
    }
    const channelConfiguration = aacChannelMap.indexOf(config.numberOfChannels);
    if (channelConfiguration === -1) {
        throw new TypeError(`Unsupported number of channels: ${config.numberOfChannels}`);
    }
    let bitCount = 5 + 4 + 4;
    if (config.objectType >= 32) {
        bitCount += 6;
    }
    if (frequencyIndex === 15) {
        bitCount += 24;
    }
    const byteCount = Math.ceil(bitCount / 8);
    const bytes = new Uint8Array(byteCount);
    const bitstream = new Bitstream(bytes);
    if (config.objectType < 32) {
        bitstream.writeBits(5, config.objectType);
    }
    else {
        bitstream.writeBits(5, 31);
        bitstream.writeBits(6, config.objectType - 32);
    }
    bitstream.writeBits(4, frequencyIndex);
    if (frequencyIndex === 15) {
        bitstream.writeBits(24, customSampleRate);
    }
    bitstream.writeBits(4, channelConfiguration);
    return bytes;
};
const buildAdtsHeaderTemplate = (config) => {
    const header = new Uint8Array(7);
    const bitstream = new Bitstream(header);
    const { objectType, frequencyIndex, channelConfiguration } = config;
    const profile = objectType - 1;
    bitstream.writeBits(12, 0b1111_11111111); // Syncword
    bitstream.writeBits(1, 0); // MPEG Version
    bitstream.writeBits(2, 0); // Layer
    bitstream.writeBits(1, 1); // Protection absence
    bitstream.writeBits(2, profile); // Profile
    bitstream.writeBits(4, frequencyIndex); // MPEG-4 Sampling Frequency Index
    bitstream.writeBits(1, 0); // Private bit
    bitstream.writeBits(3, channelConfiguration); // MPEG-4 Channel Configuration
    bitstream.writeBits(1, 0); // Originality
    bitstream.writeBits(1, 0); // Home
    bitstream.writeBits(1, 0); // Copyright ID bit
    bitstream.writeBits(1, 0); // Copyright ID start
    bitstream.skipBits(13); // Frame length (to be filled per packet)
    bitstream.writeBits(11, 0x7ff); // Buffer fullness
    bitstream.writeBits(2, 0); // Number of AAC frames minus 1
    // Omit CRC check
    return { header, bitstream };
};
const writeAdtsFrameLength = (bitstream, frameLength) => {
    bitstream.pos = 30;
    bitstream.writeBits(13, frameLength);
};


/***/ },

/***/ 2788
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   EZ: () => (/* binding */ getXingOffset),
/* harmony export */   Fm: () => (/* binding */ decodeSynchsafe),
/* harmony export */   MJ: () => (/* binding */ XingFlags),
/* harmony export */   P8: () => (/* binding */ readMp3FrameHeader),
/* harmony export */   Yq: () => (/* binding */ FRAME_HEADER_SIZE),
/* harmony export */   hD: () => (/* binding */ computeAverageMp3FrameSize),
/* harmony export */   hY: () => (/* binding */ XING),
/* harmony export */   rD: () => (/* binding */ INFO)
/* harmony export */ });
/* unused harmony exports SAMPLING_RATES, KILOBIT_RATES, computeMp3FrameSize, encodeSynchsafe */
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
const FRAME_HEADER_SIZE = 4;
const SAMPLING_RATES = [44100, 48000, 32000];
const KILOBIT_RATES = [
    // lowSamplingFrequency === 0
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, // layer = 0
    -1, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, -1, // layer 1
    -1, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, -1, // layer = 2
    -1, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448, -1, // layer = 3
    // lowSamplingFrequency === 1
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, // layer = 0
    -1, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, -1, // layer = 1
    -1, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, -1, // layer = 2
    -1, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256, -1, // layer = 3
];
/** 'Xing' */
const XING = 0x58696e67;
/** 'Info' */
const INFO = 0x496e666f;
const computeMp3FrameSize = (lowSamplingFrequency, layer, bitrate, sampleRate, padding) => {
    if (layer === 0) {
        return 0; // Not expected that this is hit
    }
    else if (layer === 1) {
        return Math.floor(144 * bitrate / (sampleRate << lowSamplingFrequency)) + padding;
    }
    else if (layer === 2) {
        return Math.floor(144 * bitrate / sampleRate) + padding;
    }
    else { // layer === 3
        return (Math.floor(12 * bitrate / sampleRate) + padding) * 4;
    }
};
const computeAverageMp3FrameSize = (lowSamplingFrequency, layer, bitrate, sampleRate) => {
    if (layer === 0) {
        return 0; // Not expected that this is hit
    }
    else if (layer === 1) {
        return 144 * bitrate / (sampleRate << lowSamplingFrequency);
    }
    else if (layer === 2) {
        return 144 * bitrate / sampleRate;
    }
    else { // layer === 3
        return (12 * bitrate / sampleRate) * 4;
    }
};
const getXingOffset = (mpegVersionId, channel) => {
    return mpegVersionId === 3
        ? (channel === 3 ? 21 : 36)
        : (channel === 3 ? 13 : 21);
};
const readMp3FrameHeader = (word, remainingBytes) => {
    const firstByte = word >>> 24;
    const secondByte = (word >>> 16) & 0xff;
    const thirdByte = (word >>> 8) & 0xff;
    const fourthByte = word & 0xff;
    if (firstByte !== 0xff && secondByte !== 0xff && thirdByte !== 0xff && fourthByte !== 0xff) {
        return {
            header: null,
            bytesAdvanced: 4,
        };
    }
    if (firstByte !== 0xff) {
        return { header: null, bytesAdvanced: 1 };
    }
    if ((secondByte & 0xe0) !== 0xe0) {
        return { header: null, bytesAdvanced: 1 };
    }
    let lowSamplingFrequency = 0;
    let mpeg25 = 0;
    if (secondByte & (1 << 4)) {
        lowSamplingFrequency = (secondByte & (1 << 3)) ? 0 : 1;
    }
    else {
        lowSamplingFrequency = 1;
        mpeg25 = 1;
    }
    const mpegVersionId = (secondByte >> 3) & 0x3;
    const layer = (secondByte >> 1) & 0x3;
    const bitrateIndex = (thirdByte >> 4) & 0xf;
    const frequencyIndex = ((thirdByte >> 2) & 0x3) % 3;
    const padding = (thirdByte >> 1) & 0x1;
    const channel = (fourthByte >> 6) & 0x3;
    const modeExtension = (fourthByte >> 4) & 0x3;
    const copyright = (fourthByte >> 3) & 0x1;
    const original = (fourthByte >> 2) & 0x1;
    const emphasis = fourthByte & 0x3;
    const kilobitRate = KILOBIT_RATES[lowSamplingFrequency * 16 * 4 + layer * 16 + bitrateIndex];
    if (kilobitRate === -1) {
        return { header: null, bytesAdvanced: 1 };
    }
    const bitrate = kilobitRate * 1000;
    const sampleRate = SAMPLING_RATES[frequencyIndex] >> (lowSamplingFrequency + mpeg25);
    const frameLength = computeMp3FrameSize(lowSamplingFrequency, layer, bitrate, sampleRate, padding);
    if (remainingBytes !== null && remainingBytes < frameLength) {
        // The frame doesn't fit into the rest of the file
        return { header: null, bytesAdvanced: 1 };
    }
    let audioSamplesInFrame;
    if (mpegVersionId === 3) {
        audioSamplesInFrame = layer === 3 ? 384 : 1152;
    }
    else {
        if (layer === 3) {
            audioSamplesInFrame = 384;
        }
        else if (layer === 2) {
            audioSamplesInFrame = 1152;
        }
        else {
            audioSamplesInFrame = 576;
        }
    }
    return {
        header: {
            totalSize: frameLength,
            mpegVersionId,
            lowSamplingFrequency,
            layer,
            bitrate,
            frequencyIndex,
            sampleRate,
            channel,
            modeExtension,
            copyright,
            original,
            emphasis,
            audioSamplesInFrame,
        },
        bytesAdvanced: 1,
    };
};
const encodeSynchsafe = (unsynchsafed) => {
    let mask = 0x7f;
    let synchsafed = 0;
    let unsynchsafedRest = unsynchsafed;
    while ((mask ^ 0x7fffffff) !== 0) {
        synchsafed = unsynchsafedRest & ~mask;
        synchsafed <<= 1;
        synchsafed |= unsynchsafedRest & mask;
        mask = ((mask + 1) << 8) - 1;
        unsynchsafedRest = synchsafed;
    }
    return synchsafed;
};
const decodeSynchsafe = (synchsafed) => {
    let mask = 0x7f000000;
    let unsynchsafed = 0;
    while (mask !== 0) {
        unsynchsafed >>= 1;
        unsynchsafed |= synchsafed & mask;
        mask >>= 8;
    }
    return unsynchsafed;
};
var XingFlags;
(function (XingFlags) {
    XingFlags[XingFlags["FrameCount"] = 1] = "FrameCount";
    XingFlags[XingFlags["FileSize"] = 2] = "FileSize";
    XingFlags[XingFlags["Toc"] = 4] = "Toc";
})(XingFlags || (XingFlags = {}));


/***/ },

/***/ 6297
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   A3: () => (/* binding */ FlacBlockType),
/* harmony export */   BP: () => (/* binding */ deserializeAvcDecoderConfigurationRecord),
/* harmony export */   Co: () => (/* binding */ parseModesFromVorbisSetupPacket),
/* harmony export */   D5: () => (/* binding */ extractHevcDecoderConfigurationRecord),
/* harmony export */   FY: () => (/* binding */ EAC3_NUMBLKS_TABLE),
/* harmony export */   Ir: () => (/* binding */ AC3_SAMPLES_PER_FRAME),
/* harmony export */   LM: () => (/* binding */ parseAc3SyncFrame),
/* harmony export */   O9: () => (/* binding */ extractNalUnitTypeForHevc),
/* harmony export */   Oc: () => (/* binding */ readVorbisComments),
/* harmony export */   PK: () => (/* binding */ getEac3SampleRate),
/* harmony export */   PR: () => (/* binding */ determineVideoPacketType),
/* harmony export */   Pl: () => (/* binding */ AC3_FRAME_SIZES),
/* harmony export */   Qf: () => (/* binding */ parseOpusIdentificationHeader),
/* harmony export */   RF: () => (/* binding */ iterateHevcNalUnits),
/* harmony export */   RO: () => (/* binding */ iterateAvcNalUnits),
/* harmony export */   Sd: () => (/* binding */ parseEac3Config),
/* harmony export */   UU: () => (/* binding */ extractAv1CodecInfoFromPacket),
/* harmony export */   Zi: () => (/* binding */ concatAvcNalUnits),
/* harmony export */   bs: () => (/* binding */ extractVp9CodecInfoFromPacket),
/* harmony export */   eM: () => (/* binding */ parseAvcSps),
/* harmony export */   fH: () => (/* binding */ extractAvcDecoderConfigurationRecord),
/* harmony export */   gT: () => (/* binding */ parseHevcSps),
/* harmony export */   iJ: () => (/* binding */ HevcNalUnitType),
/* harmony export */   ls: () => (/* binding */ parseOpusTocByte),
/* harmony export */   mY: () => (/* binding */ AvcNalUnitType),
/* harmony export */   oL: () => (/* binding */ parseEac3SyncFrame),
/* harmony export */   uN: () => (/* binding */ extractNalUnitTypeForAvc),
/* harmony export */   ux: () => (/* binding */ AC3_ACMOD_CHANNEL_COUNTS),
/* harmony export */   zV: () => (/* binding */ getEac3ChannelCount)
/* harmony export */ });
/* unused harmony exports iterateNalUnitsInAnnexB, iterateNalUnitsInLengthPrefixed, concatNalUnitsInAnnexB, concatNalUnitsInLengthPrefixed, serializeAvcDecoderConfigurationRecord, serializeHevcDecoderConfigurationRecord, deserializeHevcDecoderConfigurationRecord, iterateAv1PacketObus, createVorbisComments, AC3_REGISTRATION_DESCRIPTOR, EAC3_REGISTRATION_DESCRIPTOR */
/* unused harmony import specifier */ var assert;
/* unused harmony import specifier */ var toDataView;
/* unused harmony import specifier */ var textEncoder;
/* unused harmony import specifier */ var keyValueIterator;
/* unused harmony import specifier */ var bytesToBase64;
/* unused harmony import specifier */ var assertNever;
/* harmony import */ var _codec_js__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(1188);
/* harmony import */ var _misc_js__WEBPACK_IMPORTED_MODULE_1__ = __webpack_require__(3912);
/* harmony import */ var _shared_ac3_misc_js__WEBPACK_IMPORTED_MODULE_2__ = __webpack_require__(7553);
/* harmony import */ var _shared_bitstream_js__WEBPACK_IMPORTED_MODULE_3__ = __webpack_require__(1390);
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */




// References for AVC/HEVC code:
// ISO 14496-15
// Rec. ITU-T H.264
// Rec. ITU-T H.265
// https://stackoverflow.com/questions/24884827
var AvcNalUnitType;
(function (AvcNalUnitType) {
    AvcNalUnitType[AvcNalUnitType["NON_IDR_SLICE"] = 1] = "NON_IDR_SLICE";
    AvcNalUnitType[AvcNalUnitType["SLICE_DPA"] = 2] = "SLICE_DPA";
    AvcNalUnitType[AvcNalUnitType["SLICE_DPB"] = 3] = "SLICE_DPB";
    AvcNalUnitType[AvcNalUnitType["SLICE_DPC"] = 4] = "SLICE_DPC";
    AvcNalUnitType[AvcNalUnitType["IDR"] = 5] = "IDR";
    AvcNalUnitType[AvcNalUnitType["SEI"] = 6] = "SEI";
    AvcNalUnitType[AvcNalUnitType["SPS"] = 7] = "SPS";
    AvcNalUnitType[AvcNalUnitType["PPS"] = 8] = "PPS";
    AvcNalUnitType[AvcNalUnitType["AUD"] = 9] = "AUD";
    AvcNalUnitType[AvcNalUnitType["SPS_EXT"] = 13] = "SPS_EXT";
})(AvcNalUnitType || (AvcNalUnitType = {}));
var HevcNalUnitType;
(function (HevcNalUnitType) {
    HevcNalUnitType[HevcNalUnitType["RASL_N"] = 8] = "RASL_N";
    HevcNalUnitType[HevcNalUnitType["RASL_R"] = 9] = "RASL_R";
    HevcNalUnitType[HevcNalUnitType["BLA_W_LP"] = 16] = "BLA_W_LP";
    HevcNalUnitType[HevcNalUnitType["RSV_IRAP_VCL23"] = 23] = "RSV_IRAP_VCL23";
    HevcNalUnitType[HevcNalUnitType["VPS_NUT"] = 32] = "VPS_NUT";
    HevcNalUnitType[HevcNalUnitType["SPS_NUT"] = 33] = "SPS_NUT";
    HevcNalUnitType[HevcNalUnitType["PPS_NUT"] = 34] = "PPS_NUT";
    HevcNalUnitType[HevcNalUnitType["AUD_NUT"] = 35] = "AUD_NUT";
    HevcNalUnitType[HevcNalUnitType["PREFIX_SEI_NUT"] = 39] = "PREFIX_SEI_NUT";
    HevcNalUnitType[HevcNalUnitType["SUFFIX_SEI_NUT"] = 40] = "SUFFIX_SEI_NUT";
})(HevcNalUnitType || (HevcNalUnitType = {}));
const iterateNalUnitsInAnnexB = function* (packetData) {
    let i = 0;
    let nalStart = -1;
    while (i < packetData.length - 2) {
        const zeroIndex = packetData.indexOf(0, i);
        if (zeroIndex === -1 || zeroIndex >= packetData.length - 2) {
            break;
        }
        i = zeroIndex;
        let startCodeLength = 0;
        // Check for 4-byte start code (0x00000001)
        if (i + 3 < packetData.length
            && packetData[i + 1] === 0
            && packetData[i + 2] === 0
            && packetData[i + 3] === 1) {
            startCodeLength = 4;
        }
        else if (packetData[i + 1] === 0 && packetData[i + 2] === 1) {
            // Check for 3-byte start code (0x000001)
            startCodeLength = 3;
        }
        if (startCodeLength === 0) {
            i++;
            continue;
        }
        // If we had a previous NAL unit, yield it
        if (nalStart !== -1 && i > nalStart) {
            yield {
                offset: nalStart,
                length: i - nalStart,
            };
        }
        nalStart = i + startCodeLength;
        i = nalStart;
    }
    // Yield the last NAL unit if there is one
    if (nalStart !== -1 && nalStart < packetData.length) {
        yield {
            offset: nalStart,
            length: packetData.length - nalStart,
        };
    }
};
const iterateNalUnitsInLengthPrefixed = function* (packetData, lengthSize) {
    let offset = 0;
    const dataView = new DataView(packetData.buffer, packetData.byteOffset, packetData.byteLength);
    while (offset + lengthSize <= packetData.length) {
        let nalUnitLength;
        if (lengthSize === 1) {
            nalUnitLength = dataView.getUint8(offset);
        }
        else if (lengthSize === 2) {
            nalUnitLength = dataView.getUint16(offset, false);
        }
        else if (lengthSize === 3) {
            nalUnitLength = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .getUint24 */ .dq)(dataView, offset, false);
        }
        else {
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .assert */ .vA)(lengthSize === 4);
            nalUnitLength = dataView.getUint32(offset, false);
        }
        offset += lengthSize;
        yield {
            offset,
            length: nalUnitLength,
        };
        offset += nalUnitLength;
    }
};
const iterateAvcNalUnits = (packetData, decoderConfig) => {
    if (decoderConfig.description) {
        const bytes = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .toUint8Array */ .Fo)(decoderConfig.description);
        const lengthSizeMinusOne = bytes[4] & 0b11;
        const lengthSize = (lengthSizeMinusOne + 1);
        return iterateNalUnitsInLengthPrefixed(packetData, lengthSize);
    }
    else {
        return iterateNalUnitsInAnnexB(packetData);
    }
};
const extractNalUnitTypeForAvc = (byte) => {
    return byte & 0x1F;
};
const removeEmulationPreventionBytes = (data) => {
    const result = [];
    const len = data.length;
    for (let i = 0; i < len; i++) {
        // Look for the 0x000003 pattern
        if (i + 2 < len && data[i] === 0x00 && data[i + 1] === 0x00 && data[i + 2] === 0x03) {
            result.push(0x00, 0x00); // Push the first two bytes
            i += 2; // Skip the 0x03 byte
        }
        else {
            result.push(data[i]);
        }
    }
    return new Uint8Array(result);
};
const ANNEX_B_START_CODE = new Uint8Array([0, 0, 0, 1]);
const concatNalUnitsInAnnexB = (nalUnits) => {
    const totalLength = nalUnits.reduce((a, b) => a + ANNEX_B_START_CODE.byteLength + b.byteLength, 0);
    const result = new Uint8Array(totalLength);
    let offset = 0;
    for (const nalUnit of nalUnits) {
        result.set(ANNEX_B_START_CODE, offset);
        offset += ANNEX_B_START_CODE.byteLength;
        result.set(nalUnit, offset);
        offset += nalUnit.byteLength;
    }
    return result;
};
const concatNalUnitsInLengthPrefixed = (nalUnits, lengthSize) => {
    const totalLength = nalUnits.reduce((a, b) => a + lengthSize + b.byteLength, 0);
    const result = new Uint8Array(totalLength);
    let offset = 0;
    for (const nalUnit of nalUnits) {
        const dataView = new DataView(result.buffer, result.byteOffset, result.byteLength);
        switch (lengthSize) {
            case 1:
                dataView.setUint8(offset, nalUnit.byteLength);
                break;
            case 2:
                dataView.setUint16(offset, nalUnit.byteLength, false);
                break;
            case 3:
                (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .setUint24 */ .jD)(dataView, offset, nalUnit.byteLength, false);
                break;
            case 4:
                dataView.setUint32(offset, nalUnit.byteLength, false);
                break;
        }
        offset += lengthSize;
        result.set(nalUnit, offset);
        offset += nalUnit.byteLength;
    }
    return result;
};
const concatAvcNalUnits = (nalUnits, decoderConfig) => {
    if (decoderConfig.description) {
        // Stream is length-prefixed. Let's extract the size of the length prefix from the decoder config
        const bytes = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .toUint8Array */ .Fo)(decoderConfig.description);
        const lengthSizeMinusOne = bytes[4] & 0b11;
        const lengthSize = (lengthSizeMinusOne + 1);
        return concatNalUnitsInLengthPrefixed(nalUnits, lengthSize);
    }
    else {
        // Stream is in Annex B format
        return concatNalUnitsInAnnexB(nalUnits);
    }
};
/** Builds an AvcDecoderConfigurationRecord from an AVC packet in Annex B format. */
const extractAvcDecoderConfigurationRecord = (packetData) => {
    try {
        const spsUnits = [];
        const ppsUnits = [];
        const spsExtUnits = [];
        for (const loc of iterateNalUnitsInAnnexB(packetData)) {
            const nalUnit = packetData.subarray(loc.offset, loc.offset + loc.length);
            const type = extractNalUnitTypeForAvc(nalUnit[0]);
            if (type === AvcNalUnitType.SPS) {
                spsUnits.push(nalUnit);
            }
            else if (type === AvcNalUnitType.PPS) {
                ppsUnits.push(nalUnit);
            }
            else if (type === AvcNalUnitType.SPS_EXT) {
                spsExtUnits.push(nalUnit);
            }
        }
        if (spsUnits.length === 0) {
            return null;
        }
        if (ppsUnits.length === 0) {
            return null;
        }
        // Let's get the first SPS for profile and level information
        const spsData = spsUnits[0];
        const spsInfo = parseAvcSps(spsData);
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .assert */ .vA)(spsInfo !== null);
        const hasExtendedData = spsInfo.profileIdc === 100
            || spsInfo.profileIdc === 110
            || spsInfo.profileIdc === 122
            || spsInfo.profileIdc === 144;
        return {
            configurationVersion: 1,
            avcProfileIndication: spsInfo.profileIdc,
            profileCompatibility: spsInfo.constraintFlags,
            avcLevelIndication: spsInfo.levelIdc,
            lengthSizeMinusOne: 3, // Typically 4 bytes for length field
            sequenceParameterSets: spsUnits,
            pictureParameterSets: ppsUnits,
            chromaFormat: hasExtendedData ? spsInfo.chromaFormatIdc : null,
            bitDepthLumaMinus8: hasExtendedData ? spsInfo.bitDepthLumaMinus8 : null,
            bitDepthChromaMinus8: hasExtendedData ? spsInfo.bitDepthChromaMinus8 : null,
            sequenceParameterSetExt: hasExtendedData ? spsExtUnits : null,
        };
    }
    catch (error) {
        console.error('Error building AVC Decoder Configuration Record:', error);
        return null;
    }
};
/** Serializes an AvcDecoderConfigurationRecord into the format specified in Section 5.3.3.1 of ISO 14496-15. */
const serializeAvcDecoderConfigurationRecord = (record) => {
    const bytes = [];
    // Write header
    bytes.push(record.configurationVersion);
    bytes.push(record.avcProfileIndication);
    bytes.push(record.profileCompatibility);
    bytes.push(record.avcLevelIndication);
    bytes.push(0xFC | (record.lengthSizeMinusOne & 0x03)); // Reserved bits (6) + lengthSizeMinusOne (2)
    // Reserved bits (3) + numOfSequenceParameterSets (5)
    bytes.push(0xE0 | (record.sequenceParameterSets.length & 0x1F));
    // Write SPS
    for (const sps of record.sequenceParameterSets) {
        const length = sps.byteLength;
        bytes.push(length >> 8); // High byte
        bytes.push(length & 0xFF); // Low byte
        for (let i = 0; i < length; i++) {
            bytes.push(sps[i]);
        }
    }
    bytes.push(record.pictureParameterSets.length);
    // Write PPS
    for (const pps of record.pictureParameterSets) {
        const length = pps.byteLength;
        bytes.push(length >> 8); // High byte
        bytes.push(length & 0xFF); // Low byte
        for (let i = 0; i < length; i++) {
            bytes.push(pps[i]);
        }
    }
    if (record.avcProfileIndication === 100
        || record.avcProfileIndication === 110
        || record.avcProfileIndication === 122
        || record.avcProfileIndication === 144) {
        assert(record.chromaFormat !== null);
        assert(record.bitDepthLumaMinus8 !== null);
        assert(record.bitDepthChromaMinus8 !== null);
        assert(record.sequenceParameterSetExt !== null);
        bytes.push(0xFC | (record.chromaFormat & 0x03)); // Reserved bits + chroma_format
        bytes.push(0xF8 | (record.bitDepthLumaMinus8 & 0x07)); // Reserved bits + bit_depth_luma_minus8
        bytes.push(0xF8 | (record.bitDepthChromaMinus8 & 0x07)); // Reserved bits + bit_depth_chroma_minus8
        bytes.push(record.sequenceParameterSetExt.length);
        // Write SPS Ext
        for (const spsExt of record.sequenceParameterSetExt) {
            const length = spsExt.byteLength;
            bytes.push(length >> 8); // High byte
            bytes.push(length & 0xFF); // Low byte
            for (let i = 0; i < length; i++) {
                bytes.push(spsExt[i]);
            }
        }
    }
    return new Uint8Array(bytes);
};
/** Deserializes an AvcDecoderConfigurationRecord from the format specified in Section 5.3.3.1 of ISO 14496-15. */
const deserializeAvcDecoderConfigurationRecord = (data) => {
    try {
        const view = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .toDataView */ .Zc)(data);
        let offset = 0;
        // Read header
        const configurationVersion = view.getUint8(offset++);
        const avcProfileIndication = view.getUint8(offset++);
        const profileCompatibility = view.getUint8(offset++);
        const avcLevelIndication = view.getUint8(offset++);
        const lengthSizeMinusOne = view.getUint8(offset++) & 0x03;
        const numOfSequenceParameterSets = view.getUint8(offset++) & 0x1F;
        // Read SPS
        const sequenceParameterSets = [];
        for (let i = 0; i < numOfSequenceParameterSets; i++) {
            const length = view.getUint16(offset, false);
            offset += 2;
            sequenceParameterSets.push(data.subarray(offset, offset + length));
            offset += length;
        }
        const numOfPictureParameterSets = view.getUint8(offset++);
        // Read PPS
        const pictureParameterSets = [];
        for (let i = 0; i < numOfPictureParameterSets; i++) {
            const length = view.getUint16(offset, false);
            offset += 2;
            pictureParameterSets.push(data.subarray(offset, offset + length));
            offset += length;
        }
        const record = {
            configurationVersion,
            avcProfileIndication,
            profileCompatibility,
            avcLevelIndication,
            lengthSizeMinusOne,
            sequenceParameterSets,
            pictureParameterSets,
            chromaFormat: null,
            bitDepthLumaMinus8: null,
            bitDepthChromaMinus8: null,
            sequenceParameterSetExt: null,
        };
        // Check if there are extended profile fields
        if ((avcProfileIndication === 100
            || avcProfileIndication === 110
            || avcProfileIndication === 122
            || avcProfileIndication === 144)
            && offset + 4 <= data.length) {
            const chromaFormat = view.getUint8(offset++) & 0x03;
            const bitDepthLumaMinus8 = view.getUint8(offset++) & 0x07;
            const bitDepthChromaMinus8 = view.getUint8(offset++) & 0x07;
            const numOfSequenceParameterSetExt = view.getUint8(offset++);
            record.chromaFormat = chromaFormat;
            record.bitDepthLumaMinus8 = bitDepthLumaMinus8;
            record.bitDepthChromaMinus8 = bitDepthChromaMinus8;
            // Read SPS Ext
            const sequenceParameterSetExt = [];
            for (let i = 0; i < numOfSequenceParameterSetExt; i++) {
                const length = view.getUint16(offset, false);
                offset += 2;
                sequenceParameterSetExt.push(data.subarray(offset, offset + length));
                offset += length;
            }
            record.sequenceParameterSetExt = sequenceParameterSetExt;
        }
        return record;
    }
    catch (error) {
        console.error('Error deserializing AVC Decoder Configuration Record:', error);
        return null;
    }
};
const AVC_HEVC_ASPECT_RATIO_IDC_TABLE = {
    1: { num: 1, den: 1 },
    2: { num: 12, den: 11 },
    3: { num: 10, den: 11 },
    4: { num: 16, den: 11 },
    5: { num: 40, den: 33 },
    6: { num: 24, den: 11 },
    7: { num: 20, den: 11 },
    8: { num: 32, den: 11 },
    9: { num: 80, den: 33 },
    10: { num: 18, den: 11 },
    11: { num: 15, den: 11 },
    12: { num: 64, den: 33 },
    13: { num: 160, den: 99 },
    14: { num: 4, den: 3 },
    15: { num: 3, den: 2 },
    16: { num: 2, den: 1 },
};
/** Parses an AVC SPS (Sequence Parameter Set) to extract basic information. */
const parseAvcSps = (sps) => {
    try {
        const bitstream = new _shared_bitstream_js__WEBPACK_IMPORTED_MODULE_3__/* .Bitstream */ ._(removeEmulationPreventionBytes(sps));
        bitstream.skipBits(1); // forbidden_zero_bit
        bitstream.skipBits(2); // nal_ref_idc
        const nalUnitType = bitstream.readBits(5);
        if (nalUnitType !== 7) { // SPS NAL unit type is 7
            return null;
        }
        const profileIdc = bitstream.readAlignedByte();
        const constraintFlags = bitstream.readAlignedByte();
        const levelIdc = bitstream.readAlignedByte();
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // seq_parameter_set_id
        // "When chroma_format_idc is not present, it shall be inferred to be equal to 1 (4:2:0 chroma format)."
        let chromaFormatIdc = 1;
        // "When bit_depth_luma_minus8 is not present, it shall be inferred to be equal to 0.""
        let bitDepthLumaMinus8 = 0;
        // "When bit_depth_chroma_minus8 is not present, it shall be inferred to be equal to 0."
        let bitDepthChromaMinus8 = 0;
        // "When separate_colour_plane_flag is not present, it shall be inferred to be equal to 0."
        let separateColourPlaneFlag = 0;
        // Handle high profile chroma_format_idc
        if (profileIdc === 100
            || profileIdc === 110
            || profileIdc === 122
            || profileIdc === 244
            || profileIdc === 44
            || profileIdc === 83
            || profileIdc === 86
            || profileIdc === 118
            || profileIdc === 128) {
            chromaFormatIdc = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream);
            if (chromaFormatIdc === 3) {
                separateColourPlaneFlag = bitstream.readBits(1);
            }
            bitDepthLumaMinus8 = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream);
            bitDepthChromaMinus8 = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream);
            bitstream.skipBits(1); // qpprime_y_zero_transform_bypass_flag
            const seqScalingMatrixPresentFlag = bitstream.readBits(1);
            if (seqScalingMatrixPresentFlag) {
                for (let i = 0; i < (chromaFormatIdc !== 3 ? 8 : 12); i++) {
                    const seqScalingListPresentFlag = bitstream.readBits(1);
                    if (seqScalingListPresentFlag) {
                        const sizeOfScalingList = i < 6 ? 16 : 64;
                        let lastScale = 8;
                        let nextScale = 8;
                        for (let j = 0; j < sizeOfScalingList; j++) {
                            if (nextScale !== 0) {
                                const deltaScale = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readSignedExpGolomb */ .OO)(bitstream);
                                nextScale = (lastScale + deltaScale + 256) % 256;
                            }
                            lastScale = nextScale === 0 ? lastScale : nextScale;
                        }
                    }
                }
            }
        }
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // log2_max_frame_num_minus4
        const picOrderCntType = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream);
        if (picOrderCntType === 0) {
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // log2_max_pic_order_cnt_lsb_minus4
        }
        else if (picOrderCntType === 1) {
            bitstream.skipBits(1); // delta_pic_order_always_zero_flag
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readSignedExpGolomb */ .OO)(bitstream); // offset_for_non_ref_pic
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readSignedExpGolomb */ .OO)(bitstream); // offset_for_top_to_bottom_field
            const numRefFramesInPicOrderCntCycle = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream);
            for (let i = 0; i < numRefFramesInPicOrderCntCycle; i++) {
                (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readSignedExpGolomb */ .OO)(bitstream); // offset_for_ref_frame[i]
            }
        }
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // max_num_ref_frames
        bitstream.skipBits(1); // gaps_in_frame_num_value_allowed_flag
        const picWidthInMbsMinus1 = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream);
        const picHeightInMapUnitsMinus1 = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream);
        const codedWidth = 16 * (picWidthInMbsMinus1 + 1);
        const codedHeight = 16 * (picHeightInMapUnitsMinus1 + 1);
        let displayWidth = codedWidth;
        let displayHeight = codedHeight;
        const frameMbsOnlyFlag = bitstream.readBits(1);
        if (!frameMbsOnlyFlag) {
            bitstream.skipBits(1); // mb_adaptive_frame_field_flag
        }
        bitstream.skipBits(1); // direct_8x8_inference_flag
        const frameCroppingFlag = bitstream.readBits(1);
        if (frameCroppingFlag) {
            const frameCropLeftOffset = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream);
            const frameCropRightOffset = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream);
            const frameCropTopOffset = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream);
            const frameCropBottomOffset = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream);
            let cropUnitX;
            let cropUnitY;
            const chromaArrayType = separateColourPlaneFlag === 0 ? chromaFormatIdc : 0;
            if (chromaArrayType === 0) {
                // "If ChromaArrayType is equal to 0, CropUnitX and CropUnitY are derived as:"
                cropUnitX = 1;
                cropUnitY = 2 - frameMbsOnlyFlag;
            }
            else {
                // "Otherwise (ChromaArrayType is equal to 1, 2, or 3), CropUnitX and CropUnitY are derived as:"
                const subWidthC = chromaFormatIdc === 3 ? 1 : 2;
                const subHeightC = chromaFormatIdc === 1 ? 2 : 1;
                cropUnitX = subWidthC;
                cropUnitY = subHeightC * (2 - frameMbsOnlyFlag);
            }
            displayWidth -= (cropUnitX * (frameCropLeftOffset + frameCropRightOffset));
            displayHeight -= (cropUnitY * (frameCropTopOffset + frameCropBottomOffset));
        }
        // 2 = unspecified
        let colourPrimaries = 2;
        let transferCharacteristics = 2;
        let matrixCoefficients = 2;
        let fullRangeFlag = 0;
        let pixelAspectRatio = { num: 1, den: 1 };
        let numReorderFrames = null;
        let maxDecFrameBuffering = null;
        const vuiParametersPresentFlag = bitstream.readBits(1);
        if (vuiParametersPresentFlag) {
            const aspectRatioInfoPresentFlag = bitstream.readBits(1);
            if (aspectRatioInfoPresentFlag) {
                const aspectRatioIdc = bitstream.readBits(8);
                if (aspectRatioIdc === 255) { // Extended_SAR
                    pixelAspectRatio = {
                        num: bitstream.readBits(16),
                        den: bitstream.readBits(16),
                    };
                }
                else {
                    const aspectRatio = AVC_HEVC_ASPECT_RATIO_IDC_TABLE[aspectRatioIdc];
                    if (aspectRatio) {
                        pixelAspectRatio = aspectRatio;
                    }
                }
            }
            const overscanInfoPresentFlag = bitstream.readBits(1);
            if (overscanInfoPresentFlag) {
                bitstream.skipBits(1); // overscan_appropriate_flag
            }
            const videoSignalTypePresentFlag = bitstream.readBits(1);
            if (videoSignalTypePresentFlag) {
                bitstream.skipBits(3); // video_format
                fullRangeFlag = bitstream.readBits(1);
                const colourDescriptionPresentFlag = bitstream.readBits(1);
                if (colourDescriptionPresentFlag) {
                    colourPrimaries = bitstream.readBits(8);
                    transferCharacteristics = bitstream.readBits(8);
                    matrixCoefficients = bitstream.readBits(8);
                }
            }
            const chromaLocInfoPresentFlag = bitstream.readBits(1);
            if (chromaLocInfoPresentFlag) {
                (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // chroma_sample_loc_type_top_field
                (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // chroma_sample_loc_type_bottom_field
            }
            const timingInfoPresentFlag = bitstream.readBits(1);
            if (timingInfoPresentFlag) {
                bitstream.skipBits(32); // num_units_in_tick
                bitstream.skipBits(32); // time_scale
                bitstream.skipBits(1); // fixed_frame_rate_flag
            }
            const nalHrdParametersPresentFlag = bitstream.readBits(1);
            if (nalHrdParametersPresentFlag) {
                skipAvcHrdParameters(bitstream);
            }
            const vclHrdParametersPresentFlag = bitstream.readBits(1);
            if (vclHrdParametersPresentFlag) {
                skipAvcHrdParameters(bitstream);
            }
            if (nalHrdParametersPresentFlag || vclHrdParametersPresentFlag) {
                bitstream.skipBits(1); // low_delay_hrd_flag
            }
            bitstream.skipBits(1); // pic_struct_present_flag
            const bitstreamRestrictionFlag = bitstream.readBits(1);
            if (bitstreamRestrictionFlag) {
                bitstream.skipBits(1); // motion_vectors_over_pic_boundaries_flag
                (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // max_bytes_per_pic_denom
                (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // max_bits_per_mb_denom
                (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // log2_max_mv_length_horizontal
                (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // log2_max_mv_length_vertical
                numReorderFrames = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream);
                maxDecFrameBuffering = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream);
            }
        }
        if (numReorderFrames === null) {
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .assert */ .vA)(maxDecFrameBuffering === null);
            const constraintSet3Flag = constraintFlags & 0b00010000;
            if ((profileIdc === 44 || profileIdc === 86 || profileIdc === 100
                || profileIdc === 110 || profileIdc === 122 || profileIdc === 244) && constraintSet3Flag) {
                // "If profile_idc is equal to 44, 86, 100, 110, 122, or 244 and constraint_set3_flag is equal to 1, the
                // value of num_reorder_frames shall be inferred to be equal to 0."
                numReorderFrames = 0;
                maxDecFrameBuffering = 0;
            }
            else {
                const picWidthInMbs = picWidthInMbsMinus1 + 1;
                const picHeightInMapUnits = picHeightInMapUnitsMinus1 + 1;
                const frameHeightInMbs = (2 - frameMbsOnlyFlag) * picHeightInMapUnits;
                const levelInfo = _codec_js__WEBPACK_IMPORTED_MODULE_0__/* .AVC_LEVEL_TABLE */ .$3.find(x => x.level >= levelIdc) ?? (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .last */ ._g)(_codec_js__WEBPACK_IMPORTED_MODULE_0__/* .AVC_LEVEL_TABLE */ .$3);
                // "MaxDpbFrames is equal to
                // Min( MaxDpbMbs / ( picWidthInMbs * frameHeightInMbs ), 16 ) and MaxDpbMbs is given in Table A-1."
                const maxDpbFrames = Math.min(Math.floor(levelInfo.maxDpbMbs / (picWidthInMbs * frameHeightInMbs)), 16);
                // "Otherwise, [...] the value of num_reorder_frames shall be inferred to be equal to MaxDpbFrames."
                numReorderFrames = maxDpbFrames;
                maxDecFrameBuffering = maxDpbFrames;
            }
        }
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .assert */ .vA)(maxDecFrameBuffering !== null);
        return {
            profileIdc,
            constraintFlags,
            levelIdc,
            frameMbsOnlyFlag,
            chromaFormatIdc,
            bitDepthLumaMinus8,
            bitDepthChromaMinus8,
            codedWidth,
            codedHeight,
            displayWidth,
            displayHeight,
            pixelAspectRatio,
            colourPrimaries,
            matrixCoefficients,
            transferCharacteristics,
            fullRangeFlag,
            numReorderFrames,
            maxDecFrameBuffering,
        };
    }
    catch (error) {
        console.error('Error parsing AVC SPS:', error);
        return null;
    }
};
const skipAvcHrdParameters = (bitstream) => {
    const cpb_cnt_minus1 = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream);
    bitstream.skipBits(4); // bit_rate_scale
    bitstream.skipBits(4); // cpb_size_scale
    for (let i = 0; i <= cpb_cnt_minus1; i++) {
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // bit_rate_value_minus1[i]
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // cpb_size_value_minus1[i]
        bitstream.skipBits(1); // cbr_flag[i]
    }
    bitstream.skipBits(5); // initial_cpb_removal_delay_length_minus1
    bitstream.skipBits(5); // cpb_removal_delay_length_minus1
    bitstream.skipBits(5); // dpb_output_delay_length_minus1
    bitstream.skipBits(5); // time_offset_length
};
const iterateHevcNalUnits = (packetData, decoderConfig) => {
    if (decoderConfig.description) {
        const bytes = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .toUint8Array */ .Fo)(decoderConfig.description);
        const lengthSizeMinusOne = bytes[21] & 0b11;
        const lengthSize = (lengthSizeMinusOne + 1);
        return iterateNalUnitsInLengthPrefixed(packetData, lengthSize);
    }
    else {
        return iterateNalUnitsInAnnexB(packetData);
    }
};
const extractNalUnitTypeForHevc = (byte) => {
    return (byte >> 1) & 0x3F;
};
/** Parses an HEVC SPS (Sequence Parameter Set) to extract video information. */
const parseHevcSps = (sps) => {
    try {
        const bitstream = new _shared_bitstream_js__WEBPACK_IMPORTED_MODULE_3__/* .Bitstream */ ._(removeEmulationPreventionBytes(sps));
        bitstream.skipBits(16); // NAL header
        bitstream.readBits(4); // sps_video_parameter_set_id
        const spsMaxSubLayersMinus1 = bitstream.readBits(3);
        const spsTemporalIdNestingFlag = bitstream.readBits(1);
        const { general_profile_space, general_tier_flag, general_profile_idc, general_profile_compatibility_flags, general_constraint_indicator_flags, general_level_idc, } = parseProfileTierLevel(bitstream, spsMaxSubLayersMinus1);
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // sps_seq_parameter_set_id
        const chromaFormatIdc = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream);
        let separateColourPlaneFlag = 0;
        if (chromaFormatIdc === 3) {
            separateColourPlaneFlag = bitstream.readBits(1);
        }
        const picWidthInLumaSamples = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream);
        const picHeightInLumaSamples = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream);
        let displayWidth = picWidthInLumaSamples;
        let displayHeight = picHeightInLumaSamples;
        if (bitstream.readBits(1)) { // conformance_window_flag
            const confWinLeftOffset = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream);
            const confWinRightOffset = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream);
            const confWinTopOffset = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream);
            const confWinBottomOffset = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream);
            // SubWidthC and SubHeightC depend on chroma_format_idc and separate_colour_plane_flag
            let subWidthC = 1;
            let subHeightC = 1;
            const chromaArrayType = separateColourPlaneFlag === 0 ? chromaFormatIdc : 0;
            if (chromaArrayType === 1) {
                subWidthC = 2;
                subHeightC = 2;
            }
            else if (chromaArrayType === 2) {
                subWidthC = 2;
                subHeightC = 1;
            }
            displayWidth -= (confWinLeftOffset + confWinRightOffset) * subWidthC;
            displayHeight -= (confWinTopOffset + confWinBottomOffset) * subHeightC;
        }
        const bitDepthLumaMinus8 = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream);
        const bitDepthChromaMinus8 = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream);
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // log2_max_pic_order_cnt_lsb_minus4
        const spsSubLayerOrderingInfoPresentFlag = bitstream.readBits(1);
        const startI = spsSubLayerOrderingInfoPresentFlag ? 0 : spsMaxSubLayersMinus1;
        let spsMaxNumReorderPics = 0;
        for (let i = startI; i <= spsMaxSubLayersMinus1; i++) {
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // sps_max_dec_pic_buffering_minus1[i]
            spsMaxNumReorderPics = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // sps_max_num_reorder_pics[i]
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // sps_max_latency_increase_plus1[i]
        }
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // log2_min_luma_coding_block_size_minus3
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // log2_diff_max_min_luma_coding_block_size
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // log2_min_luma_transform_block_size_minus2
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // log2_diff_max_min_luma_transform_block_size
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // max_transform_hierarchy_depth_inter
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // max_transform_hierarchy_depth_intra
        if (bitstream.readBits(1)) { // scaling_list_enabled_flag
            if (bitstream.readBits(1)) {
                skipScalingListData(bitstream);
            }
        }
        bitstream.skipBits(1); // amp_enabled_flag
        bitstream.skipBits(1); // sample_adaptive_offset_enabled_flag
        if (bitstream.readBits(1)) { // pcm_enabled_flag
            bitstream.skipBits(4); // pcm_sample_bit_depth_luma_minus1
            bitstream.skipBits(4); // pcm_sample_bit_depth_chroma_minus1
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // log2_min_pcm_luma_coding_block_size_minus3
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // log2_diff_max_min_pcm_luma_coding_block_size
            bitstream.skipBits(1); // pcm_loop_filter_disabled_flag
        }
        const numShortTermRefPicSets = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream);
        skipAllStRefPicSets(bitstream, numShortTermRefPicSets);
        if (bitstream.readBits(1)) { // long_term_ref_pics_present_flag
            const numLongTermRefPicsSps = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream);
            for (let i = 0; i < numLongTermRefPicsSps; i++) {
                (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // lt_ref_pic_poc_lsb_sps[i]
                bitstream.skipBits(1); // used_by_curr_pic_lt_sps_flag[i]
            }
        }
        bitstream.skipBits(1); // sps_temporal_mvp_enabled_flag
        bitstream.skipBits(1); // strong_intra_smoothing_enabled_flag
        let colourPrimaries = 2;
        let transferCharacteristics = 2;
        let matrixCoefficients = 2;
        let fullRangeFlag = 0;
        let minSpatialSegmentationIdc = 0;
        let pixelAspectRatio = { num: 1, den: 1 };
        if (bitstream.readBits(1)) { // vui_parameters_present_flag
            const vui = parseHevcVui(bitstream, spsMaxSubLayersMinus1);
            pixelAspectRatio = vui.pixelAspectRatio;
            colourPrimaries = vui.colourPrimaries;
            transferCharacteristics = vui.transferCharacteristics;
            matrixCoefficients = vui.matrixCoefficients;
            fullRangeFlag = vui.fullRangeFlag;
            minSpatialSegmentationIdc = vui.minSpatialSegmentationIdc;
        }
        return {
            displayWidth,
            displayHeight,
            pixelAspectRatio,
            colourPrimaries,
            transferCharacteristics,
            matrixCoefficients,
            fullRangeFlag,
            maxDecFrameBuffering: spsMaxNumReorderPics + 1,
            spsMaxSubLayersMinus1,
            spsTemporalIdNestingFlag,
            generalProfileSpace: general_profile_space,
            generalTierFlag: general_tier_flag,
            generalProfileIdc: general_profile_idc,
            generalProfileCompatibilityFlags: general_profile_compatibility_flags,
            generalConstraintIndicatorFlags: general_constraint_indicator_flags,
            generalLevelIdc: general_level_idc,
            chromaFormatIdc,
            bitDepthLumaMinus8,
            bitDepthChromaMinus8,
            minSpatialSegmentationIdc,
        };
    }
    catch (error) {
        console.error('Error parsing HEVC SPS:', error);
        return null;
    }
};
/** Builds a HevcDecoderConfigurationRecord from an HEVC packet in Annex B format. */
const extractHevcDecoderConfigurationRecord = (packetData) => {
    try {
        const vpsUnits = [];
        const spsUnits = [];
        const ppsUnits = [];
        const seiUnits = [];
        for (const loc of iterateNalUnitsInAnnexB(packetData)) {
            const nalUnit = packetData.subarray(loc.offset, loc.offset + loc.length);
            const type = extractNalUnitTypeForHevc(nalUnit[0]);
            if (type === HevcNalUnitType.VPS_NUT) {
                vpsUnits.push(nalUnit);
            }
            else if (type === HevcNalUnitType.SPS_NUT) {
                spsUnits.push(nalUnit);
            }
            else if (type === HevcNalUnitType.PPS_NUT) {
                ppsUnits.push(nalUnit);
            }
            else if (type === HevcNalUnitType.PREFIX_SEI_NUT || type === HevcNalUnitType.SUFFIX_SEI_NUT) {
                seiUnits.push(nalUnit);
            }
        }
        if (spsUnits.length === 0 || ppsUnits.length === 0)
            return null;
        const spsInfo = parseHevcSps(spsUnits[0]);
        if (!spsInfo)
            return null;
        // Parse PPS for parallelismType
        let parallelismType = 0;
        if (ppsUnits.length > 0) {
            const pps = ppsUnits[0];
            const ppsBitstream = new _shared_bitstream_js__WEBPACK_IMPORTED_MODULE_3__/* .Bitstream */ ._(removeEmulationPreventionBytes(pps));
            ppsBitstream.skipBits(16); // NAL header
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(ppsBitstream); // pps_pic_parameter_set_id
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(ppsBitstream); // pps_seq_parameter_set_id
            ppsBitstream.skipBits(1); // dependent_slice_segments_enabled_flag
            ppsBitstream.skipBits(1); // output_flag_present_flag
            ppsBitstream.skipBits(3); // num_extra_slice_header_bits
            ppsBitstream.skipBits(1); // sign_data_hiding_enabled_flag
            ppsBitstream.skipBits(1); // cabac_init_present_flag
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(ppsBitstream); // num_ref_idx_l0_default_active_minus1
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(ppsBitstream); // num_ref_idx_l1_default_active_minus1
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readSignedExpGolomb */ .OO)(ppsBitstream); // init_qp_minus26
            ppsBitstream.skipBits(1); // constrained_intra_pred_flag
            ppsBitstream.skipBits(1); // transform_skip_enabled_flag
            if (ppsBitstream.readBits(1)) { // cu_qp_delta_enabled_flag
                (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(ppsBitstream); // diff_cu_qp_delta_depth
            }
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readSignedExpGolomb */ .OO)(ppsBitstream); // pps_cb_qp_offset
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readSignedExpGolomb */ .OO)(ppsBitstream); // pps_cr_qp_offset
            ppsBitstream.skipBits(1); // pps_slice_chroma_qp_offsets_present_flag
            ppsBitstream.skipBits(1); // weighted_pred_flag
            ppsBitstream.skipBits(1); // weighted_bipred_flag
            ppsBitstream.skipBits(1); // transquant_bypass_enabled_flag
            const tiles_enabled_flag = ppsBitstream.readBits(1);
            const entropy_coding_sync_enabled_flag = ppsBitstream.readBits(1);
            if (!tiles_enabled_flag && !entropy_coding_sync_enabled_flag)
                parallelismType = 0;
            else if (tiles_enabled_flag && !entropy_coding_sync_enabled_flag)
                parallelismType = 2;
            else if (!tiles_enabled_flag && entropy_coding_sync_enabled_flag)
                parallelismType = 3;
            else
                parallelismType = 0;
        }
        const arrays = [
            ...(vpsUnits.length
                ? [
                    {
                        arrayCompleteness: 1,
                        nalUnitType: HevcNalUnitType.VPS_NUT,
                        nalUnits: vpsUnits,
                    },
                ]
                : []),
            ...(spsUnits.length
                ? [
                    {
                        arrayCompleteness: 1,
                        nalUnitType: HevcNalUnitType.SPS_NUT,
                        nalUnits: spsUnits,
                    },
                ]
                : []),
            ...(ppsUnits.length
                ? [
                    {
                        arrayCompleteness: 1,
                        nalUnitType: HevcNalUnitType.PPS_NUT,
                        nalUnits: ppsUnits,
                    },
                ]
                : []),
            ...(seiUnits.length
                ? [
                    {
                        arrayCompleteness: 1,
                        nalUnitType: extractNalUnitTypeForHevc(seiUnits[0][0]),
                        nalUnits: seiUnits,
                    },
                ]
                : []),
        ];
        const record = {
            configurationVersion: 1,
            generalProfileSpace: spsInfo.generalProfileSpace,
            generalTierFlag: spsInfo.generalTierFlag,
            generalProfileIdc: spsInfo.generalProfileIdc,
            generalProfileCompatibilityFlags: spsInfo.generalProfileCompatibilityFlags,
            generalConstraintIndicatorFlags: spsInfo.generalConstraintIndicatorFlags,
            generalLevelIdc: spsInfo.generalLevelIdc,
            minSpatialSegmentationIdc: spsInfo.minSpatialSegmentationIdc,
            parallelismType,
            chromaFormatIdc: spsInfo.chromaFormatIdc,
            bitDepthLumaMinus8: spsInfo.bitDepthLumaMinus8,
            bitDepthChromaMinus8: spsInfo.bitDepthChromaMinus8,
            avgFrameRate: 0,
            constantFrameRate: 0,
            numTemporalLayers: spsInfo.spsMaxSubLayersMinus1 + 1,
            temporalIdNested: spsInfo.spsTemporalIdNestingFlag,
            lengthSizeMinusOne: 3,
            arrays,
        };
        return record;
    }
    catch (error) {
        console.error('Error building HEVC Decoder Configuration Record:', error);
        return null;
    }
};
const parseProfileTierLevel = (bitstream, maxNumSubLayersMinus1) => {
    const general_profile_space = bitstream.readBits(2);
    const general_tier_flag = bitstream.readBits(1);
    const general_profile_idc = bitstream.readBits(5);
    let general_profile_compatibility_flags = 0;
    for (let i = 0; i < 32; i++) {
        general_profile_compatibility_flags = (general_profile_compatibility_flags << 1) | bitstream.readBits(1);
    }
    const general_constraint_indicator_flags = new Uint8Array(6);
    for (let i = 0; i < 6; i++) {
        general_constraint_indicator_flags[i] = bitstream.readBits(8);
    }
    const general_level_idc = bitstream.readBits(8);
    const sub_layer_profile_present_flag = [];
    const sub_layer_level_present_flag = [];
    for (let i = 0; i < maxNumSubLayersMinus1; i++) {
        sub_layer_profile_present_flag.push(bitstream.readBits(1));
        sub_layer_level_present_flag.push(bitstream.readBits(1));
    }
    if (maxNumSubLayersMinus1 > 0) {
        for (let i = maxNumSubLayersMinus1; i < 8; i++) {
            bitstream.skipBits(2); // reserved_zero_2bits
        }
    }
    for (let i = 0; i < maxNumSubLayersMinus1; i++) {
        if (sub_layer_profile_present_flag[i])
            bitstream.skipBits(88);
        if (sub_layer_level_present_flag[i])
            bitstream.skipBits(8);
    }
    return {
        general_profile_space,
        general_tier_flag,
        general_profile_idc,
        general_profile_compatibility_flags,
        general_constraint_indicator_flags,
        general_level_idc,
    };
};
const skipScalingListData = (bitstream) => {
    for (let sizeId = 0; sizeId < 4; sizeId++) {
        for (let matrixId = 0; matrixId < (sizeId === 3 ? 2 : 6); matrixId++) {
            const scaling_list_pred_mode_flag = bitstream.readBits(1);
            if (!scaling_list_pred_mode_flag) {
                (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // scaling_list_pred_matrix_id_delta
            }
            else {
                const coefNum = Math.min(64, 1 << (4 + (sizeId << 1)));
                if (sizeId > 1) {
                    (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readSignedExpGolomb */ .OO)(bitstream); // scaling_list_dc_coef_minus8
                }
                for (let i = 0; i < coefNum; i++) {
                    (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readSignedExpGolomb */ .OO)(bitstream); // scaling_list_delta_coef
                }
            }
        }
    }
};
const skipAllStRefPicSets = (bitstream, num_short_term_ref_pic_sets) => {
    const NumDeltaPocs = [];
    for (let stRpsIdx = 0; stRpsIdx < num_short_term_ref_pic_sets; stRpsIdx++) {
        NumDeltaPocs[stRpsIdx] = skipStRefPicSet(bitstream, stRpsIdx, num_short_term_ref_pic_sets, NumDeltaPocs);
    }
};
const skipStRefPicSet = (bitstream, stRpsIdx, num_short_term_ref_pic_sets, NumDeltaPocs) => {
    let NumDeltaPocsThis = 0;
    let inter_ref_pic_set_prediction_flag = 0;
    let RefRpsIdx = 0;
    if (stRpsIdx !== 0) {
        inter_ref_pic_set_prediction_flag = bitstream.readBits(1);
    }
    if (inter_ref_pic_set_prediction_flag) {
        if (stRpsIdx === num_short_term_ref_pic_sets) {
            const delta_idx_minus1 = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream);
            RefRpsIdx = stRpsIdx - (delta_idx_minus1 + 1);
        }
        else {
            RefRpsIdx = stRpsIdx - 1;
        }
        bitstream.readBits(1); // delta_rps_sign
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // abs_delta_rps_minus1
        // The number of iterations is NumDeltaPocs[RefRpsIdx] + 1
        const numDelta = NumDeltaPocs[RefRpsIdx] ?? 0;
        for (let j = 0; j <= numDelta; j++) {
            const used_by_curr_pic_flag = bitstream.readBits(1);
            if (!used_by_curr_pic_flag) {
                bitstream.readBits(1); // use_delta_flag
            }
        }
        NumDeltaPocsThis = NumDeltaPocs[RefRpsIdx];
    }
    else {
        const num_negative_pics = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream);
        const num_positive_pics = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream);
        for (let i = 0; i < num_negative_pics; i++) {
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // delta_poc_s0_minus1[i]
            bitstream.readBits(1); // used_by_curr_pic_s0_flag[i]
        }
        for (let i = 0; i < num_positive_pics; i++) {
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // delta_poc_s1_minus1[i]
            bitstream.readBits(1); // used_by_curr_pic_s1_flag[i]
        }
        NumDeltaPocsThis = num_negative_pics + num_positive_pics;
    }
    return NumDeltaPocsThis;
};
const parseHevcVui = (bitstream, sps_max_sub_layers_minus1) => {
    // Defaults: 2 = unspecified
    let colourPrimaries = 2;
    let transferCharacteristics = 2;
    let matrixCoefficients = 2;
    let fullRangeFlag = 0;
    let minSpatialSegmentationIdc = 0;
    let pixelAspectRatio = { num: 1, den: 1 };
    if (bitstream.readBits(1)) { // aspect_ratio_info_present_flag
        const aspect_ratio_idc = bitstream.readBits(8);
        if (aspect_ratio_idc === 255) {
            pixelAspectRatio = {
                num: bitstream.readBits(16),
                den: bitstream.readBits(16),
            };
        }
        else {
            const aspectRatio = AVC_HEVC_ASPECT_RATIO_IDC_TABLE[aspect_ratio_idc];
            if (aspectRatio) {
                pixelAspectRatio = aspectRatio;
            }
        }
    }
    if (bitstream.readBits(1)) { // overscan_info_present_flag
        bitstream.readBits(1); // overscan_appropriate_flag
    }
    if (bitstream.readBits(1)) { // video_signal_type_present_flag
        bitstream.readBits(3); // video_format
        fullRangeFlag = bitstream.readBits(1);
        if (bitstream.readBits(1)) { // colour_description_present_flag
            colourPrimaries = bitstream.readBits(8);
            transferCharacteristics = bitstream.readBits(8);
            matrixCoefficients = bitstream.readBits(8);
        }
    }
    if (bitstream.readBits(1)) { // chroma_loc_info_present_flag
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // chroma_sample_loc_type_top_field
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // chroma_sample_loc_type_bottom_field
    }
    bitstream.readBits(1); // neutral_chroma_indication_flag
    bitstream.readBits(1); // field_seq_flag
    bitstream.readBits(1); // frame_field_info_present_flag
    if (bitstream.readBits(1)) { // default_display_window_flag
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // def_disp_win_left_offset
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // def_disp_win_right_offset
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // def_disp_win_top_offset
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // def_disp_win_bottom_offset
    }
    if (bitstream.readBits(1)) { // vui_timing_info_present_flag
        bitstream.readBits(32); // vui_num_units_in_tick
        bitstream.readBits(32); // vui_time_scale
        if (bitstream.readBits(1)) { // vui_poc_proportional_to_timing_flag
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // vui_num_ticks_poc_diff_one_minus1
        }
        if (bitstream.readBits(1)) {
            skipHevcHrdParameters(bitstream, true, sps_max_sub_layers_minus1);
        }
    }
    if (bitstream.readBits(1)) { // bitstream_restriction_flag
        bitstream.readBits(1); // tiles_fixed_structure_flag
        bitstream.readBits(1); // motion_vectors_over_pic_boundaries_flag
        bitstream.readBits(1); // restricted_ref_pic_lists_flag
        minSpatialSegmentationIdc = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream);
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // max_bytes_per_pic_denom
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // max_bits_per_min_cu_denom
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // log2_max_mv_length_horizontal
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // log2_max_mv_length_vertical
    }
    return {
        pixelAspectRatio,
        colourPrimaries,
        transferCharacteristics,
        matrixCoefficients,
        fullRangeFlag,
        minSpatialSegmentationIdc,
    };
};
const skipHevcHrdParameters = (bitstream, commonInfPresentFlag, maxNumSubLayersMinus1) => {
    let nal_hrd_parameters_present_flag = false;
    let vcl_hrd_parameters_present_flag = false;
    let sub_pic_hrd_params_present_flag = false;
    if (commonInfPresentFlag) {
        nal_hrd_parameters_present_flag = bitstream.readBits(1) === 1;
        vcl_hrd_parameters_present_flag = bitstream.readBits(1) === 1;
        if (nal_hrd_parameters_present_flag || vcl_hrd_parameters_present_flag) {
            sub_pic_hrd_params_present_flag = bitstream.readBits(1) === 1;
            if (sub_pic_hrd_params_present_flag) {
                bitstream.readBits(8); // tick_divisor_minus2
                bitstream.readBits(5); // du_cpb_removal_delay_increment_length_minus1
                bitstream.readBits(1); // sub_pic_cpb_params_in_pic_timing_sei_flag
                bitstream.readBits(5); // dpb_output_delay_du_length_minus1
            }
            bitstream.readBits(4); // bit_rate_scale
            bitstream.readBits(4); // cpb_size_scale
            if (sub_pic_hrd_params_present_flag) {
                bitstream.readBits(4); // cpb_size_du_scale
            }
            bitstream.readBits(5); // initial_cpb_removal_delay_length_minus1
            bitstream.readBits(5); // au_cpb_removal_delay_length_minus1
            bitstream.readBits(5); // dpb_output_delay_length_minus1
        }
    }
    for (let i = 0; i <= maxNumSubLayersMinus1; i++) {
        const fixed_pic_rate_general_flag = bitstream.readBits(1) === 1;
        let fixed_pic_rate_within_cvs_flag = true; // Default assumption if general is true
        if (!fixed_pic_rate_general_flag) {
            fixed_pic_rate_within_cvs_flag = bitstream.readBits(1) === 1;
        }
        let low_delay_hrd_flag = false; // Default assumption
        if (fixed_pic_rate_within_cvs_flag) {
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // elemental_duration_in_tc_minus1[i]
        }
        else {
            low_delay_hrd_flag = bitstream.readBits(1) === 1;
        }
        let CpbCnt = 1; // Default if low_delay is true
        if (!low_delay_hrd_flag) {
            const cpb_cnt_minus1 = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // cpb_cnt_minus1[i]
            CpbCnt = cpb_cnt_minus1 + 1;
        }
        if (nal_hrd_parameters_present_flag) {
            skipSubLayerHrdParameters(bitstream, CpbCnt, sub_pic_hrd_params_present_flag);
        }
        if (vcl_hrd_parameters_present_flag) {
            skipSubLayerHrdParameters(bitstream, CpbCnt, sub_pic_hrd_params_present_flag);
        }
    }
};
const skipSubLayerHrdParameters = (bitstream, CpbCnt, sub_pic_hrd_params_present_flag) => {
    for (let i = 0; i < CpbCnt; i++) {
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // bit_rate_value_minus1[i]
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // cpb_size_value_minus1[i]
        if (sub_pic_hrd_params_present_flag) {
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // cpb_size_du_value_minus1[i]
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream); // bit_rate_du_value_minus1[i]
        }
        bitstream.readBits(1); // cbr_flag[i]
    }
};
/** Serializes an HevcDecoderConfigurationRecord into the format specified in Section 8.3.3.1 of ISO 14496-15. */
const serializeHevcDecoderConfigurationRecord = (record) => {
    const bytes = [];
    bytes.push(record.configurationVersion);
    bytes.push(((record.generalProfileSpace & 0x3) << 6)
        | ((record.generalTierFlag & 0x1) << 5)
        | (record.generalProfileIdc & 0x1F));
    bytes.push((record.generalProfileCompatibilityFlags >>> 24) & 0xFF);
    bytes.push((record.generalProfileCompatibilityFlags >>> 16) & 0xFF);
    bytes.push((record.generalProfileCompatibilityFlags >>> 8) & 0xFF);
    bytes.push(record.generalProfileCompatibilityFlags & 0xFF);
    bytes.push(...record.generalConstraintIndicatorFlags);
    bytes.push(record.generalLevelIdc & 0xFF);
    bytes.push(0xF0 | ((record.minSpatialSegmentationIdc >> 8) & 0x0F)); // Reserved + high nibble
    bytes.push(record.minSpatialSegmentationIdc & 0xFF); // Low byte
    bytes.push(0xFC | (record.parallelismType & 0x03));
    bytes.push(0xFC | (record.chromaFormatIdc & 0x03));
    bytes.push(0xF8 | (record.bitDepthLumaMinus8 & 0x07));
    bytes.push(0xF8 | (record.bitDepthChromaMinus8 & 0x07));
    bytes.push((record.avgFrameRate >> 8) & 0xFF); // High byte
    bytes.push(record.avgFrameRate & 0xFF); // Low byte
    bytes.push(((record.constantFrameRate & 0x03) << 6)
        | ((record.numTemporalLayers & 0x07) << 3)
        | ((record.temporalIdNested & 0x01) << 2)
        | (record.lengthSizeMinusOne & 0x03));
    bytes.push(record.arrays.length & 0xFF);
    for (const arr of record.arrays) {
        bytes.push(((arr.arrayCompleteness & 0x01) << 7)
            | (0 << 6)
            | (arr.nalUnitType & 0x3F));
        bytes.push((arr.nalUnits.length >> 8) & 0xFF); // High byte
        bytes.push(arr.nalUnits.length & 0xFF); // Low byte
        for (const nal of arr.nalUnits) {
            bytes.push((nal.length >> 8) & 0xFF); // High byte
            bytes.push(nal.length & 0xFF); // Low byte
            for (let i = 0; i < nal.length; i++) {
                bytes.push(nal[i]);
            }
        }
    }
    return new Uint8Array(bytes);
};
/** Deserializes an HevcDecoderConfigurationRecord from the format specified in Section 8.3.3.1 of ISO 14496-15. */
const deserializeHevcDecoderConfigurationRecord = (data) => {
    try {
        const view = toDataView(data);
        let offset = 0;
        const configurationVersion = view.getUint8(offset++);
        const byte1 = view.getUint8(offset++);
        const generalProfileSpace = (byte1 >> 6) & 0x3;
        const generalTierFlag = (byte1 >> 5) & 0x1;
        const generalProfileIdc = byte1 & 0x1F;
        const generalProfileCompatibilityFlags = view.getUint32(offset, false);
        offset += 4;
        const generalConstraintIndicatorFlags = data.subarray(offset, offset + 6);
        offset += 6;
        const generalLevelIdc = view.getUint8(offset++);
        const minSpatialSegmentationIdc = ((view.getUint8(offset++) & 0x0F) << 8) | view.getUint8(offset++);
        const parallelismType = view.getUint8(offset++) & 0x03;
        const chromaFormatIdc = view.getUint8(offset++) & 0x03;
        const bitDepthLumaMinus8 = view.getUint8(offset++) & 0x07;
        const bitDepthChromaMinus8 = view.getUint8(offset++) & 0x07;
        const avgFrameRate = view.getUint16(offset, false);
        offset += 2;
        const byte21 = view.getUint8(offset++);
        const constantFrameRate = (byte21 >> 6) & 0x03;
        const numTemporalLayers = (byte21 >> 3) & 0x07;
        const temporalIdNested = (byte21 >> 2) & 0x01;
        const lengthSizeMinusOne = byte21 & 0x03;
        const numOfArrays = view.getUint8(offset++);
        const arrays = [];
        for (let i = 0; i < numOfArrays; i++) {
            const arrByte = view.getUint8(offset++);
            const arrayCompleteness = (arrByte >> 7) & 0x01;
            const nalUnitType = arrByte & 0x3F;
            const numNalus = view.getUint16(offset, false);
            offset += 2;
            const nalUnits = [];
            for (let j = 0; j < numNalus; j++) {
                const nalUnitLength = view.getUint16(offset, false);
                offset += 2;
                nalUnits.push(data.subarray(offset, offset + nalUnitLength));
                offset += nalUnitLength;
            }
            arrays.push({
                arrayCompleteness,
                nalUnitType,
                nalUnits,
            });
        }
        return {
            configurationVersion,
            generalProfileSpace,
            generalTierFlag,
            generalProfileIdc,
            generalProfileCompatibilityFlags,
            generalConstraintIndicatorFlags,
            generalLevelIdc,
            minSpatialSegmentationIdc,
            parallelismType,
            chromaFormatIdc,
            bitDepthLumaMinus8,
            bitDepthChromaMinus8,
            avgFrameRate,
            constantFrameRate,
            numTemporalLayers,
            temporalIdNested,
            lengthSizeMinusOne,
            arrays,
        };
    }
    catch (error) {
        console.error('Error deserializing HEVC Decoder Configuration Record:', error);
        return null;
    }
};
const extractVp9CodecInfoFromPacket = (packet) => {
    // eslint-disable-next-line @stylistic/max-len
    // https://storage.googleapis.com/downloads.webmproject.org/docs/vp9/vp9-bitstream-specification-v0.7-20170222-draft.pdf
    // http://downloads.webmproject.org/docs/vp9/vp9-bitstream_superframe-and-uncompressed-header_v1.0.pdf
    const bitstream = new _shared_bitstream_js__WEBPACK_IMPORTED_MODULE_3__/* .Bitstream */ ._(packet);
    // Frame marker (0b10)
    const frameMarker = bitstream.readBits(2);
    if (frameMarker !== 2) {
        return null;
    }
    // Profile
    const profileLowBit = bitstream.readBits(1);
    const profileHighBit = bitstream.readBits(1);
    const profile = (profileHighBit << 1) + profileLowBit;
    // Skip reserved bit for profile 3
    if (profile === 3) {
        bitstream.skipBits(1);
    }
    // show_existing_frame
    const showExistingFrame = bitstream.readBits(1);
    if (showExistingFrame === 1) {
        return null;
    }
    // frame_type (0 = key frame)
    const frameType = bitstream.readBits(1);
    if (frameType !== 0) {
        return null;
    }
    // Skip show_frame and error_resilient_mode
    bitstream.skipBits(2);
    // Sync code (0x498342)
    const syncCode = bitstream.readBits(24);
    if (syncCode !== 0x498342) {
        return null;
    }
    // Color config
    let bitDepth = 8;
    if (profile >= 2) {
        const tenOrTwelveBit = bitstream.readBits(1);
        bitDepth = tenOrTwelveBit ? 12 : 10;
    }
    // Color space
    const colorSpace = bitstream.readBits(3);
    let chromaSubsampling = 0;
    let videoFullRangeFlag = 0;
    if (colorSpace !== 7) { // 7 is CS_RGB
        const colorRange = bitstream.readBits(1);
        videoFullRangeFlag = colorRange;
        if (profile === 1 || profile === 3) {
            const subsamplingX = bitstream.readBits(1);
            const subsamplingY = bitstream.readBits(1);
            // 0 = 4:2:0 vertical
            // 1 = 4:2:0 colocated
            // 2 = 4:2:2
            // 3 = 4:4:4
            chromaSubsampling = !subsamplingX && !subsamplingY
                ? 3 // 0,0 = 4:4:4
                : subsamplingX && !subsamplingY
                    ? 2 // 1,0 = 4:2:2
                    : 1; // 1,1 = 4:2:0 colocated (default)
            // Skip reserved bit
            bitstream.skipBits(1);
        }
        else {
            // For profile 0 and 2, always 4:2:0
            chromaSubsampling = 1; // Using colocated as default
        }
    }
    else {
        // RGB is always 4:4:4
        chromaSubsampling = 3;
        videoFullRangeFlag = 1;
    }
    // Parse frame size
    const widthMinusOne = bitstream.readBits(16);
    const heightMinusOne = bitstream.readBits(16);
    const width = widthMinusOne + 1;
    const height = heightMinusOne + 1;
    // Calculate level based on dimensions
    const pictureSize = width * height;
    let level = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .last */ ._g)(_codec_js__WEBPACK_IMPORTED_MODULE_0__/* .VP9_LEVEL_TABLE */ .ye).level; // Default to highest level
    for (const entry of _codec_js__WEBPACK_IMPORTED_MODULE_0__/* .VP9_LEVEL_TABLE */ .ye) {
        if (pictureSize <= entry.maxPictureSize) {
            level = entry.level;
            break;
        }
    }
    // Map color_space to standard values
    const matrixCoefficients = colorSpace === 7
        ? 0
        : colorSpace === 2
            ? 1
            : colorSpace === 1
                ? 6
                : 2;
    const colourPrimaries = colorSpace === 2
        ? 1
        : colorSpace === 1
            ? 6
            : 2;
    const transferCharacteristics = colorSpace === 2
        ? 1
        : colorSpace === 1
            ? 6
            : 2;
    return {
        profile,
        level,
        bitDepth,
        chromaSubsampling,
        videoFullRangeFlag,
        colourPrimaries,
        transferCharacteristics,
        matrixCoefficients,
    };
};
/** Iterates over all OBUs in an AV1 packet bistream. */
const iterateAv1PacketObus = function* (packet) {
    // https://aomediacodec.github.io/av1-spec/av1-spec.pdf
    const bitstream = new _shared_bitstream_js__WEBPACK_IMPORTED_MODULE_3__/* .Bitstream */ ._(packet);
    const readLeb128 = () => {
        let value = 0;
        for (let i = 0; i < 8; i++) {
            const byte = bitstream.readAlignedByte();
            value |= ((byte & 0x7f) << (i * 7));
            if (!(byte & 0x80)) {
                break;
            }
            // Spec requirement
            if (i === 7 && (byte & 0x80)) {
                return null;
            }
        }
        // Spec requirement
        if (value >= 2 ** 32 - 1) {
            return null;
        }
        return value;
    };
    while (bitstream.getBitsLeft() >= 8) {
        // Parse OBU header
        bitstream.skipBits(1);
        const obuType = bitstream.readBits(4);
        const obuExtension = bitstream.readBits(1);
        const obuHasSizeField = bitstream.readBits(1);
        bitstream.skipBits(1);
        // Skip extension header if present
        if (obuExtension) {
            bitstream.skipBits(8);
        }
        // Read OBU size if present
        let obuSize;
        if (obuHasSizeField) {
            const obuSizeValue = readLeb128();
            if (obuSizeValue === null)
                return; // It was invalid
            obuSize = obuSizeValue;
        }
        else {
            // Calculate remaining bits and convert to bytes, rounding down
            obuSize = Math.floor(bitstream.getBitsLeft() / 8);
        }
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .assert */ .vA)(bitstream.pos % 8 === 0);
        yield {
            type: obuType,
            data: packet.subarray(bitstream.pos / 8, bitstream.pos / 8 + obuSize),
        };
        // Move to next OBU
        bitstream.skipBits(obuSize * 8);
    }
};
/**
 * When AV1 codec information is not provided by the container, we can still try to extract the information by digging
 * into the AV1 bitstream.
 */
const extractAv1CodecInfoFromPacket = (packet) => {
    // https://aomediacodec.github.io/av1-spec/av1-spec.pdf
    for (const { type, data } of iterateAv1PacketObus(packet)) {
        if (type !== 1) {
            continue; // 1 == OBU_SEQUENCE_HEADER
        }
        const bitstream = new _shared_bitstream_js__WEBPACK_IMPORTED_MODULE_3__/* .Bitstream */ ._(data);
        // Read sequence header fields
        const seqProfile = bitstream.readBits(3);
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        const stillPicture = bitstream.readBits(1);
        const reducedStillPictureHeader = bitstream.readBits(1);
        let seqLevel = 0;
        let seqTier = 0;
        let bufferDelayLengthMinus1 = 0;
        if (reducedStillPictureHeader) {
            seqLevel = bitstream.readBits(5);
        }
        else {
            // Parse timing_info_present_flag
            const timingInfoPresentFlag = bitstream.readBits(1);
            if (timingInfoPresentFlag) {
                // Skip timing info (num_units_in_display_tick, time_scale, equal_picture_interval)
                bitstream.skipBits(32); // num_units_in_display_tick
                bitstream.skipBits(32); // time_scale
                const equalPictureInterval = bitstream.readBits(1);
                if (equalPictureInterval) {
                    // Skip num_ticks_per_picture_minus_1 (uvlc)
                    // Since this is variable length, we'd need to implement uvlc reading
                    // For now, we'll return null as this is rare
                    return null;
                }
            }
            // Parse decoder_model_info_present_flag
            const decoderModelInfoPresentFlag = bitstream.readBits(1);
            if (decoderModelInfoPresentFlag) {
                // Store buffer_delay_length_minus_1 instead of just skipping
                bufferDelayLengthMinus1 = bitstream.readBits(5);
                bitstream.skipBits(32); // num_units_in_decoding_tick
                bitstream.skipBits(5); // buffer_removal_time_length_minus_1
                bitstream.skipBits(5); // frame_presentation_time_length_minus_1
            }
            // Parse operating_points_cnt_minus_1
            const operatingPointsCntMinus1 = bitstream.readBits(5);
            // For each operating point
            for (let i = 0; i <= operatingPointsCntMinus1; i++) {
                // operating_point_idc[i]
                bitstream.skipBits(12);
                // seq_level_idx[i]
                const seqLevelIdx = bitstream.readBits(5);
                if (i === 0) {
                    seqLevel = seqLevelIdx;
                }
                if (seqLevelIdx > 7) {
                    // seq_tier[i]
                    const seqTierTemp = bitstream.readBits(1);
                    if (i === 0) {
                        seqTier = seqTierTemp;
                    }
                }
                if (decoderModelInfoPresentFlag) {
                    // decoder_model_present_for_this_op[i]
                    const decoderModelPresentForThisOp = bitstream.readBits(1);
                    if (decoderModelPresentForThisOp) {
                        const n = bufferDelayLengthMinus1 + 1;
                        bitstream.skipBits(n); // decoder_buffer_delay[op]
                        bitstream.skipBits(n); // encoder_buffer_delay[op]
                        bitstream.skipBits(1); // low_delay_mode_flag[op]
                    }
                }
                // initial_display_delay_present_flag
                const initialDisplayDelayPresentFlag = bitstream.readBits(1);
                if (initialDisplayDelayPresentFlag) {
                    // initial_display_delay_minus_1[i]
                    bitstream.skipBits(4);
                }
            }
        }
        // Frame size
        const frameWidthBitsMinus1 = bitstream.readBits(4);
        const frameHeightBitsMinus1 = bitstream.readBits(4);
        const n1 = frameWidthBitsMinus1 + 1;
        bitstream.skipBits(n1); // max_frame_width_minus_1
        const n2 = frameHeightBitsMinus1 + 1;
        bitstream.skipBits(n2); // max_frame_height_minus_1
        // Frame IDs
        let frameIdNumbersPresentFlag = 0;
        if (reducedStillPictureHeader) {
            frameIdNumbersPresentFlag = 0;
        }
        else {
            frameIdNumbersPresentFlag = bitstream.readBits(1);
        }
        if (frameIdNumbersPresentFlag) {
            bitstream.skipBits(4); // delta_frame_id_length_minus_2
            bitstream.skipBits(3); // additional_frame_id_length_minus_1
        }
        bitstream.skipBits(1); // use_128x128_superblock
        bitstream.skipBits(1); // enable_filter_intra
        bitstream.skipBits(1); // enable_intra_edge_filter
        if (!reducedStillPictureHeader) {
            bitstream.skipBits(1); // enable_interintra_compound
            bitstream.skipBits(1); // enable_masked_compound
            bitstream.skipBits(1); // enable_warped_motion
            bitstream.skipBits(1); // enable_dual_filter
            const enableOrderHint = bitstream.readBits(1);
            if (enableOrderHint) {
                bitstream.skipBits(1); // enable_jnt_comp
                bitstream.skipBits(1); // enable_ref_frame_mvs
            }
            const seqChooseScreenContentTools = bitstream.readBits(1);
            let seqForceScreenContentTools = 0;
            if (seqChooseScreenContentTools) {
                seqForceScreenContentTools = 2; // SELECT_SCREEN_CONTENT_TOOLS
            }
            else {
                seqForceScreenContentTools = bitstream.readBits(1);
            }
            if (seqForceScreenContentTools > 0) {
                const seqChooseIntegerMv = bitstream.readBits(1);
                if (!seqChooseIntegerMv) {
                    bitstream.skipBits(1); // seq_force_integer_mv
                }
            }
            if (enableOrderHint) {
                bitstream.skipBits(3); // order_hint_bits_minus_1
            }
        }
        bitstream.skipBits(1); // enable_superres
        bitstream.skipBits(1); // enable_cdef
        bitstream.skipBits(1); // enable_restoration
        // color_config()
        const highBitdepth = bitstream.readBits(1);
        let bitDepth = 8;
        if (seqProfile === 2 && highBitdepth) {
            const twelveBit = bitstream.readBits(1);
            bitDepth = twelveBit ? 12 : 10;
        }
        else if (seqProfile <= 2) {
            bitDepth = highBitdepth ? 10 : 8;
        }
        let monochrome = 0;
        if (seqProfile !== 1) {
            monochrome = bitstream.readBits(1);
        }
        let chromaSubsamplingX = 1;
        let chromaSubsamplingY = 1;
        let chromaSamplePosition = 0;
        if (!monochrome) {
            if (seqProfile === 0) {
                chromaSubsamplingX = 1;
                chromaSubsamplingY = 1;
            }
            else if (seqProfile === 1) {
                chromaSubsamplingX = 0;
                chromaSubsamplingY = 0;
            }
            else {
                if (bitDepth === 12) {
                    chromaSubsamplingX = bitstream.readBits(1);
                    if (chromaSubsamplingX) {
                        chromaSubsamplingY = bitstream.readBits(1);
                    }
                }
            }
            if (chromaSubsamplingX && chromaSubsamplingY) {
                chromaSamplePosition = bitstream.readBits(2);
            }
        }
        return {
            profile: seqProfile,
            level: seqLevel,
            tier: seqTier,
            bitDepth,
            monochrome,
            chromaSubsamplingX,
            chromaSubsamplingY,
            chromaSamplePosition,
        };
    }
    return null;
};
const parseOpusIdentificationHeader = (bytes) => {
    const view = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .toDataView */ .Zc)(bytes);
    const outputChannelCount = view.getUint8(9);
    const preSkip = view.getUint16(10, true);
    const inputSampleRate = view.getUint32(12, true);
    const outputGain = view.getInt16(16, true);
    const channelMappingFamily = view.getUint8(18);
    let channelMappingTable = null;
    if (channelMappingFamily) {
        channelMappingTable = bytes.subarray(19, 19 + 2 + outputChannelCount);
    }
    return {
        outputChannelCount,
        preSkip,
        inputSampleRate,
        outputGain,
        channelMappingFamily,
        channelMappingTable,
    };
};
// From https://datatracker.ietf.org/doc/html/rfc6716, in 48 kHz samples
const OPUS_FRAME_DURATION_TABLE = [
    480, 960, 1920, 2880,
    480, 960, 1920, 2880,
    480, 960, 1920, 2880,
    480, 960,
    480, 960,
    120, 240, 480, 960,
    120, 240, 480, 960,
    120, 240, 480, 960,
    120, 240, 480, 960,
];
const parseOpusTocByte = (packet) => {
    const config = packet[0] >> 3;
    return {
        durationInSamples: OPUS_FRAME_DURATION_TABLE[config],
    };
};
// Based on vorbis_parser.c from FFmpeg.
const parseModesFromVorbisSetupPacket = (setupHeader) => {
    // Verify that this is a Setup header.
    if (setupHeader.length < 7) {
        throw new Error('Setup header is too short.');
    }
    if (setupHeader[0] !== 5) {
        throw new Error('Wrong packet type in Setup header.');
    }
    const signature = String.fromCharCode(...setupHeader.slice(1, 7));
    if (signature !== 'vorbis') {
        throw new Error('Invalid packet signature in Setup header.');
    }
    // Reverse the entire buffer.
    const bufSize = setupHeader.length;
    const revBuffer = new Uint8Array(bufSize);
    for (let i = 0; i < bufSize; i++) {
        revBuffer[i] = setupHeader[bufSize - 1 - i];
    }
    // Initialize a Bitstream on the reversed buffer.
    const bitstream = new _shared_bitstream_js__WEBPACK_IMPORTED_MODULE_3__/* .Bitstream */ ._(revBuffer);
    // --- Find the framing bit.
    // In FFmpeg code, we scan until get_bits1() returns 1.
    let gotFramingBit = 0;
    while (bitstream.getBitsLeft() > 97) {
        if (bitstream.readBits(1) === 1) {
            gotFramingBit = bitstream.pos;
            break;
        }
    }
    if (gotFramingBit === 0) {
        throw new Error('Invalid Setup header: framing bit not found.');
    }
    // --- Search backwards for a valid mode header.
    // We try to “guess” the number of modes by reading a fixed pattern.
    let modeCount = 0;
    let gotModeHeader = false;
    let lastModeCount = 0;
    while (bitstream.getBitsLeft() >= 97) {
        const tempPos = bitstream.pos;
        const a = bitstream.readBits(8);
        const b = bitstream.readBits(16);
        const c = bitstream.readBits(16);
        // If a > 63 or b or c nonzero, assume we’ve gone too far.
        if (a > 63 || b !== 0 || c !== 0) {
            bitstream.pos = tempPos;
            break;
        }
        bitstream.skipBits(1);
        modeCount++;
        if (modeCount > 64) {
            break;
        }
        const bsClone = bitstream.clone();
        const candidate = bsClone.readBits(6) + 1;
        if (candidate === modeCount) {
            gotModeHeader = true;
            lastModeCount = modeCount;
        }
    }
    if (!gotModeHeader) {
        throw new Error('Invalid Setup header: mode header not found.');
    }
    if (lastModeCount > 63) {
        throw new Error(`Unsupported mode count: ${lastModeCount}.`);
    }
    const finalModeCount = lastModeCount;
    // --- Reinitialize the bitstream.
    bitstream.pos = 0;
    // Skip the bits up to the found framing bit.
    bitstream.skipBits(gotFramingBit);
    // --- Now read, for each mode (in reverse order), 40 bits then one bit.
    // That one bit is the mode blockflag.
    const modeBlockflags = Array(finalModeCount).fill(0);
    for (let i = finalModeCount - 1; i >= 0; i--) {
        bitstream.skipBits(40);
        modeBlockflags[i] = bitstream.readBits(1);
    }
    return { modeBlockflags };
};
/** Determines a packet's type (key or delta) by digging into the packet bitstream. */
const determineVideoPacketType = (codec, decoderConfig, packetData) => {
    switch (codec) {
        case 'avc':
            {
                for (const loc of iterateAvcNalUnits(packetData, decoderConfig)) {
                    const nalTypeByte = packetData[loc.offset];
                    const type = extractNalUnitTypeForAvc(nalTypeByte);
                    if (type >= AvcNalUnitType.NON_IDR_SLICE && type <= AvcNalUnitType.SLICE_DPC) {
                        return 'delta';
                    }
                    if (type === AvcNalUnitType.IDR) {
                        return 'key';
                    }
                    // In addition to IDR, Recovery Point SEI also counts as a valid H.264 keyframe by current consensus.
                    // See https://github.com/w3c/webcodecs/issues/650 for the relevant discussion. WebKit and Firefox have
                    // always supported them, but Chromium hasn't, therefore the (admittedly dirty) version check.
                    if (type === AvcNalUnitType.SEI && (!(0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .isChromium */ .F2)() || (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .getChromiumVersion */ .zp)() >= 144)) {
                        const nalUnit = packetData.subarray(loc.offset, loc.offset + loc.length);
                        const bytes = removeEmulationPreventionBytes(nalUnit);
                        let pos = 1; // Skip NALU header
                        // sei_rbsp()
                        do {
                            // sei_message()
                            let payloadType = 0;
                            while (true) {
                                const nextByte = bytes[pos++];
                                if (nextByte === undefined)
                                    break;
                                payloadType += nextByte;
                                if (nextByte < 255) {
                                    break;
                                }
                            }
                            let payloadSize = 0;
                            while (true) {
                                const nextByte = bytes[pos++];
                                if (nextByte === undefined)
                                    break;
                                payloadSize += nextByte;
                                if (nextByte < 255) {
                                    break;
                                }
                            }
                            // sei_payload()
                            const PAYLOAD_TYPE_RECOVERY_POINT = 6;
                            if (payloadType === PAYLOAD_TYPE_RECOVERY_POINT) {
                                const bitstream = new _shared_bitstream_js__WEBPACK_IMPORTED_MODULE_3__/* .Bitstream */ ._(bytes);
                                bitstream.pos = 8 * pos;
                                const recoveryFrameCount = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .readExpGolomb */ .IP)(bitstream);
                                const exactMatchFlag = bitstream.readBits(1);
                                if (recoveryFrameCount === 0 && exactMatchFlag === 1) {
                                    // https://github.com/w3c/webcodecs/pull/910
                                    // "recovery_frame_cnt == 0 and exact_match_flag=1 in the SEI recovery payload"
                                    return 'key';
                                }
                            }
                            pos += payloadSize;
                        } while (pos < bytes.length - 1);
                    }
                }
                return 'delta';
            }
            // removed by dead control flow

        case 'hevc':
            {
                for (const loc of iterateHevcNalUnits(packetData, decoderConfig)) {
                    const type = extractNalUnitTypeForHevc(packetData[loc.offset]);
                    if (type < HevcNalUnitType.BLA_W_LP) {
                        return 'delta';
                    }
                    if (type <= HevcNalUnitType.RSV_IRAP_VCL23) {
                        return 'key';
                    }
                }
                return 'delta';
            }
            // removed by dead control flow

        case 'vp8':
            {
                // VP8, once again, by far the easiest to deal with.
                const frameType = packetData[0] & 0b1;
                return frameType === 0 ? 'key' : 'delta';
            }
            // removed by dead control flow

        case 'vp9':
            {
                const bitstream = new _shared_bitstream_js__WEBPACK_IMPORTED_MODULE_3__/* .Bitstream */ ._(packetData);
                if (bitstream.readBits(2) !== 2) {
                    return null;
                }
                ;
                const profileLowBit = bitstream.readBits(1);
                const profileHighBit = bitstream.readBits(1);
                const profile = (profileHighBit << 1) + profileLowBit;
                // Skip reserved bit for profile 3
                if (profile === 3) {
                    bitstream.skipBits(1);
                }
                const showExistingFrame = bitstream.readBits(1);
                if (showExistingFrame) {
                    return null;
                }
                const frameType = bitstream.readBits(1);
                return frameType === 0 ? 'key' : 'delta';
            }
            // removed by dead control flow

        case 'av1':
            {
                let reducedStillPictureHeader = false;
                for (const { type, data } of iterateAv1PacketObus(packetData)) {
                    if (type === 1) { // OBU_SEQUENCE_HEADER
                        const bitstream = new _shared_bitstream_js__WEBPACK_IMPORTED_MODULE_3__/* .Bitstream */ ._(data);
                        bitstream.skipBits(4);
                        reducedStillPictureHeader = !!bitstream.readBits(1);
                    }
                    else if (type === 3 // OBU_FRAME_HEADER
                        || type === 6 // OBU_FRAME
                        || type === 7 // OBU_REDUNDANT_FRAME_HEADER
                    ) {
                        if (reducedStillPictureHeader) {
                            return 'key';
                        }
                        const bitstream = new _shared_bitstream_js__WEBPACK_IMPORTED_MODULE_3__/* .Bitstream */ ._(data);
                        const showExistingFrame = bitstream.readBits(1);
                        if (showExistingFrame) {
                            return null;
                        }
                        const frameType = bitstream.readBits(2);
                        return frameType === 0 ? 'key' : 'delta';
                    }
                }
                return null;
            }
            // removed by dead control flow

        default:
            {
                (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .assertNever */ .xb)(codec);
                (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .assert */ .vA)(false);
            }
            ;
    }
};
var FlacBlockType;
(function (FlacBlockType) {
    FlacBlockType[FlacBlockType["STREAMINFO"] = 0] = "STREAMINFO";
    FlacBlockType[FlacBlockType["VORBIS_COMMENT"] = 4] = "VORBIS_COMMENT";
    FlacBlockType[FlacBlockType["PICTURE"] = 6] = "PICTURE";
})(FlacBlockType || (FlacBlockType = {}));
const readVorbisComments = (bytes, metadataTags) => {
    // https://datatracker.ietf.org/doc/html/rfc7845#section-5.2
    const commentView = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .toDataView */ .Zc)(bytes);
    let commentPos = 0;
    const vendorStringLength = commentView.getUint32(commentPos, true);
    commentPos += 4;
    const vendorString = _misc_js__WEBPACK_IMPORTED_MODULE_1__/* .textDecoder */ .su.decode(bytes.subarray(commentPos, commentPos + vendorStringLength));
    commentPos += vendorStringLength;
    if (vendorStringLength > 0) {
        // Expose the vendor string in the raw metadata
        metadataTags.raw ??= {};
        metadataTags.raw['vendor'] ??= vendorString;
    }
    const listLength = commentView.getUint32(commentPos, true);
    commentPos += 4;
    // Loop over all metadata tags
    for (let i = 0; i < listLength; i++) {
        const stringLength = commentView.getUint32(commentPos, true);
        commentPos += 4;
        const string = _misc_js__WEBPACK_IMPORTED_MODULE_1__/* .textDecoder */ .su.decode(bytes.subarray(commentPos, commentPos + stringLength));
        commentPos += stringLength;
        const separatorIndex = string.indexOf('=');
        if (separatorIndex === -1) {
            continue;
        }
        const key = string.slice(0, separatorIndex).toUpperCase();
        const value = string.slice(separatorIndex + 1);
        metadataTags.raw ??= {};
        metadataTags.raw[key] ??= value;
        switch (key) {
            case 'TITLE':
                {
                    metadataTags.title ??= value;
                }
                ;
                break;
            case 'DESCRIPTION':
                {
                    metadataTags.description ??= value;
                }
                ;
                break;
            case 'ARTIST':
                {
                    metadataTags.artist ??= value;
                }
                ;
                break;
            case 'ALBUM':
                {
                    metadataTags.album ??= value;
                }
                ;
                break;
            case 'ALBUMARTIST':
                {
                    metadataTags.albumArtist ??= value;
                }
                ;
                break;
            case 'COMMENT':
                {
                    metadataTags.comment ??= value;
                }
                ;
                break;
            case 'LYRICS':
                {
                    metadataTags.lyrics ??= value;
                }
                ;
                break;
            case 'TRACKNUMBER':
                {
                    const parts = value.split('/');
                    const trackNum = Number.parseInt(parts[0], 10);
                    const tracksTotal = parts[1] && Number.parseInt(parts[1], 10);
                    if (Number.isInteger(trackNum) && trackNum > 0) {
                        metadataTags.trackNumber ??= trackNum;
                    }
                    if (tracksTotal && Number.isInteger(tracksTotal) && tracksTotal > 0) {
                        metadataTags.tracksTotal ??= tracksTotal;
                    }
                }
                ;
                break;
            case 'TRACKTOTAL':
                {
                    const tracksTotal = Number.parseInt(value, 10);
                    if (Number.isInteger(tracksTotal) && tracksTotal > 0) {
                        metadataTags.tracksTotal ??= tracksTotal;
                    }
                }
                ;
                break;
            case 'DISCNUMBER':
                {
                    const parts = value.split('/');
                    const discNum = Number.parseInt(parts[0], 10);
                    const discsTotal = parts[1] && Number.parseInt(parts[1], 10);
                    if (Number.isInteger(discNum) && discNum > 0) {
                        metadataTags.discNumber ??= discNum;
                    }
                    if (discsTotal && Number.isInteger(discsTotal) && discsTotal > 0) {
                        metadataTags.discsTotal ??= discsTotal;
                    }
                }
                ;
                break;
            case 'DISCTOTAL':
                {
                    const discsTotal = Number.parseInt(value, 10);
                    if (Number.isInteger(discsTotal) && discsTotal > 0) {
                        metadataTags.discsTotal ??= discsTotal;
                    }
                }
                ;
                break;
            case 'DATE':
                {
                    const date = new Date(value);
                    if (!Number.isNaN(date.getTime())) {
                        metadataTags.date ??= date;
                    }
                }
                ;
                break;
            case 'GENRE':
                {
                    metadataTags.genre ??= value;
                }
                ;
                break;
            case 'METADATA_BLOCK_PICTURE':
                {
                    // https://datatracker.ietf.org/doc/rfc9639/ Section 8.8
                    const decoded = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .base64ToBytes */ .Kp)(value);
                    const view = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .toDataView */ .Zc)(decoded);
                    const pictureType = view.getUint32(0, false);
                    const mediaTypeLength = view.getUint32(4, false);
                    const mediaType = String.fromCharCode(...decoded.subarray(8, 8 + mediaTypeLength)); // ASCII
                    const descriptionLength = view.getUint32(8 + mediaTypeLength, false);
                    const description = _misc_js__WEBPACK_IMPORTED_MODULE_1__/* .textDecoder */ .su.decode(decoded.subarray(12 + mediaTypeLength, 12 + mediaTypeLength + descriptionLength));
                    const dataLength = view.getUint32(mediaTypeLength + descriptionLength + 28);
                    const data = decoded.subarray(mediaTypeLength + descriptionLength + 32, mediaTypeLength + descriptionLength + 32 + dataLength);
                    metadataTags.images ??= [];
                    metadataTags.images.push({
                        data,
                        mimeType: mediaType,
                        kind: pictureType === 3 ? 'coverFront' : pictureType === 4 ? 'coverBack' : 'unknown',
                        name: undefined,
                        description: description || undefined,
                    });
                }
                ;
                break;
        }
    }
};
const createVorbisComments = (headerBytes, tags, writeImages) => {
    // https://datatracker.ietf.org/doc/html/rfc7845#section-5.2
    const commentHeaderParts = [
        headerBytes,
    ];
    const vendorString = 'Mediabunny';
    const encodedVendorString = textEncoder.encode(vendorString);
    let currentBuffer = new Uint8Array(4 + encodedVendorString.length);
    let currentView = new DataView(currentBuffer.buffer);
    currentView.setUint32(0, encodedVendorString.length, true);
    currentBuffer.set(encodedVendorString, 4);
    commentHeaderParts.push(currentBuffer);
    const writtenTags = new Set();
    const addCommentTag = (key, value) => {
        const joined = `${key}=${value}`;
        const encoded = textEncoder.encode(joined);
        currentBuffer = new Uint8Array(4 + encoded.length);
        currentView = new DataView(currentBuffer.buffer);
        currentView.setUint32(0, encoded.length, true);
        currentBuffer.set(encoded, 4);
        commentHeaderParts.push(currentBuffer);
        writtenTags.add(key);
    };
    for (const { key, value } of keyValueIterator(tags)) {
        switch (key) {
            case 'title':
                {
                    addCommentTag('TITLE', value);
                }
                ;
                break;
            case 'description':
                {
                    addCommentTag('DESCRIPTION', value);
                }
                ;
                break;
            case 'artist':
                {
                    addCommentTag('ARTIST', value);
                }
                ;
                break;
            case 'album':
                {
                    addCommentTag('ALBUM', value);
                }
                ;
                break;
            case 'albumArtist':
                {
                    addCommentTag('ALBUMARTIST', value);
                }
                ;
                break;
            case 'genre':
                {
                    addCommentTag('GENRE', value);
                }
                ;
                break;
            case 'date':
                {
                    const rawVersion = tags.raw?.['DATE'] ?? tags.raw?.['date'];
                    if (rawVersion && typeof rawVersion === 'string') {
                        addCommentTag('DATE', rawVersion);
                    }
                    else {
                        addCommentTag('DATE', value.toISOString().slice(0, 10));
                    }
                }
                ;
                break;
            case 'comment':
                {
                    addCommentTag('COMMENT', value);
                }
                ;
                break;
            case 'lyrics':
                {
                    addCommentTag('LYRICS', value);
                }
                ;
                break;
            case 'trackNumber':
                {
                    addCommentTag('TRACKNUMBER', value.toString());
                }
                ;
                break;
            case 'tracksTotal':
                {
                    addCommentTag('TRACKTOTAL', value.toString());
                }
                ;
                break;
            case 'discNumber':
                {
                    addCommentTag('DISCNUMBER', value.toString());
                }
                ;
                break;
            case 'discsTotal':
                {
                    addCommentTag('DISCTOTAL', value.toString());
                }
                ;
                break;
            case 'images':
                {
                    // For example, in .flac, we put the pictures in a different section,
                    // not in the Vorbis comment header.
                    if (!writeImages) {
                        break;
                    }
                    for (const image of value) {
                        // https://datatracker.ietf.org/doc/rfc9639/ Section 8.8
                        const pictureType = image.kind === 'coverFront' ? 3 : image.kind === 'coverBack' ? 4 : 0;
                        const encodedMediaType = new Uint8Array(image.mimeType.length);
                        for (let i = 0; i < image.mimeType.length; i++) {
                            encodedMediaType[i] = image.mimeType.charCodeAt(i);
                        }
                        const encodedDescription = textEncoder.encode(image.description ?? '');
                        const buffer = new Uint8Array(4 // Picture type
                            + 4 // MIME type length
                            + encodedMediaType.length // MIME type
                            + 4 // Description length
                            + encodedDescription.length // Description
                            + 16 // Width, height, color depth, number of colors
                            + 4 // Picture data length
                            + image.data.length);
                        const view = toDataView(buffer);
                        view.setUint32(0, pictureType, false);
                        view.setUint32(4, encodedMediaType.length, false);
                        buffer.set(encodedMediaType, 8);
                        view.setUint32(8 + encodedMediaType.length, encodedDescription.length, false);
                        buffer.set(encodedDescription, 12 + encodedMediaType.length);
                        // Skip a bunch of fields (width, height, color depth, number of colors)
                        view.setUint32(28 + encodedMediaType.length + encodedDescription.length, image.data.length, false);
                        buffer.set(image.data, 32 + encodedMediaType.length + encodedDescription.length);
                        const encoded = bytesToBase64(buffer);
                        addCommentTag('METADATA_BLOCK_PICTURE', encoded);
                    }
                }
                ;
                break;
            case 'raw':
                {
                    // Handled later
                }
                ;
                break;
            default: assertNever(key);
        }
    }
    if (tags.raw) {
        for (const key in tags.raw) {
            const value = tags.raw[key] ?? tags.raw[key.toLowerCase()];
            if (key === 'vendor' || value == null || writtenTags.has(key)) {
                continue;
            }
            if (typeof value === 'string') {
                addCommentTag(key, value);
            }
        }
    }
    const listLengthBuffer = new Uint8Array(4);
    toDataView(listLengthBuffer).setUint32(0, writtenTags.size, true);
    commentHeaderParts.splice(2, 0, listLengthBuffer); // Insert after the header and vendor section
    // Merge all comment header parts into a single buffer
    const commentHeaderLength = commentHeaderParts.reduce((a, b) => a + b.length, 0);
    const commentHeader = new Uint8Array(commentHeaderLength);
    let pos = 0;
    for (const part of commentHeaderParts) {
        commentHeader.set(part, pos);
        pos += part.length;
    }
    return commentHeader;
};
// ============================================================================
// AC-3 / E-AC-3 Parsing
// Reference: ETSI TS 102 366 V1.4.1
// ============================================================================
/**
 * Channel counts indexed by acmod (Table 4.3).
 * Does NOT include LFE - add lfeon to get total channel count.
 */
const AC3_ACMOD_CHANNEL_COUNTS = [2, 1, 2, 3, 3, 4, 4, 5];
/**
 * Parse an AC-3 syncframe to extract BSI (Bit Stream Information) fields.
 * Section 4.3
 */
const parseAc3SyncFrame = (data) => {
    if (data.length < 7) {
        return null;
    }
    // Check sync word (0x0B77)
    if (data[0] !== 0x0B || data[1] !== 0x77) {
        return null;
    }
    const bitstream = new _shared_bitstream_js__WEBPACK_IMPORTED_MODULE_3__/* .Bitstream */ ._(data);
    bitstream.skipBits(16); // sync word
    bitstream.skipBits(16); // crc1
    const fscod = bitstream.readBits(2);
    if (fscod === 3) {
        return null; // Reserved, invalid
    }
    const frmsizecod = bitstream.readBits(6);
    const bsid = bitstream.readBits(5);
    // Verify this is AC-3
    if (bsid > 8) {
        return null;
    }
    const bsmod = bitstream.readBits(3);
    const acmod = bitstream.readBits(3);
    // Skip cmixlev (center downmix level) if three front channels are in use (L, C, R).
    if ((acmod & 0x1) !== 0 && acmod !== 0x1) {
        bitstream.skipBits(2);
    }
    // Skip surmixlev (surround downmix level) if surround channels are in use.
    if ((acmod & 0x4) !== 0) {
        bitstream.skipBits(2);
    }
    // Skip dsurmod if stereo (acmod === 2)
    if (acmod === 0x2) {
        bitstream.skipBits(2);
    }
    const lfeon = bitstream.readBits(1);
    const bitRateCode = Math.floor(frmsizecod / 2);
    return { fscod, bsid, bsmod, acmod, lfeon, bitRateCode };
};
/**
 * AC-3 frame sizes in bytes, indexed by [3 * frmsizecod + fscod].
 * fscod: 0=48kHz, 1=44.1kHz, 2=32kHz
 * Values are 16-bit words * 2 (to convert to bytes).
 * Table 4.13
 */
const AC3_FRAME_SIZES = [
    // frmsizecod, [48kHz, 44.1kHz, 32kHz] in bytes
    64 * 2, 69 * 2, 96 * 2,
    64 * 2, 70 * 2, 96 * 2,
    80 * 2, 87 * 2, 120 * 2,
    80 * 2, 88 * 2, 120 * 2,
    96 * 2, 104 * 2, 144 * 2,
    96 * 2, 105 * 2, 144 * 2,
    112 * 2, 121 * 2, 168 * 2,
    112 * 2, 122 * 2, 168 * 2,
    128 * 2, 139 * 2, 192 * 2,
    128 * 2, 140 * 2, 192 * 2,
    160 * 2, 174 * 2, 240 * 2,
    160 * 2, 175 * 2, 240 * 2,
    192 * 2, 208 * 2, 288 * 2,
    192 * 2, 209 * 2, 288 * 2,
    224 * 2, 243 * 2, 336 * 2,
    224 * 2, 244 * 2, 336 * 2,
    256 * 2, 278 * 2, 384 * 2,
    256 * 2, 279 * 2, 384 * 2,
    320 * 2, 348 * 2, 480 * 2,
    320 * 2, 349 * 2, 480 * 2,
    384 * 2, 417 * 2, 576 * 2,
    384 * 2, 418 * 2, 576 * 2,
    448 * 2, 487 * 2, 672 * 2,
    448 * 2, 488 * 2, 672 * 2,
    512 * 2, 557 * 2, 768 * 2,
    512 * 2, 558 * 2, 768 * 2,
    640 * 2, 696 * 2, 960 * 2,
    640 * 2, 697 * 2, 960 * 2,
    768 * 2, 835 * 2, 1152 * 2,
    768 * 2, 836 * 2, 1152 * 2,
    896 * 2, 975 * 2, 1344 * 2,
    896 * 2, 976 * 2, 1344 * 2,
    1024 * 2, 1114 * 2, 1536 * 2,
    1024 * 2, 1115 * 2, 1536 * 2,
    1152 * 2, 1253 * 2, 1728 * 2,
    1152 * 2, 1254 * 2, 1728 * 2,
    1280 * 2, 1393 * 2, 1920 * 2,
    1280 * 2, 1394 * 2, 1920 * 2,
];
/** Number of samples per AC-3 syncframe (always 1536) */
const AC3_SAMPLES_PER_FRAME = 1536;
/**
 * AC-3 registration_descriptor for MPEG-TS.
 * Section A.2.3
 */
const AC3_REGISTRATION_DESCRIPTOR = new Uint8Array([0x05, 0x04, 0x41, 0x43, 0x2d, 0x33]);
/** E-AC-3 registration_descriptor for MPEG-TS/ */
const EAC3_REGISTRATION_DESCRIPTOR = new Uint8Array([0x05, 0x04, 0x45, 0x41, 0x43, 0x33]);
/** Number of audio blocks per syncframe, indexed by numblkscod */
const EAC3_NUMBLKS_TABLE = [1, 2, 3, 6];
/**
 * Parse an E-AC-3 syncframe to extract BSI fields.
 * Section E.1.2
 */
const parseEac3SyncFrame = (data) => {
    if (data.length < 6) {
        return null;
    }
    // Check sync word (0x0B77)
    if (data[0] !== 0x0B || data[1] !== 0x77) {
        return null;
    }
    const bitstream = new _shared_bitstream_js__WEBPACK_IMPORTED_MODULE_3__/* .Bitstream */ ._(data);
    bitstream.skipBits(16); // sync word
    const strmtyp = bitstream.readBits(2);
    bitstream.skipBits(3); // substreamid
    // Only parse independent substreams (strmtyp 0 or 2)
    if (strmtyp !== 0 && strmtyp !== 2) {
        return null;
    }
    const frmsiz = bitstream.readBits(11);
    const fscod = bitstream.readBits(2);
    let fscod2 = 0;
    let numblkscod;
    if (fscod === 3) {
        // fscod2 enables reduced sample rates (24/22.05/16 kHz) per ATSC A/52:2018
        fscod2 = bitstream.readBits(2);
        numblkscod = 3; // Implicitly 6 blocks when fscod=3
    }
    else {
        numblkscod = bitstream.readBits(2);
    }
    const acmod = bitstream.readBits(3);
    const lfeon = bitstream.readBits(1);
    const bsid = bitstream.readBits(5);
    // Verify this is E-AC-3
    if (bsid < 11 || bsid > 16) {
        return null;
    }
    // Calculate data rate: ((frmsiz + 1) * fs) / (numblks * 16)
    const numblks = EAC3_NUMBLKS_TABLE[numblkscod];
    let fs;
    if (fscod < 3) {
        fs = _shared_ac3_misc_js__WEBPACK_IMPORTED_MODULE_2__/* .AC3_SAMPLE_RATES */ .N[fscod] / 1000;
    }
    else {
        fs = _shared_ac3_misc_js__WEBPACK_IMPORTED_MODULE_2__/* .EAC3_REDUCED_SAMPLE_RATES */ .P[fscod2] / 1000;
    }
    const dataRate = Math.round(((frmsiz + 1) * fs) / (numblks * 16));
    // These fields require parsing beyond the first frame.
    // Defaults are correct for almost all content.
    const bsmod = 0;
    const numDepSub = 0;
    const chanLoc = 0;
    const substream = {
        fscod,
        fscod2,
        bsid,
        bsmod,
        acmod,
        lfeon,
        numDepSub,
        chanLoc,
    };
    return {
        dataRate,
        substreams: [substream],
    };
};
/**
 * Parse a dec3 box to extract E-AC-3 parameters.
 * Section F.6
 */
const parseEac3Config = (data) => {
    if (data.length < 2) {
        return null;
    }
    const bitstream = new _shared_bitstream_js__WEBPACK_IMPORTED_MODULE_3__/* .Bitstream */ ._(data);
    const dataRate = bitstream.readBits(13);
    const numIndSub = bitstream.readBits(3);
    const substreams = [];
    for (let i = 0; i <= numIndSub; i++) {
        // Check we have enough data for this substream
        // Each substream needs at least 24 bits (3 bytes) without dependent subs
        if (Math.ceil(bitstream.pos / 8) + 3 > data.length) {
            break;
        }
        const fscod = bitstream.readBits(2);
        const bsid = bitstream.readBits(5);
        bitstream.skipBits(1); // reserved
        bitstream.skipBits(1); // asvc
        const bsmod = bitstream.readBits(3);
        const acmod = bitstream.readBits(3);
        const lfeon = bitstream.readBits(1);
        bitstream.skipBits(3); // reserved
        const numDepSub = bitstream.readBits(4);
        let chanLoc = 0;
        if (numDepSub > 0) {
            chanLoc = bitstream.readBits(9);
        }
        else {
            bitstream.skipBits(1); // reserved
        }
        substreams.push({
            fscod,
            fscod2: null,
            bsid,
            bsmod,
            acmod,
            lfeon,
            numDepSub,
            chanLoc,
        });
    }
    if (substreams.length === 0) {
        return null;
    }
    return { dataRate, substreams };
};
/**
 * Get sample rate from E-AC-3 config.
 * See ATSC A/52:2018 for handling fscod2.
 */
const getEac3SampleRate = (config) => {
    const sub = config.substreams[0];
    (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .assert */ .vA)(sub);
    if (sub.fscod < 3) {
        return _shared_ac3_misc_js__WEBPACK_IMPORTED_MODULE_2__/* .AC3_SAMPLE_RATES */ .N[sub.fscod];
    }
    else if (sub.fscod2 !== null && sub.fscod2 < 3) {
        return _shared_ac3_misc_js__WEBPACK_IMPORTED_MODULE_2__/* .EAC3_REDUCED_SAMPLE_RATES */ .P[sub.fscod2];
    }
    return null;
};
/**
 * Get channel count from E-AC-3 config (first independent substream only).
 */
const getEac3ChannelCount = (config) => {
    const sub = config.substreams[0];
    (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .assert */ .vA)(sub);
    let channels = AC3_ACMOD_CHANNEL_COUNTS[sub.acmod] + sub.lfeon;
    // Add channels from dependent substreams
    if (sub.numDepSub > 0) {
        const CHAN_LOC_COUNTS = [2, 2, 1, 1, 2, 2, 2, 1, 1];
        for (let bit = 0; bit < 9; bit++) {
            if (sub.chanLoc & (1 << (8 - bit))) {
                channels += CHAN_LOC_COUNTS[bit];
            }
        }
    }
    return channels;
};


/***/ },

/***/ 1188
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   $3: () => (/* binding */ AVC_LEVEL_TABLE),
/* harmony export */   Ei: () => (/* binding */ parsePcmCodec),
/* harmony export */   PP: () => (/* binding */ AUDIO_CODECS),
/* harmony export */   QP: () => (/* binding */ extractVideoCodecString),
/* harmony export */   WN: () => (/* binding */ VIDEO_CODECS),
/* harmony export */   Wq: () => (/* binding */ PCM_AUDIO_CODECS),
/* harmony export */   X0: () => (/* binding */ extractAudioCodecString),
/* harmony export */   oU: () => (/* binding */ inferCodecFromCodecString),
/* harmony export */   ye: () => (/* binding */ VP9_LEVEL_TABLE),
/* harmony export */   yo: () => (/* binding */ OPUS_SAMPLE_RATE)
/* harmony export */ });
/* unused harmony exports NON_PCM_AUDIO_CODECS, SUBTITLE_CODECS, buildVideoCodecString, generateVp9CodecConfigurationFromCodecString, generateAv1CodecConfigurationFromCodecString, buildAudioCodecString, guessDescriptionForVideo, guessDescriptionForAudio, getVideoEncoderConfigExtension, getAudioEncoderConfigExtension, validateVideoChunkMetadata, validateAudioChunkMetadata, validateSubtitleMetadata */
/* unused harmony import specifier */ var last;
/* unused harmony import specifier */ var base64ToBytes;
/* unused harmony import specifier */ var toDataView;
/* unused harmony import specifier */ var isAllowSharedBufferSource;
/* unused harmony import specifier */ var COLOR_PRIMARIES_MAP;
/* unused harmony import specifier */ var TRANSFER_CHARACTERISTICS_MAP;
/* unused harmony import specifier */ var MATRIX_COEFFICIENTS_MAP;
/* harmony import */ var _shared_aac_misc_js__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(1299);
/* harmony import */ var _misc_js__WEBPACK_IMPORTED_MODULE_1__ = __webpack_require__(3912);
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


/**
 * List of known video codecs, ordered by encoding preference.
 * @group Codecs
 * @public
 */
const VIDEO_CODECS = [
    'avc',
    'hevc',
    'vp9',
    'av1',
    'vp8',
];
/**
 * List of known PCM (uncompressed) audio codecs, ordered by encoding preference.
 * @group Codecs
 * @public
 */
const PCM_AUDIO_CODECS = [
    'pcm-s16', // We don't prefix 'le' so we're compatible with the WebCodecs-registered PCM codec strings
    'pcm-s16be',
    'pcm-s24',
    'pcm-s24be',
    'pcm-s32',
    'pcm-s32be',
    'pcm-f32',
    'pcm-f32be',
    'pcm-f64',
    'pcm-f64be',
    'pcm-u8',
    'pcm-s8',
    'ulaw',
    'alaw',
];
/**
 * List of known compressed audio codecs, ordered by encoding preference.
 * @group Codecs
 * @public
 */
const NON_PCM_AUDIO_CODECS = [
    'aac',
    'opus',
    'mp3',
    'vorbis',
    'flac',
    'ac3',
    'eac3',
];
/**
 * List of known audio codecs, ordered by encoding preference.
 * @group Codecs
 * @public
 */
const AUDIO_CODECS = [
    ...NON_PCM_AUDIO_CODECS,
    ...PCM_AUDIO_CODECS,
];
/**
 * List of known subtitle codecs, ordered by encoding preference.
 * @group Codecs
 * @public
 */
const SUBTITLE_CODECS = (/* unused pure expression or super */ null && ([
    'webvtt',
])); // TODO add the rest
// https://en.wikipedia.org/wiki/Advanced_Video_Coding
const AVC_LEVEL_TABLE = [
    { maxMacroblocks: 99, maxBitrate: 64000, maxDpbMbs: 396, level: 0x0A }, // Level 1
    { maxMacroblocks: 396, maxBitrate: 192000, maxDpbMbs: 900, level: 0x0B }, // Level 1.1
    { maxMacroblocks: 396, maxBitrate: 384000, maxDpbMbs: 2376, level: 0x0C }, // Level 1.2
    { maxMacroblocks: 396, maxBitrate: 768000, maxDpbMbs: 2376, level: 0x0D }, // Level 1.3
    { maxMacroblocks: 396, maxBitrate: 2000000, maxDpbMbs: 2376, level: 0x14 }, // Level 2
    { maxMacroblocks: 792, maxBitrate: 4000000, maxDpbMbs: 4752, level: 0x15 }, // Level 2.1
    { maxMacroblocks: 1620, maxBitrate: 4000000, maxDpbMbs: 8100, level: 0x16 }, // Level 2.2
    { maxMacroblocks: 1620, maxBitrate: 10000000, maxDpbMbs: 8100, level: 0x1E }, // Level 3
    { maxMacroblocks: 3600, maxBitrate: 14000000, maxDpbMbs: 18000, level: 0x1F }, // Level 3.1
    { maxMacroblocks: 5120, maxBitrate: 20000000, maxDpbMbs: 20480, level: 0x20 }, // Level 3.2
    { maxMacroblocks: 8192, maxBitrate: 20000000, maxDpbMbs: 32768, level: 0x28 }, // Level 4
    { maxMacroblocks: 8192, maxBitrate: 50000000, maxDpbMbs: 32768, level: 0x29 }, // Level 4.1
    { maxMacroblocks: 8704, maxBitrate: 50000000, maxDpbMbs: 34816, level: 0x2A }, // Level 4.2
    { maxMacroblocks: 22080, maxBitrate: 135000000, maxDpbMbs: 110400, level: 0x32 }, // Level 5
    { maxMacroblocks: 36864, maxBitrate: 240000000, maxDpbMbs: 184320, level: 0x33 }, // Level 5.1
    { maxMacroblocks: 36864, maxBitrate: 240000000, maxDpbMbs: 184320, level: 0x34 }, // Level 5.2
    { maxMacroblocks: 139264, maxBitrate: 240000000, maxDpbMbs: 696320, level: 0x3C }, // Level 6
    { maxMacroblocks: 139264, maxBitrate: 480000000, maxDpbMbs: 696320, level: 0x3D }, // Level 6.1
    { maxMacroblocks: 139264, maxBitrate: 800000000, maxDpbMbs: 696320, level: 0x3E }, // Level 6.2
];
// https://en.wikipedia.org/wiki/High_Efficiency_Video_Coding
const HEVC_LEVEL_TABLE = [
    { maxPictureSize: 36864, maxBitrate: 128000, tier: 'L', level: 30 }, // Level 1 (Low Tier)
    { maxPictureSize: 122880, maxBitrate: 1500000, tier: 'L', level: 60 }, // Level 2 (Low Tier)
    { maxPictureSize: 245760, maxBitrate: 3000000, tier: 'L', level: 63 }, // Level 2.1 (Low Tier)
    { maxPictureSize: 552960, maxBitrate: 6000000, tier: 'L', level: 90 }, // Level 3 (Low Tier)
    { maxPictureSize: 983040, maxBitrate: 10000000, tier: 'L', level: 93 }, // Level 3.1 (Low Tier)
    { maxPictureSize: 2228224, maxBitrate: 12000000, tier: 'L', level: 120 }, // Level 4 (Low Tier)
    { maxPictureSize: 2228224, maxBitrate: 30000000, tier: 'H', level: 120 }, // Level 4 (High Tier)
    { maxPictureSize: 2228224, maxBitrate: 20000000, tier: 'L', level: 123 }, // Level 4.1 (Low Tier)
    { maxPictureSize: 2228224, maxBitrate: 50000000, tier: 'H', level: 123 }, // Level 4.1 (High Tier)
    { maxPictureSize: 8912896, maxBitrate: 25000000, tier: 'L', level: 150 }, // Level 5 (Low Tier)
    { maxPictureSize: 8912896, maxBitrate: 100000000, tier: 'H', level: 150 }, // Level 5 (High Tier)
    { maxPictureSize: 8912896, maxBitrate: 40000000, tier: 'L', level: 153 }, // Level 5.1 (Low Tier)
    { maxPictureSize: 8912896, maxBitrate: 160000000, tier: 'H', level: 153 }, // Level 5.1 (High Tier)
    { maxPictureSize: 8912896, maxBitrate: 60000000, tier: 'L', level: 156 }, // Level 5.2 (Low Tier)
    { maxPictureSize: 8912896, maxBitrate: 240000000, tier: 'H', level: 156 }, // Level 5.2 (High Tier)
    { maxPictureSize: 35651584, maxBitrate: 60000000, tier: 'L', level: 180 }, // Level 6 (Low Tier)
    { maxPictureSize: 35651584, maxBitrate: 240000000, tier: 'H', level: 180 }, // Level 6 (High Tier)
    { maxPictureSize: 35651584, maxBitrate: 120000000, tier: 'L', level: 183 }, // Level 6.1 (Low Tier)
    { maxPictureSize: 35651584, maxBitrate: 480000000, tier: 'H', level: 183 }, // Level 6.1 (High Tier)
    { maxPictureSize: 35651584, maxBitrate: 240000000, tier: 'L', level: 186 }, // Level 6.2 (Low Tier)
    { maxPictureSize: 35651584, maxBitrate: 800000000, tier: 'H', level: 186 }, // Level 6.2 (High Tier)
];
// https://en.wikipedia.org/wiki/VP9
const VP9_LEVEL_TABLE = [
    { maxPictureSize: 36864, maxBitrate: 200000, level: 10 }, // Level 1
    { maxPictureSize: 73728, maxBitrate: 800000, level: 11 }, // Level 1.1
    { maxPictureSize: 122880, maxBitrate: 1800000, level: 20 }, // Level 2
    { maxPictureSize: 245760, maxBitrate: 3600000, level: 21 }, // Level 2.1
    { maxPictureSize: 552960, maxBitrate: 7200000, level: 30 }, // Level 3
    { maxPictureSize: 983040, maxBitrate: 12000000, level: 31 }, // Level 3.1
    { maxPictureSize: 2228224, maxBitrate: 18000000, level: 40 }, // Level 4
    { maxPictureSize: 2228224, maxBitrate: 30000000, level: 41 }, // Level 4.1
    { maxPictureSize: 8912896, maxBitrate: 60000000, level: 50 }, // Level 5
    { maxPictureSize: 8912896, maxBitrate: 120000000, level: 51 }, // Level 5.1
    { maxPictureSize: 8912896, maxBitrate: 180000000, level: 52 }, // Level 5.2
    { maxPictureSize: 35651584, maxBitrate: 180000000, level: 60 }, // Level 6
    { maxPictureSize: 35651584, maxBitrate: 240000000, level: 61 }, // Level 6.1
    { maxPictureSize: 35651584, maxBitrate: 480000000, level: 62 }, // Level 6.2
];
// https://en.wikipedia.org/wiki/AV1
const AV1_LEVEL_TABLE = [
    { maxPictureSize: 147456, maxBitrate: 1500000, tier: 'M', level: 0 }, // Level 2.0 (Main Tier)
    { maxPictureSize: 278784, maxBitrate: 3000000, tier: 'M', level: 1 }, // Level 2.1 (Main Tier)
    { maxPictureSize: 665856, maxBitrate: 6000000, tier: 'M', level: 4 }, // Level 3.0 (Main Tier)
    { maxPictureSize: 1065024, maxBitrate: 10000000, tier: 'M', level: 5 }, // Level 3.1 (Main Tier)
    { maxPictureSize: 2359296, maxBitrate: 12000000, tier: 'M', level: 8 }, // Level 4.0 (Main Tier)
    { maxPictureSize: 2359296, maxBitrate: 30000000, tier: 'H', level: 8 }, // Level 4.0 (High Tier)
    { maxPictureSize: 2359296, maxBitrate: 20000000, tier: 'M', level: 9 }, // Level 4.1 (Main Tier)
    { maxPictureSize: 2359296, maxBitrate: 50000000, tier: 'H', level: 9 }, // Level 4.1 (High Tier)
    { maxPictureSize: 8912896, maxBitrate: 30000000, tier: 'M', level: 12 }, // Level 5.0 (Main Tier)
    { maxPictureSize: 8912896, maxBitrate: 100000000, tier: 'H', level: 12 }, // Level 5.0 (High Tier)
    { maxPictureSize: 8912896, maxBitrate: 40000000, tier: 'M', level: 13 }, // Level 5.1 (Main Tier)
    { maxPictureSize: 8912896, maxBitrate: 160000000, tier: 'H', level: 13 }, // Level 5.1 (High Tier)
    { maxPictureSize: 8912896, maxBitrate: 60000000, tier: 'M', level: 14 }, // Level 5.2 (Main Tier)
    { maxPictureSize: 8912896, maxBitrate: 240000000, tier: 'H', level: 14 }, // Level 5.2 (High Tier)
    { maxPictureSize: 35651584, maxBitrate: 60000000, tier: 'M', level: 15 }, // Level 5.3 (Main Tier)
    { maxPictureSize: 35651584, maxBitrate: 240000000, tier: 'H', level: 15 }, // Level 5.3 (High Tier)
    { maxPictureSize: 35651584, maxBitrate: 60000000, tier: 'M', level: 16 }, // Level 6.0 (Main Tier)
    { maxPictureSize: 35651584, maxBitrate: 240000000, tier: 'H', level: 16 }, // Level 6.0 (High Tier)
    { maxPictureSize: 35651584, maxBitrate: 100000000, tier: 'M', level: 17 }, // Level 6.1 (Main Tier)
    { maxPictureSize: 35651584, maxBitrate: 480000000, tier: 'H', level: 17 }, // Level 6.1 (High Tier)
    { maxPictureSize: 35651584, maxBitrate: 160000000, tier: 'M', level: 18 }, // Level 6.2 (Main Tier)
    { maxPictureSize: 35651584, maxBitrate: 800000000, tier: 'H', level: 18 }, // Level 6.2 (High Tier)
    { maxPictureSize: 35651584, maxBitrate: 160000000, tier: 'M', level: 19 }, // Level 6.3 (Main Tier)
    { maxPictureSize: 35651584, maxBitrate: 800000000, tier: 'H', level: 19 }, // Level 6.3 (High Tier)
];
const VP9_DEFAULT_SUFFIX = '.01.01.01.01.00';
const AV1_DEFAULT_SUFFIX = '.0.110.01.01.01.0';
const buildVideoCodecString = (codec, width, height, bitrate) => {
    if (codec === 'avc') {
        const profileIndication = 0x64; // High Profile
        const totalMacroblocks = Math.ceil(width / 16) * Math.ceil(height / 16);
        // Determine the level based on the table
        const levelInfo = AVC_LEVEL_TABLE.find(level => totalMacroblocks <= level.maxMacroblocks && bitrate <= level.maxBitrate) ?? last(AVC_LEVEL_TABLE);
        const levelIndication = levelInfo ? levelInfo.level : 0;
        const hexProfileIndication = profileIndication.toString(16).padStart(2, '0');
        const hexProfileCompatibility = '00';
        const hexLevelIndication = levelIndication.toString(16).padStart(2, '0');
        return `avc1.${hexProfileIndication}${hexProfileCompatibility}${hexLevelIndication}`;
    }
    else if (codec === 'hevc') {
        const profilePrefix = ''; // Profile space 0
        const profileIdc = 1; // Main Profile
        const compatibilityFlags = '6'; // Taken from the example in ISO 14496-15
        const pictureSize = width * height;
        const levelInfo = HEVC_LEVEL_TABLE.find(level => pictureSize <= level.maxPictureSize && bitrate <= level.maxBitrate) ?? last(HEVC_LEVEL_TABLE);
        const constraintFlags = 'B0'; // Progressive source flag
        return 'hev1.'
            + `${profilePrefix}${profileIdc}.`
            + `${compatibilityFlags}.`
            + `${levelInfo.tier}${levelInfo.level}.`
            + `${constraintFlags}`;
    }
    else if (codec === 'vp8') {
        return 'vp8'; // Easy, this one
    }
    else if (codec === 'vp9') {
        const profile = '00'; // Profile 0
        const pictureSize = width * height;
        const levelInfo = VP9_LEVEL_TABLE.find(level => pictureSize <= level.maxPictureSize && bitrate <= level.maxBitrate) ?? last(VP9_LEVEL_TABLE);
        const bitDepth = '08'; // 8-bit
        return `vp09.${profile}.${levelInfo.level.toString().padStart(2, '0')}.${bitDepth}`;
    }
    else if (codec === 'av1') {
        const profile = 0; // Main Profile, single digit
        const pictureSize = width * height;
        const levelInfo = AV1_LEVEL_TABLE.find(level => pictureSize <= level.maxPictureSize && bitrate <= level.maxBitrate) ?? last(AV1_LEVEL_TABLE);
        const level = levelInfo.level.toString().padStart(2, '0');
        const bitDepth = '08'; // 8-bit
        return `av01.${profile}.${level}${levelInfo.tier}.${bitDepth}`;
    }
    // eslint-disable-next-line @typescript-eslint/restrict-template-expressions
    throw new TypeError(`Unhandled codec '${codec}'.`);
};
const generateVp9CodecConfigurationFromCodecString = (codecString) => {
    // Reference: https://www.webmproject.org/docs/container/#vp9-codec-feature-metadata-codecprivate
    const parts = codecString.split('.'); // We can derive the required values from the codec string
    const profile = Number(parts[1]);
    const level = Number(parts[2]);
    const bitDepth = Number(parts[3]);
    const chromaSubsampling = parts[4] ? Number(parts[4]) : 1;
    return [
        1, 1, profile,
        2, 1, level,
        3, 1, bitDepth,
        4, 1, chromaSubsampling,
    ];
};
const generateAv1CodecConfigurationFromCodecString = (codecString) => {
    // Reference: https://aomediacodec.github.io/av1-isobmff/
    const parts = codecString.split('.'); // We can derive the required values from the codec string
    const marker = 1;
    const version = 1;
    const firstByte = (marker << 7) + version;
    const profile = Number(parts[1]);
    const levelAndTier = parts[2];
    const level = Number(levelAndTier.slice(0, -1));
    const secondByte = (profile << 5) + level;
    const tier = levelAndTier.slice(-1) === 'H' ? 1 : 0;
    const bitDepth = Number(parts[3]);
    const highBitDepth = bitDepth === 8 ? 0 : 1;
    const twelveBit = 0;
    const monochrome = parts[4] ? Number(parts[4]) : 0;
    const chromaSubsamplingX = parts[5] ? Number(parts[5][0]) : 1;
    const chromaSubsamplingY = parts[5] ? Number(parts[5][1]) : 1;
    const chromaSamplePosition = parts[5] ? Number(parts[5][2]) : 0; // CSP_UNKNOWN
    const thirdByte = (tier << 7)
        + (highBitDepth << 6)
        + (twelveBit << 5)
        + (monochrome << 4)
        + (chromaSubsamplingX << 3)
        + (chromaSubsamplingY << 2)
        + chromaSamplePosition;
    const initialPresentationDelayPresent = 0; // Should be fine
    const fourthByte = initialPresentationDelayPresent;
    return [firstByte, secondByte, thirdByte, fourthByte];
};
const extractVideoCodecString = (trackInfo) => {
    const { codec, codecDescription, colorSpace, avcCodecInfo, hevcCodecInfo, vp9CodecInfo, av1CodecInfo } = trackInfo;
    if (codec === 'avc') {
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .assert */ .vA)(trackInfo.avcType !== null);
        if (avcCodecInfo) {
            const bytes = new Uint8Array([
                avcCodecInfo.avcProfileIndication,
                avcCodecInfo.profileCompatibility,
                avcCodecInfo.avcLevelIndication,
            ]);
            return `avc${trackInfo.avcType}.${(0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .bytesToHexString */ .Br)(bytes)}`;
        }
        if (!codecDescription || codecDescription.byteLength < 4) {
            throw new TypeError('AVC decoder description is not provided or is not at least 4 bytes long.');
        }
        return `avc${trackInfo.avcType}.${(0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .bytesToHexString */ .Br)(codecDescription.subarray(1, 4))}`;
    }
    else if (codec === 'hevc') {
        let generalProfileSpace;
        let generalProfileIdc;
        let compatibilityFlags;
        let generalTierFlag;
        let generalLevelIdc;
        let constraintFlags;
        if (hevcCodecInfo) {
            generalProfileSpace = hevcCodecInfo.generalProfileSpace;
            generalProfileIdc = hevcCodecInfo.generalProfileIdc;
            compatibilityFlags = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .reverseBitsU32 */ .P5)(hevcCodecInfo.generalProfileCompatibilityFlags);
            generalTierFlag = hevcCodecInfo.generalTierFlag;
            generalLevelIdc = hevcCodecInfo.generalLevelIdc;
            constraintFlags = [...hevcCodecInfo.generalConstraintIndicatorFlags];
        }
        else {
            if (!codecDescription || codecDescription.byteLength < 23) {
                throw new TypeError('HEVC decoder description is not provided or is not at least 23 bytes long.');
            }
            const view = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .toDataView */ .Zc)(codecDescription);
            const profileByte = view.getUint8(1);
            generalProfileSpace = (profileByte >> 6) & 0x03;
            generalProfileIdc = profileByte & 0x1F;
            compatibilityFlags = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .reverseBitsU32 */ .P5)(view.getUint32(2));
            generalTierFlag = (profileByte >> 5) & 0x01;
            generalLevelIdc = view.getUint8(12);
            constraintFlags = [];
            for (let i = 0; i < 6; i++) {
                constraintFlags.push(view.getUint8(6 + i));
            }
        }
        let codecString = 'hev1.';
        codecString += ['', 'A', 'B', 'C'][generalProfileSpace] + generalProfileIdc;
        codecString += '.';
        codecString += compatibilityFlags.toString(16).toUpperCase();
        codecString += '.';
        codecString += generalTierFlag === 0 ? 'L' : 'H';
        codecString += generalLevelIdc;
        while (constraintFlags.length > 0 && constraintFlags[constraintFlags.length - 1] === 0) {
            constraintFlags.pop();
        }
        if (constraintFlags.length > 0) {
            codecString += '.';
            codecString += constraintFlags.map(x => x.toString(16).toUpperCase()).join('.');
        }
        return codecString;
    }
    else if (codec === 'vp8') {
        return 'vp8'; // Easy, this one
    }
    else if (codec === 'vp9') {
        if (!vp9CodecInfo) {
            // Calculate level based on dimensions
            const pictureSize = trackInfo.width * trackInfo.height;
            let level = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .last */ ._g)(VP9_LEVEL_TABLE).level; // Default to highest level
            for (const entry of VP9_LEVEL_TABLE) {
                if (pictureSize <= entry.maxPictureSize) {
                    level = entry.level;
                    break;
                }
            }
            // We don't really know better, so let's return a general-purpose, common codec string and hope for the best
            return `vp09.00.${level.toString().padStart(2, '0')}.08`;
        }
        const profile = vp9CodecInfo.profile.toString().padStart(2, '0');
        const level = vp9CodecInfo.level.toString().padStart(2, '0');
        const bitDepth = vp9CodecInfo.bitDepth.toString().padStart(2, '0');
        const chromaSubsampling = vp9CodecInfo.chromaSubsampling.toString().padStart(2, '0');
        const colourPrimaries = vp9CodecInfo.colourPrimaries.toString().padStart(2, '0');
        const transferCharacteristics = vp9CodecInfo.transferCharacteristics.toString().padStart(2, '0');
        const matrixCoefficients = vp9CodecInfo.matrixCoefficients.toString().padStart(2, '0');
        const videoFullRangeFlag = vp9CodecInfo.videoFullRangeFlag.toString().padStart(2, '0');
        let string = `vp09.${profile}.${level}.${bitDepth}.${chromaSubsampling}`;
        string += `.${colourPrimaries}.${transferCharacteristics}.${matrixCoefficients}.${videoFullRangeFlag}`;
        if (string.endsWith(VP9_DEFAULT_SUFFIX)) {
            string = string.slice(0, -VP9_DEFAULT_SUFFIX.length);
        }
        return string;
    }
    else if (codec === 'av1') {
        if (!av1CodecInfo) {
            // Calculate level based on dimensions
            const pictureSize = trackInfo.width * trackInfo.height;
            let level = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .last */ ._g)(VP9_LEVEL_TABLE).level; // Default to highest level
            for (const entry of VP9_LEVEL_TABLE) {
                if (pictureSize <= entry.maxPictureSize) {
                    level = entry.level;
                    break;
                }
            }
            // We don't really know better, so let's return a general-purpose, common codec string and hope for the best
            return `av01.0.${level.toString().padStart(2, '0')}M.08`;
        }
        // https://aomediacodec.github.io/av1-isobmff/#codecsparam
        const profile = av1CodecInfo.profile; // Single digit
        const level = av1CodecInfo.level.toString().padStart(2, '0');
        const tier = av1CodecInfo.tier ? 'H' : 'M';
        const bitDepth = av1CodecInfo.bitDepth.toString().padStart(2, '0');
        const monochrome = av1CodecInfo.monochrome ? '1' : '0';
        const chromaSubsampling = 100 * av1CodecInfo.chromaSubsamplingX
            + 10 * av1CodecInfo.chromaSubsamplingY
            + 1 * (av1CodecInfo.chromaSubsamplingX && av1CodecInfo.chromaSubsamplingY
                ? av1CodecInfo.chromaSamplePosition
                : 0);
        // The defaults are 1 (ITU-R BT.709)
        const colorPrimaries = colorSpace?.primaries ? _misc_js__WEBPACK_IMPORTED_MODULE_1__/* .COLOR_PRIMARIES_MAP */ .wd[colorSpace.primaries] : 1;
        const transferCharacteristics = colorSpace?.transfer ? _misc_js__WEBPACK_IMPORTED_MODULE_1__/* .TRANSFER_CHARACTERISTICS_MAP */ .uN[colorSpace.transfer] : 1;
        const matrixCoefficients = colorSpace?.matrix ? _misc_js__WEBPACK_IMPORTED_MODULE_1__/* .MATRIX_COEFFICIENTS_MAP */ .Au[colorSpace.matrix] : 1;
        const videoFullRangeFlag = colorSpace?.fullRange ? 1 : 0;
        let string = `av01.${profile}.${level}${tier}.${bitDepth}`;
        string += `.${monochrome}.${chromaSubsampling.toString().padStart(3, '0')}`;
        string += `.${colorPrimaries.toString().padStart(2, '0')}`;
        string += `.${transferCharacteristics.toString().padStart(2, '0')}`;
        string += `.${matrixCoefficients.toString().padStart(2, '0')}`;
        string += `.${videoFullRangeFlag}`;
        if (string.endsWith(AV1_DEFAULT_SUFFIX)) {
            string = string.slice(0, -AV1_DEFAULT_SUFFIX.length);
        }
        return string;
    }
    throw new TypeError(`Unhandled codec '${codec}'.`);
};
const buildAudioCodecString = (codec, numberOfChannels, sampleRate) => {
    if (codec === 'aac') {
        // If stereo or higher channels and lower sample rate, likely using HE-AAC v2 with PS
        if (numberOfChannels >= 2 && sampleRate <= 24000) {
            return 'mp4a.40.29'; // HE-AAC v2 (AAC LC + SBR + PS)
        }
        // If sample rate is low, likely using HE-AAC v1 with SBR
        if (sampleRate <= 24000) {
            return 'mp4a.40.5'; // HE-AAC v1 (AAC LC + SBR)
        }
        // Default to standard AAC-LC for higher sample rates
        return 'mp4a.40.2'; // AAC-LC
    }
    else if (codec === 'mp3') {
        return 'mp3';
    }
    else if (codec === 'opus') {
        return 'opus';
    }
    else if (codec === 'vorbis') {
        return 'vorbis';
    }
    else if (codec === 'flac') {
        return 'flac';
    }
    else if (codec === 'ac3') {
        return 'ac-3';
    }
    else if (codec === 'eac3') {
        return 'ec-3';
    }
    else if (PCM_AUDIO_CODECS.includes(codec)) {
        return codec;
    }
    throw new TypeError(`Unhandled codec '${codec}'.`);
};
const extractAudioCodecString = (trackInfo) => {
    const { codec, codecDescription, aacCodecInfo } = trackInfo;
    if (codec === 'aac') {
        if (!aacCodecInfo) {
            throw new TypeError('AAC codec info must be provided.');
        }
        if (aacCodecInfo.isMpeg2) {
            return 'mp4a.67';
        }
        else {
            let objectType;
            if (aacCodecInfo.objectType !== null) {
                objectType = aacCodecInfo.objectType;
            }
            else {
                const audioSpecificConfig = (0,_shared_aac_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .parseAacAudioSpecificConfig */ .zF)(codecDescription);
                objectType = audioSpecificConfig.objectType;
            }
            return `mp4a.40.${objectType}`;
        }
    }
    else if (codec === 'mp3') {
        return 'mp3';
    }
    else if (codec === 'opus') {
        return 'opus';
    }
    else if (codec === 'vorbis') {
        return 'vorbis';
    }
    else if (codec === 'flac') {
        return 'flac';
    }
    else if (codec === 'ac3') {
        return 'ac-3';
    }
    else if (codec === 'eac3') {
        return 'ec-3';
    }
    else if (codec && PCM_AUDIO_CODECS.includes(codec)) {
        return codec;
    }
    throw new TypeError(`Unhandled codec '${codec}'.`);
};
// eslint-disable-next-line @typescript-eslint/no-unused-vars
const guessDescriptionForVideo = (decoderConfig) => {
    return undefined; // All codecs allow an undefined description
};
const guessDescriptionForAudio = (decoderConfig) => {
    switch (decoderConfig.codec) {
        case 'flac':
            {
                const referenceDescription = base64ToBytes('ZkxhQ4AAACIQABAAAAYtACWtCsRC8AANRBhVFucAcYu5ASE2m1Dxv8tw');
                if (decoderConfig.sampleRate >= (1 << 20) || decoderConfig.numberOfChannels > 8) {
                    return false;
                }
                referenceDescription[18] = decoderConfig.sampleRate >>> 12;
                referenceDescription[19] = decoderConfig.sampleRate >>> 4;
                referenceDescription[20]
                    = ((decoderConfig.sampleRate & 0x0f) << 4) | ((decoderConfig.numberOfChannels - 1) << 1);
                return referenceDescription;
            }
            // removed by dead control flow

        case 'vorbis':
            {
                // eslint-disable-next-line @stylistic/max-len
                const referenceDescription = base64ToBytes('Ah7/AgF2b3JiaXMAAAAAAoC7AAAAAAAAgLUBAAAAAAC4AQN2b3JiaXMNAAAATGF2ZjU4Ljc2LjEwMAgAAAAMAAAAbGFuZ3VhZ2U9dW5kGQAAAGhhbmRsZXJfbmFtZT1Tb3VuZEhhbmRsZXIWAAAAdmVuZG9yX2lkPVswXVswXVswXVswXSAAAABlbmNvZGVyPUxhdmM1OC4xMzQuMTAwIGxpYnZvcmJpcxAAAABtYWpvcl9icmFuZD1pc29tEQAAAG1pbm9yX3ZlcnNpb249NTEyIgAAAGNvbXBhdGlibGVfYnJhbmRzPWlzb21pc28yYXZjMW1wNDEmAAAAREVTQ1JJUFRJT049TWFkZSB3aXRoIFJlbW90aW9uIDQuMC4yNzgBBXZvcmJpcyVCQ1YBAEAAACRzGCpGpXMWhBAaQlAZ4xxCzmvsGUJMEYIcMkxbyyVzkCGkoEKIWyiB0JBVAABAAACHQXgUhIpBCCGEJT1YkoMnPQghhIg5eBSEaUEIIYQQQgghhBBCCCGERTlokoMnQQgdhOMwOAyD5Tj4HIRFOVgQgydB6CCED0K4moOsOQghhCQ1SFCDBjnoHITCLCiKgsQwuBaEBDUojILkMMjUgwtCiJqDSTX4GoRnQXgWhGlBCCGEJEFIkIMGQcgYhEZBWJKDBjm4FITLQagahCo5CB+EIDRkFQCQAACgoiiKoigKEBqyCgDIAAAQQFEUx3EcyZEcybEcCwgNWQUAAAEACAAAoEiKpEiO5EiSJFmSJVmSJVmS5omqLMuyLMuyLMsyEBqyCgBIAABQUQxFcRQHCA1ZBQBkAAAIoDiKpViKpWiK54iOCISGrAIAgAAABAAAEDRDUzxHlETPVFXXtm3btm3btm3btm3btm1blmUZCA1ZBQBAAAAQ0mlmqQaIMAMZBkJDVgEACAAAgBGKMMSA0JBVAABAAACAGEoOogmtOd+c46BZDppKsTkdnEi1eZKbirk555xzzsnmnDHOOeecopxZDJoJrTnnnMSgWQqaCa0555wnsXnQmiqtOeeccc7pYJwRxjnnnCateZCajbU555wFrWmOmkuxOeecSLl5UptLtTnnnHPOOeecc84555zqxekcnBPOOeecqL25lpvQxTnnnE/G6d6cEM4555xzzjnnnHPOOeecIDRkFQAABABAEIaNYdwpCNLnaCBGEWIaMulB9+gwCRqDnELq0ehopJQ6CCWVcVJKJwgNWQUAAAIAQAghhRRSSCGFFFJIIYUUYoghhhhyyimnoIJKKqmooowyyyyzzDLLLLPMOuyssw47DDHEEEMrrcRSU2011lhr7jnnmoO0VlprrbVSSimllFIKQkNWAQAgAAAEQgYZZJBRSCGFFGKIKaeccgoqqIDQkFUAACAAgAAAAABP8hzRER3RER3RER3RER3R8RzPESVREiVREi3TMjXTU0VVdWXXlnVZt31b2IVd933d933d+HVhWJZlWZZlWZZlWZZlWZZlWZYgNGQVAAACAAAghBBCSCGFFFJIKcYYc8w56CSUEAgNWQUAAAIACAAAAHAUR3EcyZEcSbIkS9IkzdIsT/M0TxM9URRF0zRV0RVdUTdtUTZl0zVdUzZdVVZtV5ZtW7Z125dl2/d93/d93/d93/d93/d9XQdCQ1YBABIAADqSIymSIimS4ziOJElAaMgqAEAGAEAAAIriKI7jOJIkSZIlaZJneZaomZrpmZ4qqkBoyCoAABAAQAAAAAAAAIqmeIqpeIqoeI7oiJJomZaoqZoryqbsuq7ruq7ruq7ruq7ruq7ruq7ruq7ruq7ruq7ruq7ruq7ruq4LhIasAgAkAAB0JEdyJEdSJEVSJEdygNCQVQCADACAAAAcwzEkRXIsy9I0T/M0TxM90RM901NFV3SB0JBVAAAgAIAAAAAAAAAMybAUy9EcTRIl1VItVVMt1VJF1VNVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVN0zRNEwgNWQkAkAEAkBBTLS3GmgmLJGLSaqugYwxS7KWxSCpntbfKMYUYtV4ah5RREHupJGOKQcwtpNApJq3WVEKFFKSYYyoVUg5SIDRkhQAQmgHgcBxAsixAsiwAAAAAAAAAkDQN0DwPsDQPAAAAAAAAACRNAyxPAzTPAwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABA0jRA8zxA8zwAAAAAAAAA0DwP8DwR8EQRAAAAAAAAACzPAzTRAzxRBAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABA0jRA8zxA8zwAAAAAAAAAsDwP8EQR0DwRAAAAAAAAACzPAzxRBDzRAwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEAAAEOAAABBgIRQasiIAiBMAcEgSJAmSBM0DSJYFTYOmwTQBkmVB06BpME0AAAAAAAAAAAAAJE2DpkHTIIoASdOgadA0iCIAAAAAAAAAAAAAkqZB06BpEEWApGnQNGgaRBEAAAAAAAAAAAAAzzQhihBFmCbAM02IIkQRpgkAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAAGHAAAAgwoQwUGrIiAIgTAHA4imUBAIDjOJYFAACO41gWAABYliWKAABgWZooAgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIAAAYcAAACDChDBQashIAiAIAcCiKZQHHsSzgOJYFJMmyAJYF0DyApgFEEQAIAAAocAAACLBBU2JxgEJDVgIAUQAABsWxLE0TRZKkaZoniiRJ0zxPFGma53meacLzPM80IYqiaJoQRVE0TZimaaoqME1VFQAAUOAAABBgg6bE4gCFhqwEAEICAByKYlma5nmeJ4qmqZokSdM8TxRF0TRNU1VJkqZ5niiKommapqqyLE3zPFEURdNUVVWFpnmeKIqiaaqq6sLzPE8URdE0VdV14XmeJ4qiaJqq6roQRVE0TdNUTVV1XSCKpmmaqqqqrgtETxRNU1Vd13WB54miaaqqq7ouEE3TVFVVdV1ZBpimaaqq68oyQFVV1XVdV5YBqqqqruu6sgxQVdd1XVmWZQCu67qyLMsCAAAOHAAAAoygk4wqi7DRhAsPQKEhKwKAKAAAwBimFFPKMCYhpBAaxiSEFEImJaXSUqogpFJSKRWEVEoqJaOUUmopVRBSKamUCkIqJZVSAADYgQMA2IGFUGjISgAgDwCAMEYpxhhzTiKkFGPOOScRUoox55yTSjHmnHPOSSkZc8w556SUzjnnnHNSSuacc845KaVzzjnnnJRSSuecc05KKSWEzkEnpZTSOeecEwAAVOAAABBgo8jmBCNBhYasBABSAQAMjmNZmuZ5omialiRpmud5niiapiZJmuZ5nieKqsnzPE8URdE0VZXneZ4oiqJpqirXFUXTNE1VVV2yLIqmaZqq6rowTdNUVdd1XZimaaqq67oubFtVVdV1ZRm2raqq6rqyDFzXdWXZloEsu67s2rIAAPAEBwCgAhtWRzgpGgssNGQlAJABAEAYg5BCCCFlEEIKIYSUUggJAAAYcAAACDChDBQashIASAUAAIyx1lprrbXWQGettdZaa62AzFprrbXWWmuttdZaa6211lJrrbXWWmuttdZaa6211lprrbXWWmuttdZaa6211lprrbXWWmuttdZaa6211lprrbXWWmstpZRSSimllFJKKaWUUkoppZRSSgUA+lU4APg/2LA6wknRWGChISsBgHAAAMAYpRhzDEIppVQIMeacdFRai7FCiDHnJKTUWmzFc85BKCGV1mIsnnMOQikpxVZjUSmEUlJKLbZYi0qho5JSSq3VWIwxqaTWWoutxmKMSSm01FqLMRYjbE2ptdhqq7EYY2sqLbQYY4zFCF9kbC2m2moNxggjWywt1VprMMYY3VuLpbaaizE++NpSLDHWXAAAd4MDAESCjTOsJJ0VjgYXGrISAAgJACAQUooxxhhzzjnnpFKMOeaccw5CCKFUijHGnHMOQgghlIwx5pxzEEIIIYRSSsaccxBCCCGEkFLqnHMQQgghhBBKKZ1zDkIIIYQQQimlgxBCCCGEEEoopaQUQgghhBBCCKmklEIIIYRSQighlZRSCCGEEEIpJaSUUgohhFJCCKGElFJKKYUQQgillJJSSimlEkoJJYQSUikppRRKCCGUUkpKKaVUSgmhhBJKKSWllFJKIYQQSikFAAAcOAAABBhBJxlVFmGjCRcegEJDVgIAZAAAkKKUUiktRYIipRikGEtGFXNQWoqocgxSzalSziDmJJaIMYSUk1Qy5hRCDELqHHVMKQYtlRhCxhik2HJLoXMOAAAAQQCAgJAAAAMEBTMAwOAA4XMQdAIERxsAgCBEZohEw0JweFAJEBFTAUBigkIuAFRYXKRdXECXAS7o4q4DIQQhCEEsDqCABByccMMTb3jCDU7QKSp1IAAAAAAADADwAACQXAAREdHMYWRobHB0eHyAhIiMkAgAAAAAABcAfAAAJCVAREQ0cxgZGhscHR4fICEiIyQBAIAAAgAAAAAggAAEBAQAAAAAAAIAAAAEBA==');
                const view = toDataView(referenceDescription);
                view.setUint8(15, decoderConfig.numberOfChannels);
                view.setUint32(16, decoderConfig.sampleRate, true);
                return referenceDescription;
            }
            // removed by dead control flow

        default: return undefined; // All other codecs allow an undefined description
    }
};
const OPUS_SAMPLE_RATE = 48_000;
const PCM_CODEC_REGEX = /^pcm-([usf])(\d+)+(be)?$/;
const parsePcmCodec = (codec) => {
    (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .assert */ .vA)(PCM_AUDIO_CODECS.includes(codec));
    if (codec === 'ulaw') {
        return { dataType: 'ulaw', sampleSize: 1, littleEndian: true, silentValue: 255 };
    }
    else if (codec === 'alaw') {
        return { dataType: 'alaw', sampleSize: 1, littleEndian: true, silentValue: 213 };
    }
    const match = PCM_CODEC_REGEX.exec(codec);
    (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .assert */ .vA)(match);
    let dataType;
    if (match[1] === 'u') {
        dataType = 'unsigned';
    }
    else if (match[1] === 's') {
        dataType = 'signed';
    }
    else {
        dataType = 'float';
    }
    const sampleSize = (Number(match[2]) / 8);
    const littleEndian = match[3] !== 'be';
    const silentValue = codec === 'pcm-u8' ? 2 ** 7 : 0;
    return { dataType, sampleSize, littleEndian, silentValue };
};
const inferCodecFromCodecString = (codecString) => {
    // Video codecs
    if (codecString.startsWith('avc1') || codecString.startsWith('avc3')) {
        return 'avc';
    }
    else if (codecString.startsWith('hev1') || codecString.startsWith('hvc1')) {
        return 'hevc';
    }
    else if (codecString === 'vp8') {
        return 'vp8';
    }
    else if (codecString.startsWith('vp09')) {
        return 'vp9';
    }
    else if (codecString.startsWith('av01')) {
        return 'av1';
    }
    // Audio codecs
    if (codecString === 'mp3'
        || codecString === 'mp4a.69'
        || codecString === 'mp4a.6B'
        || codecString === 'mp4a.6b'
        || codecString === 'mp4a.40.34') {
        return 'mp3';
    }
    else if (codecString.startsWith('mp4a.40.') || codecString === 'mp4a.67') {
        return 'aac';
    }
    else if (codecString === 'opus') {
        return 'opus';
    }
    else if (codecString === 'vorbis') {
        return 'vorbis';
    }
    else if (codecString === 'flac') {
        return 'flac';
    }
    else if (codecString === 'ac-3' || codecString === 'ac3') {
        return 'ac3';
    }
    else if (codecString === 'ec-3' || codecString === 'eac3') {
        return 'eac3';
    }
    else if (codecString === 'ulaw') {
        return 'ulaw';
    }
    else if (codecString === 'alaw') {
        return 'alaw';
    }
    else if (PCM_CODEC_REGEX.test(codecString)) {
        return codecString;
    }
    // Subtitle codecs
    if (codecString === 'webvtt') {
        return 'webvtt';
    }
    return null;
};
const getVideoEncoderConfigExtension = (codec) => {
    if (codec === 'avc') {
        return {
            avc: {
                format: 'avc', // Ensure the format is not Annex B
            },
        };
    }
    else if (codec === 'hevc') {
        return {
            hevc: {
                format: 'hevc', // Ensure the format is not Annex B
            },
        };
    }
    return {};
};
const getAudioEncoderConfigExtension = (codec) => {
    if (codec === 'aac') {
        return {
            aac: {
                format: 'aac', // Ensure the format is not ADTS
            },
        };
    }
    else if (codec === 'opus') {
        return {
            opus: {
                format: 'opus',
            },
        };
    }
    return {};
};
const VALID_VIDEO_CODEC_STRING_PREFIXES = (/* unused pure expression or super */ null && (['avc1', 'avc3', 'hev1', 'hvc1', 'vp8', 'vp09', 'av01']));
const AVC_CODEC_STRING_REGEX = /^(avc1|avc3)\.[0-9a-fA-F]{6}$/;
const HEVC_CODEC_STRING_REGEX = /^(hev1|hvc1)\.(?:[ABC]?\d+)\.[0-9a-fA-F]{1,8}\.[LH]\d+(?:\.[0-9a-fA-F]{1,2}){0,6}$/;
const VP9_CODEC_STRING_REGEX = /^vp09(?:\.\d{2}){3}(?:(?:\.\d{2}){5})?$/;
const AV1_CODEC_STRING_REGEX = /^av01\.\d\.\d{2}[MH]\.\d{2}(?:\.\d\.\d{3}\.\d{2}\.\d{2}\.\d{2}\.\d)?$/;
const validateVideoChunkMetadata = (metadata) => {
    if (!metadata) {
        throw new TypeError('Video chunk metadata must be provided.');
    }
    if (typeof metadata !== 'object') {
        throw new TypeError('Video chunk metadata must be an object.');
    }
    if (!metadata.decoderConfig) {
        throw new TypeError('Video chunk metadata must include a decoder configuration.');
    }
    if (typeof metadata.decoderConfig !== 'object') {
        throw new TypeError('Video chunk metadata decoder configuration must be an object.');
    }
    if (typeof metadata.decoderConfig.codec !== 'string') {
        throw new TypeError('Video chunk metadata decoder configuration must specify a codec string.');
    }
    if (!VALID_VIDEO_CODEC_STRING_PREFIXES.some(prefix => metadata.decoderConfig.codec.startsWith(prefix))) {
        throw new TypeError('Video chunk metadata decoder configuration codec string must be a valid video codec string as specified in'
            + ' the Mediabunny Codec Registry.');
    }
    if (!Number.isInteger(metadata.decoderConfig.codedWidth) || metadata.decoderConfig.codedWidth <= 0) {
        throw new TypeError('Video chunk metadata decoder configuration must specify a valid codedWidth (positive integer).');
    }
    if (!Number.isInteger(metadata.decoderConfig.codedHeight) || metadata.decoderConfig.codedHeight <= 0) {
        throw new TypeError('Video chunk metadata decoder configuration must specify a valid codedHeight (positive integer).');
    }
    if (metadata.decoderConfig.description !== undefined) {
        if (!isAllowSharedBufferSource(metadata.decoderConfig.description)) {
            throw new TypeError('Video chunk metadata decoder configuration description, when defined, must be an ArrayBuffer or an'
                + ' ArrayBuffer view.');
        }
    }
    if (metadata.decoderConfig.colorSpace !== undefined) {
        const { colorSpace } = metadata.decoderConfig;
        if (typeof colorSpace !== 'object') {
            throw new TypeError('Video chunk metadata decoder configuration colorSpace, when provided, must be an object.');
        }
        const primariesValues = Object.keys(COLOR_PRIMARIES_MAP);
        if (colorSpace.primaries != null && !primariesValues.includes(colorSpace.primaries)) {
            throw new TypeError(`Video chunk metadata decoder configuration colorSpace primaries, when defined, must be one of`
                + ` ${primariesValues.join(', ')}.`);
        }
        const transferValues = Object.keys(TRANSFER_CHARACTERISTICS_MAP);
        if (colorSpace.transfer != null && !transferValues.includes(colorSpace.transfer)) {
            throw new TypeError(`Video chunk metadata decoder configuration colorSpace transfer, when defined, must be one of`
                + ` ${transferValues.join(', ')}.`);
        }
        const matrixValues = Object.keys(MATRIX_COEFFICIENTS_MAP);
        if (colorSpace.matrix != null && !matrixValues.includes(colorSpace.matrix)) {
            throw new TypeError(`Video chunk metadata decoder configuration colorSpace matrix, when defined, must be one of`
                + ` ${matrixValues.join(', ')}.`);
        }
        if (colorSpace.fullRange != null && typeof colorSpace.fullRange !== 'boolean') {
            throw new TypeError('Video chunk metadata decoder configuration colorSpace fullRange, when defined, must be a boolean.');
        }
    }
    if (metadata.decoderConfig.codec.startsWith('avc1') || metadata.decoderConfig.codec.startsWith('avc3')) {
        // AVC-specific validation
        if (!AVC_CODEC_STRING_REGEX.test(metadata.decoderConfig.codec)) {
            throw new TypeError('Video chunk metadata decoder configuration codec string for AVC must be a valid AVC codec string as'
                + ' specified in Section 3.4 of RFC 6381.');
        }
        // `description` may or may not be set, depending on if the format is AVCC or Annex B, so don't perform any
        // validation for it.
        // https://www.w3.org/TR/webcodecs-avc-codec-registration
    }
    else if (metadata.decoderConfig.codec.startsWith('hev1') || metadata.decoderConfig.codec.startsWith('hvc1')) {
        // HEVC-specific validation
        if (!HEVC_CODEC_STRING_REGEX.test(metadata.decoderConfig.codec)) {
            throw new TypeError('Video chunk metadata decoder configuration codec string for HEVC must be a valid HEVC codec string as'
                + ' specified in Section E.3 of ISO 14496-15.');
        }
        // `description` may or may not be set, depending on if the format is HEVC or Annex B, so don't perform any
        // validation for it.
        // https://www.w3.org/TR/webcodecs-hevc-codec-registration
    }
    else if (metadata.decoderConfig.codec.startsWith('vp8')) {
        // VP8-specific validation
        if (metadata.decoderConfig.codec !== 'vp8') {
            throw new TypeError('Video chunk metadata decoder configuration codec string for VP8 must be "vp8".');
        }
    }
    else if (metadata.decoderConfig.codec.startsWith('vp09')) {
        // VP9-specific validation
        if (!VP9_CODEC_STRING_REGEX.test(metadata.decoderConfig.codec)) {
            throw new TypeError('Video chunk metadata decoder configuration codec string for VP9 must be a valid VP9 codec string as'
                + ' specified in Section "Codecs Parameter String" of https://www.webmproject.org/vp9/mp4/.');
        }
    }
    else if (metadata.decoderConfig.codec.startsWith('av01')) {
        // AV1-specific validation
        if (!AV1_CODEC_STRING_REGEX.test(metadata.decoderConfig.codec)) {
            throw new TypeError('Video chunk metadata decoder configuration codec string for AV1 must be a valid AV1 codec string as'
                + ' specified in Section "Codecs Parameter String" of https://aomediacodec.github.io/av1-isobmff/.');
        }
    }
};
const VALID_AUDIO_CODEC_STRING_PREFIXES = (/* unused pure expression or super */ null && ([
    'mp4a', 'mp3', 'opus', 'vorbis', 'flac', 'ulaw', 'alaw', 'pcm', 'ac-3', 'ec-3',
]));
const validateAudioChunkMetadata = (metadata) => {
    if (!metadata) {
        throw new TypeError('Audio chunk metadata must be provided.');
    }
    if (typeof metadata !== 'object') {
        throw new TypeError('Audio chunk metadata must be an object.');
    }
    if (!metadata.decoderConfig) {
        throw new TypeError('Audio chunk metadata must include a decoder configuration.');
    }
    if (typeof metadata.decoderConfig !== 'object') {
        throw new TypeError('Audio chunk metadata decoder configuration must be an object.');
    }
    if (typeof metadata.decoderConfig.codec !== 'string') {
        throw new TypeError('Audio chunk metadata decoder configuration must specify a codec string.');
    }
    if (!VALID_AUDIO_CODEC_STRING_PREFIXES.some(prefix => metadata.decoderConfig.codec.startsWith(prefix))) {
        throw new TypeError('Audio chunk metadata decoder configuration codec string must be a valid audio codec string as specified in'
            + ' the Mediabunny Codec Registry.');
    }
    if (!Number.isInteger(metadata.decoderConfig.sampleRate) || metadata.decoderConfig.sampleRate <= 0) {
        throw new TypeError('Audio chunk metadata decoder configuration must specify a valid sampleRate (positive integer).');
    }
    if (!Number.isInteger(metadata.decoderConfig.numberOfChannels) || metadata.decoderConfig.numberOfChannels <= 0) {
        throw new TypeError('Audio chunk metadata decoder configuration must specify a valid numberOfChannels (positive integer).');
    }
    if (metadata.decoderConfig.description !== undefined) {
        if (!isAllowSharedBufferSource(metadata.decoderConfig.description)) {
            throw new TypeError('Audio chunk metadata decoder configuration description, when defined, must be an ArrayBuffer or an'
                + ' ArrayBuffer view.');
        }
    }
    if (metadata.decoderConfig.codec.startsWith('mp4a')
        // These three refer to MP3:
        && metadata.decoderConfig.codec !== 'mp4a.69'
        && metadata.decoderConfig.codec !== 'mp4a.6B'
        && metadata.decoderConfig.codec !== 'mp4a.6b') {
        // AAC-specific validation
        const validStrings = ['mp4a.40.2', 'mp4a.40.02', 'mp4a.40.5', 'mp4a.40.05', 'mp4a.40.29', 'mp4a.67'];
        if (!validStrings.includes(metadata.decoderConfig.codec)) {
            throw new TypeError('Audio chunk metadata decoder configuration codec string for AAC must be a valid AAC codec string as'
                + ' specified in https://www.w3.org/TR/webcodecs-aac-codec-registration/.');
        }
        // `description` may or may not be set, depending on if the format is AAC or ADTS, so don't perform any
        // validation for it.
        // https://www.w3.org/TR/webcodecs-aac-codec-registration
    }
    else if (metadata.decoderConfig.codec.startsWith('mp3') || metadata.decoderConfig.codec.startsWith('mp4a')) {
        // MP3-specific validation
        if (metadata.decoderConfig.codec !== 'mp3'
            && metadata.decoderConfig.codec !== 'mp4a.69'
            && metadata.decoderConfig.codec !== 'mp4a.6B'
            && metadata.decoderConfig.codec !== 'mp4a.6b') {
            throw new TypeError('Audio chunk metadata decoder configuration codec string for MP3 must be "mp3", "mp4a.69" or'
                + ' "mp4a.6B".');
        }
    }
    else if (metadata.decoderConfig.codec.startsWith('opus')) {
        // Opus-specific validation
        if (metadata.decoderConfig.codec !== 'opus') {
            throw new TypeError('Audio chunk metadata decoder configuration codec string for Opus must be "opus".');
        }
        if (metadata.decoderConfig.description && metadata.decoderConfig.description.byteLength < 18) {
            // Description is optional for Opus per-spec, so we shouldn't enforce it
            throw new TypeError('Audio chunk metadata decoder configuration description, when specified, is expected to be an'
                + ' Identification Header as specified in Section 5.1 of RFC 7845.');
        }
    }
    else if (metadata.decoderConfig.codec.startsWith('vorbis')) {
        // Vorbis-specific validation
        if (metadata.decoderConfig.codec !== 'vorbis') {
            throw new TypeError('Audio chunk metadata decoder configuration codec string for Vorbis must be "vorbis".');
        }
        if (!metadata.decoderConfig.description) {
            throw new TypeError('Audio chunk metadata decoder configuration for Vorbis must include a description, which is expected to'
                + ' adhere to the format described in https://www.w3.org/TR/webcodecs-vorbis-codec-registration/.');
        }
    }
    else if (metadata.decoderConfig.codec.startsWith('flac')) {
        // FLAC-specific validation
        if (metadata.decoderConfig.codec !== 'flac') {
            throw new TypeError('Audio chunk metadata decoder configuration codec string for FLAC must be "flac".');
        }
        const minDescriptionSize = 4 + 4 + 34; // 'fLaC' + metadata block header + STREAMINFO block
        if (!metadata.decoderConfig.description || metadata.decoderConfig.description.byteLength < minDescriptionSize) {
            throw new TypeError('Audio chunk metadata decoder configuration for FLAC must include a description, which is expected to'
                + ' adhere to the format described in https://www.w3.org/TR/webcodecs-flac-codec-registration/.');
        }
    }
    else if (metadata.decoderConfig.codec.startsWith('ac-3') || metadata.decoderConfig.codec.startsWith('ac3')) {
        // AC3-specific validation
        if (metadata.decoderConfig.codec !== 'ac-3') {
            throw new TypeError('Audio chunk metadata decoder configuration codec string for AC-3 must be "ac-3".');
        }
    }
    else if (metadata.decoderConfig.codec.startsWith('ec-3') || metadata.decoderConfig.codec.startsWith('eac3')) {
        // EAC3-specific validation
        if (metadata.decoderConfig.codec !== 'ec-3') {
            throw new TypeError('Audio chunk metadata decoder configuration codec string for EC-3 must be "ec-3".');
        }
    }
    else if (metadata.decoderConfig.codec.startsWith('pcm')
        || metadata.decoderConfig.codec.startsWith('ulaw')
        || metadata.decoderConfig.codec.startsWith('alaw')) {
        // PCM-specific validation
        if (!PCM_AUDIO_CODECS.includes(metadata.decoderConfig.codec)) {
            throw new TypeError('Audio chunk metadata decoder configuration codec string for PCM must be one of the supported PCM'
                + ` codecs (${PCM_AUDIO_CODECS.join(', ')}).`);
        }
    }
};
const validateSubtitleMetadata = (metadata) => {
    if (!metadata) {
        throw new TypeError('Subtitle metadata must be provided.');
    }
    if (typeof metadata !== 'object') {
        throw new TypeError('Subtitle metadata must be an object.');
    }
    if (!metadata.config) {
        throw new TypeError('Subtitle metadata must include a config object.');
    }
    if (typeof metadata.config !== 'object') {
        throw new TypeError('Subtitle metadata config must be an object.');
    }
    if (typeof metadata.config.description !== 'string') {
        throw new TypeError('Subtitle metadata config description must be a string.');
    }
};


/***/ },

/***/ 8647
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   wb: () => (/* binding */ customVideoDecoders),
/* harmony export */   zx: () => (/* binding */ customAudioDecoders)
/* harmony export */ });
/* unused harmony exports CustomVideoDecoder, CustomAudioDecoder, CustomVideoEncoder, CustomAudioEncoder, customVideoEncoders, customAudioEncoders, registerDecoder, registerEncoder */
/* unused harmony import specifier */ var canDecodeVideoMemo;
/* unused harmony import specifier */ var canDecodeAudioMemo;
/* unused harmony import specifier */ var canEncodeVideoMemo;
/* unused harmony import specifier */ var canEncodeAudioMemo;
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


/**
 * Base class for custom video decoders. To add your own custom video decoder, extend this class, implement the
 * abstract methods and static `supports` method, and register the decoder using {@link registerDecoder}.
 * @group Custom coders
 * @public
 */
class CustomVideoDecoder {
    /** Returns true if and only if the decoder can decode the given codec configuration. */
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    static supports(codec, config) {
        return false;
    }
}
/**
 * Base class for custom audio decoders. To add your own custom audio decoder, extend this class, implement the
 * abstract methods and static `supports` method, and register the decoder using {@link registerDecoder}.
 * @group Custom coders
 * @public
 */
class CustomAudioDecoder {
    /** Returns true if and only if the decoder can decode the given codec configuration. */
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    static supports(codec, config) {
        return false;
    }
}
/**
 * Base class for custom video encoders. To add your own custom video encoder, extend this class, implement the
 * abstract methods and static `supports` method, and register the encoder using {@link registerEncoder}.
 * @group Custom coders
 * @public
 */
class CustomVideoEncoder {
    /** Returns true if and only if the encoder can encode the given codec configuration. */
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    static supports(codec, config) {
        return false;
    }
}
/**
 * Base class for custom audio encoders. To add your own custom audio encoder, extend this class, implement the
 * abstract methods and static `supports` method, and register the encoder using {@link registerEncoder}.
 * @group Custom coders
 * @public
 */
class CustomAudioEncoder {
    /** Returns true if and only if the encoder can encode the given codec configuration. */
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    static supports(codec, config) {
        return false;
    }
}
const customVideoDecoders = [];
const customAudioDecoders = [];
const customVideoEncoders = (/* unused pure expression or super */ null && ([]));
const customAudioEncoders = (/* unused pure expression or super */ null && ([]));
/**
 * Registers a custom video or audio decoder. Registered decoders will automatically be used for decoding whenever
 * possible.
 * @group Custom coders
 * @public
 */
const registerDecoder = (decoder) => {
    if (decoder.prototype instanceof CustomVideoDecoder) {
        const casted = decoder;
        if (customVideoDecoders.includes(casted)) {
            console.warn('Video decoder already registered.');
            return;
        }
        customVideoDecoders.push(casted);
        canDecodeVideoMemo.clear();
    }
    else if (decoder.prototype instanceof CustomAudioDecoder) {
        const casted = decoder;
        if (customAudioDecoders.includes(casted)) {
            console.warn('Audio decoder already registered.');
            return;
        }
        customAudioDecoders.push(casted);
        canDecodeAudioMemo.clear();
    }
    else {
        throw new TypeError('Decoder must be a CustomVideoDecoder or CustomAudioDecoder.');
    }
};
/**
 * Registers a custom video or audio encoder. Registered encoders will automatically be used for encoding whenever
 * possible.
 * @group Custom coders
 * @public
 */
const registerEncoder = (encoder) => {
    if (encoder.prototype instanceof CustomVideoEncoder) {
        const casted = encoder;
        if (customVideoEncoders.includes(casted)) {
            console.warn('Video encoder already registered.');
            return;
        }
        customVideoEncoders.push(casted);
        canEncodeVideoMemo.clear();
    }
    else if (encoder.prototype instanceof CustomAudioEncoder) {
        const casted = encoder;
        if (customAudioEncoders.includes(casted)) {
            console.warn('Audio encoder already registered.');
            return;
        }
        customAudioEncoders.push(casted);
        canEncodeAudioMemo.clear();
    }
    else {
        throw new TypeError('Encoder must be a CustomVideoEncoder or CustomAudioEncoder.');
    }
};


/***/ },

/***/ 7576
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   IX: () => (/* binding */ readId3V2Header),
/* harmony export */   aU: () => (/* binding */ ID3_V1_TAG_SIZE),
/* harmony export */   cG: () => (/* binding */ parseId3V2Tag),
/* harmony export */   p_: () => (/* binding */ parseId3V1Tag),
/* harmony export */   sY: () => (/* binding */ ID3_V2_HEADER_SIZE)
/* harmony export */ });
/* unused harmony exports Id3V2HeaderFlags, Id3V2TextEncoding, ID3_V1_GENRES, readId3V1String, Id3V2Reader, Id3V2Writer */
/* unused harmony import specifier */ var encodeSynchsafe;
/* unused harmony import specifier */ var toDataView;
/* unused harmony import specifier */ var keyValueIterator;
/* unused harmony import specifier */ var assertNever;
/* unused harmony import specifier */ var isIso88591Compatible;
/* unused harmony import specifier */ var textEncoder;
/* unused harmony import specifier */ var isRecordStringString;
/* harmony import */ var _shared_mp3_misc_js__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(2788);
/* harmony import */ var _misc_js__WEBPACK_IMPORTED_MODULE_1__ = __webpack_require__(3912);
/* harmony import */ var _reader_js__WEBPACK_IMPORTED_MODULE_2__ = __webpack_require__(7735);
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */



var Id3V2HeaderFlags;
(function (Id3V2HeaderFlags) {
    Id3V2HeaderFlags[Id3V2HeaderFlags["Unsynchronisation"] = 128] = "Unsynchronisation";
    Id3V2HeaderFlags[Id3V2HeaderFlags["ExtendedHeader"] = 64] = "ExtendedHeader";
    Id3V2HeaderFlags[Id3V2HeaderFlags["ExperimentalIndicator"] = 32] = "ExperimentalIndicator";
    Id3V2HeaderFlags[Id3V2HeaderFlags["Footer"] = 16] = "Footer";
})(Id3V2HeaderFlags || (Id3V2HeaderFlags = {}));
var Id3V2TextEncoding;
(function (Id3V2TextEncoding) {
    Id3V2TextEncoding[Id3V2TextEncoding["ISO_8859_1"] = 0] = "ISO_8859_1";
    Id3V2TextEncoding[Id3V2TextEncoding["UTF_16_WITH_BOM"] = 1] = "UTF_16_WITH_BOM";
    Id3V2TextEncoding[Id3V2TextEncoding["UTF_16_BE_NO_BOM"] = 2] = "UTF_16_BE_NO_BOM";
    Id3V2TextEncoding[Id3V2TextEncoding["UTF_8"] = 3] = "UTF_8";
})(Id3V2TextEncoding || (Id3V2TextEncoding = {}));
const ID3_V1_TAG_SIZE = 128;
const ID3_V2_HEADER_SIZE = 10;
const ID3_V1_GENRES = [
    'Blues', 'Classic rock', 'Country', 'Dance', 'Disco', 'Funk', 'Grunge', 'Hip-hop', 'Jazz',
    'Metal', 'New age', 'Oldies', 'Other', 'Pop', 'Rhythm and blues', 'Rap', 'Reggae', 'Rock',
    'Techno', 'Industrial', 'Alternative', 'Ska', 'Death metal', 'Pranks', 'Soundtrack',
    'Euro-techno', 'Ambient', 'Trip-hop', 'Vocal', 'Jazz & funk', 'Fusion', 'Trance', 'Classical',
    'Instrumental', 'Acid', 'House', 'Game', 'Sound clip', 'Gospel', 'Noise', 'Alternative rock',
    'Bass', 'Soul', 'Punk', 'Space', 'Meditative', 'Instrumental pop', 'Instrumental rock',
    'Ethnic', 'Gothic', 'Darkwave', 'Techno-industrial', 'Electronic', 'Pop-folk', 'Eurodance',
    'Dream', 'Southern rock', 'Comedy', 'Cult', 'Gangsta', 'Top 40', 'Christian rap', 'Pop/funk',
    'Jungle music', 'Native US', 'Cabaret', 'New wave', 'Psychedelic', 'Rave', 'Showtunes',
    'Trailer', 'Lo-fi', 'Tribal', 'Acid punk', 'Acid jazz', 'Polka', 'Retro', 'Musical',
    'Rock \'n\' roll', 'Hard rock', 'Folk', 'Folk rock', 'National folk', 'Swing', 'Fast fusion',
    'Bebop', 'Latin', 'Revival', 'Celtic', 'Bluegrass', 'Avantgarde', 'Gothic rock',
    'Progressive rock', 'Psychedelic rock', 'Symphonic rock', 'Slow rock', 'Big band', 'Chorus',
    'Easy listening', 'Acoustic', 'Humour', 'Speech', 'Chanson', 'Opera', 'Chamber music',
    'Sonata', 'Symphony', 'Booty bass', 'Primus', 'Porn groove', 'Satire', 'Slow jam', 'Club',
    'Tango', 'Samba', 'Folklore', 'Ballad', 'Power ballad', 'Rhythmic Soul', 'Freestyle', 'Duet',
    'Punk rock', 'Drum solo', 'A cappella', 'Euro-house', 'Dance hall', 'Goa music', 'Drum & bass',
    'Club-house', 'Hardcore techno', 'Terror', 'Indie', 'Britpop', 'Negerpunk', 'Polsk punk',
    'Beat', 'Christian gangsta rap', 'Heavy metal', 'Black metal', 'Crossover',
    'Contemporary Christian', 'Christian rock', 'Merengue', 'Salsa', 'Thrash metal', 'Anime',
    'Jpop', 'Synthpop', 'Christmas', 'Art rock', 'Baroque', 'Bhangra', 'Big beat', 'Breakbeat',
    'Chillout', 'Downtempo', 'Dub', 'EBM', 'Eclectic', 'Electro', 'Electroclash', 'Emo',
    'Experimental', 'Garage', 'Global', 'IDM', 'Illbient', 'Industro-Goth', 'Jam Band',
    'Krautrock', 'Leftfield', 'Lounge', 'Math rock', 'New romantic', 'Nu-breakz', 'Post-punk',
    'Post-rock', 'Psytrance', 'Shoegaze', 'Space rock', 'Trop rock', 'World music', 'Neoclassical',
    'Audiobook', 'Audio theatre', 'Neue Deutsche Welle', 'Podcast', 'Indie rock', 'G-Funk',
    'Dubstep', 'Garage rock', 'Psybient',
];
const parseId3V1Tag = (slice, tags) => {
    const startPos = slice.filePos;
    tags.raw ??= {};
    tags.raw['TAG'] ??= (0,_reader_js__WEBPACK_IMPORTED_MODULE_2__/* .readBytes */ .io)(slice, ID3_V1_TAG_SIZE - 3); // Dump the whole tag into the raw metadata
    slice.filePos = startPos;
    const title = readId3V1String(slice, 30);
    if (title)
        tags.title ??= title;
    const artist = readId3V1String(slice, 30);
    if (artist)
        tags.artist ??= artist;
    const album = readId3V1String(slice, 30);
    if (album)
        tags.album ??= album;
    const yearText = readId3V1String(slice, 4);
    const year = Number.parseInt(yearText, 10);
    if (Number.isInteger(year) && year > 0) {
        tags.date ??= new Date(year, 0, 1);
    }
    const commentBytes = (0,_reader_js__WEBPACK_IMPORTED_MODULE_2__/* .readBytes */ .io)(slice, 30);
    let comment;
    // Check for the ID3v1.1 track number format:
    // The 29th byte (index 28) is a null terminator, and the 30th byte is the track number.
    if (commentBytes[28] === 0 && commentBytes[29] !== 0) {
        const trackNum = commentBytes[29];
        if (trackNum > 0) {
            tags.trackNumber ??= trackNum;
        }
        slice.skip(-30);
        comment = readId3V1String(slice, 28);
        slice.skip(2);
    }
    else {
        slice.skip(-30);
        comment = readId3V1String(slice, 30);
    }
    if (comment)
        tags.comment ??= comment;
    const genreIndex = (0,_reader_js__WEBPACK_IMPORTED_MODULE_2__/* .readU8 */ .eo)(slice);
    if (genreIndex < ID3_V1_GENRES.length) {
        tags.genre ??= ID3_V1_GENRES[genreIndex];
    }
};
const readId3V1String = (slice, length) => {
    const bytes = (0,_reader_js__WEBPACK_IMPORTED_MODULE_2__/* .readBytes */ .io)(slice, length);
    const endIndex = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .coalesceIndex */ .Sf)(bytes.indexOf(0), bytes.length);
    const relevantBytes = bytes.subarray(0, endIndex);
    // Decode as ISO-8859-1
    let str = '';
    for (let i = 0; i < relevantBytes.length; i++) {
        str += String.fromCharCode(relevantBytes[i]);
    }
    return str.trimEnd(); // String also may be padded with spaces
};
const readId3V2Header = (slice) => {
    const startPos = slice.filePos;
    const tag = (0,_reader_js__WEBPACK_IMPORTED_MODULE_2__/* .readAscii */ .IT)(slice, 3);
    const majorVersion = (0,_reader_js__WEBPACK_IMPORTED_MODULE_2__/* .readU8 */ .eo)(slice);
    const revision = (0,_reader_js__WEBPACK_IMPORTED_MODULE_2__/* .readU8 */ .eo)(slice);
    const flags = (0,_reader_js__WEBPACK_IMPORTED_MODULE_2__/* .readU8 */ .eo)(slice);
    const sizeRaw = (0,_reader_js__WEBPACK_IMPORTED_MODULE_2__/* .readU32Be */ .cN)(slice);
    if (tag !== 'ID3' || majorVersion === 0xff || revision === 0xff || (sizeRaw & 0x80808080) !== 0) {
        slice.filePos = startPos;
        return null;
    }
    const size = (0,_shared_mp3_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .decodeSynchsafe */ .Fm)(sizeRaw);
    return { majorVersion, revision, flags, size };
};
const parseId3V2Tag = (slice, header, tags) => {
    // https://id3.org/id3v2.3.0
    if (![2, 3, 4].includes(header.majorVersion)) {
        console.warn(`Unsupported ID3v2 major version: ${header.majorVersion}`);
        return;
    }
    const bytes = (0,_reader_js__WEBPACK_IMPORTED_MODULE_2__/* .readBytes */ .io)(slice, header.size);
    const reader = new Id3V2Reader(header, bytes);
    if (header.flags & Id3V2HeaderFlags.Footer) {
        reader.removeFooter();
    }
    if ((header.flags & Id3V2HeaderFlags.Unsynchronisation) && header.majorVersion === 3) {
        reader.ununsynchronizeAll();
    }
    if (header.flags & Id3V2HeaderFlags.ExtendedHeader) {
        const extendedHeaderSize = reader.readU32();
        if (header.majorVersion === 3) {
            reader.pos += extendedHeaderSize; // The extended header size excludes itself
        }
        else {
            reader.pos += extendedHeaderSize - 4; // The extended header size includes itself
        }
    }
    while (reader.pos <= reader.bytes.length - reader.frameHeaderSize()) {
        const frame = reader.readId3V2Frame();
        if (!frame) {
            break;
        }
        const frameStartPos = reader.pos;
        const frameEndPos = reader.pos + frame.size;
        let frameEncrypted = false;
        let frameCompressed = false;
        let frameUnsynchronized = false;
        if (header.majorVersion === 3) {
            frameEncrypted = !!(frame.flags & (1 << 6));
            frameCompressed = !!(frame.flags & (1 << 7));
        }
        else if (header.majorVersion === 4) {
            frameEncrypted = !!(frame.flags & (1 << 2));
            frameCompressed = !!(frame.flags & (1 << 3));
            frameUnsynchronized = !!(frame.flags & (1 << 1))
                || !!(header.flags & Id3V2HeaderFlags.Unsynchronisation);
        }
        if (frameEncrypted) {
            console.warn(`Skipping encrypted ID3v2 frame ${frame.id}`);
            reader.pos = frameEndPos;
            continue;
        }
        if (frameCompressed) {
            console.warn(`Skipping compressed ID3v2 frame ${frame.id}`); // Maybe someday? Idk
            reader.pos = frameEndPos;
            continue;
        }
        if (frameUnsynchronized) {
            reader.ununsynchronizeRegion(reader.pos, frameEndPos);
        }
        tags.raw ??= {};
        if (frame.id === 'TXXX') {
            const txxx = tags.raw['TXXX'] ??= {};
            const encoding = reader.readId3V2TextEncoding();
            const description = reader.readId3V2Text(encoding, frameEndPos);
            const value = reader.readId3V2Text(encoding, frameEndPos);
            txxx[description] ??= value;
        }
        else if (frame.id[0] === 'T') {
            // It's a text frame, let's decode as text
            tags.raw[frame.id] ??= reader.readId3V2EncodingAndText(frameEndPos);
        }
        else {
            // For the others, let's just get the bytes
            tags.raw[frame.id] ??= reader.readBytes(frame.size);
        }
        reader.pos = frameStartPos;
        switch (frame.id) {
            case 'TIT2':
            case 'TT2':
                {
                    tags.title ??= reader.readId3V2EncodingAndText(frameEndPos);
                }
                ;
                break;
            case 'TIT3':
            case 'TT3':
                {
                    tags.description ??= reader.readId3V2EncodingAndText(frameEndPos);
                }
                ;
                break;
            case 'TPE1':
            case 'TP1':
                {
                    tags.artist ??= reader.readId3V2EncodingAndText(frameEndPos);
                }
                ;
                break;
            case 'TALB':
            case 'TAL':
                {
                    tags.album ??= reader.readId3V2EncodingAndText(frameEndPos);
                }
                ;
                break;
            case 'TPE2':
            case 'TP2':
                {
                    tags.albumArtist ??= reader.readId3V2EncodingAndText(frameEndPos);
                }
                ;
                break;
            case 'TRCK':
            case 'TRK':
                {
                    const trackText = reader.readId3V2EncodingAndText(frameEndPos);
                    const parts = trackText.split('/');
                    const trackNum = Number.parseInt(parts[0], 10);
                    const tracksTotal = parts[1] && Number.parseInt(parts[1], 10);
                    if (Number.isInteger(trackNum) && trackNum > 0) {
                        tags.trackNumber ??= trackNum;
                    }
                    if (tracksTotal && Number.isInteger(tracksTotal) && tracksTotal > 0) {
                        tags.tracksTotal ??= tracksTotal;
                    }
                }
                ;
                break;
            case 'TPOS':
            case 'TPA':
                {
                    const discText = reader.readId3V2EncodingAndText(frameEndPos);
                    const parts = discText.split('/');
                    const discNum = Number.parseInt(parts[0], 10);
                    const discsTotal = parts[1] && Number.parseInt(parts[1], 10);
                    if (Number.isInteger(discNum) && discNum > 0) {
                        tags.discNumber ??= discNum;
                    }
                    if (discsTotal && Number.isInteger(discsTotal) && discsTotal > 0) {
                        tags.discsTotal ??= discsTotal;
                    }
                }
                ;
                break;
            case 'TCON':
            case 'TCO':
                {
                    const genreText = reader.readId3V2EncodingAndText(frameEndPos);
                    let match = /^\((\d+)\)/.exec(genreText);
                    if (match) {
                        const genreNumber = Number.parseInt(match[1]);
                        if (ID3_V1_GENRES[genreNumber] !== undefined) {
                            tags.genre ??= ID3_V1_GENRES[genreNumber];
                            break;
                        }
                    }
                    match = /^\d+$/.exec(genreText);
                    if (match) {
                        const genreNumber = Number.parseInt(match[0]);
                        if (ID3_V1_GENRES[genreNumber] !== undefined) {
                            tags.genre ??= ID3_V1_GENRES[genreNumber];
                            break;
                        }
                    }
                    tags.genre ??= genreText;
                }
                ;
                break;
            case 'TDRC':
            case 'TDAT':
                {
                    const dateText = reader.readId3V2EncodingAndText(frameEndPos);
                    const date = new Date(dateText);
                    if (!Number.isNaN(date.getTime())) {
                        tags.date ??= date;
                    }
                }
                ;
                break;
            case 'TYER':
            case 'TYE':
                {
                    const yearText = reader.readId3V2EncodingAndText(frameEndPos);
                    const year = Number.parseInt(yearText, 10);
                    if (Number.isInteger(year)) {
                        tags.date ??= new Date(year, 0, 1);
                    }
                }
                ;
                break;
            case 'USLT':
            case 'ULT':
                {
                    const encoding = reader.readU8();
                    reader.pos += 3; // Skip language
                    reader.readId3V2Text(encoding, frameEndPos); // Short content description
                    tags.lyrics ??= reader.readId3V2Text(encoding, frameEndPos);
                }
                ;
                break;
            case 'COMM':
            case 'COM':
                {
                    const encoding = reader.readU8();
                    reader.pos += 3; // Skip language
                    reader.readId3V2Text(encoding, frameEndPos); // Short content description
                    tags.comment ??= reader.readId3V2Text(encoding, frameEndPos);
                }
                ;
                break;
            case 'APIC':
            case 'PIC':
                {
                    const encoding = reader.readId3V2TextEncoding();
                    let mimeType;
                    if (header.majorVersion === 2) {
                        const imageFormat = reader.readAscii(3);
                        mimeType = imageFormat === 'PNG'
                            ? 'image/png'
                            : imageFormat === 'JPG'
                                ? 'image/jpeg'
                                : 'image/*';
                    }
                    else {
                        mimeType = reader.readId3V2Text(encoding, frameEndPos);
                    }
                    const pictureType = reader.readU8();
                    const description = reader.readId3V2Text(encoding, frameEndPos).trimEnd(); // Trim ending spaces
                    const imageDataSize = frameEndPos - reader.pos;
                    if (imageDataSize >= 0) {
                        const imageData = reader.readBytes(imageDataSize);
                        if (!tags.images)
                            tags.images = [];
                        tags.images.push({
                            data: imageData,
                            mimeType,
                            kind: pictureType === 3
                                ? 'coverFront'
                                : pictureType === 4
                                    ? 'coverBack'
                                    : 'unknown',
                            description,
                        });
                    }
                }
                ;
                break;
            default:
                {
                    reader.pos += frame.size;
                }
                ;
                break;
        }
        reader.pos = frameEndPos;
    }
};
// https://id3.org/id3v2.3.0
class Id3V2Reader {
    constructor(header, bytes) {
        this.header = header;
        this.bytes = bytes;
        this.pos = 0;
        this.view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    }
    frameHeaderSize() {
        return this.header.majorVersion === 2 ? 6 : 10;
    }
    ununsynchronizeAll() {
        const newBytes = [];
        for (let i = 0; i < this.bytes.length; i++) {
            const value1 = this.bytes[i];
            newBytes.push(value1);
            if (value1 === 0xff && i !== this.bytes.length - 1) {
                const value2 = this.bytes[i];
                if (value2 === 0x00) {
                    i++;
                }
            }
        }
        this.bytes = new Uint8Array(newBytes);
        this.view = new DataView(this.bytes.buffer);
    }
    ununsynchronizeRegion(start, end) {
        const newBytes = [];
        for (let i = start; i < end; i++) {
            const value1 = this.bytes[i];
            newBytes.push(value1);
            if (value1 === 0xff && i !== end - 1) {
                const value2 = this.bytes[i + 1];
                if (value2 === 0x00) {
                    i++;
                }
            }
        }
        const before = this.bytes.subarray(0, start);
        const after = this.bytes.subarray(end);
        this.bytes = new Uint8Array(before.length + newBytes.length + after.length);
        this.bytes.set(before, 0);
        this.bytes.set(newBytes, before.length);
        this.bytes.set(after, before.length + newBytes.length);
        this.view = new DataView(this.bytes.buffer);
    }
    removeFooter() {
        this.bytes = this.bytes.subarray(0, this.bytes.length - ID3_V2_HEADER_SIZE);
        this.view = new DataView(this.bytes.buffer);
    }
    readBytes(length) {
        const slice = this.bytes.subarray(this.pos, this.pos + length);
        this.pos += length;
        return slice;
    }
    readU8() {
        const value = this.view.getUint8(this.pos);
        this.pos += 1;
        return value;
    }
    readU16() {
        const value = this.view.getUint16(this.pos, false);
        this.pos += 2;
        return value;
    }
    readU24() {
        const high = this.view.getUint16(this.pos, false);
        const low = this.view.getUint8(this.pos + 1);
        this.pos += 3;
        return high * 0x100 + low;
    }
    readU32() {
        const value = this.view.getUint32(this.pos, false);
        this.pos += 4;
        return value;
    }
    readAscii(length) {
        let str = '';
        for (let i = 0; i < length; i++) {
            str += String.fromCharCode(this.view.getUint8(this.pos + i));
        }
        this.pos += length;
        return str;
    }
    readId3V2Frame() {
        if (this.header.majorVersion === 2) {
            const id = this.readAscii(3);
            if (id === '\x00\x00\x00') {
                return null;
            }
            const size = this.readU24();
            return { id, size, flags: 0 };
        }
        else {
            const id = this.readAscii(4);
            if (id === '\x00\x00\x00\x00') {
                // We've landed in the padding section
                return null;
            }
            const sizeRaw = this.readU32();
            let size = this.header.majorVersion === 4
                ? (0,_shared_mp3_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .decodeSynchsafe */ .Fm)(sizeRaw)
                : sizeRaw;
            const flags = this.readU16();
            const headerEndPos = this.pos;
            // Some files may have incorrectly synchsafed/unsynchsafed sizes. To validate which interpretation is valid,
            // we validate a size by skipping ahead and seeing if we land at a valid frame header (or at the end of the
            // tag.
            const isSizeValid = (size) => {
                const nextPos = this.pos + size;
                if (nextPos > this.bytes.length) {
                    return false;
                }
                if (nextPos <= this.bytes.length - this.frameHeaderSize()) {
                    this.pos += size;
                    const nextId = this.readAscii(4);
                    if (nextId !== '\x00\x00\x00\x00' && !/[0-9A-Z]{4}/.test(nextId)) {
                        return false;
                    }
                }
                return true;
            };
            if (!isSizeValid(size)) {
                // Flip the synchsafing, and try if this one makes more sense
                const otherSize = this.header.majorVersion === 4
                    ? sizeRaw
                    : (0,_shared_mp3_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .decodeSynchsafe */ .Fm)(sizeRaw);
                if (isSizeValid(otherSize)) {
                    size = otherSize;
                }
            }
            this.pos = headerEndPos;
            return { id, size, flags };
        }
    }
    readId3V2TextEncoding() {
        const number = this.readU8();
        if (number > 3) {
            throw new Error(`Unsupported text encoding: ${number}`);
        }
        return number;
    }
    readId3V2Text(encoding, until) {
        const startPos = this.pos;
        const data = this.readBytes(until - this.pos);
        switch (encoding) {
            case Id3V2TextEncoding.ISO_8859_1: {
                let str = '';
                for (let i = 0; i < data.length; i++) {
                    const value = data[i];
                    if (value === 0) {
                        this.pos = startPos + i + 1;
                        break;
                    }
                    str += String.fromCharCode(value);
                }
                return str;
            }
            case Id3V2TextEncoding.UTF_16_WITH_BOM: {
                if (data[0] === 0xff && data[1] === 0xfe) {
                    const decoder = new TextDecoder('utf-16le');
                    const endIndex = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .coalesceIndex */ .Sf)(data.findIndex((x, i) => x === 0 && data[i + 1] === 0 && i % 2 === 0), data.length);
                    this.pos = startPos + Math.min(endIndex + 2, data.length);
                    return decoder.decode(data.subarray(2, endIndex));
                }
                else if (data[0] === 0xfe && data[1] === 0xff) {
                    const decoder = new TextDecoder('utf-16be');
                    const endIndex = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .coalesceIndex */ .Sf)(data.findIndex((x, i) => x === 0 && data[i + 1] === 0 && i % 2 === 0), data.length);
                    this.pos = startPos + Math.min(endIndex + 2, data.length);
                    return decoder.decode(data.subarray(2, endIndex));
                }
                else {
                    // Treat it like UTF-8, some files do this
                    const endIndex = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .coalesceIndex */ .Sf)(data.findIndex(x => x === 0), data.length);
                    this.pos = startPos + Math.min(endIndex + 1, data.length);
                    return _misc_js__WEBPACK_IMPORTED_MODULE_1__/* .textDecoder */ .su.decode(data.subarray(0, endIndex));
                }
            }
            case Id3V2TextEncoding.UTF_16_BE_NO_BOM: {
                const decoder = new TextDecoder('utf-16be');
                const endIndex = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .coalesceIndex */ .Sf)(data.findIndex((x, i) => x === 0 && data[i + 1] === 0 && i % 2 === 0), data.length);
                this.pos = startPos + Math.min(endIndex + 2, data.length);
                return decoder.decode(data.subarray(0, endIndex));
            }
            case Id3V2TextEncoding.UTF_8: {
                const endIndex = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .coalesceIndex */ .Sf)(data.findIndex(x => x === 0), data.length);
                this.pos = startPos + Math.min(endIndex + 1, data.length);
                return _misc_js__WEBPACK_IMPORTED_MODULE_1__/* .textDecoder */ .su.decode(data.subarray(0, endIndex));
            }
        }
    }
    readId3V2EncodingAndText(until) {
        if (this.pos >= until) {
            return '';
        }
        const encoding = this.readId3V2TextEncoding();
        return this.readId3V2Text(encoding, until);
    }
}
class Id3V2Writer {
    constructor(writer) {
        this.helper = new Uint8Array(8);
        this.helperView = toDataView(this.helper);
        this.writer = writer;
    }
    writeId3V2Tag(metadata) {
        const tagStartPos = this.writer.getPos();
        // Write ID3v2.4 header
        this.writeAscii('ID3');
        this.writeU8(0x04); // Version 2.4
        this.writeU8(0x00); // Revision 0
        this.writeU8(0x00); // Flags
        this.writeSynchsafeU32(0); // Size placeholder
        const framesStartPos = this.writer.getPos();
        const writtenTags = new Set();
        // Write all metadata frames
        for (const { key, value } of keyValueIterator(metadata)) {
            switch (key) {
                case 'title':
                    {
                        this.writeId3V2TextFrame('TIT2', value);
                        writtenTags.add('TIT2');
                    }
                    ;
                    break;
                case 'description':
                    {
                        this.writeId3V2TextFrame('TIT3', value);
                        writtenTags.add('TIT3');
                    }
                    ;
                    break;
                case 'artist':
                    {
                        this.writeId3V2TextFrame('TPE1', value);
                        writtenTags.add('TPE1');
                    }
                    ;
                    break;
                case 'album':
                    {
                        this.writeId3V2TextFrame('TALB', value);
                        writtenTags.add('TALB');
                    }
                    ;
                    break;
                case 'albumArtist':
                    {
                        this.writeId3V2TextFrame('TPE2', value);
                        writtenTags.add('TPE2');
                    }
                    ;
                    break;
                case 'trackNumber':
                    {
                        const string = metadata.tracksTotal !== undefined
                            ? `${value}/${metadata.tracksTotal}`
                            : value.toString();
                        this.writeId3V2TextFrame('TRCK', string);
                        writtenTags.add('TRCK');
                    }
                    ;
                    break;
                case 'discNumber':
                    {
                        const string = metadata.discsTotal !== undefined
                            ? `${value}/${metadata.discsTotal}`
                            : value.toString();
                        this.writeId3V2TextFrame('TPOS', string);
                        writtenTags.add('TPOS');
                    }
                    ;
                    break;
                case 'genre':
                    {
                        this.writeId3V2TextFrame('TCON', value);
                        writtenTags.add('TCON');
                    }
                    ;
                    break;
                case 'date':
                    {
                        this.writeId3V2TextFrame('TDRC', value.toISOString().slice(0, 10));
                        writtenTags.add('TDRC');
                    }
                    ;
                    break;
                case 'lyrics':
                    {
                        this.writeId3V2LyricsFrame(value);
                        writtenTags.add('USLT');
                    }
                    ;
                    break;
                case 'comment':
                    {
                        this.writeId3V2CommentFrame(value);
                        writtenTags.add('COMM');
                    }
                    ;
                    break;
                case 'images':
                    {
                        const pictureTypeMap = { coverFront: 0x03, coverBack: 0x04, unknown: 0x00 };
                        for (const image of value) {
                            const pictureType = pictureTypeMap[image.kind] ?? 0x00;
                            const description = image.description ?? '';
                            this.writeId3V2ApicFrame(image.mimeType, pictureType, description, image.data);
                        }
                    }
                    ;
                    break;
                case 'tracksTotal':
                case 'discsTotal':
                    {
                        // Handled with trackNumber and discNumber respectively
                    }
                    ;
                    break;
                case 'raw':
                    {
                        // Handled later
                    }
                    ;
                    break;
                default: {
                    assertNever(key);
                }
            }
        }
        if (metadata.raw) {
            for (const key in metadata.raw) {
                const value = metadata.raw[key];
                if (value == null || key.length !== 4 || writtenTags.has(key)) {
                    continue;
                }
                let bytes;
                if (typeof value === 'string') {
                    const useIso88591 = isIso88591Compatible(value);
                    if (useIso88591) {
                        bytes = new Uint8Array(value.length + 2);
                        bytes[0] = Id3V2TextEncoding.ISO_8859_1;
                        for (let i = 0; i < value.length; i++) {
                            bytes[i + 1] = value.charCodeAt(i);
                        }
                        // Last byte is the null terminator
                    }
                    else {
                        const encoded = textEncoder.encode(value);
                        bytes = new Uint8Array(encoded.byteLength + 2);
                        bytes[0] = Id3V2TextEncoding.UTF_8;
                        bytes.set(encoded, 1);
                        // Last byte is the null terminator
                    }
                }
                else if (value instanceof Uint8Array) {
                    bytes = value;
                }
                else if (key === 'TXXX' && isRecordStringString(value)) {
                    for (const description in value) {
                        const frameValue = value[description];
                        const useIso88591 = isIso88591Compatible(description) && isIso88591Compatible(frameValue);
                        const encodedDescription = useIso88591 ? null : textEncoder.encode(description);
                        const encodedValue = useIso88591 ? null : textEncoder.encode(frameValue);
                        const descriptionDataLength = useIso88591 ? description.length : encodedDescription.byteLength;
                        const valueDataLength = useIso88591 ? frameValue.length : encodedValue.byteLength;
                        const frameSize = 1 + descriptionDataLength + 1 + valueDataLength + 1;
                        this.writeAscii('TXXX');
                        this.writeSynchsafeU32(frameSize);
                        this.writeU16(0x0000);
                        this.writeU8(useIso88591 ? Id3V2TextEncoding.ISO_8859_1 : Id3V2TextEncoding.UTF_8);
                        if (useIso88591) {
                            this.writeIsoString(description);
                            this.writeIsoString(frameValue);
                        }
                        else {
                            this.writer.write(encodedDescription);
                            this.writeU8(0x00);
                            this.writer.write(encodedValue);
                            this.writeU8(0x00);
                        }
                    }
                    continue;
                }
                else {
                    continue;
                }
                this.writeAscii(key);
                this.writeSynchsafeU32(bytes.byteLength);
                this.writeU16(0x0000);
                this.writer.write(bytes);
            }
        }
        const framesEndPos = this.writer.getPos();
        const framesSize = framesEndPos - framesStartPos;
        // Update the size field in the header (synchsafe)
        this.writer.seek(tagStartPos + 6); // Skip 'ID3' + version + revision + flags
        this.writeSynchsafeU32(framesSize);
        this.writer.seek(framesEndPos);
        return framesSize + 10; // +10 for the header size
    }
    writeU8(value) {
        this.helper[0] = value;
        this.writer.write(this.helper.subarray(0, 1));
    }
    writeU16(value) {
        this.helperView.setUint16(0, value, false);
        this.writer.write(this.helper.subarray(0, 2));
    }
    writeU32(value) {
        this.helperView.setUint32(0, value, false);
        this.writer.write(this.helper.subarray(0, 4));
    }
    writeAscii(text) {
        for (let i = 0; i < text.length; i++) {
            this.helper[i] = text.charCodeAt(i);
        }
        this.writer.write(this.helper.subarray(0, text.length));
    }
    writeSynchsafeU32(value) {
        this.writeU32(encodeSynchsafe(value));
    }
    writeIsoString(text) {
        const bytes = new Uint8Array(text.length + 1);
        for (let i = 0; i < text.length; i++) {
            bytes[i] = text.charCodeAt(i);
        }
        // Last byte is the null terminator
        this.writer.write(bytes);
    }
    writeUtf8String(text) {
        const utf8Data = textEncoder.encode(text);
        this.writer.write(utf8Data);
        this.writeU8(0x00);
    }
    writeId3V2TextFrame(frameId, text) {
        const useIso88591 = isIso88591Compatible(text);
        const textDataLength = useIso88591 ? text.length : textEncoder.encode(text).byteLength;
        const frameSize = 1 + textDataLength + 1;
        this.writeAscii(frameId);
        this.writeSynchsafeU32(frameSize);
        this.writeU16(0x0000);
        this.writeU8(useIso88591 ? Id3V2TextEncoding.ISO_8859_1 : Id3V2TextEncoding.UTF_8);
        if (useIso88591) {
            this.writeIsoString(text);
        }
        else {
            this.writeUtf8String(text);
        }
    }
    writeId3V2LyricsFrame(lyrics) {
        const useIso88591 = isIso88591Compatible(lyrics);
        const shortDescription = '';
        const frameSize = 1 + 3 + shortDescription.length + 1 + lyrics.length + 1;
        this.writeAscii('USLT');
        this.writeSynchsafeU32(frameSize);
        this.writeU16(0x0000);
        this.writeU8(useIso88591 ? Id3V2TextEncoding.ISO_8859_1 : Id3V2TextEncoding.UTF_8);
        this.writeAscii('und');
        if (useIso88591) {
            this.writeIsoString(shortDescription);
            this.writeIsoString(lyrics);
        }
        else {
            this.writeUtf8String(shortDescription);
            this.writeUtf8String(lyrics);
        }
    }
    writeId3V2CommentFrame(comment) {
        const useIso88591 = isIso88591Compatible(comment);
        const textDataLength = useIso88591 ? comment.length : textEncoder.encode(comment).byteLength;
        const shortDescription = '';
        const frameSize = 1 + 3 + shortDescription.length + 1 + textDataLength + 1;
        this.writeAscii('COMM');
        this.writeSynchsafeU32(frameSize);
        this.writeU16(0x0000);
        this.writeU8(useIso88591 ? Id3V2TextEncoding.ISO_8859_1 : Id3V2TextEncoding.UTF_8);
        this.writeU8(0x75); // 'u'
        this.writeU8(0x6E); // 'n'
        this.writeU8(0x64); // 'd'
        if (useIso88591) {
            this.writeIsoString(shortDescription);
            this.writeIsoString(comment);
        }
        else {
            this.writeUtf8String(shortDescription);
            this.writeUtf8String(comment);
        }
    }
    writeId3V2ApicFrame(mimeType, pictureType, description, imageData) {
        const useIso88591 = isIso88591Compatible(mimeType) && isIso88591Compatible(description);
        const descriptionDataLength = useIso88591
            ? description.length
            : textEncoder.encode(description).byteLength;
        const frameSize = 1 + mimeType.length + 1 + 1 + descriptionDataLength + 1 + imageData.byteLength;
        this.writeAscii('APIC');
        this.writeSynchsafeU32(frameSize);
        this.writeU16(0x0000);
        this.writeU8(useIso88591 ? Id3V2TextEncoding.ISO_8859_1 : Id3V2TextEncoding.UTF_8);
        if (useIso88591) {
            this.writeIsoString(mimeType);
        }
        else {
            this.writeUtf8String(mimeType);
        }
        this.writeU8(pictureType);
        if (useIso88591) {
            this.writeIsoString(description);
        }
        else {
            this.writeUtf8String(description);
        }
        this.writer.write(imageData);
    }
}


/***/ },

/***/ 6411
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   Cl: () => (/* binding */ EBMLId),
/* harmony export */   De: () => (/* binding */ MIN_HEADER_SIZE),
/* harmony export */   IQ: () => (/* binding */ searchForNextElementId),
/* harmony export */   IX: () => (/* binding */ readAsciiString),
/* harmony export */   K9: () => (/* binding */ LEVEL_0_AND_1_EBML_IDS),
/* harmony export */   Kb: () => (/* binding */ readElementSize),
/* harmony export */   Ry: () => (/* binding */ readUnsignedBigInt),
/* harmony export */   SR: () => (/* binding */ readElementId),
/* harmony export */   VE: () => (/* binding */ LEVEL_1_EBML_IDS),
/* harmony export */   YO: () => (/* binding */ readVarIntSize),
/* harmony export */   dl: () => (/* binding */ readUnsignedInt),
/* harmony export */   jR: () => (/* binding */ readUnicodeString),
/* harmony export */   nE: () => (/* binding */ resync),
/* harmony export */   oo: () => (/* binding */ CODEC_STRING_MAP),
/* harmony export */   p: () => (/* binding */ assertDefinedSize),
/* harmony export */   pT: () => (/* binding */ readVarInt),
/* harmony export */   r1: () => (/* binding */ MAX_HEADER_SIZE),
/* harmony export */   ur: () => (/* binding */ readElementHeader),
/* harmony export */   zH: () => (/* binding */ readFloat)
/* harmony export */ });
/* unused harmony exports EBMLFloat32, EBMLFloat64, EBMLSignedInt, EBMLUnicodeString, LEVEL_0_EBML_IDS, measureUnsignedInt, measureUnsignedBigInt, measureSignedInt, measureVarInt, EBMLWriter, MAX_VAR_INT_SIZE, readSignedInt */
/* unused harmony import specifier */ var textEncoder;
/* unused harmony import specifier */ var assertNever;
/* harmony import */ var _misc_js__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(3912);
/* harmony import */ var _reader_js__WEBPACK_IMPORTED_MODULE_1__ = __webpack_require__(7735);
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


/** Wrapper around a number to be able to differentiate it in the writer. */
class EBMLFloat32 {
    constructor(value) {
        this.value = value;
    }
}
/** Wrapper around a number to be able to differentiate it in the writer. */
class EBMLFloat64 {
    constructor(value) {
        this.value = value;
    }
}
/** Wrapper around a number to be able to differentiate it in the writer. */
class EBMLSignedInt {
    constructor(value) {
        this.value = value;
    }
}
class EBMLUnicodeString {
    constructor(value) {
        this.value = value;
    }
}
/** Defines some of the EBML IDs used by Matroska files. */
var EBMLId;
(function (EBMLId) {
    EBMLId[EBMLId["EBML"] = 440786851] = "EBML";
    EBMLId[EBMLId["EBMLVersion"] = 17030] = "EBMLVersion";
    EBMLId[EBMLId["EBMLReadVersion"] = 17143] = "EBMLReadVersion";
    EBMLId[EBMLId["EBMLMaxIDLength"] = 17138] = "EBMLMaxIDLength";
    EBMLId[EBMLId["EBMLMaxSizeLength"] = 17139] = "EBMLMaxSizeLength";
    EBMLId[EBMLId["DocType"] = 17026] = "DocType";
    EBMLId[EBMLId["DocTypeVersion"] = 17031] = "DocTypeVersion";
    EBMLId[EBMLId["DocTypeReadVersion"] = 17029] = "DocTypeReadVersion";
    EBMLId[EBMLId["Void"] = 236] = "Void";
    EBMLId[EBMLId["Segment"] = 408125543] = "Segment";
    EBMLId[EBMLId["SeekHead"] = 290298740] = "SeekHead";
    EBMLId[EBMLId["Seek"] = 19899] = "Seek";
    EBMLId[EBMLId["SeekID"] = 21419] = "SeekID";
    EBMLId[EBMLId["SeekPosition"] = 21420] = "SeekPosition";
    EBMLId[EBMLId["Duration"] = 17545] = "Duration";
    EBMLId[EBMLId["Info"] = 357149030] = "Info";
    EBMLId[EBMLId["TimestampScale"] = 2807729] = "TimestampScale";
    EBMLId[EBMLId["MuxingApp"] = 19840] = "MuxingApp";
    EBMLId[EBMLId["WritingApp"] = 22337] = "WritingApp";
    EBMLId[EBMLId["Tracks"] = 374648427] = "Tracks";
    EBMLId[EBMLId["TrackEntry"] = 174] = "TrackEntry";
    EBMLId[EBMLId["TrackNumber"] = 215] = "TrackNumber";
    EBMLId[EBMLId["TrackUID"] = 29637] = "TrackUID";
    EBMLId[EBMLId["TrackType"] = 131] = "TrackType";
    EBMLId[EBMLId["FlagEnabled"] = 185] = "FlagEnabled";
    EBMLId[EBMLId["FlagDefault"] = 136] = "FlagDefault";
    EBMLId[EBMLId["FlagForced"] = 21930] = "FlagForced";
    EBMLId[EBMLId["FlagOriginal"] = 21934] = "FlagOriginal";
    EBMLId[EBMLId["FlagHearingImpaired"] = 21931] = "FlagHearingImpaired";
    EBMLId[EBMLId["FlagVisualImpaired"] = 21932] = "FlagVisualImpaired";
    EBMLId[EBMLId["FlagCommentary"] = 21935] = "FlagCommentary";
    EBMLId[EBMLId["FlagLacing"] = 156] = "FlagLacing";
    EBMLId[EBMLId["Name"] = 21358] = "Name";
    EBMLId[EBMLId["Language"] = 2274716] = "Language";
    EBMLId[EBMLId["LanguageBCP47"] = 2274717] = "LanguageBCP47";
    EBMLId[EBMLId["CodecID"] = 134] = "CodecID";
    EBMLId[EBMLId["CodecPrivate"] = 25506] = "CodecPrivate";
    EBMLId[EBMLId["CodecDelay"] = 22186] = "CodecDelay";
    EBMLId[EBMLId["SeekPreRoll"] = 22203] = "SeekPreRoll";
    EBMLId[EBMLId["DefaultDuration"] = 2352003] = "DefaultDuration";
    EBMLId[EBMLId["Video"] = 224] = "Video";
    EBMLId[EBMLId["PixelWidth"] = 176] = "PixelWidth";
    EBMLId[EBMLId["PixelHeight"] = 186] = "PixelHeight";
    EBMLId[EBMLId["DisplayWidth"] = 21680] = "DisplayWidth";
    EBMLId[EBMLId["DisplayHeight"] = 21690] = "DisplayHeight";
    EBMLId[EBMLId["DisplayUnit"] = 21682] = "DisplayUnit";
    EBMLId[EBMLId["AlphaMode"] = 21440] = "AlphaMode";
    EBMLId[EBMLId["Audio"] = 225] = "Audio";
    EBMLId[EBMLId["SamplingFrequency"] = 181] = "SamplingFrequency";
    EBMLId[EBMLId["Channels"] = 159] = "Channels";
    EBMLId[EBMLId["BitDepth"] = 25188] = "BitDepth";
    EBMLId[EBMLId["SimpleBlock"] = 163] = "SimpleBlock";
    EBMLId[EBMLId["BlockGroup"] = 160] = "BlockGroup";
    EBMLId[EBMLId["Block"] = 161] = "Block";
    EBMLId[EBMLId["BlockAdditions"] = 30113] = "BlockAdditions";
    EBMLId[EBMLId["BlockMore"] = 166] = "BlockMore";
    EBMLId[EBMLId["BlockAdditional"] = 165] = "BlockAdditional";
    EBMLId[EBMLId["BlockAddID"] = 238] = "BlockAddID";
    EBMLId[EBMLId["BlockDuration"] = 155] = "BlockDuration";
    EBMLId[EBMLId["ReferenceBlock"] = 251] = "ReferenceBlock";
    EBMLId[EBMLId["Cluster"] = 524531317] = "Cluster";
    EBMLId[EBMLId["Timestamp"] = 231] = "Timestamp";
    EBMLId[EBMLId["Cues"] = 475249515] = "Cues";
    EBMLId[EBMLId["CuePoint"] = 187] = "CuePoint";
    EBMLId[EBMLId["CueTime"] = 179] = "CueTime";
    EBMLId[EBMLId["CueTrackPositions"] = 183] = "CueTrackPositions";
    EBMLId[EBMLId["CueTrack"] = 247] = "CueTrack";
    EBMLId[EBMLId["CueClusterPosition"] = 241] = "CueClusterPosition";
    EBMLId[EBMLId["Colour"] = 21936] = "Colour";
    EBMLId[EBMLId["MatrixCoefficients"] = 21937] = "MatrixCoefficients";
    EBMLId[EBMLId["TransferCharacteristics"] = 21946] = "TransferCharacteristics";
    EBMLId[EBMLId["Primaries"] = 21947] = "Primaries";
    EBMLId[EBMLId["Range"] = 21945] = "Range";
    EBMLId[EBMLId["Projection"] = 30320] = "Projection";
    EBMLId[EBMLId["ProjectionType"] = 30321] = "ProjectionType";
    EBMLId[EBMLId["ProjectionPoseRoll"] = 30325] = "ProjectionPoseRoll";
    EBMLId[EBMLId["Attachments"] = 423732329] = "Attachments";
    EBMLId[EBMLId["AttachedFile"] = 24999] = "AttachedFile";
    EBMLId[EBMLId["FileDescription"] = 18046] = "FileDescription";
    EBMLId[EBMLId["FileName"] = 18030] = "FileName";
    EBMLId[EBMLId["FileMediaType"] = 18016] = "FileMediaType";
    EBMLId[EBMLId["FileData"] = 18012] = "FileData";
    EBMLId[EBMLId["FileUID"] = 18094] = "FileUID";
    EBMLId[EBMLId["Chapters"] = 272869232] = "Chapters";
    EBMLId[EBMLId["Tags"] = 307544935] = "Tags";
    EBMLId[EBMLId["Tag"] = 29555] = "Tag";
    EBMLId[EBMLId["Targets"] = 25536] = "Targets";
    EBMLId[EBMLId["TargetTypeValue"] = 26826] = "TargetTypeValue";
    EBMLId[EBMLId["TargetType"] = 25546] = "TargetType";
    EBMLId[EBMLId["TagTrackUID"] = 25541] = "TagTrackUID";
    EBMLId[EBMLId["TagEditionUID"] = 25545] = "TagEditionUID";
    EBMLId[EBMLId["TagChapterUID"] = 25540] = "TagChapterUID";
    EBMLId[EBMLId["TagAttachmentUID"] = 25542] = "TagAttachmentUID";
    EBMLId[EBMLId["SimpleTag"] = 26568] = "SimpleTag";
    EBMLId[EBMLId["TagName"] = 17827] = "TagName";
    EBMLId[EBMLId["TagLanguage"] = 17530] = "TagLanguage";
    EBMLId[EBMLId["TagString"] = 17543] = "TagString";
    EBMLId[EBMLId["TagBinary"] = 17541] = "TagBinary";
    EBMLId[EBMLId["ContentEncodings"] = 28032] = "ContentEncodings";
    EBMLId[EBMLId["ContentEncoding"] = 25152] = "ContentEncoding";
    EBMLId[EBMLId["ContentEncodingOrder"] = 20529] = "ContentEncodingOrder";
    EBMLId[EBMLId["ContentEncodingScope"] = 20530] = "ContentEncodingScope";
    EBMLId[EBMLId["ContentCompression"] = 20532] = "ContentCompression";
    EBMLId[EBMLId["ContentCompAlgo"] = 16980] = "ContentCompAlgo";
    EBMLId[EBMLId["ContentCompSettings"] = 16981] = "ContentCompSettings";
    EBMLId[EBMLId["ContentEncryption"] = 20533] = "ContentEncryption";
})(EBMLId || (EBMLId = {}));
const LEVEL_0_EBML_IDS = [
    EBMLId.EBML,
    EBMLId.Segment,
];
// All the stuff that can appear in a segment, basically
const LEVEL_1_EBML_IDS = [
    EBMLId.SeekHead,
    EBMLId.Info,
    EBMLId.Cluster,
    EBMLId.Tracks,
    EBMLId.Cues,
    EBMLId.Attachments,
    EBMLId.Chapters,
    EBMLId.Tags,
];
const LEVEL_0_AND_1_EBML_IDS = [
    ...LEVEL_0_EBML_IDS,
    ...LEVEL_1_EBML_IDS,
];
const measureUnsignedInt = (value) => {
    if (value < (1 << 8)) {
        return 1;
    }
    else if (value < (1 << 16)) {
        return 2;
    }
    else if (value < (1 << 24)) {
        return 3;
    }
    else if (value < 2 ** 32) {
        return 4;
    }
    else if (value < 2 ** 40) {
        return 5;
    }
    else {
        return 6;
    }
};
const measureUnsignedBigInt = (value) => {
    if (value < (1n << 8n)) {
        return 1;
    }
    else if (value < (1n << 16n)) {
        return 2;
    }
    else if (value < (1n << 24n)) {
        return 3;
    }
    else if (value < (1n << 32n)) {
        return 4;
    }
    else if (value < (1n << 40n)) {
        return 5;
    }
    else if (value < (1n << 48n)) {
        return 6;
    }
    else if (value < (1n << 56n)) {
        return 7;
    }
    else {
        return 8;
    }
};
const measureSignedInt = (value) => {
    if (value >= -(1 << 6) && value < (1 << 6)) {
        return 1;
    }
    else if (value >= -(1 << 13) && value < (1 << 13)) {
        return 2;
    }
    else if (value >= -(1 << 20) && value < (1 << 20)) {
        return 3;
    }
    else if (value >= -(1 << 27) && value < (1 << 27)) {
        return 4;
    }
    else if (value >= -(2 ** 34) && value < 2 ** 34) {
        return 5;
    }
    else {
        return 6;
    }
};
const measureVarInt = (value) => {
    if (value < (1 << 7) - 1) {
        /** Top bit is set, leaving 7 bits to hold the integer, but we can't store
         * 127 because "all bits set to one" is a reserved value. Same thing for the
         * other cases below:
         */
        return 1;
    }
    else if (value < (1 << 14) - 1) {
        return 2;
    }
    else if (value < (1 << 21) - 1) {
        return 3;
    }
    else if (value < (1 << 28) - 1) {
        return 4;
    }
    else if (value < 2 ** 35 - 1) {
        return 5;
    }
    else if (value < 2 ** 42 - 1) {
        return 6;
    }
    else {
        throw new Error('EBML varint size not supported ' + value);
    }
};
class EBMLWriter {
    constructor(writer) {
        this.writer = writer;
        this.helper = new Uint8Array(8);
        this.helperView = new DataView(this.helper.buffer);
        /**
         * Stores the position from the start of the file to where EBML elements have been written. This is used to
         * rewrite/edit elements that were already added before, and to measure sizes of things.
         */
        this.offsets = new WeakMap();
        /** Same as offsets, but stores position where the element's data starts (after ID and size fields). */
        this.dataOffsets = new WeakMap();
    }
    writeByte(value) {
        this.helperView.setUint8(0, value);
        this.writer.write(this.helper.subarray(0, 1));
    }
    writeFloat32(value) {
        this.helperView.setFloat32(0, value, false);
        this.writer.write(this.helper.subarray(0, 4));
    }
    writeFloat64(value) {
        this.helperView.setFloat64(0, value, false);
        this.writer.write(this.helper);
    }
    writeUnsignedInt(value, width = measureUnsignedInt(value)) {
        let pos = 0;
        // Each case falls through:
        switch (width) {
            case 6:
                // Need to use division to access >32 bits of floating point var
                this.helperView.setUint8(pos++, (value / 2 ** 40) | 0);
            // eslint-disable-next-line no-fallthrough
            case 5:
                this.helperView.setUint8(pos++, (value / 2 ** 32) | 0);
            // eslint-disable-next-line no-fallthrough
            case 4:
                this.helperView.setUint8(pos++, value >> 24);
            // eslint-disable-next-line no-fallthrough
            case 3:
                this.helperView.setUint8(pos++, value >> 16);
            // eslint-disable-next-line no-fallthrough
            case 2:
                this.helperView.setUint8(pos++, value >> 8);
            // eslint-disable-next-line no-fallthrough
            case 1:
                this.helperView.setUint8(pos++, value);
                break;
            default:
                throw new Error('Bad unsigned int size ' + width);
        }
        this.writer.write(this.helper.subarray(0, pos));
    }
    writeUnsignedBigInt(value, width = measureUnsignedBigInt(value)) {
        let pos = 0;
        for (let i = width - 1; i >= 0; i--) {
            this.helperView.setUint8(pos++, Number((value >> BigInt(i * 8)) & 0xffn));
        }
        this.writer.write(this.helper.subarray(0, pos));
    }
    writeSignedInt(value, width = measureSignedInt(value)) {
        if (value < 0) {
            // Two's complement stuff
            value += 2 ** (width * 8);
        }
        this.writeUnsignedInt(value, width);
    }
    writeVarInt(value, width = measureVarInt(value)) {
        let pos = 0;
        switch (width) {
            case 1:
                this.helperView.setUint8(pos++, (1 << 7) | value);
                break;
            case 2:
                this.helperView.setUint8(pos++, (1 << 6) | (value >> 8));
                this.helperView.setUint8(pos++, value);
                break;
            case 3:
                this.helperView.setUint8(pos++, (1 << 5) | (value >> 16));
                this.helperView.setUint8(pos++, value >> 8);
                this.helperView.setUint8(pos++, value);
                break;
            case 4:
                this.helperView.setUint8(pos++, (1 << 4) | (value >> 24));
                this.helperView.setUint8(pos++, value >> 16);
                this.helperView.setUint8(pos++, value >> 8);
                this.helperView.setUint8(pos++, value);
                break;
            case 5:
                /**
                 * JavaScript converts its doubles to 32-bit integers for bitwise
                 * operations, so we need to do a division by 2^32 instead of a
                 * right-shift of 32 to retain those top 3 bits
                 */
                this.helperView.setUint8(pos++, (1 << 3) | ((value / 2 ** 32) & 0x7));
                this.helperView.setUint8(pos++, value >> 24);
                this.helperView.setUint8(pos++, value >> 16);
                this.helperView.setUint8(pos++, value >> 8);
                this.helperView.setUint8(pos++, value);
                break;
            case 6:
                this.helperView.setUint8(pos++, (1 << 2) | ((value / 2 ** 40) & 0x3));
                this.helperView.setUint8(pos++, (value / 2 ** 32) | 0);
                this.helperView.setUint8(pos++, value >> 24);
                this.helperView.setUint8(pos++, value >> 16);
                this.helperView.setUint8(pos++, value >> 8);
                this.helperView.setUint8(pos++, value);
                break;
            default:
                throw new Error('Bad EBML varint size ' + width);
        }
        this.writer.write(this.helper.subarray(0, pos));
    }
    writeAsciiString(str) {
        this.writer.write(new Uint8Array(str.split('').map(x => x.charCodeAt(0))));
    }
    writeEBML(data) {
        if (data === null)
            return;
        if (data instanceof Uint8Array) {
            this.writer.write(data);
        }
        else if (Array.isArray(data)) {
            for (const elem of data) {
                this.writeEBML(elem);
            }
        }
        else {
            this.offsets.set(data, this.writer.getPos());
            this.writeUnsignedInt(data.id); // ID field
            if (Array.isArray(data.data)) {
                const sizePos = this.writer.getPos();
                const sizeSize = data.size === -1 ? 1 : (data.size ?? 4);
                if (data.size === -1) {
                    // Write the reserved all-one-bits marker for unknown/unbounded size.
                    this.writeByte(0xff);
                }
                else {
                    this.writer.seek(this.writer.getPos() + sizeSize);
                }
                const startPos = this.writer.getPos();
                this.dataOffsets.set(data, startPos);
                this.writeEBML(data.data);
                if (data.size !== -1) {
                    const size = this.writer.getPos() - startPos;
                    const endPos = this.writer.getPos();
                    this.writer.seek(sizePos);
                    this.writeVarInt(size, sizeSize);
                    this.writer.seek(endPos);
                }
            }
            else if (typeof data.data === 'number') {
                const size = data.size ?? measureUnsignedInt(data.data);
                this.writeVarInt(size);
                this.writeUnsignedInt(data.data, size);
            }
            else if (typeof data.data === 'bigint') {
                const size = data.size ?? measureUnsignedBigInt(data.data);
                this.writeVarInt(size);
                this.writeUnsignedBigInt(data.data, size);
            }
            else if (typeof data.data === 'string') {
                this.writeVarInt(data.data.length);
                this.writeAsciiString(data.data);
            }
            else if (data.data instanceof Uint8Array) {
                this.writeVarInt(data.data.byteLength, data.size);
                this.writer.write(data.data);
            }
            else if (data.data instanceof EBMLFloat32) {
                this.writeVarInt(4);
                this.writeFloat32(data.data.value);
            }
            else if (data.data instanceof EBMLFloat64) {
                this.writeVarInt(8);
                this.writeFloat64(data.data.value);
            }
            else if (data.data instanceof EBMLSignedInt) {
                const size = data.size ?? measureSignedInt(data.data.value);
                this.writeVarInt(size);
                this.writeSignedInt(data.data.value, size);
            }
            else if (data.data instanceof EBMLUnicodeString) {
                const bytes = textEncoder.encode(data.data.value);
                this.writeVarInt(bytes.length);
                this.writer.write(bytes);
            }
            else {
                assertNever(data.data);
            }
        }
    }
}
const MAX_VAR_INT_SIZE = 8;
const MIN_HEADER_SIZE = 2; // 1-byte ID and 1-byte size
const MAX_HEADER_SIZE = 2 * MAX_VAR_INT_SIZE; // 8-byte ID and 8-byte size
const readVarIntSize = (slice) => {
    if (slice.remainingLength < 1) {
        return null;
    }
    const firstByte = (0,_reader_js__WEBPACK_IMPORTED_MODULE_1__/* .readU8 */ .eo)(slice);
    slice.skip(-1);
    if (firstByte === 0) {
        return null; // Invalid VINT
    }
    let width = 1;
    let mask = 0x80;
    while ((firstByte & mask) === 0) {
        width++;
        mask >>= 1;
    }
    // Check if we have enough bytes to read the full varint
    if (slice.remainingLength < width) {
        return null;
    }
    return width;
};
const readVarInt = (slice) => {
    if (slice.remainingLength < 1) {
        return null;
    }
    // Read the first byte to determine the width of the variable-length integer
    const firstByte = (0,_reader_js__WEBPACK_IMPORTED_MODULE_1__/* .readU8 */ .eo)(slice);
    if (firstByte === 0) {
        return null; // Invalid VINT
    }
    // Find the position of VINT_MARKER, which determines the width
    let width = 1;
    let mask = 1 << 7;
    while ((firstByte & mask) === 0) {
        width++;
        mask >>= 1;
    }
    if (slice.remainingLength < width - 1) {
        // Not enough bytes
        return null;
    }
    // First byte's value needs the marker bit cleared
    let value = firstByte & (mask - 1);
    // Read remaining bytes
    for (let i = 1; i < width; i++) {
        value *= 1 << 8;
        value += (0,_reader_js__WEBPACK_IMPORTED_MODULE_1__/* .readU8 */ .eo)(slice);
    }
    return value;
};
const readUnsignedInt = (slice, width) => {
    if (width < 1 || width > 8) {
        throw new Error('Bad unsigned int size ' + width);
    }
    let value = 0;
    // Read bytes from most significant to least significant
    for (let i = 0; i < width; i++) {
        value *= 1 << 8;
        value += (0,_reader_js__WEBPACK_IMPORTED_MODULE_1__/* .readU8 */ .eo)(slice);
    }
    return value;
};
const readUnsignedBigInt = (slice, width) => {
    if (width < 1) {
        throw new Error('Bad unsigned int size ' + width);
    }
    let value = 0n;
    for (let i = 0; i < width; i++) {
        value <<= 8n;
        value += BigInt((0,_reader_js__WEBPACK_IMPORTED_MODULE_1__/* .readU8 */ .eo)(slice));
    }
    return value;
};
const readSignedInt = (slice, width) => {
    let value = readUnsignedInt(slice, width);
    // If the highest bit is set, convert from two's complement
    if (value & (1 << (width * 8 - 1))) {
        value -= 2 ** (width * 8);
    }
    return value;
};
const readElementId = (slice) => {
    const size = readVarIntSize(slice);
    if (size === null) {
        return null;
    }
    if (slice.remainingLength < size) {
        return null; // It don't fit
    }
    const id = readUnsignedInt(slice, size);
    return id;
};
/** Returns `undefined` to indicate the EBML undefined size. Returns `null` if the size couldn't be read. */
const readElementSize = (slice) => {
    // Need at least 1 byte to read the size
    if (slice.remainingLength < 1) {
        return null;
    }
    const firstByte = (0,_reader_js__WEBPACK_IMPORTED_MODULE_1__/* .readU8 */ .eo)(slice);
    if (firstByte === 0xff) {
        return undefined;
    }
    slice.skip(-1);
    const size = readVarInt(slice);
    if (size === null) {
        return null;
    }
    // In some (livestreamed) files, this is the value of the size field. While this technically is just a very
    // large number, it is intended to behave like the reserved size 0xFF, meaning the size is undefined. We
    // catch the number here. Note that it cannot be perfectly represented as a double, but the comparison works
    // nonetheless.
    // eslint-disable-next-line no-loss-of-precision
    if (size === 0x00ffffffffffffff) {
        return undefined;
    }
    return size;
};
const readElementHeader = (slice) => {
    (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(slice.remainingLength >= MIN_HEADER_SIZE);
    const id = readElementId(slice);
    if (id === null) {
        return null;
    }
    const size = readElementSize(slice);
    if (size === null) {
        return null;
    }
    return { id, size };
};
const readAsciiString = (slice, length) => {
    const bytes = (0,_reader_js__WEBPACK_IMPORTED_MODULE_1__/* .readBytes */ .io)(slice, length);
    // Actual string length might be shorter due to null terminators
    let strLength = 0;
    while (strLength < length && bytes[strLength] !== 0) {
        strLength += 1;
    }
    return String.fromCharCode(...bytes.subarray(0, strLength));
};
const readUnicodeString = (slice, length) => {
    const bytes = (0,_reader_js__WEBPACK_IMPORTED_MODULE_1__/* .readBytes */ .io)(slice, length);
    // Actual string length might be shorter due to null terminators
    let strLength = 0;
    while (strLength < length && bytes[strLength] !== 0) {
        strLength += 1;
    }
    return _misc_js__WEBPACK_IMPORTED_MODULE_0__/* .textDecoder */ .su.decode(bytes.subarray(0, strLength));
};
const readFloat = (slice, width) => {
    if (width === 0) {
        return 0;
    }
    if (width !== 4 && width !== 8) {
        throw new Error('Bad float size ' + width);
    }
    return width === 4 ? (0,_reader_js__WEBPACK_IMPORTED_MODULE_1__/* .readF32Be */ .Jk)(slice) : (0,_reader_js__WEBPACK_IMPORTED_MODULE_1__/* .readF64Be */ ._3)(slice);
};
/** Returns the byte offset in the file of the next element with a matching ID. */
const searchForNextElementId = async (reader, startPos, ids, until) => {
    const idsSet = new Set(ids);
    let currentPos = startPos;
    while (until === null || currentPos < until) {
        let slice = reader.requestSliceRange(currentPos, MIN_HEADER_SIZE, MAX_HEADER_SIZE);
        if (slice instanceof Promise)
            slice = await slice;
        if (!slice)
            break;
        const elementHeader = readElementHeader(slice);
        if (!elementHeader) {
            break;
        }
        if (idsSet.has(elementHeader.id)) {
            return { pos: currentPos, found: true };
        }
        assertDefinedSize(elementHeader.size);
        currentPos = slice.filePos + elementHeader.size;
    }
    return { pos: (until !== null && until > currentPos) ? until : currentPos, found: false };
};
/** Searches for the next occurrence of an element ID using a naive byte-wise search. */
const resync = async (reader, startPos, ids, until) => {
    const CHUNK_SIZE = 2 ** 16; // So we don't need to grab thousands of slices
    const idsSet = new Set(ids);
    let currentPos = startPos;
    while (currentPos < until) {
        let slice = reader.requestSliceRange(currentPos, 0, Math.min(CHUNK_SIZE, until - currentPos));
        if (slice instanceof Promise)
            slice = await slice;
        if (!slice)
            break;
        if (slice.length < MAX_VAR_INT_SIZE)
            break;
        for (let i = 0; i < slice.length - MAX_VAR_INT_SIZE; i++) {
            slice.filePos = currentPos;
            const elementId = readElementId(slice);
            if (elementId !== null && idsSet.has(elementId)) {
                return currentPos;
            }
            currentPos++;
        }
    }
    return null;
};
const CODEC_STRING_MAP = {
    'avc': 'V_MPEG4/ISO/AVC',
    'hevc': 'V_MPEGH/ISO/HEVC',
    'vp8': 'V_VP8',
    'vp9': 'V_VP9',
    'av1': 'V_AV1',
    'aac': 'A_AAC',
    'mp3': 'A_MPEG/L3',
    'opus': 'A_OPUS',
    'vorbis': 'A_VORBIS',
    'flac': 'A_FLAC',
    'ac3': 'A_AC3',
    'eac3': 'A_EAC3',
    'pcm-u8': 'A_PCM/INT/LIT',
    'pcm-s16': 'A_PCM/INT/LIT',
    'pcm-s16be': 'A_PCM/INT/BIG',
    'pcm-s24': 'A_PCM/INT/LIT',
    'pcm-s24be': 'A_PCM/INT/BIG',
    'pcm-s32': 'A_PCM/INT/LIT',
    'pcm-s32be': 'A_PCM/INT/BIG',
    'pcm-f32': 'A_PCM/FLOAT/IEEE',
    'pcm-f64': 'A_PCM/FLOAT/IEEE',
    'webvtt': 'S_TEXT/WEBVTT',
};
function assertDefinedSize(size) {
    if (size === undefined) {
        throw new Error('Undefined element size is used in a place where it is not supported.');
    }
}
;


/***/ },

/***/ 388
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   kQ: () => (/* binding */ EncodedPacketSink),
/* harmony export */   qw: () => (/* binding */ AudioSampleSink)
/* harmony export */ });
/* unused harmony exports BaseMediaSampleSink, VideoSampleSink, CanvasSink, AudioBufferSink */
/* unused harmony import specifier */ var InputVideoTrack;
/* unused harmony import specifier */ var InputAudioTrack;
/* unused harmony import specifier */ var isFirefox;
/* unused harmony import specifier */ var assert;
/* unused harmony import specifier */ var mapAsyncGenerator;
/* unused harmony import specifier */ var validateCropRectangle;
/* unused harmony import specifier */ var clampCropRectangle;
/* harmony import */ var _codec_js__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(1188);
/* harmony import */ var _codec_data_js__WEBPACK_IMPORTED_MODULE_1__ = __webpack_require__(6297);
/* harmony import */ var _custom_coder_js__WEBPACK_IMPORTED_MODULE_2__ = __webpack_require__(8647);
/* harmony import */ var _input_js__WEBPACK_IMPORTED_MODULE_3__ = __webpack_require__(2030);
/* harmony import */ var _input_track_js__WEBPACK_IMPORTED_MODULE_4__ = __webpack_require__(6244);
/* harmony import */ var _misc_js__WEBPACK_IMPORTED_MODULE_5__ = __webpack_require__(3912);
/* harmony import */ var _packet_js__WEBPACK_IMPORTED_MODULE_6__ = __webpack_require__(3936);
/* harmony import */ var _pcm_js__WEBPACK_IMPORTED_MODULE_7__ = __webpack_require__(358);
/* harmony import */ var _sample_js__WEBPACK_IMPORTED_MODULE_8__ = __webpack_require__(4166);
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */









const validatePacketRetrievalOptions = (options) => {
    if (!options || typeof options !== 'object') {
        throw new TypeError('options must be an object.');
    }
    if (options.metadataOnly !== undefined && typeof options.metadataOnly !== 'boolean') {
        throw new TypeError('options.metadataOnly, when defined, must be a boolean.');
    }
    if (options.verifyKeyPackets !== undefined && typeof options.verifyKeyPackets !== 'boolean') {
        throw new TypeError('options.verifyKeyPackets, when defined, must be a boolean.');
    }
    if (options.verifyKeyPackets && options.metadataOnly) {
        throw new TypeError('options.verifyKeyPackets and options.metadataOnly cannot be enabled together.');
    }
    if (options.skipLiveWait !== undefined && typeof options.skipLiveWait !== 'boolean') {
        throw new TypeError('options.skipLiveWait, when defined, must be a boolean.');
    }
};
const validateTimestamp = (timestamp) => {
    if (!(0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .isNumber */ .Et)(timestamp)) {
        throw new TypeError('timestamp must be a number.'); // It can be non-finite, that's fine
    }
};
const maybeFixPacketType = (track, promise, options) => {
    if (options.verifyKeyPackets) {
        return promise.then(async (packet) => {
            if (!packet || packet.type === 'delta') {
                return packet;
            }
            const determinedType = await track.determinePacketType(packet);
            if (determinedType) {
                // @ts-expect-error Technically readonly
                packet.type = determinedType;
            }
            return packet;
        });
    }
    else {
        return promise;
    }
};
/**
 * Sink for retrieving encoded packets from an input track.
 * @group Media sinks
 * @public
 */
class EncodedPacketSink {
    /** Creates a new {@link EncodedPacketSink} for the given {@link InputTrack}. */
    constructor(track) {
        if (!(track instanceof _input_track_js__WEBPACK_IMPORTED_MODULE_4__/* .InputTrack */ .Kh)) {
            throw new TypeError('track must be an InputTrack.');
        }
        this._track = track;
    }
    /**
     * Retrieves the track's first packet (in decode order), or null if it has no packets. The first packet is very
     * likely to be a key packet, but it doesn't have to be.
     */
    async getFirstPacket(options = {}) {
        validatePacketRetrievalOptions(options);
        if (this._track.input._disposed) {
            throw new _input_js__WEBPACK_IMPORTED_MODULE_3__/* .InputDisposedError */ .QO();
        }
        return maybeFixPacketType(this._track, this._track._backing.getFirstPacket(options), options);
    }
    /** Retrieves the track's first key packet (in decode order), or null if it has no key packets. */
    async getFirstKeyPacket(options = {}) {
        validatePacketRetrievalOptions(options);
        const firstPacket = await this.getFirstPacket(options);
        if (!firstPacket) {
            return null;
        }
        if (firstPacket.type === 'key') {
            // Great
            return firstPacket;
        }
        return this.getNextKeyPacket(firstPacket, options);
    }
    /**
     * Retrieves the packet corresponding to the given timestamp, in seconds. More specifically, returns the last packet
     * (in presentation order) with a start timestamp less than or equal to the given timestamp. This method can be
     * used to retrieve a track's last packet using `getPacket(Infinity)`. The method returns null if the timestamp
     * is before the first packet in the track.
     *
     * @param timestamp - The timestamp used for retrieval, in seconds.
     */
    async getPacket(timestamp, options = {}) {
        validateTimestamp(timestamp);
        validatePacketRetrievalOptions(options);
        if (this._track.input._disposed) {
            throw new _input_js__WEBPACK_IMPORTED_MODULE_3__/* .InputDisposedError */ .QO();
        }
        return maybeFixPacketType(this._track, this._track._backing.getPacket(timestamp, options), options);
    }
    /**
     * Retrieves the packet following the given packet (in decode order), or null if the given packet is the
     * last packet.
     */
    async getNextPacket(packet, options = {}) {
        if (!(packet instanceof _packet_js__WEBPACK_IMPORTED_MODULE_6__/* .EncodedPacket */ .Z)) {
            throw new TypeError('packet must be an EncodedPacket.');
        }
        validatePacketRetrievalOptions(options);
        if (this._track.input._disposed) {
            throw new _input_js__WEBPACK_IMPORTED_MODULE_3__/* .InputDisposedError */ .QO();
        }
        return maybeFixPacketType(this._track, this._track._backing.getNextPacket(packet, options), options);
    }
    /**
     * Retrieves the key packet corresponding to the given timestamp, in seconds. More specifically, returns the last
     * key packet (in presentation order) with a start timestamp less than or equal to the given timestamp. A key packet
     * is a packet that doesn't require previous packets to be decoded. This method can be used to retrieve a track's
     * last key packet using `getKeyPacket(Infinity)`. The method returns null if the timestamp is before the first
     * key packet in the track.
     *
     * To ensure that the returned packet is guaranteed to be a real key frame, enable `options.verifyKeyPackets`.
     *
     * @param timestamp - The timestamp used for retrieval, in seconds.
     */
    async getKeyPacket(timestamp, options = {}) {
        validateTimestamp(timestamp);
        validatePacketRetrievalOptions(options);
        if (this._track.input._disposed) {
            throw new _input_js__WEBPACK_IMPORTED_MODULE_3__/* .InputDisposedError */ .QO();
        }
        if (!options.verifyKeyPackets) {
            return this._track._backing.getKeyPacket(timestamp, options);
        }
        const packet = await this._track._backing.getKeyPacket(timestamp, options);
        if (!packet) {
            return packet;
        }
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .assert */ .vA)(packet.type === 'key');
        const determinedType = await this._track.determinePacketType(packet);
        if (determinedType === 'delta') {
            // Try returning the previous key packet (in hopes that it's actually a key packet)
            return this.getKeyPacket(packet.timestamp - 1 / await this._track.getTimeResolution(), options);
        }
        return packet;
    }
    /**
     * Retrieves the key packet following the given packet (in decode order), or null if the given packet is the last
     * key packet.
     *
     * To ensure that the returned packet is guaranteed to be a real key frame, enable `options.verifyKeyPackets`.
     */
    async getNextKeyPacket(packet, options = {}) {
        if (!(packet instanceof _packet_js__WEBPACK_IMPORTED_MODULE_6__/* .EncodedPacket */ .Z)) {
            throw new TypeError('packet must be an EncodedPacket.');
        }
        validatePacketRetrievalOptions(options);
        if (this._track.input._disposed) {
            throw new _input_js__WEBPACK_IMPORTED_MODULE_3__/* .InputDisposedError */ .QO();
        }
        if (!options.verifyKeyPackets) {
            return this._track._backing.getNextKeyPacket(packet, options);
        }
        const nextPacket = await this._track._backing.getNextKeyPacket(packet, options);
        if (!nextPacket) {
            return nextPacket;
        }
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .assert */ .vA)(nextPacket.type === 'key');
        const determinedType = await this._track.determinePacketType(nextPacket);
        if (determinedType === 'delta') {
            // Try returning the next key packet (in hopes that it's actually a key packet)
            return this.getNextKeyPacket(nextPacket, options);
        }
        return nextPacket;
    }
    /**
     * Creates an async iterator that yields the packets in this track in decode order. To enable fast iteration, this
     * method will intelligently preload packets based on the speed of the consumer.
     *
     * @param startPacket - (optional) The packet from which iteration should begin. This packet will also be yielded.
     * @param endPacket - (optional) The packet at which iteration should end. This packet will _not_ be yielded.
     */
    packets(startPacket, endPacket, options = {}) {
        if (startPacket !== undefined && !(startPacket instanceof _packet_js__WEBPACK_IMPORTED_MODULE_6__/* .EncodedPacket */ .Z)) {
            throw new TypeError('startPacket must be an EncodedPacket.');
        }
        if (startPacket !== undefined && startPacket.isMetadataOnly && !options?.metadataOnly) {
            throw new TypeError('startPacket can only be metadata-only if options.metadataOnly is enabled.');
        }
        if (endPacket !== undefined && !(endPacket instanceof _packet_js__WEBPACK_IMPORTED_MODULE_6__/* .EncodedPacket */ .Z)) {
            throw new TypeError('endPacket must be an EncodedPacket.');
        }
        validatePacketRetrievalOptions(options);
        if (this._track.input._disposed) {
            throw new _input_js__WEBPACK_IMPORTED_MODULE_3__/* .InputDisposedError */ .QO();
        }
        const packetQueue = [];
        let { promise: queueNotEmpty, resolve: onQueueNotEmpty } = (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .promiseWithResolvers */ .nJ)();
        let { promise: queueDequeue, resolve: onQueueDequeue } = (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .promiseWithResolvers */ .nJ)();
        let ended = false;
        let terminated = false;
        // This stores errors that are "out of band" in the sense that they didn't occur in the normal flow of this
        // method but instead in a different context. This error should not go unnoticed and must be bubbled up to
        // the consumer.
        let outOfBandError = null;
        const timestamps = [];
        // The queue should always be big enough to hold 1 second worth of packets
        const maxQueueSize = () => Math.max(2, timestamps.length);
        // The following is the "pump" process that keeps pumping packets into the queue
        (async () => {
            let packet = startPacket ?? await this.getFirstPacket(options);
            while (packet && !terminated && !this._track.input._disposed) {
                if (endPacket && packet.sequenceNumber >= endPacket?.sequenceNumber) {
                    break;
                }
                if (packetQueue.length > maxQueueSize()) {
                    ({ promise: queueDequeue, resolve: onQueueDequeue } = (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .promiseWithResolvers */ .nJ)());
                    await queueDequeue;
                    continue;
                }
                packetQueue.push(packet);
                onQueueNotEmpty();
                ({ promise: queueNotEmpty, resolve: onQueueNotEmpty } = (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .promiseWithResolvers */ .nJ)());
                packet = await this.getNextPacket(packet, options);
            }
            ended = true;
            onQueueNotEmpty();
        })().catch((error) => {
            if (!outOfBandError) {
                outOfBandError = error;
                onQueueNotEmpty();
            }
        });
        const track = this._track;
        return {
            async next() {
                while (true) {
                    if (track.input._disposed) {
                        throw new _input_js__WEBPACK_IMPORTED_MODULE_3__/* .InputDisposedError */ .QO();
                    }
                    else if (terminated) {
                        return { value: undefined, done: true };
                    }
                    else if (outOfBandError) {
                        throw outOfBandError;
                    }
                    else if (packetQueue.length > 0) {
                        const value = packetQueue.shift();
                        const now = performance.now();
                        timestamps.push(now);
                        while (timestamps.length > 0 && now - timestamps[0] >= 1000) {
                            timestamps.shift();
                        }
                        onQueueDequeue();
                        return { value, done: false };
                    }
                    else if (ended) {
                        return { value: undefined, done: true };
                    }
                    else {
                        await queueNotEmpty;
                    }
                }
            },
            async return() {
                terminated = true;
                onQueueDequeue();
                onQueueNotEmpty();
                return { value: undefined, done: true };
            },
            async throw(error) {
                throw error;
            },
            [Symbol.asyncIterator]() {
                return this;
            },
        };
    }
}
class DecoderWrapper {
    constructor(onSample, onError) {
        this.onSample = onSample;
        this.onError = onError;
    }
}
/**
 * Base class for decoded media sample sinks.
 * @group Media sinks
 * @public
 */
class BaseMediaSampleSink {
    /** @internal */
    mediaSamplesInRange(startTimestamp = 0, endTimestamp = Infinity, options) {
        validateTimestamp(startTimestamp);
        validateTimestamp(endTimestamp);
        const sampleQueue = [];
        let firstSampleQueued = false;
        let lastSample = null;
        let { promise: queueNotEmpty, resolve: onQueueNotEmpty } = (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .promiseWithResolvers */ .nJ)();
        let { promise: queueDequeue, resolve: onQueueDequeue } = (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .promiseWithResolvers */ .nJ)();
        let decoderIsFlushed = false;
        let ended = false;
        let terminated = false;
        // This stores errors that are "out of band" in the sense that they didn't occur in the normal flow of this
        // method but instead in a different context. This error should not go unnoticed and must be bubbled up to
        // the consumer.
        let outOfBandError = null;
        const packetRetrievalOptions = {
            ...options,
            verifyKeyPackets: true,
            metadataOnly: false,
        };
        // The following is the "pump" process that keeps pumping packets into the decoder
        (async () => {
            const decoder = await this._createDecoder((sample) => {
                onQueueDequeue();
                if (sample.timestamp >= endTimestamp) {
                    ended = true;
                }
                if (ended) {
                    sample.close();
                    return;
                }
                if (lastSample) {
                    if (sample.timestamp > startTimestamp) {
                        // We don't know ahead of time what the first first is. This is because the first first is the
                        // last first whose timestamp is less than or equal to the start timestamp. Therefore we need to
                        // wait for the first first after the start timestamp, and then we'll know that the previous
                        // first was the first first.
                        sampleQueue.push(lastSample);
                        firstSampleQueued = true;
                    }
                    else {
                        lastSample.close();
                    }
                }
                if (sample.timestamp >= startTimestamp) {
                    sampleQueue.push(sample);
                    firstSampleQueued = true;
                }
                lastSample = firstSampleQueued ? null : sample;
                if (sampleQueue.length > 0) {
                    onQueueNotEmpty();
                    ({ promise: queueNotEmpty, resolve: onQueueNotEmpty } = (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .promiseWithResolvers */ .nJ)());
                }
            }, (error) => {
                if (!outOfBandError) {
                    outOfBandError = error;
                    onQueueNotEmpty();
                }
            });
            const packetSink = this._createPacketSink();
            const keyPacket = await packetSink.getKeyPacket(startTimestamp, packetRetrievalOptions)
                ?? await packetSink.getFirstKeyPacket(packetRetrievalOptions);
            let currentPacket = keyPacket;
            // B-frames make it exceedingly difficult to properly define an upper bound for packet iteration if an end
            // timestamp is set, so we just don't do it. The case that makes it especially tricky is when the frames
            // following a key frame have a lower timestamp than the keyframe; something that quite frequently happens
            // in HEVC streams. The price to pay for not upper-bounding the packet iterator is a slight increase in
            // decoder work at the end of the range, but the added correctness and reliability makes this tradeoff worth
            // it.
            const endPacket = undefined;
            const packets = packetSink.packets(keyPacket ?? undefined, endPacket, packetRetrievalOptions);
            await packets.next(); // Skip the start packet as we already have it
            while (currentPacket && !ended && !this._track.input._disposed) {
                const maxQueueSize = computeMaxQueueSize(sampleQueue.length);
                if (sampleQueue.length + decoder.getDecodeQueueSize() > maxQueueSize) {
                    ({ promise: queueDequeue, resolve: onQueueDequeue } = (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .promiseWithResolvers */ .nJ)());
                    await queueDequeue;
                    continue;
                }
                decoder.decode(currentPacket);
                const packetResult = await packets.next();
                if (packetResult.done) {
                    break;
                }
                currentPacket = packetResult.value;
            }
            await packets.return();
            if (!terminated && !this._track.input._disposed) {
                await decoder.flush();
            }
            decoder.close();
            if (!firstSampleQueued && lastSample) {
                sampleQueue.push(lastSample);
            }
            decoderIsFlushed = true;
            onQueueNotEmpty(); // To unstuck the generator
        })().catch((error) => {
            if (!outOfBandError) {
                outOfBandError = error;
                onQueueNotEmpty();
            }
        });
        const track = this._track;
        const closeSamples = () => {
            lastSample?.close();
            for (const sample of sampleQueue) {
                sample.close();
            }
        };
        return {
            async next() {
                while (true) {
                    if (track.input._disposed) {
                        closeSamples();
                        throw new _input_js__WEBPACK_IMPORTED_MODULE_3__/* .InputDisposedError */ .QO();
                    }
                    else if (terminated) {
                        return { value: undefined, done: true };
                    }
                    else if (outOfBandError) {
                        closeSamples();
                        throw outOfBandError;
                    }
                    else if (sampleQueue.length > 0) {
                        const value = sampleQueue.shift();
                        onQueueDequeue();
                        return { value, done: false };
                    }
                    else if (!decoderIsFlushed) {
                        await queueNotEmpty;
                    }
                    else {
                        return { value: undefined, done: true };
                    }
                }
            },
            async return() {
                terminated = true;
                ended = true;
                onQueueDequeue();
                onQueueNotEmpty();
                closeSamples();
                return { value: undefined, done: true };
            },
            async throw(error) {
                throw error;
            },
            [Symbol.asyncIterator]() {
                return this;
            },
        };
    }
    /** @internal */
    mediaSamplesAtTimestamps(timestamps, options) {
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .validateAnyIterable */ .D5)(timestamps);
        const timestampIterator = (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .toAsyncIterator */ .i1)(timestamps);
        const timestampsOfInterest = [];
        const sampleQueue = [];
        let { promise: queueNotEmpty, resolve: onQueueNotEmpty } = (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .promiseWithResolvers */ .nJ)();
        let { promise: queueDequeue, resolve: onQueueDequeue } = (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .promiseWithResolvers */ .nJ)();
        let decoderIsFlushed = false;
        let terminated = false;
        // This stores errors that are "out of band" in the sense that they didn't occur in the normal flow of this
        // method but instead in a different context. This error should not go unnoticed and must be bubbled up to
        // the consumer.
        let outOfBandError = null;
        const pushToQueue = (sample) => {
            sampleQueue.push(sample);
            onQueueNotEmpty();
            ({ promise: queueNotEmpty, resolve: onQueueNotEmpty } = (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .promiseWithResolvers */ .nJ)());
        };
        const retrievalOptions = {
            ...options,
            verifyKeyPackets: true,
            metadataOnly: false,
        };
        // The following is the "pump" process that keeps pumping packets into the decoder
        (async () => {
            const decoder = await this._createDecoder((sample) => {
                onQueueDequeue();
                if (terminated) {
                    sample.close();
                    return;
                }
                let sampleUses = 0;
                while (timestampsOfInterest.length > 0
                    && sample.timestamp - timestampsOfInterest[0] > -1e-10 // Give it a little epsilon
                ) {
                    sampleUses++;
                    timestampsOfInterest.shift();
                }
                if (sampleUses > 0) {
                    for (let i = 0; i < sampleUses; i++) {
                        // Clone the sample if we need to emit it multiple times
                        pushToQueue((i < sampleUses - 1 ? sample.clone() : sample));
                    }
                }
                else {
                    sample.close();
                }
            }, (error) => {
                if (!outOfBandError) {
                    outOfBandError = error;
                    onQueueNotEmpty();
                }
            });
            const packetSink = this._createPacketSink();
            let lastPacket = null;
            let lastKeyPacket = null;
            // The end sequence number (inclusive) in the next batch of packets that will be decoded. The batch starts
            // at the last key frame and goes until this sequence number.
            let maxSequenceNumber = -1;
            const decodePackets = async () => {
                (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .assert */ .vA)(lastKeyPacket);
                // Start at the current key packet
                let currentPacket = lastKeyPacket;
                decoder.decode(currentPacket);
                while (currentPacket.sequenceNumber < maxSequenceNumber) {
                    const maxQueueSize = computeMaxQueueSize(sampleQueue.length);
                    while (sampleQueue.length + decoder.getDecodeQueueSize() > maxQueueSize && !terminated) {
                        ({ promise: queueDequeue, resolve: onQueueDequeue } = (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .promiseWithResolvers */ .nJ)());
                        await queueDequeue;
                    }
                    if (terminated) {
                        break;
                    }
                    const nextPacket = await packetSink.getNextPacket(currentPacket, retrievalOptions);
                    (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .assert */ .vA)(nextPacket);
                    decoder.decode(nextPacket);
                    currentPacket = nextPacket;
                }
                maxSequenceNumber = -1;
            };
            const flushDecoder = async () => {
                await decoder.flush();
                // We don't expect this list to have any elements in it anymore, but in case it does, let's emit
                // nulls for every remaining element, then clear it.
                for (let i = 0; i < timestampsOfInterest.length; i++) {
                    pushToQueue(null);
                }
                timestampsOfInterest.length = 0;
            };
            for await (const timestamp of timestampIterator) {
                validateTimestamp(timestamp);
                if (terminated || this._track.input._disposed) {
                    break;
                }
                const targetPacket = await packetSink.getPacket(timestamp, retrievalOptions);
                const keyPacket = targetPacket && await packetSink.getKeyPacket(timestamp, retrievalOptions);
                if (!keyPacket) {
                    if (maxSequenceNumber !== -1) {
                        await decodePackets();
                        await flushDecoder();
                    }
                    pushToQueue(null);
                    lastPacket = null;
                    continue;
                }
                // Check if the key packet has changed or if we're going back in time
                if (lastPacket
                    && (keyPacket.sequenceNumber !== lastKeyPacket.sequenceNumber
                        || targetPacket.timestamp < lastPacket.timestamp)) {
                    await decodePackets();
                    await flushDecoder(); // Always flush here, improves decoder compatibility
                }
                timestampsOfInterest.push(targetPacket.timestamp);
                maxSequenceNumber = Math.max(targetPacket.sequenceNumber, maxSequenceNumber);
                lastPacket = targetPacket;
                lastKeyPacket = keyPacket;
            }
            if (!terminated && !this._track.input._disposed) {
                if (maxSequenceNumber !== -1) {
                    // We still need to decode packets
                    await decodePackets();
                }
                await flushDecoder();
            }
            decoder.close();
            decoderIsFlushed = true;
            onQueueNotEmpty(); // To unstuck the generator
        })().catch((error) => {
            if (!outOfBandError) {
                outOfBandError = error;
                onQueueNotEmpty();
            }
        });
        const track = this._track;
        const closeSamples = () => {
            for (const sample of sampleQueue) {
                sample?.close();
            }
        };
        return {
            async next() {
                while (true) {
                    if (track.input._disposed) {
                        closeSamples();
                        throw new _input_js__WEBPACK_IMPORTED_MODULE_3__/* .InputDisposedError */ .QO();
                    }
                    else if (terminated) {
                        return { value: undefined, done: true };
                    }
                    else if (outOfBandError) {
                        closeSamples();
                        throw outOfBandError;
                    }
                    else if (sampleQueue.length > 0) {
                        const value = sampleQueue.shift();
                        (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .assert */ .vA)(value !== undefined);
                        onQueueDequeue();
                        return { value, done: false };
                    }
                    else if (!decoderIsFlushed) {
                        await queueNotEmpty;
                    }
                    else {
                        return { value: undefined, done: true };
                    }
                }
            },
            async return() {
                terminated = true;
                onQueueDequeue();
                onQueueNotEmpty();
                closeSamples();
                return { value: undefined, done: true };
            },
            async throw(error) {
                throw error;
            },
            [Symbol.asyncIterator]() {
                return this;
            },
        };
    }
}
const computeMaxQueueSize = (decodedSampleQueueSize) => {
    // If we have decoded samples lying around, limit the total queue size to a small value (decoded samples can use up
    // a lot of memory). If not, we're fine with a much bigger queue of encoded packets waiting to be decoded. In fact,
    // some decoders only start flushing out decoded chunks when the packet queue is large enough.
    return decodedSampleQueueSize === 0 ? 40 : 8;
};
class VideoDecoderWrapper extends DecoderWrapper {
    constructor(onSample, onError, codec, decoderConfig, rotation, timeResolution) {
        super(onSample, onError);
        this.codec = codec;
        this.decoderConfig = decoderConfig;
        this.rotation = rotation;
        this.timeResolution = timeResolution;
        this.decoder = null;
        this.customDecoder = null;
        this.customDecoderCallSerializer = new _misc_js__WEBPACK_IMPORTED_MODULE_5__/* .CallSerializer */ .dY();
        this.customDecoderQueueSize = 0;
        this.inputTimestamps = []; // Timestamps input into the decoder, sorted.
        this.sampleQueue = []; // Safari-specific thing, check usage.
        this.currentPacketIndex = 0;
        this.raslSkipped = false; // For HEVC stuff
        // Alpha stuff
        this.alphaDecoder = null;
        this.alphaHadKeyframe = false;
        this.colorQueue = [];
        this.alphaQueue = [];
        this.merger = null;
        this.mergerCreationFailed = false;
        this.decodedAlphaChunkCount = 0;
        this.alphaDecoderQueueSize = 0;
        /** Each value is the number of decoded alpha chunks at which a null alpha frame should be added. */
        this.nullAlphaFrameQueue = [];
        this.currentAlphaPacketIndex = 0;
        this.alphaRaslSkipped = false; // For HEVC stuff
        const MatchingCustomDecoder = _custom_coder_js__WEBPACK_IMPORTED_MODULE_2__/* .customVideoDecoders */ .wb.find(x => x.supports(codec, decoderConfig));
        if (MatchingCustomDecoder) {
            // @ts-expect-error "Can't create instance of abstract class 🤓"
            this.customDecoder = new MatchingCustomDecoder();
            // @ts-expect-error It's technically readonly
            this.customDecoder.codec = codec;
            // @ts-expect-error It's technically readonly
            this.customDecoder.config = decoderConfig;
            // @ts-expect-error It's technically readonly
            this.customDecoder.onSample = (sample) => {
                if (!(sample instanceof _sample_js__WEBPACK_IMPORTED_MODULE_8__/* .VideoSample */ .U2)) {
                    throw new TypeError('The argument passed to onSample must be a VideoSample.');
                }
                this.finalizeAndEmitSample(sample);
            };
            void this.customDecoderCallSerializer.call(() => this.customDecoder.init());
        }
        else {
            const colorHandler = (frame) => {
                if (this.alphaQueue.length > 0) {
                    // Even when no alpha data is present (most of the time), there will be nulls in this queue
                    const alphaFrame = this.alphaQueue.shift();
                    (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .assert */ .vA)(alphaFrame !== undefined);
                    this.mergeAlpha(frame, alphaFrame);
                }
                else {
                    this.colorQueue.push(frame);
                }
            };
            if (codec === 'avc' && this.decoderConfig.description && (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .isChromium */ .F2)()) {
                // Chromium has/had a bug with playing interlaced AVC (https://issues.chromium.org/issues/456919096)
                // which can be worked around by requesting that software decoding be used. So, here we peek into the
                // AVC description, if present, and switch to software decoding if we find interlaced content.
                const record = (0,_codec_data_js__WEBPACK_IMPORTED_MODULE_1__/* .deserializeAvcDecoderConfigurationRecord */ .BP)((0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .toUint8Array */ .Fo)(this.decoderConfig.description));
                if (record && record.sequenceParameterSets.length > 0) {
                    const sps = (0,_codec_data_js__WEBPACK_IMPORTED_MODULE_1__/* .parseAvcSps */ .eM)(record.sequenceParameterSets[0]);
                    if (sps && sps.frameMbsOnlyFlag === 0) {
                        this.decoderConfig = {
                            ...this.decoderConfig,
                            hardwareAcceleration: 'prefer-software',
                        };
                    }
                }
            }
            const stack = new Error('Decoding error').stack;
            this.decoder = new VideoDecoder({
                output: (frame) => {
                    try {
                        colorHandler(frame);
                    }
                    catch (error) {
                        this.onError(error);
                    }
                },
                error: (error) => {
                    error.stack = stack; // Provide a more useful stack trace, the default one sucks
                    this.onError(error);
                },
            });
            this.decoder.configure(this.decoderConfig);
        }
    }
    getDecodeQueueSize() {
        if (this.customDecoder) {
            return this.customDecoderQueueSize;
        }
        else {
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .assert */ .vA)(this.decoder);
            return Math.max(this.decoder.decodeQueueSize, this.alphaDecoder?.decodeQueueSize ?? 0);
        }
    }
    decode(packet) {
        if (this.codec === 'hevc' && this.currentPacketIndex > 0 && !this.raslSkipped) {
            if (this.hasHevcRaslPicture(packet.data)) {
                return; // Drop
            }
            this.raslSkipped = true;
        }
        if (this.customDecoder) {
            this.customDecoderQueueSize++;
            void this.customDecoderCallSerializer
                .call(() => this.customDecoder.decode(packet))
                .then(() => this.customDecoderQueueSize--);
        }
        else {
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .assert */ .vA)(this.decoder);
            if (!(0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .isWebKit */ .Tc)()) {
                (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .insertSorted */ .h8)(this.inputTimestamps, packet.timestamp, x => x);
            }
            // Workaround for https://issues.chromium.org/issues/470109459
            if ((0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .isChromium */ .F2)() && this.currentPacketIndex === 0 && this.codec === 'avc') {
                const filteredNalUnits = [];
                for (const loc of (0,_codec_data_js__WEBPACK_IMPORTED_MODULE_1__/* .iterateAvcNalUnits */ .RO)(packet.data, this.decoderConfig)) {
                    const type = (0,_codec_data_js__WEBPACK_IMPORTED_MODULE_1__/* .extractNalUnitTypeForAvc */ .uN)(packet.data[loc.offset]);
                    // These trip up Chromium's key frame detection, so let's strip them
                    if (!(type >= 20 && type <= 31)) {
                        filteredNalUnits.push(packet.data.subarray(loc.offset, loc.offset + loc.length));
                    }
                }
                const newData = (0,_codec_data_js__WEBPACK_IMPORTED_MODULE_1__/* .concatAvcNalUnits */ .Zi)(filteredNalUnits, this.decoderConfig);
                packet = new _packet_js__WEBPACK_IMPORTED_MODULE_6__/* .EncodedPacket */ .Z(newData, packet.type, packet.timestamp, packet.duration);
            }
            this.decoder.decode(packet.toEncodedVideoChunk());
            this.decodeAlphaData(packet);
        }
        this.currentPacketIndex++;
    }
    decodeAlphaData(packet) {
        if (!packet.sideData.alpha || this.mergerCreationFailed) {
            // No alpha side data in the packet, most common case
            this.pushNullAlphaFrame();
            return;
        }
        if (!this.merger) {
            try {
                this.merger = new ColorAlphaMerger();
            }
            catch (error) {
                console.error('Due to an error, only color data will be decoded.', error);
                this.mergerCreationFailed = true;
                this.decodeAlphaData(packet); // Go again
                return;
            }
        }
        // Check if we need to set up the alpha decoder
        if (!this.alphaDecoder) {
            const alphaHandler = (frame) => {
                this.alphaDecoderQueueSize--;
                if (this.colorQueue.length > 0) {
                    const colorFrame = this.colorQueue.shift();
                    (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .assert */ .vA)(colorFrame !== undefined);
                    this.mergeAlpha(colorFrame, frame);
                }
                else {
                    this.alphaQueue.push(frame);
                }
                // Check if any null frames have been queued for this point
                this.decodedAlphaChunkCount++;
                while (this.nullAlphaFrameQueue.length > 0
                    && this.nullAlphaFrameQueue[0] === this.decodedAlphaChunkCount) {
                    this.nullAlphaFrameQueue.shift();
                    if (this.colorQueue.length > 0) {
                        const colorFrame = this.colorQueue.shift();
                        (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .assert */ .vA)(colorFrame !== undefined);
                        this.mergeAlpha(colorFrame, null);
                    }
                    else {
                        this.alphaQueue.push(null);
                    }
                }
            };
            const stack = new Error('Decoding error').stack;
            this.alphaDecoder = new VideoDecoder({
                output: (frame) => {
                    try {
                        alphaHandler(frame);
                    }
                    catch (error) {
                        this.onError(error);
                    }
                },
                error: (error) => {
                    error.stack = stack; // Provide a more useful stack trace, the default one sucks
                    this.onError(error);
                },
            });
            this.alphaDecoder.configure(this.decoderConfig);
        }
        const type = (0,_codec_data_js__WEBPACK_IMPORTED_MODULE_1__/* .determineVideoPacketType */ .PR)(this.codec, this.decoderConfig, packet.sideData.alpha);
        // Alpha packets might follow a different key frame rhythm than the main packets. Therefore, before we start
        // decoding, we must first find a packet that's actually a key frame. Until then, we treat the image as opaque.
        if (!this.alphaHadKeyframe) {
            this.alphaHadKeyframe = type === 'key';
        }
        if (this.alphaHadKeyframe) {
            // Same RASL skipping logic as for color, unlikely to be hit (since who uses HEVC with separate alpha??) but
            // here for symmetry.
            if (this.codec === 'hevc' && this.currentAlphaPacketIndex > 0 && !this.alphaRaslSkipped) {
                if (this.hasHevcRaslPicture(packet.sideData.alpha)) {
                    this.pushNullAlphaFrame();
                    return;
                }
                this.alphaRaslSkipped = true;
            }
            this.currentAlphaPacketIndex++;
            this.alphaDecoder.decode(packet.alphaToEncodedVideoChunk(type ?? packet.type));
            this.alphaDecoderQueueSize++;
        }
        else {
            this.pushNullAlphaFrame();
        }
    }
    pushNullAlphaFrame() {
        if (this.alphaDecoderQueueSize === 0) {
            // Easy
            this.alphaQueue.push(null);
        }
        else {
            // There are still alpha chunks being decoded, so pushing `null` immediately would result in out-of-order
            // data and be incorrect. Instead, we need to enqueue a "null frame" for when the current decoder workload
            // has finished.
            this.nullAlphaFrameQueue.push(this.decodedAlphaChunkCount + this.alphaDecoderQueueSize);
        }
    }
    /**
     * If we're using HEVC, we need to make sure to skip any RASL slices that follow a non-IDR key frame such as
     * CRA_NUT. This is because RASL slices cannot be decoded without data before the CRA_NUT. Browsers behave
     * differently here: Chromium drops the packets, Safari throws a decoder error. Either way, it's not good
     * and causes bugs upstream. So, let's take the dropping into our own hands.
     */
    hasHevcRaslPicture(packetData) {
        for (const loc of (0,_codec_data_js__WEBPACK_IMPORTED_MODULE_1__/* .iterateHevcNalUnits */ .RF)(packetData, this.decoderConfig)) {
            const type = (0,_codec_data_js__WEBPACK_IMPORTED_MODULE_1__/* .extractNalUnitTypeForHevc */ .O9)(packetData[loc.offset]);
            if (type === _codec_data_js__WEBPACK_IMPORTED_MODULE_1__/* .HevcNalUnitType */ .iJ.RASL_N || type === _codec_data_js__WEBPACK_IMPORTED_MODULE_1__/* .HevcNalUnitType */ .iJ.RASL_R) {
                return true;
            }
        }
        return false;
    }
    /** Handler for the WebCodecs VideoDecoder for ironing out browser differences. */
    sampleHandler(sample) {
        if ((0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .isWebKit */ .Tc)()) {
            // For correct B-frame handling, we don't just hand over the frames directly but instead add them to
            // a queue, because we want to ensure frames are emitted in presentation order. We flush the queue
            // each time we receive a frame with a timestamp larger than the highest we've seen so far, as we
            // can sure that is not a B-frame. Typically, WebCodecs automatically guarantees that frames are
            // emitted in presentation order, but Safari doesn't always follow this rule.
            if (this.sampleQueue.length > 0 && (sample.timestamp >= (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .last */ ._g)(this.sampleQueue).timestamp)) {
                for (const sample of this.sampleQueue) {
                    this.finalizeAndEmitSample(sample);
                }
                this.sampleQueue.length = 0;
            }
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .insertSorted */ .h8)(this.sampleQueue, sample, x => x.timestamp);
        }
        else {
            // Assign it the next earliest timestamp from the input. We do this because browsers, by spec, are
            // required to emit decoded frames in presentation order *while* retaining the timestamp of their
            // originating EncodedVideoChunk. For files with B-frames but no out-of-order timestamps (like a
            // missing ctts box, for example), this causes a mismatch. We therefore fix the timestamps and
            // ensure they are sorted by doing this.
            const timestamp = this.inputTimestamps.shift();
            // There's no way we'd have more decoded frames than encoded packets we passed in. Actually, the
            // correspondence should be 1:1.
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .assert */ .vA)(timestamp !== undefined);
            sample.setTimestamp(timestamp);
            this.finalizeAndEmitSample(sample);
        }
    }
    finalizeAndEmitSample(sample) {
        // Round the timestamps to the time resolution
        sample.setTimestamp(Math.round(sample.timestamp * this.timeResolution) / this.timeResolution);
        sample.setDuration(Math.round(sample.duration * this.timeResolution) / this.timeResolution);
        sample.setRotation(this.rotation);
        this.onSample(sample);
    }
    mergeAlpha(color, alpha) {
        if (!alpha) {
            // Nothing needs to be merged
            const finalSample = new _sample_js__WEBPACK_IMPORTED_MODULE_8__/* .VideoSample */ .U2(color);
            this.sampleHandler(finalSample);
            return;
        }
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .assert */ .vA)(this.merger);
        this.merger.update(color, alpha);
        color.close();
        alpha.close();
        const finalFrame = new VideoFrame(this.merger.canvas, {
            timestamp: color.timestamp,
            duration: color.duration ?? undefined,
        });
        const finalSample = new _sample_js__WEBPACK_IMPORTED_MODULE_8__/* .VideoSample */ .U2(finalFrame);
        this.sampleHandler(finalSample);
    }
    async flush() {
        if (this.customDecoder) {
            await this.customDecoderCallSerializer.call(() => this.customDecoder.flush());
        }
        else {
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .assert */ .vA)(this.decoder);
            await Promise.all([
                this.decoder.flush(),
                this.alphaDecoder?.flush(),
            ]);
            this.colorQueue.forEach(x => x.close());
            this.colorQueue.length = 0;
            this.alphaQueue.forEach(x => x?.close());
            this.alphaQueue.length = 0;
            this.alphaHadKeyframe = false;
            this.decodedAlphaChunkCount = 0;
            this.alphaDecoderQueueSize = 0;
            this.nullAlphaFrameQueue.length = 0;
            this.currentAlphaPacketIndex = 0;
            this.alphaRaslSkipped = false;
        }
        if ((0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .isWebKit */ .Tc)()) {
            for (const sample of this.sampleQueue) {
                this.finalizeAndEmitSample(sample);
            }
            this.sampleQueue.length = 0;
        }
        this.currentPacketIndex = 0;
        this.raslSkipped = false;
    }
    close() {
        if (this.customDecoder) {
            void this.customDecoderCallSerializer.call(() => this.customDecoder.close());
        }
        else {
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .assert */ .vA)(this.decoder);
            this.decoder.close();
            this.alphaDecoder?.close();
            this.colorQueue.forEach(x => x.close());
            this.colorQueue.length = 0;
            this.alphaQueue.forEach(x => x?.close());
            this.alphaQueue.length = 0;
            this.merger?.close();
        }
        for (const sample of this.sampleQueue) {
            sample.close();
        }
        this.sampleQueue.length = 0;
    }
}
/** Utility class that merges together color and alpha information using simple WebGL 2 shaders. */
class ColorAlphaMerger {
    constructor() {
        // Canvas will be resized later
        if (typeof OffscreenCanvas !== 'undefined') {
            // Prefer OffscreenCanvas for Worker environments
            this.canvas = new OffscreenCanvas(300, 150);
        }
        else {
            this.canvas = document.createElement('canvas');
        }
        const gl = this.canvas.getContext('webgl2', {
            premultipliedAlpha: false,
        }); // Casting because of some TypeScript weirdness
        if (!gl) {
            throw new Error('Couldn\'t acquire WebGL 2 context.');
        }
        this.gl = gl;
        this.program = this.createProgram();
        this.vao = this.createVAO();
        this.colorTexture = this.createTexture();
        this.alphaTexture = this.createTexture();
        this.gl.useProgram(this.program);
        this.gl.uniform1i(this.gl.getUniformLocation(this.program, 'u_colorTexture'), 0);
        this.gl.uniform1i(this.gl.getUniformLocation(this.program, 'u_alphaTexture'), 1);
    }
    createProgram() {
        const vertexShader = this.createShader(this.gl.VERTEX_SHADER, `#version 300 es
			in vec2 a_position;
			in vec2 a_texCoord;
			out vec2 v_texCoord;
			
			void main() {
				gl_Position = vec4(a_position, 0.0, 1.0);
				v_texCoord = a_texCoord;
			}
		`);
        const fragmentShader = this.createShader(this.gl.FRAGMENT_SHADER, `#version 300 es
			precision highp float;
			
			uniform sampler2D u_colorTexture;
			uniform sampler2D u_alphaTexture;
			in vec2 v_texCoord;
			out vec4 fragColor;
			
			void main() {
				vec3 color = texture(u_colorTexture, v_texCoord).rgb;
				float alpha = texture(u_alphaTexture, v_texCoord).r;
				fragColor = vec4(color, alpha);
			}
		`);
        const program = this.gl.createProgram();
        this.gl.attachShader(program, vertexShader);
        this.gl.attachShader(program, fragmentShader);
        this.gl.linkProgram(program);
        return program;
    }
    createShader(type, source) {
        const shader = this.gl.createShader(type);
        this.gl.shaderSource(shader, source);
        this.gl.compileShader(shader);
        return shader;
    }
    createVAO() {
        const vao = this.gl.createVertexArray();
        this.gl.bindVertexArray(vao);
        const vertices = new Float32Array([
            -1, -1, 0, 1,
            1, -1, 1, 1,
            -1, 1, 0, 0,
            1, 1, 1, 0,
        ]);
        const buffer = this.gl.createBuffer();
        this.gl.bindBuffer(this.gl.ARRAY_BUFFER, buffer);
        this.gl.bufferData(this.gl.ARRAY_BUFFER, vertices, this.gl.STATIC_DRAW);
        const positionLocation = this.gl.getAttribLocation(this.program, 'a_position');
        const texCoordLocation = this.gl.getAttribLocation(this.program, 'a_texCoord');
        this.gl.enableVertexAttribArray(positionLocation);
        this.gl.vertexAttribPointer(positionLocation, 2, this.gl.FLOAT, false, 16, 0);
        this.gl.enableVertexAttribArray(texCoordLocation);
        this.gl.vertexAttribPointer(texCoordLocation, 2, this.gl.FLOAT, false, 16, 8);
        return vao;
    }
    createTexture() {
        const texture = this.gl.createTexture();
        this.gl.bindTexture(this.gl.TEXTURE_2D, texture);
        this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_S, this.gl.CLAMP_TO_EDGE);
        this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_WRAP_T, this.gl.CLAMP_TO_EDGE);
        this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_MIN_FILTER, this.gl.LINEAR);
        this.gl.texParameteri(this.gl.TEXTURE_2D, this.gl.TEXTURE_MAG_FILTER, this.gl.LINEAR);
        return texture;
    }
    update(color, alpha) {
        if (color.displayWidth !== this.canvas.width || color.displayHeight !== this.canvas.height) {
            this.canvas.width = color.displayWidth;
            this.canvas.height = color.displayHeight;
        }
        this.gl.activeTexture(this.gl.TEXTURE0);
        this.gl.bindTexture(this.gl.TEXTURE_2D, this.colorTexture);
        this.gl.texImage2D(this.gl.TEXTURE_2D, 0, this.gl.RGBA, this.gl.RGBA, this.gl.UNSIGNED_BYTE, color);
        this.gl.activeTexture(this.gl.TEXTURE1);
        this.gl.bindTexture(this.gl.TEXTURE_2D, this.alphaTexture);
        this.gl.texImage2D(this.gl.TEXTURE_2D, 0, this.gl.RGBA, this.gl.RGBA, this.gl.UNSIGNED_BYTE, alpha);
        this.gl.viewport(0, 0, this.canvas.width, this.canvas.height);
        this.gl.clear(this.gl.COLOR_BUFFER_BIT);
        this.gl.bindVertexArray(this.vao);
        this.gl.drawArrays(this.gl.TRIANGLE_STRIP, 0, 4);
    }
    close() {
        this.gl.getExtension('WEBGL_lose_context')?.loseContext();
        this.gl = null;
    }
}
/**
 * A sink that retrieves decoded video samples (video frames) from a video track.
 * @group Media sinks
 * @public
 */
class VideoSampleSink extends BaseMediaSampleSink {
    /** Creates a new {@link VideoSampleSink} for the given {@link InputVideoTrack}. */
    constructor(videoTrack) {
        if (!(videoTrack instanceof _input_track_js__WEBPACK_IMPORTED_MODULE_4__/* .InputVideoTrack */ .N0)) {
            throw new TypeError('videoTrack must be an InputVideoTrack.');
        }
        super();
        this._track = videoTrack;
    }
    /** @internal */
    async _createDecoder(onSample, onError) {
        if (!(await this._track.canDecode())) {
            throw new Error('This video track cannot be decoded by this browser. Make sure to check decodability before using'
                + ' a track.');
        }
        const codec = await this._track.getCodec();
        const rotation = await this._track.getRotation();
        const decoderConfig = await this._track.getDecoderConfig();
        const timeResolution = await this._track.getTimeResolution();
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .assert */ .vA)(codec && decoderConfig);
        return new VideoDecoderWrapper(onSample, onError, codec, decoderConfig, rotation, timeResolution);
    }
    /** @internal */
    _createPacketSink() {
        return new EncodedPacketSink(this._track);
    }
    /**
     * Retrieves the video sample (frame) corresponding to the given timestamp, in seconds. More specifically, returns
     * the last video sample (in presentation order) with a start timestamp less than or equal to the given timestamp.
     * Returns null if the timestamp is before the track's first timestamp.
     *
     * @param timestamp - The timestamp used for retrieval, in seconds.
     * @param options - Options used for the underlying packet retrieval.
     */
    async getSample(timestamp, options = {}) {
        validateTimestamp(timestamp);
        for await (const sample of this.mediaSamplesAtTimestamps([timestamp], options)) {
            return sample;
        }
        throw new Error('Internal error: Iterator returned nothing.');
    }
    /**
     * Creates an async iterator that yields the video samples (frames) of this track in presentation order. This method
     * will intelligently pre-decode a few frames ahead to enable fast iteration.
     *
     * @param startTimestamp - The timestamp in seconds at which to start yielding samples (inclusive).
     * @param endTimestamp - The timestamp in seconds at which to stop yielding samples (exclusive).
     * @param options - Options used for the underlying packet retrieval.
     */
    samples(startTimestamp = 0, endTimestamp = Infinity, options = {}) {
        return this.mediaSamplesInRange(startTimestamp, endTimestamp, options);
    }
    /**
     * Creates an async iterator that yields a video sample (frame) for each timestamp in the argument. This method
     * uses an optimized decoding pipeline if these timestamps are monotonically sorted, decoding each packet at most
     * once, and is therefore more efficient than manually getting the sample for every timestamp. The iterator may
     * yield null if no frame is available for a given timestamp.
     *
     * @param timestamps - An iterable or async iterable of timestamps in seconds.
     * @param options - Options used for the underlying packet retrieval.
     */
    samplesAtTimestamps(timestamps, options = {}) {
        return this.mediaSamplesAtTimestamps(timestamps, options);
    }
}
/**
 * A sink that renders video samples (frames) of the given video track to canvases. This is often more useful than
 * directly retrieving frames, as it comes with common preprocessing steps such as resizing or applying rotation
 * metadata.
 *
 * This sink will yield `HTMLCanvasElement`s when in a DOM context, and `OffscreenCanvas`es otherwise.
 *
 * @group Media sinks
 * @public
 */
class CanvasSink {
    /** Creates a new {@link CanvasSink} for the given {@link InputVideoTrack}. */
    constructor(videoTrack, options = {}) {
        /** @internal */
        this._rotation = 0;
        /** @internal */
        this._initPromise = null;
        /** @internal */
        this._nextCanvasIndex = 0;
        if (!(videoTrack instanceof InputVideoTrack)) {
            throw new TypeError('videoTrack must be an InputVideoTrack.');
        }
        if (options && typeof options !== 'object') {
            throw new TypeError('options must be an object.');
        }
        if (options.alpha !== undefined && typeof options.alpha !== 'boolean') {
            throw new TypeError('options.alpha, when provided, must be a boolean.');
        }
        if (options.width !== undefined && (!Number.isInteger(options.width) || options.width <= 0)) {
            throw new TypeError('options.width, when defined, must be a positive integer.');
        }
        if (options.height !== undefined && (!Number.isInteger(options.height) || options.height <= 0)) {
            throw new TypeError('options.height, when defined, must be a positive integer.');
        }
        if (options.fit !== undefined && !['fill', 'contain', 'cover'].includes(options.fit)) {
            throw new TypeError('options.fit, when provided, must be one of "fill", "contain", or "cover".');
        }
        if (options.width !== undefined
            && options.height !== undefined
            && options.fit === undefined) {
            throw new TypeError('When both options.width and options.height are provided, options.fit must also be provided.');
        }
        if (options.rotation !== undefined && ![0, 90, 180, 270].includes(options.rotation)) {
            throw new TypeError('options.rotation, when provided, must be 0, 90, 180 or 270.');
        }
        if (options.crop !== undefined) {
            validateCropRectangle(options.crop, 'options.');
        }
        if (options.poolSize !== undefined
            && (typeof options.poolSize !== 'number' || !Number.isInteger(options.poolSize) || options.poolSize < 0)) {
            throw new TypeError('poolSize must be a non-negative integer.');
        }
        this._videoTrack = videoTrack;
        this._alpha = options.alpha ?? false;
        this._options = options;
        this._fit = options.fit ?? 'fill';
        this._videoSampleSink = new VideoSampleSink(videoTrack);
        this._canvasPool = Array.from({ length: options.poolSize ?? 0 }, () => null);
    }
    /** @internal */
    _ensureInit() {
        return this._initPromise ??= (async () => {
            const options = this._options;
            const videoTrack = this._videoTrack;
            const rotation = options.rotation ?? await videoTrack.getRotation();
            const squarePixelWidth = await videoTrack.getSquarePixelWidth();
            const squarePixelHeight = await videoTrack.getSquarePixelHeight();
            const [rotatedWidth, rotatedHeight] = rotation % 180 === 0
                ? [squarePixelWidth, squarePixelHeight]
                : [squarePixelHeight, squarePixelWidth];
            let crop = options.crop;
            if (crop) {
                crop = clampCropRectangle(crop, rotatedWidth, rotatedHeight);
            }
            let [width, height] = crop
                ? [crop.width, crop.height]
                : [rotatedWidth, rotatedHeight];
            const originalAspectRatio = width / height;
            // If width and height aren't defined together, deduce the missing value using the aspect ratio
            if (options.width !== undefined && options.height === undefined) {
                width = options.width;
                height = Math.round(width / originalAspectRatio);
            }
            else if (options.width === undefined && options.height !== undefined) {
                height = options.height;
                width = Math.round(height * originalAspectRatio);
            }
            else if (options.width !== undefined && options.height !== undefined) {
                width = options.width;
                height = options.height;
            }
            this._width = width;
            this._height = height;
            this._rotation = rotation;
            this._crop = crop;
        })();
    }
    /** @internal */
    _videoSampleToWrappedCanvas(sample) {
        const width = this._width;
        const height = this._height;
        let canvas = this._canvasPool[this._nextCanvasIndex];
        let canvasIsNew = false;
        if (!canvas) {
            if (typeof document !== 'undefined') {
                // Prefer an HTMLCanvasElement
                canvas = document.createElement('canvas');
                canvas.width = width;
                canvas.height = height;
            }
            else {
                canvas = new OffscreenCanvas(width, height);
            }
            if (this._canvasPool.length > 0) {
                this._canvasPool[this._nextCanvasIndex] = canvas;
            }
            canvasIsNew = true;
        }
        if (this._canvasPool.length > 0) {
            this._nextCanvasIndex = (this._nextCanvasIndex + 1) % this._canvasPool.length;
        }
        const context = canvas.getContext('2d', {
            alpha: this._alpha || isFirefox(), // Firefox has VideoFrame glitches with opaque canvases
        });
        assert(context);
        context.resetTransform();
        if (!canvasIsNew) {
            if (!this._alpha && isFirefox()) {
                context.fillStyle = 'black';
                context.fillRect(0, 0, width, height);
            }
            else {
                context.clearRect(0, 0, width, height);
            }
        }
        sample.drawWithFit(context, {
            fit: this._fit,
            rotation: this._rotation,
            crop: this._crop,
        });
        const result = {
            canvas,
            timestamp: sample.timestamp,
            duration: sample.duration,
        };
        sample.close();
        return result;
    }
    /**
     * Retrieves a canvas with the video frame corresponding to the given timestamp, in seconds. More specifically,
     * returns the last video frame (in presentation order) with a start timestamp less than or equal to the given
     * timestamp. Returns null if the timestamp is before the track's first timestamp.
     *
     * @param timestamp - The timestamp used for retrieval, in seconds.
     * @param options - Options used for the underlying packet retrieval.
     */
    async getCanvas(timestamp, options) {
        validateTimestamp(timestamp);
        await this._ensureInit();
        const sample = await this._videoSampleSink.getSample(timestamp, options);
        return sample && this._videoSampleToWrappedCanvas(sample);
    }
    /**
     * Creates an async iterator that yields canvases with the video frames of this track in presentation order. This
     * method will intelligently pre-decode a few frames ahead to enable fast iteration.
     *
     * @param startTimestamp - The timestamp in seconds at which to start yielding canvases (inclusive).
     * @param endTimestamp - The timestamp in seconds at which to stop yielding canvases (exclusive).
     * @param options - Options used for the underlying packet retrieval.
     */
    async *canvases(startTimestamp = 0, endTimestamp = Infinity, options) {
        await this._ensureInit();
        yield* mapAsyncGenerator(this._videoSampleSink.samples(startTimestamp, endTimestamp, options), sample => this._videoSampleToWrappedCanvas(sample));
    }
    /**
     * Creates an async iterator that yields a canvas for each timestamp in the argument. This method uses an optimized
     * decoding pipeline if these timestamps are monotonically sorted, decoding each packet at most once, and is
     * therefore more efficient than manually getting the canvas for every timestamp. The iterator may yield null if
     * no frame is available for a given timestamp.
     *
     * @param timestamps - An iterable or async iterable of timestamps in seconds.
     * @param options - Options used for the underlying packet retrieval.
     */
    async *canvasesAtTimestamps(timestamps, options) {
        await this._ensureInit();
        yield* mapAsyncGenerator(this._videoSampleSink.samplesAtTimestamps(timestamps, options), sample => sample && this._videoSampleToWrappedCanvas(sample));
    }
}
class AudioDecoderWrapper extends DecoderWrapper {
    constructor(onSample, onError, codec, decoderConfig) {
        super(onSample, onError);
        this.decoder = null;
        this.customDecoder = null;
        this.customDecoderCallSerializer = new _misc_js__WEBPACK_IMPORTED_MODULE_5__/* .CallSerializer */ .dY();
        this.customDecoderQueueSize = 0;
        // Internal state to accumulate a precise current timestamp based on audio durations, not the (potentially
        // inaccurate) packet timestamps.
        this.currentTimestamp = null;
        const sampleHandler = (sample) => {
            if (this.currentTimestamp === null
                || Math.abs(sample.timestamp - this.currentTimestamp) >= sample.duration) {
                // We need to sync with the sample timestamp again
                this.currentTimestamp = sample.timestamp;
            }
            const preciseTimestamp = this.currentTimestamp;
            this.currentTimestamp += sample.duration;
            if (sample.numberOfFrames === 0) {
                // We skip zero-data (empty) AudioSamples. These are sometimes emitted, for example, by Firefox when it
                // decodes Vorbis (at the start).
                sample.close();
                return;
            }
            // Round the timestamp to the sample rate
            const sampleRate = decoderConfig.sampleRate;
            sample.setTimestamp(Math.round(preciseTimestamp * sampleRate) / sampleRate);
            onSample(sample);
        };
        const MatchingCustomDecoder = _custom_coder_js__WEBPACK_IMPORTED_MODULE_2__/* .customAudioDecoders */ .zx.find(x => x.supports(codec, decoderConfig));
        if (MatchingCustomDecoder) {
            // @ts-expect-error "Can't create instance of abstract class 🤓"
            this.customDecoder = new MatchingCustomDecoder();
            // @ts-expect-error It's technically readonly
            this.customDecoder.codec = codec;
            // @ts-expect-error It's technically readonly
            this.customDecoder.config = decoderConfig;
            // @ts-expect-error It's technically readonly
            this.customDecoder.onSample = (sample) => {
                if (!(sample instanceof _sample_js__WEBPACK_IMPORTED_MODULE_8__/* .AudioSample */ .B1)) {
                    throw new TypeError('The argument passed to onSample must be an AudioSample.');
                }
                sampleHandler(sample);
            };
            void this.customDecoderCallSerializer.call(() => this.customDecoder.init());
        }
        else {
            const stack = new Error('Decoding error').stack;
            this.decoder = new AudioDecoder({
                output: (data) => {
                    try {
                        sampleHandler(new _sample_js__WEBPACK_IMPORTED_MODULE_8__/* .AudioSample */ .B1(data));
                    }
                    catch (error) {
                        this.onError(error);
                    }
                },
                error: (error) => {
                    error.stack = stack; // Provide a more useful stack trace, the default one sucks
                    this.onError(error);
                },
            });
            this.decoder.configure(decoderConfig);
        }
    }
    getDecodeQueueSize() {
        if (this.customDecoder) {
            return this.customDecoderQueueSize;
        }
        else {
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .assert */ .vA)(this.decoder);
            return this.decoder.decodeQueueSize;
        }
    }
    decode(packet) {
        if (this.customDecoder) {
            this.customDecoderQueueSize++;
            void this.customDecoderCallSerializer
                .call(() => this.customDecoder.decode(packet))
                .then(() => this.customDecoderQueueSize--);
        }
        else {
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .assert */ .vA)(this.decoder);
            this.decoder.decode(packet.toEncodedAudioChunk());
        }
    }
    flush() {
        if (this.customDecoder) {
            return this.customDecoderCallSerializer.call(() => this.customDecoder.flush());
        }
        else {
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .assert */ .vA)(this.decoder);
            return this.decoder.flush();
        }
    }
    close() {
        if (this.customDecoder) {
            void this.customDecoderCallSerializer.call(() => this.customDecoder.close());
        }
        else {
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .assert */ .vA)(this.decoder);
            this.decoder.close();
        }
    }
}
// There are a lot of PCM variants not natively supported by the browser and by AudioData. Therefore we need a simple
// decoder that maps any input PCM format into a PCM format supported by the browser.
class PcmAudioDecoderWrapper extends DecoderWrapper {
    constructor(onSample, onError, decoderConfig) {
        super(onSample, onError);
        this.decoderConfig = decoderConfig;
        // Internal state to accumulate a precise current timestamp based on audio durations, not the (potentially
        // inaccurate) packet timestamps.
        this.currentTimestamp = null;
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .assert */ .vA)(_codec_js__WEBPACK_IMPORTED_MODULE_0__/* .PCM_AUDIO_CODECS */ .Wq.includes(decoderConfig.codec));
        this.codec = decoderConfig.codec;
        const { dataType, sampleSize, littleEndian } = (0,_codec_js__WEBPACK_IMPORTED_MODULE_0__/* .parsePcmCodec */ .Ei)(this.codec);
        this.inputSampleSize = sampleSize;
        switch (sampleSize) {
            case 1:
                {
                    if (dataType === 'unsigned') {
                        this.readInputValue = (view, byteOffset) => view.getUint8(byteOffset) - 2 ** 7;
                    }
                    else if (dataType === 'signed') {
                        this.readInputValue = (view, byteOffset) => view.getInt8(byteOffset);
                    }
                    else if (dataType === 'ulaw') {
                        this.readInputValue = (view, byteOffset) => (0,_pcm_js__WEBPACK_IMPORTED_MODULE_7__/* .fromUlaw */ .qS)(view.getUint8(byteOffset));
                    }
                    else if (dataType === 'alaw') {
                        this.readInputValue = (view, byteOffset) => (0,_pcm_js__WEBPACK_IMPORTED_MODULE_7__/* .fromAlaw */ .aw)(view.getUint8(byteOffset));
                    }
                    else {
                        (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .assert */ .vA)(false);
                    }
                }
                ;
                break;
            case 2:
                {
                    if (dataType === 'unsigned') {
                        this.readInputValue = (view, byteOffset) => view.getUint16(byteOffset, littleEndian) - 2 ** 15;
                    }
                    else if (dataType === 'signed') {
                        this.readInputValue = (view, byteOffset) => view.getInt16(byteOffset, littleEndian);
                    }
                    else {
                        (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .assert */ .vA)(false);
                    }
                }
                ;
                break;
            case 3:
                {
                    if (dataType === 'unsigned') {
                        this.readInputValue = (view, byteOffset) => (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .getUint24 */ .dq)(view, byteOffset, littleEndian) - 2 ** 23;
                    }
                    else if (dataType === 'signed') {
                        this.readInputValue = (view, byteOffset) => (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .getInt24 */ .Wh)(view, byteOffset, littleEndian);
                    }
                    else {
                        (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .assert */ .vA)(false);
                    }
                }
                ;
                break;
            case 4:
                {
                    if (dataType === 'unsigned') {
                        this.readInputValue = (view, byteOffset) => view.getUint32(byteOffset, littleEndian) - 2 ** 31;
                    }
                    else if (dataType === 'signed') {
                        this.readInputValue = (view, byteOffset) => view.getInt32(byteOffset, littleEndian);
                    }
                    else if (dataType === 'float') {
                        this.readInputValue = (view, byteOffset) => view.getFloat32(byteOffset, littleEndian);
                    }
                    else {
                        (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .assert */ .vA)(false);
                    }
                }
                ;
                break;
            case 8:
                {
                    if (dataType === 'float') {
                        this.readInputValue = (view, byteOffset) => view.getFloat64(byteOffset, littleEndian);
                    }
                    else {
                        (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .assert */ .vA)(false);
                    }
                }
                ;
                break;
            default:
                {
                    (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .assertNever */ .xb)(sampleSize);
                    (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .assert */ .vA)(false);
                }
                ;
        }
        switch (sampleSize) {
            case 1:
                {
                    if (dataType === 'ulaw' || dataType === 'alaw') {
                        this.outputSampleSize = 2;
                        this.outputFormat = 's16';
                        this.writeOutputValue = (view, byteOffset, value) => view.setInt16(byteOffset, value, true);
                    }
                    else {
                        this.outputSampleSize = 1;
                        this.outputFormat = 'u8';
                        this.writeOutputValue = (view, byteOffset, value) => view.setUint8(byteOffset, value + 2 ** 7);
                    }
                }
                ;
                break;
            case 2:
                {
                    this.outputSampleSize = 2;
                    this.outputFormat = 's16';
                    this.writeOutputValue = (view, byteOffset, value) => view.setInt16(byteOffset, value, true);
                }
                ;
                break;
            case 3:
                {
                    this.outputSampleSize = 4;
                    this.outputFormat = 's32';
                    // From https://www.w3.org/TR/webcodecs:
                    // AudioData containing 24-bit samples SHOULD store those samples in s32 or f32. When samples are
                    // stored in s32, each sample MUST be left-shifted by 8 bits.
                    this.writeOutputValue = (view, byteOffset, value) => view.setInt32(byteOffset, value << 8, true);
                }
                ;
                break;
            case 4:
                {
                    this.outputSampleSize = 4;
                    if (dataType === 'float') {
                        this.outputFormat = 'f32';
                        this.writeOutputValue = (view, byteOffset, value) => view.setFloat32(byteOffset, value, true);
                    }
                    else {
                        this.outputFormat = 's32';
                        this.writeOutputValue = (view, byteOffset, value) => view.setInt32(byteOffset, value, true);
                    }
                }
                ;
                break;
            case 8:
                {
                    this.outputSampleSize = 4;
                    this.outputFormat = 'f32';
                    this.writeOutputValue = (view, byteOffset, value) => view.setFloat32(byteOffset, value, true);
                }
                ;
                break;
            default:
                {
                    (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .assertNever */ .xb)(sampleSize);
                    (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .assert */ .vA)(false);
                }
                ;
        }
        ;
    }
    getDecodeQueueSize() {
        return 0;
    }
    decode(packet) {
        const inputView = (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .toDataView */ .Zc)(packet.data);
        const numberOfFrames = packet.byteLength / this.decoderConfig.numberOfChannels / this.inputSampleSize;
        const outputBufferSize = numberOfFrames * this.decoderConfig.numberOfChannels * this.outputSampleSize;
        const outputBuffer = new ArrayBuffer(outputBufferSize);
        const outputView = new DataView(outputBuffer);
        for (let i = 0; i < numberOfFrames * this.decoderConfig.numberOfChannels; i++) {
            const inputIndex = i * this.inputSampleSize;
            const outputIndex = i * this.outputSampleSize;
            const value = this.readInputValue(inputView, inputIndex);
            this.writeOutputValue(outputView, outputIndex, value);
        }
        const preciseDuration = numberOfFrames / this.decoderConfig.sampleRate;
        if (this.currentTimestamp === null || Math.abs(packet.timestamp - this.currentTimestamp) >= preciseDuration) {
            // We need to sync with the packet timestamp again
            this.currentTimestamp = packet.timestamp;
        }
        const preciseTimestamp = this.currentTimestamp;
        this.currentTimestamp += preciseDuration;
        const audioSample = new _sample_js__WEBPACK_IMPORTED_MODULE_8__/* .AudioSample */ .B1({
            format: this.outputFormat,
            data: outputBuffer,
            numberOfChannels: this.decoderConfig.numberOfChannels,
            sampleRate: this.decoderConfig.sampleRate,
            numberOfFrames,
            timestamp: preciseTimestamp,
        });
        this.onSample(audioSample);
    }
    async flush() {
        // Do nothing
    }
    close() {
        // Do nothing
    }
}
/**
 * Sink for retrieving decoded audio samples from an audio track.
 * @group Media sinks
 * @public
 */
class AudioSampleSink extends BaseMediaSampleSink {
    /** Creates a new {@link AudioSampleSink} for the given {@link InputAudioTrack}. */
    constructor(audioTrack) {
        if (!(audioTrack instanceof _input_track_js__WEBPACK_IMPORTED_MODULE_4__/* .InputAudioTrack */ .Yi)) {
            throw new TypeError('audioTrack must be an InputAudioTrack.');
        }
        super();
        this._track = audioTrack;
    }
    /** @internal */
    async _createDecoder(onSample, onError) {
        if (!(await this._track.canDecode())) {
            throw new Error('This audio track cannot be decoded by this browser. Make sure to check decodability before using'
                + ' a track.');
        }
        const codec = await this._track.getCodec();
        const decoderConfig = await this._track.getDecoderConfig();
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_5__/* .assert */ .vA)(codec && decoderConfig);
        if (_codec_js__WEBPACK_IMPORTED_MODULE_0__/* .PCM_AUDIO_CODECS */ .Wq.includes(decoderConfig.codec)) {
            return new PcmAudioDecoderWrapper(onSample, onError, decoderConfig);
        }
        else {
            return new AudioDecoderWrapper(onSample, onError, codec, decoderConfig);
        }
    }
    /** @internal */
    _createPacketSink() {
        return new EncodedPacketSink(this._track);
    }
    /**
     * Retrieves the audio sample corresponding to the given timestamp, in seconds. More specifically, returns
     * the last audio sample (in presentation order) with a start timestamp less than or equal to the given timestamp.
     * Returns null if the timestamp is before the track's first timestamp.
     *
     * @param timestamp - The timestamp used for retrieval, in seconds.
     * @param options - Options used for the underlying packet retrieval.
     */
    async getSample(timestamp, options = {}) {
        validateTimestamp(timestamp);
        for await (const sample of this.mediaSamplesAtTimestamps([timestamp], options)) {
            return sample;
        }
        throw new Error('Internal error: Iterator returned nothing.');
    }
    /**
     * Creates an async iterator that yields the audio samples of this track in presentation order. This method
     * will intelligently pre-decode a few samples ahead to enable fast iteration.
     *
     * @param startTimestamp - The timestamp in seconds at which to start yielding samples (inclusive).
     * @param endTimestamp - The timestamp in seconds at which to stop yielding samples (exclusive).
     * @param options - Options used for the underlying packet retrieval.
     */
    samples(startTimestamp = 0, endTimestamp = Infinity, options = {}) {
        return this.mediaSamplesInRange(startTimestamp, endTimestamp, options);
    }
    /**
     * Creates an async iterator that yields an audio sample for each timestamp in the argument. This method
     * uses an optimized decoding pipeline if these timestamps are monotonically sorted, decoding each packet at most
     * once, and is therefore more efficient than manually getting the sample for every timestamp. The iterator may
     * yield null if no sample is available for a given timestamp.
     *
     * @param timestamps - An iterable or async iterable of timestamps in seconds.
     * @param options - Options used for the underlying packet retrieval.
     */
    samplesAtTimestamps(timestamps, options = {}) {
        return this.mediaSamplesAtTimestamps(timestamps, options);
    }
}
/**
 * A sink that retrieves decoded audio samples from an audio track and converts them to `AudioBuffer` instances. This is
 * often more useful than directly retrieving audio samples, as audio buffers can be directly used with the
 * Web Audio API.
 * @group Media sinks
 * @public
 */
class AudioBufferSink {
    /** Creates a new {@link AudioBufferSink} for the given {@link InputAudioTrack}. */
    constructor(audioTrack) {
        if (!(audioTrack instanceof InputAudioTrack)) {
            throw new TypeError('audioTrack must be an InputAudioTrack.');
        }
        this._audioSampleSink = new AudioSampleSink(audioTrack);
    }
    /** @internal */
    _audioSampleToWrappedArrayBuffer(sample) {
        const result = {
            buffer: sample.toAudioBuffer(),
            timestamp: sample.timestamp,
            duration: sample.duration,
        };
        sample.close();
        return result;
    }
    /**
     * Retrieves the audio buffer corresponding to the given timestamp, in seconds. More specifically, returns
     * the last audio buffer (in presentation order) with a start timestamp less than or equal to the given timestamp.
     * Returns null if the timestamp is before the track's first timestamp.
     *
     * @param timestamp - The timestamp used for retrieval, in seconds.
     * @param options - Options used for the underlying packet retrieval.
     */
    async getBuffer(timestamp, options) {
        validateTimestamp(timestamp);
        const data = await this._audioSampleSink.getSample(timestamp, options);
        return data && this._audioSampleToWrappedArrayBuffer(data);
    }
    /**
     * Creates an async iterator that yields audio buffers of this track in presentation order. This method
     * will intelligently pre-decode a few buffers ahead to enable fast iteration.
     *
     * @param startTimestamp - The timestamp in seconds at which to start yielding buffers (inclusive).
     * @param endTimestamp - The timestamp in seconds at which to stop yielding buffers (exclusive).
     * @param options - Options used for the underlying packet retrieval.
     */
    buffers(startTimestamp = 0, endTimestamp = Infinity, options) {
        return mapAsyncGenerator(this._audioSampleSink.samples(startTimestamp, endTimestamp, options), data => this._audioSampleToWrappedArrayBuffer(data));
    }
    /**
     * Creates an async iterator that yields an audio buffer for each timestamp in the argument. This method
     * uses an optimized decoding pipeline if these timestamps are monotonically sorted, decoding each packet at most
     * once, and is therefore more efficient than manually getting the buffer for every timestamp. The iterator may
     * yield null if no buffer is available for a given timestamp.
     *
     * @param timestamps - An iterable or async iterable of timestamps in seconds.
     * @param options - Options used for the underlying packet retrieval.
     */
    buffersAtTimestamps(timestamps, options) {
        return mapAsyncGenerator(this._audioSampleSink.samplesAtTimestamps(timestamps, options), data => data && this._audioSampleToWrappedArrayBuffer(data));
    }
}


/***/ },

/***/ 5165
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   VF: () => (/* binding */ AttachedFile),
/* harmony export */   gM: () => (/* binding */ DEFAULT_TRACK_DISPOSITION),
/* harmony export */   sF: () => (/* binding */ RichImageData)
/* harmony export */ });
/* unused harmony exports validateMetadataTags, metadataTagsAreEmpty, validateTrackDisposition */
/* unused harmony import specifier */ var isRecordStringString;
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

/**
 * Image data with additional metadata.
 *
 * @group Metadata tags
 * @public
 */
class RichImageData {
    /** Creates a new {@link RichImageData}. */
    constructor(
    /** The raw image data. */
    data, 
    /** An RFC 6838 MIME type (e.g. image/jpeg, image/png, etc.) */
    mimeType) {
        this.data = data;
        this.mimeType = mimeType;
        if (!(data instanceof Uint8Array)) {
            throw new TypeError('data must be a Uint8Array.');
        }
        if (typeof mimeType !== 'string') {
            throw new TypeError('mimeType must be a string.');
        }
    }
}
/**
 * A file attached to a media file.
 *
 * @group Metadata tags
 * @public
 */
class AttachedFile {
    /** Creates a new {@link AttachedFile}. */
    constructor(
    /** The raw file data. */
    data, 
    /** An RFC 6838 MIME type (e.g. image/jpeg, image/png, font/ttf, etc.) */
    mimeType, 
    /** The name of the file. */
    name, 
    /** A description of the file. */
    description) {
        this.data = data;
        this.mimeType = mimeType;
        this.name = name;
        this.description = description;
        if (!(data instanceof Uint8Array)) {
            throw new TypeError('data must be a Uint8Array.');
        }
        if (mimeType !== undefined && typeof mimeType !== 'string') {
            throw new TypeError('mimeType, when provided, must be a string.');
        }
        if (name !== undefined && typeof name !== 'string') {
            throw new TypeError('name, when provided, must be a string.');
        }
        if (description !== undefined && typeof description !== 'string') {
            throw new TypeError('description, when provided, must be a string.');
        }
    }
}
;
const validateMetadataTags = (tags) => {
    if (!tags || typeof tags !== 'object') {
        throw new TypeError('tags must be an object.');
    }
    if (tags.title !== undefined && typeof tags.title !== 'string') {
        throw new TypeError('tags.title, when provided, must be a string.');
    }
    if (tags.description !== undefined && typeof tags.description !== 'string') {
        throw new TypeError('tags.description, when provided, must be a string.');
    }
    if (tags.artist !== undefined && typeof tags.artist !== 'string') {
        throw new TypeError('tags.artist, when provided, must be a string.');
    }
    if (tags.album !== undefined && typeof tags.album !== 'string') {
        throw new TypeError('tags.album, when provided, must be a string.');
    }
    if (tags.albumArtist !== undefined && typeof tags.albumArtist !== 'string') {
        throw new TypeError('tags.albumArtist, when provided, must be a string.');
    }
    if (tags.trackNumber !== undefined && (!Number.isInteger(tags.trackNumber) || tags.trackNumber <= 0)) {
        throw new TypeError('tags.trackNumber, when provided, must be a positive integer.');
    }
    if (tags.tracksTotal !== undefined
        && (!Number.isInteger(tags.tracksTotal) || tags.tracksTotal <= 0)) {
        throw new TypeError('tags.tracksTotal, when provided, must be a positive integer.');
    }
    if (tags.discNumber !== undefined && (!Number.isInteger(tags.discNumber) || tags.discNumber <= 0)) {
        throw new TypeError('tags.discNumber, when provided, must be a positive integer.');
    }
    if (tags.discsTotal !== undefined
        && (!Number.isInteger(tags.discsTotal) || tags.discsTotal <= 0)) {
        throw new TypeError('tags.discsTotal, when provided, must be a positive integer.');
    }
    if (tags.genre !== undefined && typeof tags.genre !== 'string') {
        throw new TypeError('tags.genre, when provided, must be a string.');
    }
    if (tags.date !== undefined && (!(tags.date instanceof Date) || Number.isNaN(tags.date.getTime()))) {
        throw new TypeError('tags.date, when provided, must be a valid Date.');
    }
    if (tags.lyrics !== undefined && typeof tags.lyrics !== 'string') {
        throw new TypeError('tags.lyrics, when provided, must be a string.');
    }
    if (tags.images !== undefined) {
        if (!Array.isArray(tags.images)) {
            throw new TypeError('tags.images, when provided, must be an array.');
        }
        for (const image of tags.images) {
            if (!image || typeof image !== 'object') {
                throw new TypeError('Each image in tags.images must be an object.');
            }
            if (!(image.data instanceof Uint8Array)) {
                throw new TypeError('Each image.data must be a Uint8Array.');
            }
            if (typeof image.mimeType !== 'string') {
                throw new TypeError('Each image.mimeType must be a string.');
            }
            if (!['coverFront', 'coverBack', 'unknown'].includes(image.kind)) {
                throw new TypeError('Each image.kind must be \'coverFront\', \'coverBack\', or \'unknown\'.');
            }
        }
    }
    if (tags.comment !== undefined && typeof tags.comment !== 'string') {
        throw new TypeError('tags.comment, when provided, must be a string.');
    }
    if (tags.raw !== undefined) {
        if (!tags.raw || typeof tags.raw !== 'object') {
            throw new TypeError('tags.raw, when provided, must be an object.');
        }
        for (const value of Object.values(tags.raw)) {
            if (value !== null
                && typeof value !== 'string'
                && !(value instanceof Uint8Array)
                && !(value instanceof RichImageData)
                && !(value instanceof AttachedFile)
                && !isRecordStringString(value)) {
                throw new TypeError('Each value in tags.raw must be a string, Uint8Array, RichImageData, AttachedFile, '
                    + 'Record<string, string>, or null.');
            }
        }
    }
};
const metadataTagsAreEmpty = (tags) => {
    return tags.title === undefined
        && tags.description === undefined
        && tags.artist === undefined
        && tags.album === undefined
        && tags.albumArtist === undefined
        && tags.trackNumber === undefined
        && tags.tracksTotal === undefined
        && tags.discNumber === undefined
        && tags.discsTotal === undefined
        && tags.genre === undefined
        && tags.date === undefined
        && tags.lyrics === undefined
        && (!tags.images || tags.images.length === 0)
        && tags.comment === undefined
        && (tags.raw === undefined || Object.keys(tags.raw).length === 0);
};
const DEFAULT_TRACK_DISPOSITION = {
    default: true,
    primary: true,
    forced: false,
    original: false,
    commentary: false,
    hearingImpaired: false,
    visuallyImpaired: false,
};
const validateTrackDisposition = (disposition) => {
    if (!disposition || typeof disposition !== 'object') {
        throw new TypeError('disposition must be an object.');
    }
    if (disposition.default !== undefined && typeof disposition.default !== 'boolean') {
        throw new TypeError('disposition.default must be a boolean.');
    }
    if (disposition.primary !== undefined && typeof disposition.primary !== 'boolean') {
        throw new TypeError('disposition.primary must be a boolean.');
    }
    if (disposition.forced !== undefined && typeof disposition.forced !== 'boolean') {
        throw new TypeError('disposition.forced must be a boolean.');
    }
    if (disposition.original !== undefined && typeof disposition.original !== 'boolean') {
        throw new TypeError('disposition.original must be a boolean.');
    }
    if (disposition.commentary !== undefined && typeof disposition.commentary !== 'boolean') {
        throw new TypeError('disposition.commentary must be a boolean.');
    }
    if (disposition.hearingImpaired !== undefined && typeof disposition.hearingImpaired !== 'boolean') {
        throw new TypeError('disposition.hearingImpaired must be a boolean.');
    }
    if (disposition.visuallyImpaired !== undefined && typeof disposition.visuallyImpaired !== 'boolean') {
        throw new TypeError('disposition.visuallyImpaired must be a boolean.');
    }
};


/***/ },

/***/ 3912
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   Ai: () => (/* binding */ removeItem),
/* harmony export */   Au: () => (/* binding */ MATRIX_COEFFICIENTS_MAP),
/* harmony export */   BL: () => (/* binding */ COLOR_PRIMARIES_MAP_INVERSE),
/* harmony export */   Br: () => (/* binding */ bytesToHexString),
/* harmony export */   D5: () => (/* binding */ validateAnyIterable),
/* harmony export */   Et: () => (/* binding */ isNumber),
/* harmony export */   F2: () => (/* binding */ isChromium),
/* harmony export */   Fo: () => (/* binding */ toUint8Array),
/* harmony export */   G8: () => (/* binding */ retriedFetch),
/* harmony export */   HS: () => (/* binding */ joinPaths),
/* harmony export */   IP: () => (/* binding */ readExpGolomb),
/* harmony export */   IR: () => (/* binding */ UNDETERMINED_LANGUAGE),
/* harmony export */   Kl: () => (/* binding */ findLastIndex),
/* harmony export */   Kp: () => (/* binding */ base64ToBytes),
/* harmony export */   MF: () => (/* binding */ validateRectangle),
/* harmony export */   MW: () => (/* binding */ SECOND_TO_MICROSECOND_FACTOR),
/* harmony export */   Nu: () => (/* binding */ isIso639Dash2LanguageCode),
/* harmony export */   OO: () => (/* binding */ readSignedExpGolomb),
/* harmony export */   P5: () => (/* binding */ reverseBitsU32),
/* harmony export */   Q5: () => (/* binding */ floorToMultiple),
/* harmony export */   SM: () => (/* binding */ isAllowSharedBufferSource),
/* harmony export */   Sf: () => (/* binding */ coalesceIndex),
/* harmony export */   Sn: () => (/* binding */ HEX_STRING_REGEX),
/* harmony export */   Tc: () => (/* binding */ isWebKit),
/* harmony export */   Uk: () => (/* binding */ findLast),
/* harmony export */   Wh: () => (/* binding */ getInt24),
/* harmony export */   XQ: () => (/* binding */ polyfillSymbolDispose),
/* harmony export */   Yf: () => (/* binding */ simplifyRational),
/* harmony export */   Yg: () => (/* binding */ arrayArgmin),
/* harmony export */   ZY: () => (/* binding */ hexStringToBytes),
/* harmony export */   Zc: () => (/* binding */ toDataView),
/* harmony export */   _g: () => (/* binding */ last),
/* harmony export */   _h: () => (/* binding */ mergeRequestInit),
/* harmony export */   aD: () => (/* binding */ AsyncMutex),
/* harmony export */   aI: () => (/* binding */ roundIfAlmostInteger),
/* harmony export */   al: () => (/* binding */ ilog),
/* harmony export */   bk: () => (/* binding */ EventEmitter),
/* harmony export */   dY: () => (/* binding */ CallSerializer),
/* harmony export */   dq: () => (/* binding */ getUint24),
/* harmony export */   eE: () => (/* binding */ binarySearchLessOrEqual),
/* harmony export */   fl: () => (/* binding */ MATRIX_COEFFICIENTS_MAP_INVERSE),
/* harmony export */   gl: () => (/* binding */ roundToDivisor),
/* harmony export */   gm: () => (/* binding */ isFirefox),
/* harmony export */   h8: () => (/* binding */ insertSorted),
/* harmony export */   i1: () => (/* binding */ toAsyncIterator),
/* harmony export */   "in": () => (/* binding */ roundToMultiple),
/* harmony export */   jD: () => (/* binding */ setUint24),
/* harmony export */   ju: () => (/* binding */ uint8ArraysAreEqual),
/* harmony export */   nJ: () => (/* binding */ promiseWithResolvers),
/* harmony export */   oX: () => (/* binding */ closedIntervalsOverlap),
/* harmony export */   pl: () => (/* binding */ binarySearchExact),
/* harmony export */   qE: () => (/* binding */ clamp),
/* harmony export */   qT: () => (/* binding */ normalizeRotation),
/* harmony export */   su: () => (/* binding */ textDecoder),
/* harmony export */   uN: () => (/* binding */ TRANSFER_CHARACTERISTICS_MAP),
/* harmony export */   uk: () => (/* binding */ wait),
/* harmony export */   v$: () => (/* binding */ arrayCount),
/* harmony export */   vA: () => (/* binding */ assert),
/* harmony export */   wd: () => (/* binding */ COLOR_PRIMARIES_MAP),
/* harmony export */   x_: () => (/* binding */ TRANSFER_CHARACTERISTICS_MAP_INVERSE),
/* harmony export */   xb: () => (/* binding */ assertNever),
/* harmony export */   zp: () => (/* binding */ getChromiumVersion)
/* harmony export */ });
/* unused harmony exports isU32, writeBits, textEncoder, isIso88591Compatible, colorSpaceIsComplete, setInt24, setInt64, mapAsyncGenerator, floorToDivisor, computeRationalApproximation, keyValueIterator, imageMimeTypeToExtension, bytesToBase64, arrayArgmax, setTimeoutUnthrottled, clearTimeoutUnthrottled, setIntervalUnthrottled, clearIntervalUnthrottled, rejectAfter, toArray, ceilToMultipleOfTwo, ConcurrentRunner, isRecordStringString */
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
function assert(x) {
    if (!x) {
        throw new Error('Assertion failed.');
    }
}
const normalizeRotation = (rotation) => {
    const mappedRotation = (rotation % 360 + 360) % 360;
    if (mappedRotation === 0 || mappedRotation === 90 || mappedRotation === 180 || mappedRotation === 270) {
        return mappedRotation;
    }
    else {
        throw new Error(`Invalid rotation ${rotation}.`);
    }
};
const last = (arr) => {
    return arr && arr[arr.length - 1];
};
const isU32 = (value) => {
    return value >= 0 && value < 2 ** 32;
};
/** Reads an exponential-Golomb universal code from a Bitstream.  */
const readExpGolomb = (bitstream) => {
    let leadingZeroBits = 0;
    while (bitstream.readBits(1) === 0 && leadingZeroBits < 32) {
        leadingZeroBits++;
    }
    if (leadingZeroBits >= 32) {
        throw new Error('Invalid exponential-Golomb code.');
    }
    const result = (1 << leadingZeroBits) - 1 + bitstream.readBits(leadingZeroBits);
    return result;
};
/** Reads a signed exponential-Golomb universal code from a Bitstream. */
const readSignedExpGolomb = (bitstream) => {
    const codeNum = readExpGolomb(bitstream);
    return ((codeNum & 1) === 0)
        ? -(codeNum >> 1)
        : ((codeNum + 1) >> 1);
};
const writeBits = (bytes, start, end, value) => {
    for (let i = start; i < end; i++) {
        const byteIndex = Math.floor(i / 8);
        let byte = bytes[byteIndex];
        const bitIndex = 0b111 - (i & 0b111);
        byte &= ~(1 << bitIndex);
        byte |= ((value & (1 << (end - i - 1))) >> (end - i - 1)) << bitIndex;
        bytes[byteIndex] = byte;
    }
};
const toUint8Array = (source) => {
    if (source.constructor === Uint8Array) { // We want a true Uint8Array, not something that extends it like Buffer
        return source;
    }
    else if (ArrayBuffer.isView(source)) {
        return new Uint8Array(source.buffer, source.byteOffset, source.byteLength);
    }
    else {
        return new Uint8Array(source);
    }
};
const toDataView = (source) => {
    if (source.constructor === DataView) {
        return source;
    }
    else if (ArrayBuffer.isView(source)) {
        return new DataView(source.buffer, source.byteOffset, source.byteLength);
    }
    else {
        return new DataView(source);
    }
};
const textDecoder = /* #__PURE__ */ new TextDecoder();
const textEncoder = /* #__PURE__ */ new TextEncoder();
const isIso88591Compatible = (text) => {
    for (let i = 0; i < text.length; i++) {
        const code = text.charCodeAt(i);
        if (code > 255) {
            return false;
        }
    }
    return true;
};
const invertObject = (object) => {
    return Object.fromEntries(Object.entries(object).map(([key, value]) => [value, key]));
};
// For the color space mappings, see Rec. ITU-T H.273.
const COLOR_PRIMARIES_MAP = {
    bt709: 1, // ITU-R BT.709
    bt470bg: 5, // ITU-R BT.470BG
    smpte170m: 6, // ITU-R BT.601 525 - SMPTE 170M
    bt2020: 9, // ITU-R BT.202
    smpte432: 12, // SMPTE EG 432-1
};
const COLOR_PRIMARIES_MAP_INVERSE = /* #__PURE__ */ invertObject(COLOR_PRIMARIES_MAP);
const TRANSFER_CHARACTERISTICS_MAP = {
    'bt709': 1, // ITU-R BT.709
    'smpte170m': 6, // SMPTE 170M
    'linear': 8, // Linear transfer characteristics
    'iec61966-2-1': 13, // IEC 61966-2-1
    'pq': 16, // Rec. ITU-R BT.2100-2 perceptual quantization (PQ) system
    'hlg': 18, // Rec. ITU-R BT.2100-2 hybrid loggamma (HLG) system
};
const TRANSFER_CHARACTERISTICS_MAP_INVERSE = /* #__PURE__ */ invertObject(TRANSFER_CHARACTERISTICS_MAP);
const MATRIX_COEFFICIENTS_MAP = {
    'rgb': 0, // Identity
    'bt709': 1, // ITU-R BT.709
    'bt470bg': 5, // ITU-R BT.470BG
    'smpte170m': 6, // SMPTE 170M
    'bt2020-ncl': 9, // ITU-R BT.2020-2 (non-constant luminance)
};
const MATRIX_COEFFICIENTS_MAP_INVERSE = /* #__PURE__ */ invertObject(MATRIX_COEFFICIENTS_MAP);
const colorSpaceIsComplete = (colorSpace) => {
    return (!!colorSpace
        && !!colorSpace.primaries
        && !!colorSpace.transfer
        && !!colorSpace.matrix
        && colorSpace.fullRange !== undefined);
};
const isAllowSharedBufferSource = (x) => {
    return (x instanceof ArrayBuffer
        || (typeof SharedArrayBuffer !== 'undefined' && x instanceof SharedArrayBuffer)
        || ArrayBuffer.isView(x));
};
class AsyncMutex {
    constructor() {
        this.currentPromise = Promise.resolve();
        this.pending = 0;
    }
    async acquire() {
        let resolver;
        const nextPromise = new Promise((resolve) => {
            let resolved = false;
            resolver = () => {
                if (resolved) {
                    return;
                }
                resolve();
                this.pending--;
                resolved = true;
            };
        });
        const currentPromiseAlias = this.currentPromise;
        this.currentPromise = nextPromise;
        this.pending++;
        await currentPromiseAlias;
        return resolver;
    }
}
const HEX_STRING_REGEX = /^[0-9a-fA-F]+$/;
const bytesToHexString = (bytes) => {
    return [...bytes].map(x => x.toString(16).padStart(2, '0')).join('');
};
const hexStringToBytes = (hexString) => {
    assert(hexString.length % 2 === 0);
    const bytes = new Uint8Array(hexString.length / 2);
    for (let i = 0; i < hexString.length; i += 2) {
        bytes[i / 2] = parseInt(hexString.slice(i, i + 2), 16);
    }
    return bytes;
};
const reverseBitsU32 = (x) => {
    x = ((x >> 1) & 0x55555555) | ((x & 0x55555555) << 1);
    x = ((x >> 2) & 0x33333333) | ((x & 0x33333333) << 2);
    x = ((x >> 4) & 0x0f0f0f0f) | ((x & 0x0f0f0f0f) << 4);
    x = ((x >> 8) & 0x00ff00ff) | ((x & 0x00ff00ff) << 8);
    x = ((x >> 16) & 0x0000ffff) | ((x & 0x0000ffff) << 16);
    return x >>> 0; // Ensure it's treated as an unsigned 32-bit integer
};
/** Returns the smallest index i such that val[i] === key, or -1 if no such index exists. */
const binarySearchExact = (arr, key, valueGetter) => {
    let low = 0;
    let high = arr.length - 1;
    let ans = -1;
    while (low <= high) {
        const mid = (low + high) >> 1;
        const midVal = valueGetter(arr[mid]);
        if (midVal === key) {
            ans = mid;
            high = mid - 1; // Continue searching left to find the lowest index
        }
        else if (midVal < key) {
            low = mid + 1;
        }
        else {
            high = mid - 1;
        }
    }
    return ans;
};
/** Returns the largest index i such that val[i] <= key, or -1 if no such index exists. */
const binarySearchLessOrEqual = (arr, key, valueGetter) => {
    let low = 0;
    let high = arr.length - 1;
    let ans = -1;
    while (low <= high) {
        const mid = (low + (high - low + 1) / 2) | 0;
        const midVal = valueGetter(arr[mid]);
        if (midVal <= key) {
            ans = mid;
            low = mid + 1;
        }
        else {
            high = mid - 1;
        }
    }
    return ans;
};
/** Assumes the array is already sorted. */
const insertSorted = (arr, item, valueGetter) => {
    const insertionIndex = binarySearchLessOrEqual(arr, valueGetter(item), valueGetter);
    arr.splice(insertionIndex + 1, 0, item); // This even behaves correctly for the -1 case
};
const promiseWithResolvers = () => {
    let resolve;
    let reject;
    const promise = new Promise((res, rej) => {
        resolve = res;
        reject = rej;
    });
    return { promise, resolve: resolve, reject: reject };
};
const removeItem = (arr, item) => {
    const index = arr.indexOf(item);
    if (index !== -1) {
        arr.splice(index, 1);
    }
};
const findLast = (arr, predicate) => {
    for (let i = arr.length - 1; i >= 0; i--) {
        if (predicate(arr[i])) {
            return arr[i];
        }
    }
    return undefined;
};
const findLastIndex = (arr, predicate) => {
    for (let i = arr.length - 1; i >= 0; i--) {
        if (predicate(arr[i])) {
            return i;
        }
    }
    return -1;
};
const toAsyncIterator = async function* (source) {
    if (Symbol.iterator in source) {
        // @ts-expect-error Trust me
        yield* source[Symbol.iterator]();
    }
    else {
        // @ts-expect-error Trust me
        yield* source[Symbol.asyncIterator]();
    }
};
const validateAnyIterable = (iterable) => {
    if (!(Symbol.iterator in iterable) && !(Symbol.asyncIterator in iterable)) {
        throw new TypeError('Argument must be an iterable or async iterable.');
    }
};
const assertNever = (x) => {
    // eslint-disable-next-line @typescript-eslint/restrict-template-expressions
    throw new Error(`Unexpected value: ${x}`);
};
const getUint24 = (view, byteOffset, littleEndian) => {
    const byte1 = view.getUint8(byteOffset);
    const byte2 = view.getUint8(byteOffset + 1);
    const byte3 = view.getUint8(byteOffset + 2);
    if (littleEndian) {
        return byte1 | (byte2 << 8) | (byte3 << 16);
    }
    else {
        return (byte1 << 16) | (byte2 << 8) | byte3;
    }
};
const getInt24 = (view, byteOffset, littleEndian) => {
    // The left shift pushes the most significant bit into the sign bit region, and the subsequent right shift
    // then correctly interprets the sign bit.
    return getUint24(view, byteOffset, littleEndian) << 8 >> 8;
};
const setUint24 = (view, byteOffset, value, littleEndian) => {
    // Ensure the value is within 24-bit unsigned range (0 to 16777215)
    value = value >>> 0; // Convert to unsigned 32-bit
    value = value & 0xFFFFFF; // Mask to 24 bits
    if (littleEndian) {
        view.setUint8(byteOffset, value & 0xFF);
        view.setUint8(byteOffset + 1, (value >>> 8) & 0xFF);
        view.setUint8(byteOffset + 2, (value >>> 16) & 0xFF);
    }
    else {
        view.setUint8(byteOffset, (value >>> 16) & 0xFF);
        view.setUint8(byteOffset + 1, (value >>> 8) & 0xFF);
        view.setUint8(byteOffset + 2, value & 0xFF);
    }
};
const setInt24 = (view, byteOffset, value, littleEndian) => {
    // Ensure the value is within 24-bit signed range (-8388608 to 8388607)
    value = clamp(value, -8388608, 8388607);
    // Convert negative values to their 24-bit representation
    if (value < 0) {
        value = (value + 0x1000000) & 0xFFFFFF;
    }
    setUint24(view, byteOffset, value, littleEndian);
};
const setInt64 = (view, byteOffset, value, littleEndian) => {
    if (littleEndian) {
        view.setUint32(byteOffset + 0, value, true);
        view.setInt32(byteOffset + 4, Math.floor(value / 2 ** 32), true);
    }
    else {
        view.setInt32(byteOffset + 0, Math.floor(value / 2 ** 32), true);
        view.setUint32(byteOffset + 4, value, true);
    }
};
/**
 * Calls a function on each value spat out by an async generator. The reason for writing this manually instead of
 * using a generator function is that the generator function queues return() calls - here, we forward them immediately.
 */
const mapAsyncGenerator = (generator, map) => {
    return {
        async next() {
            const result = await generator.next();
            if (result.done) {
                return { value: undefined, done: true };
            }
            else {
                return { value: map(result.value), done: false };
            }
        },
        return() {
            return generator.return();
        },
        throw(error) {
            return generator.throw(error);
        },
        [Symbol.asyncIterator]() {
            return this;
        },
    };
};
const clamp = (value, min, max) => {
    return Math.max(min, Math.min(max, value));
};
const UNDETERMINED_LANGUAGE = 'und';
const roundIfAlmostInteger = (value) => {
    const rounded = Math.round(value);
    if (Math.abs(value / rounded - 1) < 10 * Number.EPSILON) {
        return rounded;
    }
    else {
        return value;
    }
};
const roundToMultiple = (value, multiple) => {
    return Math.round(value / multiple) * multiple;
};
const roundToDivisor = (value, multiple) => {
    return Math.round(value * multiple) / multiple;
};
const floorToMultiple = (value, multiple) => {
    return Math.floor(value / multiple) * multiple;
};
const floorToDivisor = (value, multiple) => {
    return Math.floor(value * multiple) / multiple;
};
const ilog = (x) => {
    let ret = 0;
    while (x) {
        ret++;
        x >>= 1;
    }
    return ret;
};
const ISO_639_2_REGEX = /^[a-z]{3}$/;
const isIso639Dash2LanguageCode = (x) => {
    return ISO_639_2_REGEX.test(x);
};
// Since the result will be truncated, add a bit of eps to compensate for floating point errors
const SECOND_TO_MICROSECOND_FACTOR = 1e6 * (1 + Number.EPSILON);
/**
 * Merges two RequestInit objects with special handling for headers.
 * Headers are merged case-insensitively, but original casing is preserved.
 * init2 headers take precedence and will override case-insensitive matches from init1.
 */
const mergeRequestInit = (init1, init2) => {
    const merged = { ...init1, ...init2 };
    // Special handling for headers
    if (init1.headers || init2.headers) {
        const headers1 = init1.headers ? normalizeHeaders(init1.headers) : {};
        const headers2 = init2.headers ? normalizeHeaders(init2.headers) : {};
        const mergedHeaders = { ...headers1 };
        // For each header in headers2, check if a case-insensitive match exists in mergedHeaders
        Object.entries(headers2).forEach(([key2, value2]) => {
            const existingKey = Object.keys(mergedHeaders).find(key1 => key1.toLowerCase() === key2.toLowerCase());
            if (existingKey) {
                delete mergedHeaders[existingKey];
            }
            mergedHeaders[key2] = value2;
        });
        merged.headers = mergedHeaders;
    }
    return merged;
};
/** Normalizes HeadersInit to a Record<string, string> format. */
const normalizeHeaders = (headers) => {
    if (headers instanceof Headers) {
        const result = {};
        headers.forEach((value, key) => {
            result[key] = value;
        });
        return result;
    }
    if (Array.isArray(headers)) {
        const result = {};
        headers.forEach(([key, value]) => {
            result[key] = value;
        });
        return result;
    }
    return headers;
};
const retriedFetch = async (fetchFn, url, requestInit, getRetryDelay, shouldStop) => {
    let attempts = 0;
    while (true) {
        try {
            return await fetchFn(url, requestInit);
        }
        catch (error) {
            if (shouldStop()) {
                throw error;
            }
            attempts++;
            const retryDelayInSeconds = getRetryDelay(attempts, error, url);
            if (retryDelayInSeconds === null) {
                throw error;
            }
            console.error('Retrying failed fetch. Error:', error);
            if (!Number.isFinite(retryDelayInSeconds) || retryDelayInSeconds < 0) {
                throw new TypeError('Retry delay must be a non-negative finite number.');
            }
            if (retryDelayInSeconds > 0) {
                await wait(1000 * retryDelayInSeconds);
            }
            if (shouldStop()) {
                throw error;
            }
        }
    }
};
const computeRationalApproximation = (x, maxDenominator) => {
    // Handle negative numbers
    const sign = x < 0 ? -1 : 1;
    x = Math.abs(x);
    let prevNumerator = 0, prevDenominator = 1;
    let currNumerator = 1, currDenominator = 0;
    // Continued fraction algorithm
    let remainder = x;
    while (true) {
        const integer = Math.floor(remainder);
        // Calculate next convergent
        const nextNumerator = integer * currNumerator + prevNumerator;
        const nextDenominator = integer * currDenominator + prevDenominator;
        if (nextDenominator > maxDenominator) {
            return {
                numerator: sign * currNumerator,
                denominator: currDenominator,
            };
        }
        prevNumerator = currNumerator;
        prevDenominator = currDenominator;
        currNumerator = nextNumerator;
        currDenominator = nextDenominator;
        remainder = 1 / (remainder - integer);
        // Guard against precision issues
        if (!isFinite(remainder)) {
            break;
        }
    }
    return {
        numerator: sign * currNumerator,
        denominator: currDenominator,
    };
};
class CallSerializer {
    constructor() {
        this.currentPromise = Promise.resolve();
    }
    call(fn) {
        return this.currentPromise = this.currentPromise.then(fn);
    }
}
let isWebKitCache = null;
const isWebKit = () => {
    if (isWebKitCache !== null) {
        return isWebKitCache;
    }
    // This even returns true for WebKit-wrapping browsers such as Chrome on iOS
    return isWebKitCache = !!(typeof navigator !== 'undefined'
        && (
        // eslint-disable-next-line @typescript-eslint/no-deprecated
        navigator.vendor?.match(/apple/i)
            // Or, in workers:
            || (/AppleWebKit/.test(navigator.userAgent) && !/Chrome/.test(navigator.userAgent))
            || /\b(iPad|iPhone|iPod)\b/.test(navigator.userAgent)));
};
let isFirefoxCache = null;
const isFirefox = () => {
    if (isFirefoxCache !== null) {
        return isFirefoxCache;
    }
    return isFirefoxCache = typeof navigator !== 'undefined' && navigator.userAgent?.includes('Firefox');
};
let isChromiumCache = null;
const isChromium = () => {
    if (isChromiumCache !== null) {
        return isChromiumCache;
    }
    return isChromiumCache = !!(typeof navigator !== 'undefined'
        // eslint-disable-next-line @typescript-eslint/no-deprecated
        && (navigator.vendor?.includes('Google Inc') || /Chrome/.test(navigator.userAgent)));
};
let chromiumVersionCache = null;
const getChromiumVersion = () => {
    if (chromiumVersionCache !== null) {
        return chromiumVersionCache;
    }
    if (typeof navigator === 'undefined') {
        return null;
    }
    const match = /\bChrome\/(\d+)/.exec(navigator.userAgent);
    if (!match) {
        return null;
    }
    return chromiumVersionCache = Number(match[1]);
};
/** Acts like `??` except the condition is -1 and not null/undefined. */
const coalesceIndex = (a, b) => {
    return a !== -1 ? a : b;
};
const closedIntervalsOverlap = (startA, endA, startB, endB) => {
    return startA <= endB && startB <= endA;
};
const keyValueIterator = function* (object) {
    for (const key in object) {
        const value = object[key];
        if (value === undefined) {
            continue;
        }
        yield { key, value };
    }
};
const imageMimeTypeToExtension = (mimeType) => {
    switch (mimeType.toLowerCase()) {
        case 'image/jpeg':
        case 'image/jpg':
            return '.jpg';
        case 'image/png':
            return '.png';
        case 'image/gif':
            return '.gif';
        case 'image/webp':
            return '.webp';
        case 'image/bmp':
            return '.bmp';
        case 'image/svg+xml':
            return '.svg';
        case 'image/tiff':
            return '.tiff';
        case 'image/avif':
            return '.avif';
        case 'image/x-icon':
        case 'image/vnd.microsoft.icon':
            return '.ico';
        default:
            return null;
    }
};
const base64ToBytes = (base64) => {
    const decoded = atob(base64);
    const bytes = new Uint8Array(decoded.length);
    for (let i = 0; i < decoded.length; i++) {
        bytes[i] = decoded.charCodeAt(i);
    }
    return bytes;
};
const bytesToBase64 = (bytes) => {
    let string = '';
    for (let i = 0; i < bytes.length; i++) {
        string += String.fromCharCode(bytes[i]);
    }
    return btoa(string);
};
const uint8ArraysAreEqual = (a, b) => {
    if (a.length !== b.length) {
        return false;
    }
    for (let i = 0; i < a.length; i++) {
        if (a[i] !== b[i]) {
            return false;
        }
    }
    return true;
};
const polyfillSymbolDispose = () => {
    // https://www.typescriptlang.org/docs/handbook/release-notes/typescript-5-2.html
    // @ts-expect-error Readonly
    Symbol.dispose ??= Symbol('Symbol.dispose');
};
const isNumber = (x) => {
    return typeof x === 'number' && !Number.isNaN(x);
};
const joinPaths = (basePath, relativePath) => {
    // If relativePath is a full URL with protocol, return it as-is
    if (relativePath.includes('://')) {
        return relativePath;
    }
    // Strip query parameters from URL base paths so their contents don't mess up the join
    if (basePath.includes('://')) {
        const queryIndex = basePath.indexOf('?');
        if (queryIndex !== -1) {
            basePath = basePath.slice(0, queryIndex);
        }
    }
    let result;
    if (relativePath.startsWith('/')) {
        const protocolIndex = basePath.indexOf('://');
        if (protocolIndex === -1) {
            result = relativePath;
        }
        else {
            const pathStart = basePath.indexOf('/', protocolIndex + 3);
            if (pathStart === -1) {
                result = basePath + relativePath;
            }
            else {
                result = basePath.slice(0, pathStart) + relativePath;
            }
        }
    }
    else {
        const lastSlash = basePath.lastIndexOf('/');
        if (lastSlash === -1) {
            result = relativePath;
        }
        else {
            result = basePath.slice(0, lastSlash + 1) + relativePath;
        }
    }
    // Normalize ./ and ../
    let prefix = '';
    const protocolIndex = result.indexOf('://');
    if (protocolIndex !== -1) {
        const pathStart = result.indexOf('/', protocolIndex + 3);
        if (pathStart !== -1) {
            prefix = result.slice(0, pathStart);
            result = result.slice(pathStart);
        }
    }
    const segments = result.split('/');
    const normalized = [];
    for (const segment of segments) {
        if (segment === '..') {
            normalized.pop();
        }
        else if (segment !== '.') {
            normalized.push(segment);
        }
    }
    return prefix + normalized.join('/');
};
const arrayCount = (array, predicate) => {
    let count = 0;
    for (let i = 0; i < array.length; i++) {
        if (predicate(array[i])) {
            count++;
        }
    }
    return count;
};
const arrayArgmin = (array, getValue) => {
    let minIndex = -1;
    let minValue = Infinity;
    for (let i = 0; i < array.length; i++) {
        const value = getValue(array[i]);
        if (value < minValue) {
            minValue = value;
            minIndex = i;
        }
    }
    return minIndex;
};
const arrayArgmax = (array, getValue) => {
    let maxIndex = -1;
    let maxValue = -Infinity;
    for (let i = 0; i < array.length; i++) {
        const value = getValue(array[i]);
        if (value > maxValue) {
            maxValue = value;
            maxIndex = i;
        }
    }
    return maxIndex;
};
const simplifyRational = (rational) => {
    assert(rational.den !== 0);
    let a = Math.abs(rational.num);
    let b = Math.abs(rational.den);
    // Euclidean algorithm
    while (b !== 0) {
        const t = a % b;
        a = b;
        b = t;
    }
    const gcd = a || 1;
    return {
        num: rational.num / gcd,
        den: rational.den / gcd,
    };
};
const validateRectangle = (rect, propertyPath) => {
    if (typeof rect !== 'object' || !rect) {
        throw new TypeError(`${propertyPath} must be an object.`);
    }
    if (!Number.isInteger(rect.left) || rect.left < 0) {
        throw new TypeError(`${propertyPath}.left must be a non-negative integer.`);
    }
    if (!Number.isInteger(rect.top) || rect.top < 0) {
        throw new TypeError(`${propertyPath}.top must be a non-negative integer.`);
    }
    if (!Number.isInteger(rect.width) || rect.width < 0) {
        throw new TypeError(`${propertyPath}.width must be a non-negative integer.`);
    }
    if (!Number.isInteger(rect.height) || rect.height < 0) {
        throw new TypeError(`${propertyPath}.height must be a non-negative integer.`);
    }
};
let unthrottledTimerWorker;
let nextUnthrottledTimerId = 1;
const unthrottledTimeoutCallbacks = new Map();
const unthrottledIntervalCallbacks = new Map();
const shouldUseNativeTimers = () => {
    return typeof window === 'undefined';
};
const unthrottledTimerWorkerMain = () => {
    const timeoutHandles = new Map();
    const intervalHandles = new Map();
    self.onmessage = (event) => {
        const message = event.data;
        switch (message.type) {
            case 'set-timeout':
                {
                    const handle = setTimeout(() => {
                        timeoutHandles.delete(message.timerId);
                        self.postMessage({ type: 'fire', timerId: message.timerId });
                    }, message.delay);
                    timeoutHandles.set(message.timerId, handle);
                }
                ;
                break;
            case 'set-interval':
                {
                    const handle = setInterval(() => {
                        self.postMessage({ type: 'fire', timerId: message.timerId });
                    }, message.delay);
                    intervalHandles.set(message.timerId, handle);
                }
                ;
                break;
            case 'clear-timeout':
                {
                    const handle = timeoutHandles.get(message.timerId);
                    if (handle !== undefined) {
                        clearTimeout(handle);
                        timeoutHandles.delete(message.timerId);
                    }
                }
                ;
                break;
            case 'clear-interval':
                {
                    const handle = intervalHandles.get(message.timerId);
                    if (handle !== undefined) {
                        clearInterval(handle);
                        intervalHandles.delete(message.timerId);
                    }
                }
                ;
                break;
        }
    };
};
const getUnthrottledTimerWorker = () => {
    if (unthrottledTimerWorker) {
        return unthrottledTimerWorker;
    }
    const workerSource = `(${unthrottledTimerWorkerMain.toString()})();`;
    const workerURL = URL.createObjectURL(new Blob([workerSource], { type: 'text/javascript' }));
    unthrottledTimerWorker = new Worker(workerURL);
    URL.revokeObjectURL(workerURL);
    unthrottledTimerWorker.onmessage = (event) => {
        const message = event.data;
        const timeoutCallback = unthrottledTimeoutCallbacks.get(message.timerId);
        if (timeoutCallback) {
            unthrottledTimeoutCallbacks.delete(message.timerId);
            timeoutCallback();
            return;
        }
        const intervalCallback = unthrottledIntervalCallbacks.get(message.timerId);
        if (intervalCallback) {
            intervalCallback();
        }
    };
    return unthrottledTimerWorker;
};
const setTimeoutUnthrottled = (
// eslint-disable-next-line @typescript-eslint/no-unsafe-function-type
callback, delay) => {
    if (shouldUseNativeTimers()) {
        return { id: setTimeout(callback, delay) };
    }
    const timerId = nextUnthrottledTimerId++;
    unthrottledTimeoutCallbacks.set(timerId, () => {
        callback();
    });
    getUnthrottledTimerWorker().postMessage({
        type: 'set-timeout',
        timerId,
        delay,
    });
    return { id: timerId };
};
const clearTimeoutUnthrottled = (timer) => {
    if (shouldUseNativeTimers()) {
        clearTimeout(timer.id);
        return;
    }
    assert(typeof timer.id === 'number');
    unthrottledTimeoutCallbacks.delete(timer.id);
    getUnthrottledTimerWorker().postMessage({
        type: 'clear-timeout',
        timerId: timer.id,
    });
};
const setIntervalUnthrottled = (
// eslint-disable-next-line @typescript-eslint/no-unsafe-function-type
callback, delay) => {
    if (shouldUseNativeTimers()) {
        return { id: setInterval(callback, delay) };
    }
    const timerId = nextUnthrottledTimerId++;
    unthrottledIntervalCallbacks.set(timerId, () => {
        callback();
    });
    getUnthrottledTimerWorker().postMessage({
        type: 'set-interval',
        timerId,
        delay,
    });
    return { id: timerId };
};
const clearIntervalUnthrottled = (timer) => {
    if (shouldUseNativeTimers()) {
        clearInterval(timer.id);
        return;
    }
    assert(typeof timer.id === 'number');
    unthrottledIntervalCallbacks.delete(timer.id);
    getUnthrottledTimerWorker().postMessage({
        type: 'clear-interval',
        timerId: timer.id,
    });
};
const wait = (ms) => {
    return new Promise(resolve => setTimeout(resolve, ms));
};
const rejectAfter = (ms, message = 'Promise rejected') => {
    return new Promise((_, reject) => {
        setTimeout(() => reject(new Error(message)), ms);
    });
};
const toArray = (x) => {
    if (Array.isArray(x)) {
        return x;
    }
    else {
        return [x];
    }
};
/**
 * A class that manages event listeners and dispatches events to them.
 *
 * @group Miscellaneous
 * @public
 */
class EventEmitter {
    constructor() {
        /** @internal */
        this._listeners = new Map();
    }
    /** Registers a listener for the given event. */
    on(event, listener, options) {
        if (!this._listeners.has(event)) {
            this._listeners.set(event, new Set());
        }
        const entry = { fn: listener, once: options?.once ?? false };
        this._listeners.get(event).add(entry);
        return () => {
            this._listeners.get(event)?.delete(entry);
        };
    }
    /** @internal */
    _emit(...args) {
        const [event, data] = args;
        const listeners = this._listeners.get(event);
        if (!listeners) {
            return;
        }
        for (const entry of listeners) {
            try {
                entry.fn(data);
            }
            catch (error) {
                console.error(error);
            }
            if (entry.once) {
                listeners.delete(entry);
            }
        }
    }
}
const ceilToMultipleOfTwo = (value) => Math.ceil(value / 2) * 2;
/**
 * Utility class for running async functions in parallel up to a certain level of parallelism. Can be used to apply
 * backpressure only if the concurrency level would be exceeded.
 *
 * @group Miscellaneous
 * @public
*/
class ConcurrentRunner {
    constructor(parallelism) {
        /** @internal */
        this._queue = [];
        /** @internal */
        this._errored = false;
        this.parallelism = parallelism;
    }
    /** Whether any function has errored. The runner is effectively bricked if this is `true`, by design. */
    get errored() {
        return this._errored;
    }
    /** The number of tasks currently running. */
    get inFlightCount() {
        return this._queue.length;
    }
    /**
     * Schedules an async function to be run. If the maximum allowed level of parallelism has not yet been reached,
     * the function will be executed immediately and `run()` will resolve immediately. Otherwise, the function will be
     * called as soon as any currently-running function finishes, and `run()` will only resolve then.
     *
     * Throws if the runner is errored.
     */
    async run(fn) {
        if (this._errored) {
            await Promise.race(this._queue); // Will surface the error
        }
        while (this._queue.length >= this.parallelism) {
            await Promise.race(this._queue);
        }
        const promise = fn();
        this._queue.push(promise);
        void promise
            .then(() => removeItem(this._queue, promise))
            .catch(() => this._errored = true);
    }
    /** Waits for all currently running functions to finish. Throws if the runner is errored. */
    async flush() {
        await Promise.all(this._queue);
    }
}
const isRecordStringString = (value) => {
    return value !== null
        && typeof value === 'object'
        && Object.getPrototypeOf(value) === Object.prototype
        && Object.values(value).every(x => typeof x === 'string');
};


/***/ },

/***/ 358
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   aw: () => (/* binding */ fromAlaw),
/* harmony export */   qS: () => (/* binding */ fromUlaw)
/* harmony export */ });
/* unused harmony exports toUlaw, toAlaw */
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
// https://github.com/dystopiancode/pcm-g711/blob/master/pcm-g711/g711.c
const toUlaw = (s16) => {
    const MULAW_MAX = 0x1FFF;
    const MULAW_BIAS = 33;
    let number = s16;
    let mask = 0x1000;
    let sign = 0;
    let position = 12;
    let lsb = 0;
    if (number < 0) {
        number = -number;
        sign = 0x80;
    }
    number += MULAW_BIAS;
    if (number > MULAW_MAX) {
        number = MULAW_MAX;
    }
    while ((number & mask) !== mask && position >= 5) {
        mask >>= 1;
        position--;
    }
    lsb = (number >> (position - 4)) & 0x0f;
    return ~(sign | ((position - 5) << 4) | lsb) & 0xFF;
};
const fromUlaw = (u8) => {
    const MULAW_BIAS = 33;
    let sign = 0;
    let position = 0;
    let number = ~u8;
    if (number & 0x80) {
        number &= ~(1 << 7);
        sign = -1;
    }
    position = ((number & 0xF0) >> 4) + 5;
    const decoded = ((1 << position) | ((number & 0x0F) << (position - 4))
        | (1 << (position - 5))) - MULAW_BIAS;
    return (sign === 0) ? decoded : -decoded;
};
const toAlaw = (s16) => {
    const ALAW_MAX = 0xFFF;
    let mask = 0x800;
    let sign = 0;
    let position = 11;
    let lsb = 0;
    let number = s16;
    if (number < 0) {
        number = -number;
        sign = 0x80;
    }
    if (number > ALAW_MAX) {
        number = ALAW_MAX;
    }
    while ((number & mask) !== mask && position >= 5) {
        mask >>= 1;
        position--;
    }
    lsb = (number >> ((position === 4) ? 1 : (position - 4))) & 0x0f;
    return (sign | ((position - 4) << 4) | lsb) ^ 0x55;
};
const fromAlaw = (u8) => {
    let sign = 0x00;
    let position = 0;
    let number = u8 ^ 0x55;
    if (number & 0x80) {
        number &= ~(1 << 7);
        sign = -1;
    }
    position = ((number & 0xF0) >> 4) + 4;
    let decoded = 0;
    if (position !== 4) {
        decoded = ((1 << position) | ((number & 0x0F) << (position - 4))
            | (1 << (position - 5)));
    }
    else {
        decoded = (number << 1) | 1;
    }
    return (sign === 0) ? decoded : -decoded;
};


/***/ },

/***/ 4166
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   B1: () => (/* binding */ AudioSample),
/* harmony export */   U2: () => (/* binding */ VideoSample)
/* harmony export */ });
/* unused harmony exports VIDEO_SAMPLE_PIXEL_FORMATS, VideoSampleColorSpace, clampCropRectangle, validateCropRectangle */
/* harmony import */ var _misc_js__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(3912);
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

(0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .polyfillSymbolDispose */ .XQ)();
// Let's manually handle logging the garbage collection errors that are typically logged by the browser. This way, they
// also kick for audio samples (which is normally not the case), making sure any incorrect code is quickly caught.
let lastVideoGcErrorLog = -Infinity;
let lastAudioGcErrorLog = -Infinity;
let finalizationRegistry = null;
if (typeof FinalizationRegistry !== 'undefined') {
    finalizationRegistry = new FinalizationRegistry((value) => {
        const now = performance.now();
        if (value.type === 'video') {
            if (now - lastVideoGcErrorLog >= 1000) {
                // This error is annoying but oh so important
                console.error(`A VideoSample was garbage collected without first being closed. For proper resource management,`
                    + ` make sure to call close() on all your VideoSamples as soon as you're done using them.`);
                lastVideoGcErrorLog = now;
            }
            if (typeof VideoFrame !== 'undefined' && value.data instanceof VideoFrame) {
                value.data.close(); // Prevent the browser error since we're logging our own
            }
        }
        else {
            if (now - lastAudioGcErrorLog >= 1000) {
                console.error(`An AudioSample was garbage collected without first being closed. For proper resource management,`
                    + ` make sure to call close() on all your AudioSamples as soon as you're done using them.`);
                lastAudioGcErrorLog = now;
            }
            if (typeof AudioData !== 'undefined' && value.data instanceof AudioData) {
                value.data.close();
            }
        }
    });
}
/**
 * The list of {@link VideoSample} pixel formats.
 * @group Samples
 * @public
 */
const VIDEO_SAMPLE_PIXEL_FORMATS = [
    // 4:2:0 Y, U, V
    'I420',
    'I420P10',
    'I420P12',
    // 4:2:0 Y, U, V, A
    'I420A',
    'I420AP10',
    'I420AP12',
    // 4:2:2 Y, U, V
    'I422',
    'I422P10',
    'I422P12',
    // 4:2:2 Y, U, V, A
    'I422A',
    'I422AP10',
    'I422AP12',
    // 4:4:4 Y, U, V
    'I444',
    'I444P10',
    'I444P12',
    // 4:4:4 Y, U, V, A
    'I444A',
    'I444AP10',
    'I444AP12',
    // 4:2:0 Y, UV
    'NV12',
    // 4:4:4 RGBA
    'RGBA',
    // 4:4:4 RGBX (opaque)
    'RGBX',
    // 4:4:4 BGRA
    'BGRA',
    // 4:4:4 BGRX (opaque)
    'BGRX',
];
const VIDEO_SAMPLE_PIXEL_FORMATS_SET = new Set(VIDEO_SAMPLE_PIXEL_FORMATS);
/**
 * Represents a raw, unencoded video sample (frame). Mainly used as an expressive wrapper around WebCodecs API's
 * [`VideoFrame`](https://developer.mozilla.org/en-US/docs/Web/API/VideoFrame), but can also be used standalone.
 * @group Samples
 * @public
 */
class VideoSample {
    /** The width of the frame in pixels. */
    get codedWidth() {
        // This is wrong, but the fix is a v2 thing
        return this.visibleRect.width;
    }
    /** The height of the frame in pixels. */
    get codedHeight() {
        // Same here
        return this.visibleRect.height;
    }
    /** The display width of the frame in pixels, after aspect ratio adjustment and rotation. */
    get displayWidth() {
        return this.rotation % 180 === 0 ? this.squarePixelWidth : this.squarePixelHeight;
    }
    /** The display height of the frame in pixels, after aspect ratio adjustment and rotation. */
    get displayHeight() {
        return this.rotation % 180 === 0 ? this.squarePixelHeight : this.squarePixelWidth;
    }
    /** The presentation timestamp of the frame in microseconds. */
    get microsecondTimestamp() {
        return Math.trunc(_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .SECOND_TO_MICROSECOND_FACTOR */ .MW * this.timestamp);
    }
    /** The duration of the frame in microseconds. */
    get microsecondDuration() {
        return Math.trunc(_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .SECOND_TO_MICROSECOND_FACTOR */ .MW * this.duration);
    }
    /**
     * Whether this sample uses a pixel format that can hold transparency data. Note that this doesn't necessarily mean
     * that the sample is transparent.
     */
    get hasAlpha() {
        return this.format && this.format.includes('A');
    }
    constructor(data, init) {
        /** @internal */
        this._closed = false;
        if (data instanceof ArrayBuffer
            || (typeof SharedArrayBuffer !== 'undefined' && data instanceof SharedArrayBuffer)
            || ArrayBuffer.isView(data)) {
            if (!init || typeof init !== 'object') {
                throw new TypeError('init must be an object.');
            }
            if (init.format === undefined || !VIDEO_SAMPLE_PIXEL_FORMATS_SET.has(init.format)) {
                throw new TypeError('init.format must be one of: ' + VIDEO_SAMPLE_PIXEL_FORMATS.join(', '));
            }
            if (!Number.isInteger(init.codedWidth) || init.codedWidth <= 0) {
                throw new TypeError('init.codedWidth must be a positive integer.');
            }
            if (!Number.isInteger(init.codedHeight) || init.codedHeight <= 0) {
                throw new TypeError('init.codedHeight must be a positive integer.');
            }
            if (init.rotation !== undefined && ![0, 90, 180, 270].includes(init.rotation)) {
                throw new TypeError('init.rotation, when provided, must be 0, 90, 180, or 270.');
            }
            if (!Number.isFinite(init.timestamp)) {
                throw new TypeError('init.timestamp must be a number.');
            }
            if (init.duration !== undefined && (!Number.isFinite(init.duration) || init.duration < 0)) {
                throw new TypeError('init.duration, when provided, must be a non-negative number.');
            }
            if (init.layout !== undefined) {
                if (!Array.isArray(init.layout)) {
                    throw new TypeError('init.layout, when provided, must be an array.');
                }
                for (const plane of init.layout) {
                    if (!plane || typeof plane !== 'object' || Array.isArray(plane)) {
                        throw new TypeError('Each entry in init.layout must be an object.');
                    }
                    if (!Number.isInteger(plane.offset) || plane.offset < 0) {
                        throw new TypeError('plane.offset must be a non-negative integer.');
                    }
                    if (!Number.isInteger(plane.stride) || plane.stride < 0) {
                        throw new TypeError('plane.stride must be a non-negative integer.');
                    }
                }
            }
            if (init.visibleRect !== undefined) {
                (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .validateRectangle */ .MF)(init.visibleRect, 'init.visibleRect');
            }
            if (init.displayWidth !== undefined
                && (!Number.isInteger(init.displayWidth) || init.displayWidth <= 0)) {
                throw new TypeError('init.displayWidth, when provided, must be a positive integer.');
            }
            if (init.displayHeight !== undefined
                && (!Number.isInteger(init.displayHeight) || init.displayHeight <= 0)) {
                throw new TypeError('init.displayHeight, when provided, must be a positive integer.');
            }
            if ((init.displayWidth !== undefined) !== (init.displayHeight !== undefined)) {
                throw new TypeError('init.displayWidth and init.displayHeight must be either both provided or both omitted.');
            }
            this._data = (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .toUint8Array */ .Fo)(data).slice(); // Copy it
            this._layout = init.layout ?? createDefaultPlaneLayout(init.format, init.codedWidth, init.codedHeight);
            this.format = init.format;
            this.rotation = init.rotation ?? 0;
            this.timestamp = init.timestamp;
            this.duration = init.duration ?? 0;
            this.colorSpace = new VideoSampleColorSpace(init.colorSpace);
            this.visibleRect = {
                left: init.visibleRect?.left ?? 0,
                top: init.visibleRect?.top ?? 0,
                width: init.visibleRect?.width ?? init.codedWidth,
                height: init.visibleRect?.height ?? init.codedHeight,
            };
            if (init.displayWidth !== undefined) {
                this.squarePixelWidth = this.rotation % 180 === 0 ? init.displayWidth : init.displayHeight;
                this.squarePixelHeight = this.rotation % 180 === 0 ? init.displayHeight : init.displayWidth;
            }
            else {
                this.squarePixelWidth = this.codedWidth;
                this.squarePixelHeight = this.codedHeight;
            }
        }
        else if (typeof VideoFrame !== 'undefined' && data instanceof VideoFrame) {
            if (init?.rotation !== undefined && ![0, 90, 180, 270].includes(init.rotation)) {
                throw new TypeError('init.rotation, when provided, must be 0, 90, 180, or 270.');
            }
            if (init?.timestamp !== undefined && !Number.isFinite(init?.timestamp)) {
                throw new TypeError('init.timestamp, when provided, must be a number.');
            }
            if (init?.duration !== undefined && (!Number.isFinite(init.duration) || init.duration < 0)) {
                throw new TypeError('init.duration, when provided, must be a non-negative number.');
            }
            if (init?.visibleRect !== undefined) {
                (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .validateRectangle */ .MF)(init.visibleRect, 'init.visibleRect');
            }
            this._data = data;
            this._layout = null;
            this.format = data.format;
            this.visibleRect = {
                left: data.visibleRect?.x ?? 0,
                top: data.visibleRect?.y ?? 0,
                width: data.visibleRect?.width ?? data.codedWidth,
                height: data.visibleRect?.height ?? data.codedHeight,
            };
            // The VideoFrame's rotation is ignored here. It's still a new field, and I'm not sure of any application
            // where the browser makes use of it. If a case gets found, I'll add it.
            this.rotation = init?.rotation ?? 0;
            // Assuming no innate VideoFrame rotation here
            this.squarePixelWidth = data.displayWidth;
            this.squarePixelHeight = data.displayHeight;
            this.timestamp = init?.timestamp ?? data.timestamp / 1e6;
            this.duration = init?.duration ?? (data.duration ?? 0) / 1e6;
            this.colorSpace = new VideoSampleColorSpace(data.colorSpace);
        }
        else if ((typeof HTMLImageElement !== 'undefined' && data instanceof HTMLImageElement)
            || (typeof SVGImageElement !== 'undefined' && data instanceof SVGImageElement)
            || (typeof ImageBitmap !== 'undefined' && data instanceof ImageBitmap)
            || (typeof HTMLVideoElement !== 'undefined' && data instanceof HTMLVideoElement)
            || (typeof HTMLCanvasElement !== 'undefined' && data instanceof HTMLCanvasElement)
            || (typeof OffscreenCanvas !== 'undefined' && data instanceof OffscreenCanvas)) {
            if (!init || typeof init !== 'object') {
                throw new TypeError('init must be an object.');
            }
            if (init.rotation !== undefined && ![0, 90, 180, 270].includes(init.rotation)) {
                throw new TypeError('init.rotation, when provided, must be 0, 90, 180, or 270.');
            }
            if (!Number.isFinite(init.timestamp)) {
                throw new TypeError('init.timestamp must be a number.');
            }
            if (init.duration !== undefined && (!Number.isFinite(init.duration) || init.duration < 0)) {
                throw new TypeError('init.duration, when provided, must be a non-negative number.');
            }
            if (typeof VideoFrame !== 'undefined') {
                return new VideoSample(new VideoFrame(data, {
                    timestamp: Math.trunc(init.timestamp * _misc_js__WEBPACK_IMPORTED_MODULE_0__/* .SECOND_TO_MICROSECOND_FACTOR */ .MW),
                    // Drag 0 to undefined
                    duration: Math.trunc((init.duration ?? 0) * _misc_js__WEBPACK_IMPORTED_MODULE_0__/* .SECOND_TO_MICROSECOND_FACTOR */ .MW) || undefined,
                }), init);
            }
            let width = 0;
            let height = 0;
            // Determine the dimensions of the thing
            if ('naturalWidth' in data) {
                width = data.naturalWidth;
                height = data.naturalHeight;
            }
            else if ('videoWidth' in data) {
                width = data.videoWidth;
                height = data.videoHeight;
            }
            else if ('width' in data) {
                width = Number(data.width);
                height = Number(data.height);
            }
            if (!width || !height) {
                throw new TypeError('Could not determine dimensions.');
            }
            const canvas = new OffscreenCanvas(width, height);
            const context = canvas.getContext('2d', {
                alpha: (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .isFirefox */ .gm)(), // Firefox has VideoFrame glitches with opaque canvases
                willReadFrequently: true,
            });
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(context);
            // Draw it to a canvas
            context.drawImage(data, 0, 0);
            this._data = canvas;
            this._layout = null;
            this.format = 'RGBX';
            this.visibleRect = { left: 0, top: 0, width, height };
            this.squarePixelWidth = width;
            this.squarePixelHeight = height;
            this.rotation = init.rotation ?? 0;
            this.timestamp = init.timestamp;
            this.duration = init.duration ?? 0;
            this.colorSpace = new VideoSampleColorSpace({
                matrix: 'rgb',
                primaries: 'bt709',
                transfer: 'iec61966-2-1',
                fullRange: true,
            });
        }
        else {
            throw new TypeError('Invalid data type: Must be a BufferSource or CanvasImageSource.');
        }
        this.pixelAspectRatio = (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .simplifyRational */ .Yf)({
            num: this.squarePixelWidth * this.codedHeight,
            den: this.squarePixelHeight * this.codedWidth,
        });
        finalizationRegistry?.register(this, { type: 'video', data: this._data }, this);
    }
    /** Clones this video sample. */
    clone() {
        if (this._closed) {
            throw new Error('VideoSample is closed.');
        }
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(this._data !== null);
        if (isVideoFrame(this._data)) {
            return new VideoSample(this._data.clone(), {
                timestamp: this.timestamp,
                duration: this.duration,
                rotation: this.rotation,
            });
        }
        else if (this._data instanceof Uint8Array) {
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(this._layout);
            return new VideoSample(this._data, {
                format: this.format,
                layout: this._layout,
                codedWidth: this.codedWidth,
                codedHeight: this.codedHeight,
                timestamp: this.timestamp,
                duration: this.duration,
                colorSpace: this.colorSpace,
                rotation: this.rotation,
                visibleRect: this.visibleRect,
                displayWidth: this.displayWidth,
                displayHeight: this.displayHeight,
            });
        }
        else {
            return new VideoSample(this._data, {
                format: this.format,
                codedWidth: this.codedWidth,
                codedHeight: this.codedHeight,
                timestamp: this.timestamp,
                duration: this.duration,
                colorSpace: this.colorSpace,
                rotation: this.rotation,
                visibleRect: this.visibleRect,
                displayWidth: this.displayWidth,
                displayHeight: this.displayHeight,
            });
        }
    }
    /**
     * Closes this video sample, releasing held resources. Video samples should be closed as soon as they are not
     * needed anymore.
     */
    close() {
        if (this._closed) {
            return;
        }
        finalizationRegistry?.unregister(this);
        if (isVideoFrame(this._data)) {
            this._data.close();
        }
        else {
            this._data = null; // GC that shit
        }
        this._closed = true;
    }
    /**
     * Returns the number of bytes required to hold this video sample's pixel data. Throws if `format` is `null`.
     */
    allocationSize(options = {}) {
        validateVideoFrameCopyToOptions(options);
        if (this._closed) {
            throw new Error('VideoSample is closed.');
        }
        if (this.format === null) {
            // https://github.com/Vanilagy/mediabunny/issues/267
            // https://github.com/w3c/webcodecs/issues/920
            throw new Error('Cannot get allocation size when format is null. Sorry!');
        }
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(this._data !== null);
        if (!isVideoFrame(this._data)) {
            if (options.colorSpace
                || (options.format && options.format !== this.format)
                || options.layout
                || options.rect) {
                // Temporarily convert to VideoFrame to get it done
                // TODO: Compute this directly without needing to go through VideoFrame
                const videoFrame = this.toVideoFrame();
                const size = videoFrame.allocationSize(options);
                videoFrame.close();
                return size;
            }
        }
        if (isVideoFrame(this._data)) {
            return this._data.allocationSize(options);
        }
        else if (this._data instanceof Uint8Array) {
            return this._data.byteLength;
        }
        else {
            return this.codedWidth * this.codedHeight * 4; // RGBX
        }
    }
    /**
     * Copies this video sample's pixel data to an ArrayBuffer or ArrayBufferView. Throws if `format` is `null`.
     * @returns The byte layout of the planes of the copied data.
     */
    async copyTo(destination, options = {}) {
        if (!(0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .isAllowSharedBufferSource */ .SM)(destination)) {
            throw new TypeError('destination must be an ArrayBuffer or an ArrayBuffer view.');
        }
        validateVideoFrameCopyToOptions(options);
        if (this._closed) {
            throw new Error('VideoSample is closed.');
        }
        if (this.format === null) {
            throw new Error('Cannot copy video sample data when format is null. Sorry!');
        }
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(this._data !== null);
        if (!isVideoFrame(this._data)) {
            if (options.colorSpace
                || (options.format && options.format !== this.format)
                || options.layout
                || options.rect) {
                // Temporarily convert to VideoFrame to get it done
                // TODO: Do this directly without needing to go through VideoFrame
                const videoFrame = this.toVideoFrame();
                const layout = await videoFrame.copyTo(destination, options);
                videoFrame.close();
                return layout;
            }
        }
        if (isVideoFrame(this._data)) {
            return this._data.copyTo(destination, options);
        }
        else if (this._data instanceof Uint8Array) {
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(this._layout);
            const dest = (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .toUint8Array */ .Fo)(destination);
            dest.set(this._data);
            return this._layout;
        }
        else {
            const canvas = this._data;
            const context = canvas.getContext('2d');
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(context);
            const imageData = context.getImageData(0, 0, this.codedWidth, this.codedHeight);
            const dest = (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .toUint8Array */ .Fo)(destination);
            dest.set(imageData.data);
            return [{
                    offset: 0,
                    stride: 4 * this.codedWidth,
                }];
        }
    }
    /**
     * Converts this video sample to a VideoFrame for use with the WebCodecs API. The VideoFrame returned by this
     * method *must* be closed separately from this video sample.
     */
    toVideoFrame() {
        if (this._closed) {
            throw new Error('VideoSample is closed.');
        }
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(this._data !== null);
        if (isVideoFrame(this._data)) {
            return new VideoFrame(this._data, {
                timestamp: this.microsecondTimestamp,
                duration: this.microsecondDuration || undefined, // Drag 0 duration to undefined, glitches some codecs
            });
        }
        else if (this._data instanceof Uint8Array) {
            return new VideoFrame(this._data, {
                format: this.format,
                codedWidth: this.codedWidth,
                codedHeight: this.codedHeight,
                timestamp: this.microsecondTimestamp,
                duration: this.microsecondDuration || undefined,
                colorSpace: this.colorSpace,
            });
        }
        else {
            return new VideoFrame(this._data, {
                timestamp: this.microsecondTimestamp,
                duration: this.microsecondDuration || undefined,
            });
        }
    }
    draw(context, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8) {
        let sx = 0;
        let sy = 0;
        let sWidth = this.displayWidth;
        let sHeight = this.displayHeight;
        let dx = 0;
        let dy = 0;
        let dWidth = this.displayWidth;
        let dHeight = this.displayHeight;
        if (arg5 !== undefined) {
            sx = arg1;
            sy = arg2;
            sWidth = arg3;
            sHeight = arg4;
            dx = arg5;
            dy = arg6;
            if (arg7 !== undefined) {
                dWidth = arg7;
                dHeight = arg8;
            }
            else {
                dWidth = sWidth;
                dHeight = sHeight;
            }
        }
        else {
            dx = arg1;
            dy = arg2;
            if (arg3 !== undefined) {
                dWidth = arg3;
                dHeight = arg4;
            }
        }
        if (!((typeof CanvasRenderingContext2D !== 'undefined' && context instanceof CanvasRenderingContext2D)
            || (typeof OffscreenCanvasRenderingContext2D !== 'undefined'
                && context instanceof OffscreenCanvasRenderingContext2D))) {
            throw new TypeError('context must be a CanvasRenderingContext2D or OffscreenCanvasRenderingContext2D.');
        }
        if (!Number.isFinite(sx)) {
            throw new TypeError('sx must be a number.');
        }
        if (!Number.isFinite(sy)) {
            throw new TypeError('sy must be a number.');
        }
        if (!Number.isFinite(sWidth) || sWidth < 0) {
            throw new TypeError('sWidth must be a non-negative number.');
        }
        if (!Number.isFinite(sHeight) || sHeight < 0) {
            throw new TypeError('sHeight must be a non-negative number.');
        }
        if (!Number.isFinite(dx)) {
            throw new TypeError('dx must be a number.');
        }
        if (!Number.isFinite(dy)) {
            throw new TypeError('dy must be a number.');
        }
        if (!Number.isFinite(dWidth) || dWidth < 0) {
            throw new TypeError('dWidth must be a non-negative number.');
        }
        if (!Number.isFinite(dHeight) || dHeight < 0) {
            throw new TypeError('dHeight must be a non-negative number.');
        }
        if (this._closed) {
            throw new Error('VideoSample is closed.');
        }
        ({ sx, sy, sWidth, sHeight } = this._rotateSourceRegion(sx, sy, sWidth, sHeight, this.rotation));
        const source = this.toCanvasImageSource();
        context.save();
        const centerX = dx + dWidth / 2;
        const centerY = dy + dHeight / 2;
        context.translate(centerX, centerY);
        context.rotate(this.rotation * Math.PI / 180);
        const aspectRatioChange = this.rotation % 180 === 0 ? 1 : dWidth / dHeight;
        // Scale to compensate for aspect ratio changes when rotated
        context.scale(1 / aspectRatioChange, aspectRatioChange);
        context.drawImage(source, sx, sy, sWidth, sHeight, -dWidth / 2, -dHeight / 2, dWidth, dHeight);
        context.restore();
    }
    /**
     * Draws the sample in the middle of the canvas corresponding to the context with the specified fit behavior.
     */
    drawWithFit(context, options) {
        if (!((typeof CanvasRenderingContext2D !== 'undefined' && context instanceof CanvasRenderingContext2D)
            || (typeof OffscreenCanvasRenderingContext2D !== 'undefined'
                && context instanceof OffscreenCanvasRenderingContext2D))) {
            throw new TypeError('context must be a CanvasRenderingContext2D or OffscreenCanvasRenderingContext2D.');
        }
        if (!options || typeof options !== 'object') {
            throw new TypeError('options must be an object.');
        }
        if (!['fill', 'contain', 'cover'].includes(options.fit)) {
            throw new TypeError('options.fit must be \'fill\', \'contain\', or \'cover\'.');
        }
        if (options.rotation !== undefined && ![0, 90, 180, 270].includes(options.rotation)) {
            throw new TypeError('options.rotation, when provided, must be 0, 90, 180, or 270.');
        }
        if (options.crop !== undefined) {
            validateCropRectangle(options.crop, 'options.');
        }
        const canvasWidth = context.canvas.width;
        const canvasHeight = context.canvas.height;
        const rotation = options.rotation ?? this.rotation;
        const [rotatedWidth, rotatedHeight] = rotation % 180 === 0
            ? [this.squarePixelWidth, this.squarePixelHeight]
            : [this.squarePixelHeight, this.squarePixelWidth];
        if (options.crop) {
            clampCropRectangle(options.crop, rotatedWidth, rotatedHeight);
        }
        // These variables specify where the final sample will be drawn on the canvas
        let dx;
        let dy;
        let newWidth;
        let newHeight;
        const { sx, sy, sWidth, sHeight } = this._rotateSourceRegion(options.crop?.left ?? 0, options.crop?.top ?? 0, options.crop?.width ?? rotatedWidth, options.crop?.height ?? rotatedHeight, rotation);
        if (options.fit === 'fill') {
            dx = 0;
            dy = 0;
            newWidth = canvasWidth;
            newHeight = canvasHeight;
        }
        else {
            const [sampleWidth, sampleHeight] = options.crop
                ? [options.crop.width, options.crop.height]
                : [rotatedWidth, rotatedHeight];
            const scale = options.fit === 'contain'
                ? Math.min(canvasWidth / sampleWidth, canvasHeight / sampleHeight)
                : Math.max(canvasWidth / sampleWidth, canvasHeight / sampleHeight);
            newWidth = sampleWidth * scale;
            newHeight = sampleHeight * scale;
            dx = (canvasWidth - newWidth) / 2;
            dy = (canvasHeight - newHeight) / 2;
        }
        context.save();
        const aspectRatioChange = rotation % 180 === 0 ? 1 : newWidth / newHeight;
        context.translate(canvasWidth / 2, canvasHeight / 2);
        context.rotate(rotation * Math.PI / 180);
        // This aspect ratio compensation is done so that we can draw the sample with the intended dimensions and
        // don't need to think about how those dimensions change after the rotation
        context.scale(1 / aspectRatioChange, aspectRatioChange);
        context.translate(-canvasWidth / 2, -canvasHeight / 2);
        // Important that we don't use .draw() here since that would take rotation into account, but we wanna handle it
        // ourselves here
        context.drawImage(this.toCanvasImageSource(), sx, sy, sWidth, sHeight, dx, dy, newWidth, newHeight);
        context.restore();
    }
    /** @internal */
    _rotateSourceRegion(sx, sy, sWidth, sHeight, rotation) {
        // The provided sx,sy,sWidth,sHeight refer to the final rotated image, but that's not actually how the image is
        // stored. Therefore, we must map these back onto the original, pre-rotation image.
        if (rotation === 90) {
            [sx, sy, sWidth, sHeight] = [
                sy,
                this.squarePixelHeight - sx - sWidth,
                sHeight,
                sWidth,
            ];
        }
        else if (rotation === 180) {
            [sx, sy] = [
                this.squarePixelWidth - sx - sWidth,
                this.squarePixelHeight - sy - sHeight,
            ];
        }
        else if (rotation === 270) {
            [sx, sy, sWidth, sHeight] = [
                this.squarePixelWidth - sy - sHeight,
                sx,
                sHeight,
                sWidth,
            ];
        }
        return { sx, sy, sWidth, sHeight };
    }
    /**
     * Converts this video sample to a
     * [`CanvasImageSource`](https://udn.realityripple.com/docs/Web/API/CanvasImageSource) for drawing to a canvas.
     *
     * You must use the value returned by this method immediately, as any VideoFrame created internally will
     * automatically be closed in the next microtask.
     */
    toCanvasImageSource() {
        if (this._closed) {
            throw new Error('VideoSample is closed.');
        }
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(this._data !== null);
        if (this._data instanceof Uint8Array) {
            // Requires VideoFrame to be defined
            const videoFrame = this.toVideoFrame();
            queueMicrotask(() => videoFrame.close()); // Let's automatically close the frame in the next microtask
            return videoFrame;
        }
        else {
            return this._data;
        }
    }
    /** Sets the rotation metadata of this video sample. */
    setRotation(newRotation) {
        if (![0, 90, 180, 270].includes(newRotation)) {
            throw new TypeError('newRotation must be 0, 90, 180, or 270.');
        }
        // eslint-disable-next-line @typescript-eslint/no-unnecessary-type-assertion
        this.rotation = newRotation;
    }
    /** Sets the presentation timestamp of this video sample, in seconds. */
    setTimestamp(newTimestamp) {
        if (!Number.isFinite(newTimestamp)) {
            throw new TypeError('newTimestamp must be a number.');
        }
        // eslint-disable-next-line @typescript-eslint/no-unnecessary-type-assertion
        this.timestamp = newTimestamp;
    }
    /** Sets the duration of this video sample, in seconds. */
    setDuration(newDuration) {
        if (!Number.isFinite(newDuration) || newDuration < 0) {
            throw new TypeError('newDuration must be a non-negative number.');
        }
        // eslint-disable-next-line @typescript-eslint/no-unnecessary-type-assertion
        this.duration = newDuration;
    }
    /** Calls `.close()`. */
    [Symbol.dispose]() {
        this.close();
    }
}
/**
 * Describes the color space of a {@link VideoSample}. Corresponds to the WebCodecs API's VideoColorSpace.
 * @group Samples
 * @public
 */
class VideoSampleColorSpace {
    /** Creates a new VideoSampleColorSpace. */
    constructor(init) {
        if (init !== undefined) {
            if (!init || typeof init !== 'object') {
                throw new TypeError('init.colorSpace, when provided, must be an object.');
            }
            const primariesValues = Object.keys(_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .COLOR_PRIMARIES_MAP */ .wd);
            if (init.primaries != null && !primariesValues.includes(init.primaries)) {
                throw new TypeError(`init.colorSpace.primaries, when provided, must be one of ${primariesValues.join(', ')}.`);
            }
            const transferValues = Object.keys(_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .TRANSFER_CHARACTERISTICS_MAP */ .uN);
            if (init.transfer != null && !transferValues.includes(init.transfer)) {
                throw new TypeError(`init.colorSpace.transfer, when provided, must be one of ${transferValues.join(', ')}.`);
            }
            const matrixValues = Object.keys(_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .MATRIX_COEFFICIENTS_MAP */ .Au);
            if (init.matrix != null && !matrixValues.includes(init.matrix)) {
                throw new TypeError(`init.colorSpace.matrix, when provided, must be one of ${matrixValues.join(', ')}.`);
            }
            if (init.fullRange != null && typeof init.fullRange !== 'boolean') {
                throw new TypeError('init.colorSpace.fullRange, when provided, must be a boolean.');
            }
        }
        this.primaries = init?.primaries ?? null;
        this.transfer = init?.transfer ?? null;
        this.matrix = init?.matrix ?? null;
        this.fullRange = init?.fullRange ?? null;
    }
    /** Serializes the color space to a JSON object. */
    toJSON() {
        return {
            primaries: this.primaries,
            transfer: this.transfer,
            matrix: this.matrix,
            fullRange: this.fullRange,
        };
    }
}
const isVideoFrame = (x) => {
    return typeof VideoFrame !== 'undefined' && x instanceof VideoFrame;
};
const clampCropRectangle = (crop, outerWidth, outerHeight) => {
    const left = Math.min(crop.left, outerWidth);
    const top = Math.min(crop.top, outerHeight);
    const width = Math.min(crop.width, outerWidth - left);
    const height = Math.min(crop.height, outerHeight - top);
    (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(width >= 0);
    (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(height >= 0);
    return { left, top, width, height };
};
const validateCropRectangle = (crop, prefix) => {
    if (!crop || typeof crop !== 'object') {
        throw new TypeError(prefix + 'crop, when provided, must be an object.');
    }
    if (!Number.isInteger(crop.left) || crop.left < 0) {
        throw new TypeError(prefix + 'crop.left must be a non-negative integer.');
    }
    if (!Number.isInteger(crop.top) || crop.top < 0) {
        throw new TypeError(prefix + 'crop.top must be a non-negative integer.');
    }
    if (!Number.isInteger(crop.width) || crop.width < 0) {
        throw new TypeError(prefix + 'crop.width must be a non-negative integer.');
    }
    if (!Number.isInteger(crop.height) || crop.height < 0) {
        throw new TypeError(prefix + 'crop.height must be a non-negative integer.');
    }
};
const validateVideoFrameCopyToOptions = (options) => {
    if (!options || typeof options !== 'object') {
        throw new TypeError('options must be an object.');
    }
    if (options.colorSpace !== undefined && !['display-p3', 'srgb'].includes(options.colorSpace)) {
        throw new TypeError('options.colorSpace, when provided, must be \'display-p3\' or \'srgb\'.');
    }
    if (options.format !== undefined && typeof options.format !== 'string') {
        throw new TypeError('options.format, when provided, must be a string.');
    }
    if (options.layout !== undefined) {
        if (!Array.isArray(options.layout)) {
            throw new TypeError('options.layout, when provided, must be an array.');
        }
        for (const plane of options.layout) {
            if (!plane || typeof plane !== 'object') {
                throw new TypeError('Each entry in options.layout must be an object.');
            }
            if (!Number.isInteger(plane.offset) || plane.offset < 0) {
                throw new TypeError('plane.offset must be a non-negative integer.');
            }
            if (!Number.isInteger(plane.stride) || plane.stride < 0) {
                throw new TypeError('plane.stride must be a non-negative integer.');
            }
        }
    }
    if (options.rect !== undefined) {
        if (!options.rect || typeof options.rect !== 'object') {
            throw new TypeError('options.rect, when provided, must be an object.');
        }
        if (options.rect.x !== undefined && (!Number.isInteger(options.rect.x) || options.rect.x < 0)) {
            throw new TypeError('options.rect.x, when provided, must be a non-negative integer.');
        }
        if (options.rect.y !== undefined && (!Number.isInteger(options.rect.y) || options.rect.y < 0)) {
            throw new TypeError('options.rect.y, when provided, must be a non-negative integer.');
        }
        if (options.rect.width !== undefined && (!Number.isInteger(options.rect.width) || options.rect.width < 0)) {
            throw new TypeError('options.rect.width, when provided, must be a non-negative integer.');
        }
        if (options.rect.height !== undefined && (!Number.isInteger(options.rect.height) || options.rect.height < 0)) {
            throw new TypeError('options.rect.height, when provided, must be a non-negative integer.');
        }
    }
};
/** Implements logic from WebCodecs § 9.4.6 "Compute Layout and Allocation Size" */
const createDefaultPlaneLayout = (format, codedWidth, codedHeight) => {
    const planes = getPlaneConfigs(format);
    const layouts = [];
    let currentOffset = 0;
    for (const plane of planes) {
        // Per § 9.8, dimensions are usually "rounded up to the nearest integer".
        const planeWidth = Math.ceil(codedWidth / plane.widthDivisor);
        const planeHeight = Math.ceil(codedHeight / plane.heightDivisor);
        const stride = planeWidth * plane.sampleBytes;
        // Tight packing
        const planeSize = stride * planeHeight;
        layouts.push({
            offset: currentOffset,
            stride: stride,
        });
        currentOffset += planeSize;
    }
    return layouts;
};
/** Helper to retrieve plane configurations based on WebCodecs § 9.8 Pixel Format definitions. */
const getPlaneConfigs = (format) => {
    // Helper for standard YUV planes
    const yuv = (yBytes, uvBytes, subX, subY, hasAlpha) => {
        const configs = [
            { sampleBytes: yBytes, widthDivisor: 1, heightDivisor: 1 },
            { sampleBytes: uvBytes, widthDivisor: subX, heightDivisor: subY },
            { sampleBytes: uvBytes, widthDivisor: subX, heightDivisor: subY },
        ];
        if (hasAlpha) {
            // Match luma dimensions
            configs.push({ sampleBytes: yBytes, widthDivisor: 1, heightDivisor: 1 });
        }
        return configs;
    };
    switch (format) {
        case 'I420':
            return yuv(1, 1, 2, 2, false);
        case 'I420P10':
        case 'I420P12':
            return yuv(2, 2, 2, 2, false);
        case 'I420A':
            return yuv(1, 1, 2, 2, true);
        case 'I420AP10':
        case 'I420AP12':
            return yuv(2, 2, 2, 2, true);
        case 'I422':
            return yuv(1, 1, 2, 1, false);
        case 'I422P10':
        case 'I422P12':
            return yuv(2, 2, 2, 1, false);
        case 'I422A':
            return yuv(1, 1, 2, 1, true);
        case 'I422AP10':
        case 'I422AP12':
            return yuv(2, 2, 2, 1, true);
        case 'I444':
            return yuv(1, 1, 1, 1, false);
        case 'I444P10':
        case 'I444P12':
            return yuv(2, 2, 1, 1, false);
        case 'I444A':
            return yuv(1, 1, 1, 1, true);
        case 'I444AP10':
        case 'I444AP12':
            return yuv(2, 2, 1, 1, true);
        case 'NV12':
            return [
                { sampleBytes: 1, widthDivisor: 1, heightDivisor: 1 },
                { sampleBytes: 2, widthDivisor: 2, heightDivisor: 2 }, // Interleaved U and V
            ];
        case 'RGBA':
        case 'RGBX':
        case 'BGRA':
        case 'BGRX':
            return [
                { sampleBytes: 4, widthDivisor: 1, heightDivisor: 1 },
            ];
        default:
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assertNever */ .xb)(format);
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(false);
    }
};
const AUDIO_SAMPLE_FORMATS = new Set(['f32', 'f32-planar', 's16', 's16-planar', 's32', 's32-planar', 'u8', 'u8-planar']);
/**
 * Represents a raw, unencoded audio sample. Mainly used as an expressive wrapper around WebCodecs API's
 * [`AudioData`](https://developer.mozilla.org/en-US/docs/Web/API/AudioData), but can also be used standalone.
 * @group Samples
 * @public
 */
class AudioSample {
    /** The presentation timestamp of the sample in microseconds. */
    get microsecondTimestamp() {
        return Math.trunc(_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .SECOND_TO_MICROSECOND_FACTOR */ .MW * this.timestamp);
    }
    /** The duration of the sample in microseconds. */
    get microsecondDuration() {
        return Math.trunc(_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .SECOND_TO_MICROSECOND_FACTOR */ .MW * this.duration);
    }
    /**
     * Creates a new {@link AudioSample}, either from an existing
     * [`AudioData`](https://developer.mozilla.org/en-US/docs/Web/API/AudioData) or from raw bytes specified in
     * {@link AudioSampleInit}.
     */
    constructor(init) {
        /** @internal */
        this._closed = false;
        if (isAudioData(init)) {
            if (init.format === null) {
                throw new TypeError('AudioData with null format is not supported.');
            }
            this._data = init;
            this.format = init.format;
            this.sampleRate = init.sampleRate;
            this.numberOfFrames = init.numberOfFrames;
            this.numberOfChannels = init.numberOfChannels;
            this.timestamp = init.timestamp / 1e6;
            this.duration = init.numberOfFrames / init.sampleRate;
        }
        else {
            if (!init || typeof init !== 'object') {
                throw new TypeError('Invalid AudioDataInit: must be an object.');
            }
            if (!AUDIO_SAMPLE_FORMATS.has(init.format)) {
                throw new TypeError('Invalid AudioDataInit: invalid format.');
            }
            if (!Number.isFinite(init.sampleRate) || init.sampleRate <= 0) {
                throw new TypeError('Invalid AudioDataInit: sampleRate must be > 0.');
            }
            if (!Number.isInteger(init.numberOfChannels) || init.numberOfChannels === 0) {
                throw new TypeError('Invalid AudioDataInit: numberOfChannels must be an integer > 0.');
            }
            if (!Number.isFinite(init?.timestamp)) {
                throw new TypeError('init.timestamp must be a number.');
            }
            const numberOfFrames = init.data.byteLength / (getBytesPerSample(init.format) * init.numberOfChannels);
            if (!Number.isInteger(numberOfFrames)) {
                throw new TypeError('Invalid AudioDataInit: data size is not a multiple of frame size.');
            }
            this.format = init.format;
            this.sampleRate = init.sampleRate;
            this.numberOfFrames = numberOfFrames;
            this.numberOfChannels = init.numberOfChannels;
            this.timestamp = init.timestamp;
            this.duration = numberOfFrames / init.sampleRate;
            let dataBuffer;
            if (init.data instanceof ArrayBuffer) {
                dataBuffer = new Uint8Array(init.data);
            }
            else if (ArrayBuffer.isView(init.data)) {
                dataBuffer = new Uint8Array(init.data.buffer, init.data.byteOffset, init.data.byteLength);
            }
            else {
                throw new TypeError('Invalid AudioDataInit: data is not a BufferSource.');
            }
            const expectedSize = this.numberOfFrames * this.numberOfChannels * getBytesPerSample(this.format);
            if (dataBuffer.byteLength < expectedSize) {
                throw new TypeError('Invalid AudioDataInit: insufficient data size.');
            }
            this._data = dataBuffer;
        }
        finalizationRegistry?.register(this, { type: 'audio', data: this._data }, this);
    }
    /** Returns the number of bytes required to hold the audio sample's data as specified by the given options. */
    allocationSize(options) {
        if (!options || typeof options !== 'object') {
            throw new TypeError('options must be an object.');
        }
        if (!Number.isInteger(options.planeIndex) || options.planeIndex < 0) {
            throw new TypeError('planeIndex must be a non-negative integer.');
        }
        if (options.format !== undefined && !AUDIO_SAMPLE_FORMATS.has(options.format)) {
            throw new TypeError('Invalid format.');
        }
        if (options.frameOffset !== undefined && (!Number.isInteger(options.frameOffset) || options.frameOffset < 0)) {
            throw new TypeError('frameOffset must be a non-negative integer.');
        }
        if (options.frameCount !== undefined && (!Number.isInteger(options.frameCount) || options.frameCount < 0)) {
            throw new TypeError('frameCount must be a non-negative integer.');
        }
        if (this._closed) {
            throw new Error('AudioSample is closed.');
        }
        const destFormat = options.format ?? this.format;
        const frameOffset = options.frameOffset ?? 0;
        if (frameOffset >= this.numberOfFrames) {
            throw new RangeError('frameOffset out of range');
        }
        const copyFrameCount = options.frameCount !== undefined ? options.frameCount : (this.numberOfFrames - frameOffset);
        if (copyFrameCount > (this.numberOfFrames - frameOffset)) {
            throw new RangeError('frameCount out of range');
        }
        const bytesPerSample = getBytesPerSample(destFormat);
        const isPlanar = formatIsPlanar(destFormat);
        if (isPlanar && options.planeIndex >= this.numberOfChannels) {
            throw new RangeError('planeIndex out of range');
        }
        if (!isPlanar && options.planeIndex !== 0) {
            throw new RangeError('planeIndex out of range');
        }
        const elementCount = isPlanar ? copyFrameCount : copyFrameCount * this.numberOfChannels;
        return elementCount * bytesPerSample;
    }
    /** Copies the audio sample's data to an ArrayBuffer or ArrayBufferView as specified by the given options. */
    copyTo(destination, options) {
        if (!(0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .isAllowSharedBufferSource */ .SM)(destination)) {
            throw new TypeError('destination must be an ArrayBuffer or an ArrayBuffer view.');
        }
        if (!options || typeof options !== 'object') {
            throw new TypeError('options must be an object.');
        }
        if (!Number.isInteger(options.planeIndex) || options.planeIndex < 0) {
            throw new TypeError('planeIndex must be a non-negative integer.');
        }
        if (options.format !== undefined && !AUDIO_SAMPLE_FORMATS.has(options.format)) {
            throw new TypeError('Invalid format.');
        }
        if (options.frameOffset !== undefined && (!Number.isInteger(options.frameOffset) || options.frameOffset < 0)) {
            throw new TypeError('frameOffset must be a non-negative integer.');
        }
        if (options.frameCount !== undefined && (!Number.isInteger(options.frameCount) || options.frameCount < 0)) {
            throw new TypeError('frameCount must be a non-negative integer.');
        }
        if (this._closed) {
            throw new Error('AudioSample is closed.');
        }
        const { planeIndex, format, frameCount: optFrameCount, frameOffset: optFrameOffset } = options;
        const srcFormat = this.format;
        const destFormat = format ?? this.format;
        if (!destFormat)
            throw new Error('Destination format not determined');
        const numFrames = this.numberOfFrames;
        const numChannels = this.numberOfChannels;
        const frameOffset = optFrameOffset ?? 0;
        if (frameOffset >= numFrames) {
            throw new RangeError('frameOffset out of range');
        }
        const copyFrameCount = optFrameCount !== undefined ? optFrameCount : (numFrames - frameOffset);
        if (copyFrameCount > (numFrames - frameOffset)) {
            throw new RangeError('frameCount out of range');
        }
        const destBytesPerSample = getBytesPerSample(destFormat);
        const destIsPlanar = formatIsPlanar(destFormat);
        if (destIsPlanar && planeIndex >= numChannels) {
            throw new RangeError('planeIndex out of range');
        }
        if (!destIsPlanar && planeIndex !== 0) {
            throw new RangeError('planeIndex out of range');
        }
        const destElementCount = destIsPlanar ? copyFrameCount : copyFrameCount * numChannels;
        const requiredSize = destElementCount * destBytesPerSample;
        if (destination.byteLength < requiredSize) {
            throw new RangeError('Destination buffer is too small');
        }
        const destView = (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .toDataView */ .Zc)(destination);
        const writeFn = getWriteFunction(destFormat);
        if (isAudioData(this._data)) {
            if ((0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .isWebKit */ .Tc)() && numChannels > 2 && destFormat !== srcFormat) {
                // WebKit bug workaround
                doAudioDataCopyToWebKitWorkaround(this._data, destView, srcFormat, destFormat, numChannels, planeIndex, frameOffset, copyFrameCount);
            }
            else {
                // Per spec, only f32-planar conversion must be supported, but in practice, all browsers support all
                // destination formats, so let's just delegate here:
                this._data.copyTo(destination, {
                    planeIndex,
                    frameOffset,
                    frameCount: copyFrameCount,
                    format: destFormat,
                });
            }
        }
        else {
            const uint8Data = this._data;
            const srcView = (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .toDataView */ .Zc)(uint8Data);
            const readFn = getReadFunction(srcFormat);
            const srcBytesPerSample = getBytesPerSample(srcFormat);
            const srcIsPlanar = formatIsPlanar(srcFormat);
            for (let i = 0; i < copyFrameCount; i++) {
                if (destIsPlanar) {
                    const destOffset = i * destBytesPerSample;
                    let srcOffset;
                    if (srcIsPlanar) {
                        srcOffset = (planeIndex * numFrames + (i + frameOffset)) * srcBytesPerSample;
                    }
                    else {
                        srcOffset = (((i + frameOffset) * numChannels) + planeIndex) * srcBytesPerSample;
                    }
                    const normalized = readFn(srcView, srcOffset);
                    writeFn(destView, destOffset, normalized);
                }
                else {
                    for (let ch = 0; ch < numChannels; ch++) {
                        const destIndex = i * numChannels + ch;
                        const destOffset = destIndex * destBytesPerSample;
                        let srcOffset;
                        if (srcIsPlanar) {
                            srcOffset = (ch * numFrames + (i + frameOffset)) * srcBytesPerSample;
                        }
                        else {
                            srcOffset = (((i + frameOffset) * numChannels) + ch) * srcBytesPerSample;
                        }
                        const normalized = readFn(srcView, srcOffset);
                        writeFn(destView, destOffset, normalized);
                    }
                }
            }
        }
    }
    /** Clones this audio sample. */
    clone() {
        if (this._closed) {
            throw new Error('AudioSample is closed.');
        }
        if (isAudioData(this._data)) {
            const sample = new AudioSample(this._data.clone());
            sample.setTimestamp(this.timestamp); // Make sure the timestamp is precise (beyond microsecond accuracy)
            return sample;
        }
        else {
            return new AudioSample({
                format: this.format,
                sampleRate: this.sampleRate,
                numberOfFrames: this.numberOfFrames,
                numberOfChannels: this.numberOfChannels,
                timestamp: this.timestamp,
                data: this._data,
            });
        }
    }
    /**
     * Closes this audio sample, releasing held resources. Audio samples should be closed as soon as they are not
     * needed anymore.
     */
    close() {
        if (this._closed) {
            return;
        }
        finalizationRegistry?.unregister(this);
        if (isAudioData(this._data)) {
            this._data.close();
        }
        else {
            this._data = new Uint8Array(0);
        }
        this._closed = true;
    }
    /**
     * Converts this audio sample to an AudioData for use with the WebCodecs API. The AudioData returned by this
     * method *must* be closed separately from this audio sample.
     */
    toAudioData() {
        if (this._closed) {
            throw new Error('AudioSample is closed.');
        }
        if (isAudioData(this._data)) {
            if (this._data.timestamp === this.microsecondTimestamp) {
                // Timestamp matches, let's just return the data (but cloned)
                return this._data.clone();
            }
            else {
                // It's impossible to simply change an AudioData's timestamp, so we'll need to create a new one
                if (formatIsPlanar(this.format)) {
                    const size = this.allocationSize({ planeIndex: 0, format: this.format });
                    const data = new ArrayBuffer(size * this.numberOfChannels);
                    // We gotta read out each plane individually
                    for (let i = 0; i < this.numberOfChannels; i++) {
                        this.copyTo(new Uint8Array(data, i * size, size), { planeIndex: i, format: this.format });
                    }
                    return new AudioData({
                        format: this.format,
                        sampleRate: this.sampleRate,
                        numberOfFrames: this.numberOfFrames,
                        numberOfChannels: this.numberOfChannels,
                        timestamp: this.microsecondTimestamp,
                        data,
                    });
                }
                else {
                    const data = new ArrayBuffer(this.allocationSize({ planeIndex: 0, format: this.format }));
                    this.copyTo(data, { planeIndex: 0, format: this.format });
                    return new AudioData({
                        format: this.format,
                        sampleRate: this.sampleRate,
                        numberOfFrames: this.numberOfFrames,
                        numberOfChannels: this.numberOfChannels,
                        timestamp: this.microsecondTimestamp,
                        data,
                    });
                }
            }
        }
        else {
            return new AudioData({
                format: this.format,
                sampleRate: this.sampleRate,
                numberOfFrames: this.numberOfFrames,
                numberOfChannels: this.numberOfChannels,
                timestamp: this.microsecondTimestamp,
                data: this._data.buffer instanceof ArrayBuffer
                    ? this._data.buffer
                    : this._data.slice(), // In the case of SharedArrayBuffer, convert to ArrayBuffer
            });
        }
    }
    /** Convert this audio sample to an AudioBuffer for use with the Web Audio API. */
    toAudioBuffer() {
        if (this._closed) {
            throw new Error('AudioSample is closed.');
        }
        const audioBuffer = new AudioBuffer({
            numberOfChannels: this.numberOfChannels,
            length: this.numberOfFrames,
            sampleRate: this.sampleRate,
        });
        const dataBytes = new Float32Array(this.allocationSize({ planeIndex: 0, format: 'f32-planar' }) / 4);
        for (let i = 0; i < this.numberOfChannels; i++) {
            this.copyTo(dataBytes, { planeIndex: i, format: 'f32-planar' });
            audioBuffer.copyToChannel(dataBytes, i);
        }
        return audioBuffer;
    }
    /** Sets the presentation timestamp of this audio sample, in seconds. */
    setTimestamp(newTimestamp) {
        if (!Number.isFinite(newTimestamp)) {
            throw new TypeError('newTimestamp must be a number.');
        }
        // eslint-disable-next-line @typescript-eslint/no-unnecessary-type-assertion
        this.timestamp = newTimestamp;
    }
    /** Calls `.close()`. */
    [Symbol.dispose]() {
        this.close();
    }
    /** @internal */
    static *_fromAudioBuffer(audioBuffer, timestamp) {
        if (!(audioBuffer instanceof AudioBuffer)) {
            throw new TypeError('audioBuffer must be an AudioBuffer.');
        }
        const MAX_FLOAT_COUNT = 48000 * 5; // 5 seconds of mono 48 kHz audio per sample
        const numberOfChannels = audioBuffer.numberOfChannels;
        const sampleRate = audioBuffer.sampleRate;
        const totalFrames = audioBuffer.length;
        const maxFramesPerChunk = Math.floor(MAX_FLOAT_COUNT / numberOfChannels);
        let currentRelativeFrame = 0;
        let remainingFrames = totalFrames;
        // Create AudioSamples in a chunked fashion so we don't create huge Float32Arrays
        while (remainingFrames > 0) {
            const framesToCopy = Math.min(maxFramesPerChunk, remainingFrames);
            const chunkData = new Float32Array(numberOfChannels * framesToCopy);
            for (let channel = 0; channel < numberOfChannels; channel++) {
                audioBuffer.copyFromChannel(chunkData.subarray(channel * framesToCopy, (channel + 1) * framesToCopy), channel, currentRelativeFrame);
            }
            yield new AudioSample({
                format: 'f32-planar',
                sampleRate,
                numberOfFrames: framesToCopy,
                numberOfChannels,
                timestamp: timestamp + currentRelativeFrame / sampleRate,
                data: chunkData,
            });
            currentRelativeFrame += framesToCopy;
            remainingFrames -= framesToCopy;
        }
    }
    /**
     * Creates AudioSamples from an AudioBuffer, starting at the given timestamp in seconds. Typically creates exactly
     * one sample, but may create multiple if the AudioBuffer is exceedingly large.
     */
    static fromAudioBuffer(audioBuffer, timestamp) {
        if (!(audioBuffer instanceof AudioBuffer)) {
            throw new TypeError('audioBuffer must be an AudioBuffer.');
        }
        const MAX_FLOAT_COUNT = 48000 * 5; // 5 seconds of mono 48 kHz audio per sample
        const numberOfChannels = audioBuffer.numberOfChannels;
        const sampleRate = audioBuffer.sampleRate;
        const totalFrames = audioBuffer.length;
        const maxFramesPerChunk = Math.floor(MAX_FLOAT_COUNT / numberOfChannels);
        let currentRelativeFrame = 0;
        let remainingFrames = totalFrames;
        const result = [];
        // Create AudioSamples in a chunked fashion so we don't create huge Float32Arrays
        while (remainingFrames > 0) {
            const framesToCopy = Math.min(maxFramesPerChunk, remainingFrames);
            const chunkData = new Float32Array(numberOfChannels * framesToCopy);
            for (let channel = 0; channel < numberOfChannels; channel++) {
                audioBuffer.copyFromChannel(chunkData.subarray(channel * framesToCopy, (channel + 1) * framesToCopy), channel, currentRelativeFrame);
            }
            const audioSample = new AudioSample({
                format: 'f32-planar',
                sampleRate,
                numberOfFrames: framesToCopy,
                numberOfChannels,
                timestamp: timestamp + currentRelativeFrame / sampleRate,
                data: chunkData,
            });
            result.push(audioSample);
            currentRelativeFrame += framesToCopy;
            remainingFrames -= framesToCopy;
        }
        return result;
    }
}
const getBytesPerSample = (format) => {
    switch (format) {
        case 'u8':
        case 'u8-planar':
            return 1;
        case 's16':
        case 's16-planar':
            return 2;
        case 's32':
        case 's32-planar':
            return 4;
        case 'f32':
        case 'f32-planar':
            return 4;
        default:
            throw new Error('Unknown AudioSampleFormat');
    }
};
const formatIsPlanar = (format) => {
    switch (format) {
        case 'u8-planar':
        case 's16-planar':
        case 's32-planar':
        case 'f32-planar':
            return true;
        default:
            return false;
    }
};
const getReadFunction = (format) => {
    switch (format) {
        case 'u8':
        case 'u8-planar':
            return (view, offset) => (view.getUint8(offset) - 128) / 128;
        case 's16':
        case 's16-planar':
            return (view, offset) => view.getInt16(offset, true) / 32768;
        case 's32':
        case 's32-planar':
            return (view, offset) => view.getInt32(offset, true) / 2147483648;
        case 'f32':
        case 'f32-planar':
            return (view, offset) => view.getFloat32(offset, true);
    }
};
const getWriteFunction = (format) => {
    switch (format) {
        case 'u8':
        case 'u8-planar':
            return (view, offset, value) => view.setUint8(offset, (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .clamp */ .qE)((value + 1) * 127.5, 0, 255));
        case 's16':
        case 's16-planar':
            return (view, offset, value) => view.setInt16(offset, (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .clamp */ .qE)(Math.round(value * 32767), -32768, 32767), true);
        case 's32':
        case 's32-planar':
            return (view, offset, value) => view.setInt32(offset, (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .clamp */ .qE)(Math.round(value * 2147483647), -2147483648, 2147483647), true);
        case 'f32':
        case 'f32-planar':
            return (view, offset, value) => view.setFloat32(offset, value, true);
    }
};
const isAudioData = (x) => {
    return typeof AudioData !== 'undefined' && x instanceof AudioData;
};
/**
 * WebKit has a bug where calling AudioData.copyTo with a format different from the source format
 * crashes the tab when there are more than 2 channels. This function works around that by always
 * copying with the source format and then manually converting to the destination format.
 *
 * See https://bugs.webkit.org/show_bug.cgi?id=302521.
 */
const doAudioDataCopyToWebKitWorkaround = (audioData, destView, srcFormat, destFormat, numChannels, planeIndex, frameOffset, copyFrameCount) => {
    const readFn = getReadFunction(srcFormat);
    const writeFn = getWriteFunction(destFormat);
    const srcBytesPerSample = getBytesPerSample(srcFormat);
    const destBytesPerSample = getBytesPerSample(destFormat);
    const srcIsPlanar = formatIsPlanar(srcFormat);
    const destIsPlanar = formatIsPlanar(destFormat);
    if (destIsPlanar) {
        if (srcIsPlanar) {
            // src planar -> dest planar: copy single plane and convert
            const data = new ArrayBuffer(copyFrameCount * srcBytesPerSample);
            const dataView = (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .toDataView */ .Zc)(data);
            audioData.copyTo(data, {
                planeIndex,
                frameOffset,
                frameCount: copyFrameCount,
                format: srcFormat,
            });
            for (let i = 0; i < copyFrameCount; i++) {
                const srcOffset = i * srcBytesPerSample;
                const destOffset = i * destBytesPerSample;
                const sample = readFn(dataView, srcOffset);
                writeFn(destView, destOffset, sample);
            }
        }
        else {
            // src interleaved -> dest planar: copy all interleaved data, extract one channel
            const data = new ArrayBuffer(copyFrameCount * numChannels * srcBytesPerSample);
            const dataView = (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .toDataView */ .Zc)(data);
            audioData.copyTo(data, {
                planeIndex: 0,
                frameOffset,
                frameCount: copyFrameCount,
                format: srcFormat,
            });
            for (let i = 0; i < copyFrameCount; i++) {
                const srcOffset = (i * numChannels + planeIndex) * srcBytesPerSample;
                const destOffset = i * destBytesPerSample;
                const sample = readFn(dataView, srcOffset);
                writeFn(destView, destOffset, sample);
            }
        }
    }
    else {
        if (srcIsPlanar) {
            // src planar -> dest interleaved: copy each plane and interleave
            const planeSize = copyFrameCount * srcBytesPerSample;
            const data = new ArrayBuffer(planeSize);
            const dataView = (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .toDataView */ .Zc)(data);
            for (let ch = 0; ch < numChannels; ch++) {
                audioData.copyTo(data, {
                    planeIndex: ch,
                    frameOffset,
                    frameCount: copyFrameCount,
                    format: srcFormat,
                });
                for (let i = 0; i < copyFrameCount; i++) {
                    const srcOffset = i * srcBytesPerSample;
                    const destOffset = (i * numChannels + ch) * destBytesPerSample;
                    const sample = readFn(dataView, srcOffset);
                    writeFn(destView, destOffset, sample);
                }
            }
        }
        else {
            // src interleaved -> dest interleaved: copy all and convert
            const data = new ArrayBuffer(copyFrameCount * numChannels * srcBytesPerSample);
            const dataView = (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .toDataView */ .Zc)(data);
            audioData.copyTo(data, {
                planeIndex: 0,
                frameOffset,
                frameCount: copyFrameCount,
                format: srcFormat,
            });
            for (let i = 0; i < copyFrameCount; i++) {
                for (let ch = 0; ch < numChannels; ch++) {
                    const idx = i * numChannels + ch;
                    const srcOffset = idx * srcBytesPerSample;
                    const destOffset = idx * destBytesPerSample;
                    const sample = readFn(dataView, srcOffset);
                    writeFn(destView, destOffset, sample);
                }
            }
        }
    }
};


/***/ },

/***/ 260
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   E: () => (/* binding */ WaveDemuxer)
/* harmony export */ });
/* unused harmony export WaveFormat */
/* harmony import */ var _demuxer_js__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(7202);
/* harmony import */ var _metadata_js__WEBPACK_IMPORTED_MODULE_1__ = __webpack_require__(5165);
/* harmony import */ var _misc_js__WEBPACK_IMPORTED_MODULE_2__ = __webpack_require__(3912);
/* harmony import */ var _packet_js__WEBPACK_IMPORTED_MODULE_3__ = __webpack_require__(3936);
/* harmony import */ var _reader_js__WEBPACK_IMPORTED_MODULE_4__ = __webpack_require__(7735);
/* harmony import */ var _id3_js__WEBPACK_IMPORTED_MODULE_5__ = __webpack_require__(7576);
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */






var WaveFormat;
(function (WaveFormat) {
    WaveFormat[WaveFormat["PCM"] = 1] = "PCM";
    WaveFormat[WaveFormat["IEEE_FLOAT"] = 3] = "IEEE_FLOAT";
    WaveFormat[WaveFormat["ALAW"] = 6] = "ALAW";
    WaveFormat[WaveFormat["MULAW"] = 7] = "MULAW";
    WaveFormat[WaveFormat["EXTENSIBLE"] = 65534] = "EXTENSIBLE";
})(WaveFormat || (WaveFormat = {}));
class WaveDemuxer extends _demuxer_js__WEBPACK_IMPORTED_MODULE_0__/* .Demuxer */ .B {
    constructor(input) {
        super(input);
        this.metadataPromise = null;
        this.dataStart = -1;
        this.dataSize = -1;
        this.audioInfo = null;
        this.trackBackings = [];
        this.lastKnownPacketIndex = 0;
        this.metadataTags = {};
        this.reader = input._reader;
    }
    async readMetadata() {
        return this.metadataPromise ??= (async () => {
            let slice = this.reader.requestSlice(0, 12);
            if (slice instanceof Promise)
                slice = await slice;
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_2__/* .assert */ .vA)(slice);
            const riffType = (0,_reader_js__WEBPACK_IMPORTED_MODULE_4__/* .readAscii */ .IT)(slice, 4);
            const littleEndian = riffType !== 'RIFX';
            const isRf64 = riffType === 'RF64';
            const outerChunkSize = (0,_reader_js__WEBPACK_IMPORTED_MODULE_4__/* .readU32 */ .PF)(slice, littleEndian);
            let totalFileSize = isRf64
                ? this.reader.fileSize
                : Math.min(outerChunkSize + 8, this.reader.fileSize ?? Infinity);
            const format = (0,_reader_js__WEBPACK_IMPORTED_MODULE_4__/* .readAscii */ .IT)(slice, 4);
            if (format !== 'WAVE') {
                throw new Error('Invalid WAVE file - wrong format');
            }
            let chunksRead = 0;
            let dataChunkSize = null;
            let currentPos = slice.filePos;
            while (totalFileSize === null || currentPos < totalFileSize) {
                let slice = this.reader.requestSlice(currentPos, 8);
                if (slice instanceof Promise)
                    slice = await slice;
                if (!slice)
                    break;
                const chunkId = (0,_reader_js__WEBPACK_IMPORTED_MODULE_4__/* .readAscii */ .IT)(slice, 4);
                const chunkSize = (0,_reader_js__WEBPACK_IMPORTED_MODULE_4__/* .readU32 */ .PF)(slice, littleEndian);
                const startPos = slice.filePos;
                if (isRf64 && chunksRead === 0 && chunkId !== 'ds64') {
                    throw new Error('Invalid RF64 file: First chunk must be "ds64".');
                }
                if (chunkId === 'fmt ') {
                    await this.parseFmtChunk(startPos, chunkSize, littleEndian);
                }
                else if (chunkId === 'data') {
                    dataChunkSize ??= chunkSize;
                    this.dataStart = slice.filePos;
                    this.dataSize = Math.min(dataChunkSize, (totalFileSize ?? Infinity) - this.dataStart);
                    if (this.reader.fileSize === null) {
                        break; // Stop once we hit the data chunk
                    }
                }
                else if (chunkId === 'ds64') {
                    // File and data chunk sizes are defined in here instead
                    let ds64Slice = this.reader.requestSlice(startPos, chunkSize);
                    if (ds64Slice instanceof Promise)
                        ds64Slice = await ds64Slice;
                    if (!ds64Slice)
                        break;
                    const riffChunkSize = (0,_reader_js__WEBPACK_IMPORTED_MODULE_4__/* .readU64 */ .IM)(ds64Slice, littleEndian);
                    dataChunkSize = (0,_reader_js__WEBPACK_IMPORTED_MODULE_4__/* .readU64 */ .IM)(ds64Slice, littleEndian);
                    totalFileSize = Math.min(riffChunkSize + 8, this.reader.fileSize ?? Infinity);
                }
                else if (chunkId === 'LIST') {
                    await this.parseListChunk(startPos, chunkSize, littleEndian);
                }
                else if (chunkId === 'ID3 ' || chunkId === 'id3 ') {
                    await this.parseId3Chunk(startPos, chunkSize);
                }
                currentPos = startPos + chunkSize + (chunkSize & 1); // Handle padding
                chunksRead++;
            }
            if (!this.audioInfo) {
                throw new Error('Invalid WAVE file - missing "fmt " chunk');
            }
            if (this.dataStart === -1) {
                throw new Error('Invalid WAVE file - missing "data" chunk');
            }
            const blockSize = this.audioInfo.blockSizeInBytes;
            this.dataSize = Math.floor(this.dataSize / blockSize) * blockSize;
            this.trackBackings.push(new WaveAudioTrackBacking(this));
        })();
    }
    async parseFmtChunk(startPos, size, littleEndian) {
        let slice = this.reader.requestSlice(startPos, size);
        if (slice instanceof Promise)
            slice = await slice;
        if (!slice)
            return; // File too short
        let formatTag = (0,_reader_js__WEBPACK_IMPORTED_MODULE_4__/* .readU16 */ .Vv)(slice, littleEndian);
        const numChannels = (0,_reader_js__WEBPACK_IMPORTED_MODULE_4__/* .readU16 */ .Vv)(slice, littleEndian);
        const sampleRate = (0,_reader_js__WEBPACK_IMPORTED_MODULE_4__/* .readU32 */ .PF)(slice, littleEndian);
        slice.skip(4); // Bytes per second
        const blockAlign = (0,_reader_js__WEBPACK_IMPORTED_MODULE_4__/* .readU16 */ .Vv)(slice, littleEndian);
        let bitsPerSample;
        if (size === 14) { // Plain WAVEFORMAT
            bitsPerSample = 8;
        }
        else {
            bitsPerSample = (0,_reader_js__WEBPACK_IMPORTED_MODULE_4__/* .readU16 */ .Vv)(slice, littleEndian);
        }
        // Handle WAVEFORMATEXTENSIBLE
        if (size >= 18 && formatTag !== 0x0165) {
            const cbSize = (0,_reader_js__WEBPACK_IMPORTED_MODULE_4__/* .readU16 */ .Vv)(slice, littleEndian);
            const remainingSize = size - 18;
            const extensionSize = Math.min(remainingSize, cbSize);
            if (extensionSize >= 22 && formatTag === WaveFormat.EXTENSIBLE) {
                // Parse WAVEFORMATEXTENSIBLE
                slice.skip(2 + 4);
                const subFormat = (0,_reader_js__WEBPACK_IMPORTED_MODULE_4__/* .readBytes */ .io)(slice, 16);
                // Get actual format from subFormat GUID
                formatTag = subFormat[0] | (subFormat[1] << 8);
            }
        }
        if (formatTag === WaveFormat.MULAW || formatTag === WaveFormat.ALAW) {
            bitsPerSample = 8;
        }
        this.audioInfo = {
            format: formatTag,
            numberOfChannels: numChannels,
            sampleRate,
            sampleSizeInBytes: Math.ceil(bitsPerSample / 8),
            blockSizeInBytes: blockAlign,
        };
    }
    async parseListChunk(startPos, size, littleEndian) {
        let slice = this.reader.requestSlice(startPos, size);
        if (slice instanceof Promise)
            slice = await slice;
        if (!slice)
            return; // File too short
        const infoType = (0,_reader_js__WEBPACK_IMPORTED_MODULE_4__/* .readAscii */ .IT)(slice, 4);
        if (infoType !== 'INFO' && infoType !== 'INF0') { // exiftool.org claims INF0 can happen
            return; // Not an INFO chunk
        }
        let currentPos = slice.filePos;
        while (currentPos <= startPos + size - 8) {
            slice.filePos = currentPos;
            const chunkName = (0,_reader_js__WEBPACK_IMPORTED_MODULE_4__/* .readAscii */ .IT)(slice, 4);
            const chunkSize = (0,_reader_js__WEBPACK_IMPORTED_MODULE_4__/* .readU32 */ .PF)(slice, littleEndian);
            const bytes = (0,_reader_js__WEBPACK_IMPORTED_MODULE_4__/* .readBytes */ .io)(slice, chunkSize);
            let stringLength = 0;
            for (let i = 0; i < bytes.length; i++) {
                if (bytes[i] === 0) {
                    break;
                }
                stringLength++;
            }
            const value = String.fromCharCode(...bytes.subarray(0, stringLength));
            this.metadataTags.raw ??= {};
            this.metadataTags.raw[chunkName] = value;
            switch (chunkName) {
                case 'INAM':
                case 'TITL':
                    {
                        this.metadataTags.title ??= value;
                    }
                    ;
                    break;
                case 'TIT3':
                    {
                        this.metadataTags.description ??= value;
                    }
                    ;
                    break;
                case 'IART':
                    {
                        this.metadataTags.artist ??= value;
                    }
                    ;
                    break;
                case 'IPRD':
                    {
                        this.metadataTags.album ??= value;
                    }
                    ;
                    break;
                case 'IPRT':
                case 'ITRK':
                case 'TRCK':
                    {
                        const parts = value.split('/');
                        const trackNum = Number.parseInt(parts[0], 10);
                        const tracksTotal = parts[1] && Number.parseInt(parts[1], 10);
                        if (Number.isInteger(trackNum) && trackNum > 0) {
                            this.metadataTags.trackNumber ??= trackNum;
                        }
                        if (tracksTotal && Number.isInteger(tracksTotal) && tracksTotal > 0) {
                            this.metadataTags.tracksTotal ??= tracksTotal;
                        }
                    }
                    ;
                    break;
                case 'ICRD':
                case 'IDIT':
                    {
                        const date = new Date(value);
                        if (!Number.isNaN(date.getTime())) {
                            this.metadataTags.date ??= date;
                        }
                    }
                    ;
                    break;
                case 'YEAR':
                    {
                        const year = Number.parseInt(value, 10);
                        if (Number.isInteger(year) && year > 0) {
                            this.metadataTags.date ??= new Date(year, 0, 1);
                        }
                    }
                    ;
                    break;
                case 'IGNR':
                case 'GENR':
                    {
                        this.metadataTags.genre ??= value;
                    }
                    ;
                    break;
                case 'ICMT':
                case 'CMNT':
                case 'COMM':
                    {
                        this.metadataTags.comment ??= value;
                    }
                    ;
                    break;
            }
            currentPos += 8 + chunkSize + (chunkSize & 1); // Handle padding
        }
    }
    async parseId3Chunk(startPos, size) {
        // Parse ID3 tag embedded in WAV file (non-default, but used a lot in practice anyway)
        let slice = this.reader.requestSlice(startPos, size);
        if (slice instanceof Promise)
            slice = await slice;
        if (!slice)
            return; // File too short
        const id3V2Header = (0,_id3_js__WEBPACK_IMPORTED_MODULE_5__/* .readId3V2Header */ .IX)(slice);
        if (id3V2Header) {
            // Clamp to the available data in case the ID3 header claims more than the WAV chunk provides
            // https://github.com/Vanilagy/mediabunny/issues/300
            const availableSize = size - _id3_js__WEBPACK_IMPORTED_MODULE_5__/* .ID3_V2_HEADER_SIZE */ .sY;
            id3V2Header.size = Math.min(id3V2Header.size, availableSize);
            if (id3V2Header.size > 0) {
                const contentSlice = slice.slice(startPos + _id3_js__WEBPACK_IMPORTED_MODULE_5__/* .ID3_V2_HEADER_SIZE */ .sY, id3V2Header.size);
                (0,_id3_js__WEBPACK_IMPORTED_MODULE_5__/* .parseId3V2Tag */ .cG)(contentSlice, id3V2Header, this.metadataTags);
            }
        }
    }
    getCodec() {
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_2__/* .assert */ .vA)(this.audioInfo);
        if (this.audioInfo.format === WaveFormat.MULAW) {
            return 'ulaw';
        }
        if (this.audioInfo.format === WaveFormat.ALAW) {
            return 'alaw';
        }
        if (this.audioInfo.format === WaveFormat.PCM) {
            // All formats are little-endian
            if (this.audioInfo.sampleSizeInBytes === 1) {
                return 'pcm-u8';
            }
            else if (this.audioInfo.sampleSizeInBytes === 2) {
                return 'pcm-s16';
            }
            else if (this.audioInfo.sampleSizeInBytes === 3) {
                return 'pcm-s24';
            }
            else if (this.audioInfo.sampleSizeInBytes === 4) {
                return 'pcm-s32';
            }
        }
        if (this.audioInfo.format === WaveFormat.IEEE_FLOAT) {
            if (this.audioInfo.sampleSizeInBytes === 4) {
                return 'pcm-f32';
            }
        }
        return null;
    }
    async getMimeType() {
        return 'audio/wav';
    }
    async getTrackBackings() {
        await this.readMetadata();
        return this.trackBackings;
    }
    async getMetadataTags() {
        await this.readMetadata();
        return this.metadataTags;
    }
}
const PACKET_SIZE_IN_FRAMES = 2048;
class WaveAudioTrackBacking {
    constructor(demuxer) {
        this.demuxer = demuxer;
    }
    getType() {
        return 'audio';
    }
    getId() {
        return 1;
    }
    getNumber() {
        return 1;
    }
    getCodec() {
        return this.demuxer.getCodec();
    }
    getInternalCodecId() {
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_2__/* .assert */ .vA)(this.demuxer.audioInfo);
        return this.demuxer.audioInfo.format;
    }
    async getDecoderConfig() {
        const codec = this.demuxer.getCodec();
        if (!codec) {
            return null;
        }
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_2__/* .assert */ .vA)(this.demuxer.audioInfo);
        return {
            codec,
            numberOfChannels: this.demuxer.audioInfo.numberOfChannels,
            sampleRate: this.demuxer.audioInfo.sampleRate,
        };
    }
    getNumberOfChannels() {
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_2__/* .assert */ .vA)(this.demuxer.audioInfo);
        return this.demuxer.audioInfo.numberOfChannels;
    }
    getSampleRate() {
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_2__/* .assert */ .vA)(this.demuxer.audioInfo);
        return this.demuxer.audioInfo.sampleRate;
    }
    getTimeResolution() {
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_2__/* .assert */ .vA)(this.demuxer.audioInfo);
        return this.demuxer.audioInfo.sampleRate;
    }
    isRelativeToUnixEpoch() {
        return false;
    }
    getPairingMask() {
        return 1n;
    }
    getBitrate() {
        return null;
    }
    getAverageBitrate() {
        return null;
    }
    async getDurationFromMetadata() {
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_2__/* .assert */ .vA)(this.demuxer.dataSize !== -1);
        return this.demuxer.dataSize / this.demuxer.audioInfo.blockSizeInBytes / this.demuxer.audioInfo.sampleRate;
    }
    async getLiveRefreshInterval() {
        return null;
    }
    getName() {
        return null;
    }
    getLanguageCode() {
        return _misc_js__WEBPACK_IMPORTED_MODULE_2__/* .UNDETERMINED_LANGUAGE */ .IR;
    }
    getDisposition() {
        return {
            ..._metadata_js__WEBPACK_IMPORTED_MODULE_1__/* .DEFAULT_TRACK_DISPOSITION */ .gM,
        };
    }
    async getPacketAtIndex(packetIndex, options) {
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_2__/* .assert */ .vA)(packetIndex >= 0);
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_2__/* .assert */ .vA)(this.demuxer.audioInfo);
        const startOffset = packetIndex * PACKET_SIZE_IN_FRAMES * this.demuxer.audioInfo.blockSizeInBytes;
        if (startOffset >= this.demuxer.dataSize) {
            return null;
        }
        const sizeInBytes = Math.min(PACKET_SIZE_IN_FRAMES * this.demuxer.audioInfo.blockSizeInBytes, this.demuxer.dataSize - startOffset);
        if (this.demuxer.reader.fileSize === null) {
            // If the file size is unknown, we weren't able to cap the dataSize in the init logic and we instead have to
            // rely on the headers telling us how large the file is. But, these might be wrong, so let's check if the
            // requested slice actually exists.
            let slice = this.demuxer.reader.requestSlice(this.demuxer.dataStart + startOffset, sizeInBytes);
            if (slice instanceof Promise)
                slice = await slice;
            if (!slice) {
                return null;
            }
        }
        let data;
        if (options.metadataOnly) {
            data = _packet_js__WEBPACK_IMPORTED_MODULE_3__/* .PLACEHOLDER_DATA */ .T;
        }
        else {
            let slice = this.demuxer.reader.requestSlice(this.demuxer.dataStart + startOffset, sizeInBytes);
            if (slice instanceof Promise)
                slice = await slice;
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_2__/* .assert */ .vA)(slice);
            data = (0,_reader_js__WEBPACK_IMPORTED_MODULE_4__/* .readBytes */ .io)(slice, sizeInBytes);
        }
        const timestamp = packetIndex * PACKET_SIZE_IN_FRAMES / this.demuxer.audioInfo.sampleRate;
        const duration = sizeInBytes / this.demuxer.audioInfo.blockSizeInBytes / this.demuxer.audioInfo.sampleRate;
        this.demuxer.lastKnownPacketIndex = Math.max(packetIndex, this.demuxer.lastKnownPacketIndex);
        return new _packet_js__WEBPACK_IMPORTED_MODULE_3__/* .EncodedPacket */ .Z(data, 'key', timestamp, duration, packetIndex, sizeInBytes);
    }
    getFirstPacket(options) {
        return this.getPacketAtIndex(0, options);
    }
    async getPacket(timestamp, options) {
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_2__/* .assert */ .vA)(this.demuxer.audioInfo);
        const packetIndex = Math.floor(Math.min(timestamp * this.demuxer.audioInfo.sampleRate / PACKET_SIZE_IN_FRAMES, (this.demuxer.dataSize - 1) / (PACKET_SIZE_IN_FRAMES * this.demuxer.audioInfo.blockSizeInBytes)));
        if (packetIndex < 0) {
            return null;
        }
        const packet = await this.getPacketAtIndex(packetIndex, options);
        if (packet) {
            return packet;
        }
        if (packetIndex === 0) {
            return null; // Empty data chunk
        }
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_2__/* .assert */ .vA)(this.demuxer.reader.fileSize === null);
        // The file is shorter than we thought, meaning the packet we were looking for doesn't exist. So, let's find
        // the last packet by doing a sequential scan, instead.
        let currentPacket = await this.getPacketAtIndex(this.demuxer.lastKnownPacketIndex, options);
        while (currentPacket) {
            const nextPacket = await this.getNextPacket(currentPacket, options);
            if (!nextPacket) {
                break;
            }
            currentPacket = nextPacket;
        }
        return currentPacket;
    }
    getNextPacket(packet, options) {
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_2__/* .assert */ .vA)(this.demuxer.audioInfo);
        const packetIndex = Math.round(packet.timestamp * this.demuxer.audioInfo.sampleRate / PACKET_SIZE_IN_FRAMES);
        return this.getPacketAtIndex(packetIndex + 1, options);
    }
    getKeyPacket(timestamp, options) {
        return this.getPacket(timestamp, options);
    }
    getNextKeyPacket(packet, options) {
        return this.getNextPacket(packet, options);
    }
}


/***/ }

}]);
//# sourceMappingURL=408.bundle.js.map