"use strict";
(self["webpackChunkrelease_video"] = self["webpackChunkrelease_video"] || []).push([[750],{

/***/ 7553
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   N: () => (/* binding */ AC3_SAMPLE_RATES),
/* harmony export */   P: () => (/* binding */ EAC3_REDUCED_SAMPLE_RATES)
/* harmony export */ });
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
/** Sample rates indexed by fscod (Table 4.1) */
const AC3_SAMPLE_RATES = [48000, 44100, 32000];
/** E-AC-3 reduced sample rates for fscod2 per ATSC A/52:2018 */
const EAC3_REDUCED_SAMPLE_RATES = [24000, 22050, 16000];


/***/ },

/***/ 1390
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   _: () => (/* binding */ Bitstream)
/* harmony export */ });
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
class Bitstream {
    constructor(bytes) {
        this.bytes = bytes;
        /** Current offset in bits. */
        this.pos = 0;
    }
    seekToByte(byteOffset) {
        this.pos = 8 * byteOffset;
    }
    readBit() {
        const byteIndex = Math.floor(this.pos / 8);
        const byte = this.bytes[byteIndex] ?? 0;
        const bitIndex = 0b111 - (this.pos & 0b111);
        const bit = (byte & (1 << bitIndex)) >> bitIndex;
        this.pos++;
        return bit;
    }
    readBits(n) {
        if (n === 1) {
            return this.readBit();
        }
        let result = 0;
        for (let i = 0; i < n; i++) {
            result <<= 1;
            result |= this.readBit();
        }
        return result;
    }
    writeBits(n, value) {
        const end = this.pos + n;
        for (let i = this.pos; i < end; i++) {
            const byteIndex = Math.floor(i / 8);
            let byte = this.bytes[byteIndex];
            const bitIndex = 0b111 - (i & 0b111);
            byte &= ~(1 << bitIndex);
            byte |= ((value & (1 << (end - i - 1))) >> (end - i - 1)) << bitIndex;
            this.bytes[byteIndex] = byte;
        }
        this.pos = end;
    }
    ;
    readAlignedByte() {
        if (this.pos % 8 !== 0) {
            throw new Error('Bitstream is not byte-aligned.');
        }
        const byteIndex = this.pos / 8;
        const byte = this.bytes[byteIndex] ?? 0;
        this.pos += 8;
        return byte;
    }
    skipBits(n) {
        this.pos += n;
    }
    getBitsLeft() {
        return this.bytes.length * 8 - this.pos;
    }
    clone() {
        const clone = new Bitstream(this.bytes);
        clone.pos = this.pos;
        return clone;
    }
}


/***/ },

/***/ 8475
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   Y$: () => (/* binding */ MAX_ADTS_FRAME_HEADER_SIZE),
/* harmony export */   gc: () => (/* binding */ MIN_ADTS_FRAME_HEADER_SIZE),
/* harmony export */   lh: () => (/* binding */ readAdtsFrameHeader)
/* harmony export */ });
/* harmony import */ var _shared_bitstream_js__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(1390);
/* harmony import */ var _reader_js__WEBPACK_IMPORTED_MODULE_1__ = __webpack_require__(7735);
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


const MIN_ADTS_FRAME_HEADER_SIZE = 7;
const MAX_ADTS_FRAME_HEADER_SIZE = 9;
const readAdtsFrameHeader = (slice) => {
    // https://wiki.multimedia.cx/index.php/ADTS (last visited: 2025/08/17)
    const startPos = slice.filePos;
    const bytes = (0,_reader_js__WEBPACK_IMPORTED_MODULE_1__/* .readBytes */ .io)(slice, 9); // 9 with CRC, 7 without CRC
    const bitstream = new _shared_bitstream_js__WEBPACK_IMPORTED_MODULE_0__/* .Bitstream */ ._(bytes);
    const syncword = bitstream.readBits(12);
    if (syncword !== 0b1111_11111111) {
        return null;
    }
    bitstream.skipBits(1); // MPEG version
    const layer = bitstream.readBits(2);
    if (layer !== 0) {
        return null;
    }
    const protectionAbsence = bitstream.readBits(1);
    const objectType = bitstream.readBits(2) + 1;
    const samplingFrequencyIndex = bitstream.readBits(4);
    if (samplingFrequencyIndex === 15) {
        return null;
    }
    bitstream.skipBits(1); // Private bit
    const channelConfiguration = bitstream.readBits(3);
    if (channelConfiguration === 0) {
        throw new Error('ADTS frames with channel configuration 0 are not supported.');
    }
    bitstream.skipBits(1); // Originality
    bitstream.skipBits(1); // Home
    bitstream.skipBits(1); // Copyright ID bit
    bitstream.skipBits(1); // Copyright ID start
    const frameLength = bitstream.readBits(13);
    bitstream.skipBits(11); // Buffer fullness
    const numberOfAacFrames = bitstream.readBits(2) + 1;
    if (numberOfAacFrames !== 1) {
        throw new Error('ADTS frames with more than one AAC frame are not supported.');
    }
    let crcCheck = null;
    if (protectionAbsence === 1) { // No CRC
        slice.filePos -= 2;
    }
    else { // CRC
        crcCheck = bitstream.readBits(16);
    }
    return {
        objectType,
        samplingFrequencyIndex,
        channelConfiguration,
        frameLength,
        numberOfAacFrames,
        crcCheck,
        startPos,
    };
};


/***/ },

/***/ 7202
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   B: () => (/* binding */ Demuxer)
/* harmony export */ });
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
class Demuxer {
    constructor(input) {
        this.input = input;
    }
    dispose() {
        // Can be overridden
    }
}


/***/ },

/***/ 5828
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   Be: () => (/* binding */ calculateCrc8),
/* harmony export */   Ld: () => (/* binding */ readSampleRate),
/* harmony export */   X7: () => (/* binding */ readCodedNumber),
/* harmony export */   f6: () => (/* binding */ readBlockSize),
/* harmony export */   iv: () => (/* binding */ getBlockSizeOrUncommon),
/* harmony export */   oP: () => (/* binding */ getSampleRateOrUncommon)
/* harmony export */ });
/* harmony import */ var _shared_bitstream_js__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(1390);
/* harmony import */ var _misc_js__WEBPACK_IMPORTED_MODULE_1__ = __webpack_require__(3912);
/* harmony import */ var _reader_js__WEBPACK_IMPORTED_MODULE_2__ = __webpack_require__(7735);
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */



// https://www.rfc-editor.org/rfc/rfc9639.html#name-block-size-bits
const getBlockSizeOrUncommon = (bits) => {
    if (bits === 0b0000) {
        return null;
    }
    else if (bits === 0b0001) {
        return 192;
    }
    else if (bits >= 0b0010 && bits <= 0b0101) {
        return 144 * 2 ** bits;
    }
    else if (bits === 0b0110) {
        return 'uncommon-u8';
    }
    else if (bits === 0b0111) {
        return 'uncommon-u16';
    }
    else if (bits >= 0b1000 && bits <= 0b1111) {
        return 2 ** bits;
    }
    else {
        return null;
    }
};
// https://www.rfc-editor.org/rfc/rfc9639.html#name-sample-rate-bits
const getSampleRateOrUncommon = (sampleRateBits, streamInfoSampleRate) => {
    switch (sampleRateBits) {
        case 0b0000: return streamInfoSampleRate;
        case 0b0001: return 88200;
        case 0b0010: return 176400;
        case 0b0011: return 192000;
        case 0b0100: return 8000;
        case 0b0101: return 16000;
        case 0b0110: return 22050;
        case 0b0111: return 24000;
        case 0b1000: return 32000;
        case 0b1001: return 44100;
        case 0b1010: return 48000;
        case 0b1011: return 96000;
        case 0b1100: return 'uncommon-u8';
        case 0b1101: return 'uncommon-u16';
        case 0b1110: return 'uncommon-u16-10';
        default: return null;
    }
};
// https://www.rfc-editor.org/rfc/rfc9639.html#name-coded-number
const readCodedNumber = (fileSlice) => {
    let ones = 0;
    const bitstream1 = new _shared_bitstream_js__WEBPACK_IMPORTED_MODULE_0__/* .Bitstream */ ._((0,_reader_js__WEBPACK_IMPORTED_MODULE_2__/* .readBytes */ .io)(fileSlice, 1));
    while (bitstream1.readBits(1) === 1) {
        ones++;
    }
    if (ones === 0) {
        return bitstream1.readBits(7);
    }
    const bitArray = [];
    const extraBytes = ones - 1;
    const bitstream2 = new _shared_bitstream_js__WEBPACK_IMPORTED_MODULE_0__/* .Bitstream */ ._((0,_reader_js__WEBPACK_IMPORTED_MODULE_2__/* .readBytes */ .io)(fileSlice, extraBytes));
    const firstByteBits = 8 - ones - 1;
    for (let i = 0; i < firstByteBits; i++) {
        bitArray.unshift(bitstream1.readBits(1));
    }
    for (let i = 0; i < extraBytes; i++) {
        for (let j = 0; j < 8; j++) {
            const val = bitstream2.readBits(1);
            if (j < 2) {
                continue;
            }
            bitArray.unshift(val);
        }
    }
    const encoded = bitArray.reduce((acc, bit, index) => {
        return acc | (bit << index);
    }, 0);
    return encoded;
};
const readBlockSize = (slice, blockSizeBits) => {
    if (blockSizeBits === 'uncommon-u16') {
        return (0,_reader_js__WEBPACK_IMPORTED_MODULE_2__/* .readU16Be */ .mH)(slice) + 1;
    }
    else if (blockSizeBits === 'uncommon-u8') {
        return (0,_reader_js__WEBPACK_IMPORTED_MODULE_2__/* .readU8 */ .eo)(slice) + 1;
    }
    else if (typeof blockSizeBits === 'number') {
        return blockSizeBits;
    }
    else {
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .assertNever */ .xb)(blockSizeBits);
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .assert */ .vA)(false);
    }
};
const readSampleRate = (slice, sampleRateOrUncommon) => {
    if (sampleRateOrUncommon === 'uncommon-u16') {
        return (0,_reader_js__WEBPACK_IMPORTED_MODULE_2__/* .readU16Be */ .mH)(slice);
    }
    if (sampleRateOrUncommon === 'uncommon-u16-10') {
        return (0,_reader_js__WEBPACK_IMPORTED_MODULE_2__/* .readU16Be */ .mH)(slice) * 10;
    }
    if (sampleRateOrUncommon === 'uncommon-u8') {
        return (0,_reader_js__WEBPACK_IMPORTED_MODULE_2__/* .readU8 */ .eo)(slice);
    }
    if (typeof sampleRateOrUncommon === 'number') {
        return sampleRateOrUncommon;
    }
    return null;
};
// https://www.rfc-editor.org/rfc/rfc9639.html#section-9.1.1
const calculateCrc8 = (data) => {
    const polynomial = 0x07; // x^8 + x^2 + x^1 + x^0
    let crc = 0x00; // Initialize CRC to 0
    for (const byte of data) {
        crc ^= byte; // XOR byte into least significant byte of crc
        for (let i = 0; i < 8; i++) {
            // For each bit in the byte
            if ((crc & 0x80) !== 0) {
                // If the leftmost bit (MSB) is set
                crc = (crc << 1) ^ polynomial; // Shift left and XOR with polynomial
            }
            else {
                crc <<= 1; // Just shift left
            }
            crc &= 0xff; // Ensure CRC remains 8-bit
        }
    }
    return crc;
};


/***/ },

/***/ 3622
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   DT: () => (/* binding */ TAG_I_FRAMES_ONLY),
/* harmony export */   EF: () => (/* binding */ TAG_MEDIA),
/* harmony export */   Hw: () => (/* binding */ AttributeList),
/* harmony export */   L2: () => (/* binding */ TAG_KEY),
/* harmony export */   _2: () => (/* binding */ TAG_MEDIA_SEQUENCE),
/* harmony export */   bW: () => (/* binding */ TAG_PROGRAM_DATE_TIME),
/* harmony export */   c$: () => (/* binding */ TAG_STREAM_INF),
/* harmony export */   dY: () => (/* binding */ TAG_ENDLIST),
/* harmony export */   e9: () => (/* binding */ TAG_EXTINF),
/* harmony export */   g4: () => (/* binding */ TAG_I_FRAME_STREAM_INF),
/* harmony export */   i$: () => (/* binding */ TAG_DISCONTINUITY),
/* harmony export */   is: () => (/* binding */ HLS_MIME_TYPE),
/* harmony export */   nf: () => (/* binding */ canIgnoreLine),
/* harmony export */   sA: () => (/* binding */ TAG_MAP),
/* harmony export */   v6: () => (/* binding */ TAG_BYTERANGE),
/* harmony export */   xe: () => (/* binding */ TAG_TARGETDURATION),
/* harmony export */   zA: () => (/* binding */ TAG_PLAYLIST_TYPE)
/* harmony export */ });
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
const HLS_MIME_TYPE = 'application/vnd.apple.mpegurl';
const TAG_STREAM_INF = '#EXT-X-STREAM-INF:';
const TAG_I_FRAME_STREAM_INF = '#EXT-X-I-FRAME-STREAM-INF:';
const TAG_MEDIA = '#EXT-X-MEDIA:';
const TAG_EXTINF = '#EXTINF:';
const TAG_MAP = '#EXT-X-MAP:';
const TAG_KEY = '#EXT-X-KEY:';
const TAG_MEDIA_SEQUENCE = '#EXT-X-MEDIA-SEQUENCE:';
const TAG_BYTERANGE = '#EXT-X-BYTERANGE:';
const TAG_PROGRAM_DATE_TIME = '#EXT-X-PROGRAM-DATE-TIME:';
const TAG_DISCONTINUITY = '#EXT-X-DISCONTINUITY';
const TAG_TARGETDURATION = '#EXT-X-TARGETDURATION:';
const TAG_ENDLIST = '#EXT-X-ENDLIST';
const TAG_PLAYLIST_TYPE = '#EXT-X-PLAYLIST-TYPE:';
const TAG_I_FRAMES_ONLY = '#EXT-X-I-FRAMES-ONLY';
const canIgnoreLine = (line) => line.length === 0 || (line.startsWith('#') && !line.startsWith('#EXT'));
class AttributeList {
    constructor(str) {
        this._attributes = {};
        let key = '';
        let value = '';
        let inValue = false;
        let inQuotes = false;
        for (let i = 0; i < str.length; i++) {
            const char = str[i];
            if (char === '"') {
                inQuotes = !inQuotes;
            }
            else if (char === '=' && !inValue && !inQuotes) {
                inValue = true;
            }
            else if (char === ',' && !inQuotes) {
                if (key) {
                    this._attributes[key.trim().toLowerCase()] = value;
                }
                key = '';
                value = '';
                inValue = false;
            }
            else if (inValue) {
                value += char;
            }
            else {
                key += char;
            }
        }
        if (key) {
            this._attributes[key.trim().toLowerCase()] = value;
        }
    }
    get(name) {
        return this._attributes[name.toLowerCase()] ?? null;
    }
    getAsNumber(name) {
        const value = this.get(name);
        if (value === null) {
            return null;
        }
        const num = Number(value);
        return Number.isFinite(num) ? num : null;
    }
    merge(other) {
        Object.assign(this._attributes, other._attributes);
    }
}


/***/ },

/***/ 1290
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {


// EXPORTS
__webpack_require__.d(__webpack_exports__, {
  XE: () => (/* binding */ ALL_FORMATS),
  rp: () => (/* binding */ HlsInputFormat),
  CW: () => (/* binding */ InputFormat),
  Gu: () => (/* binding */ validateInputFormatOptions)
});

// UNUSED EXPORTS: ADTS, AdtsInputFormat, FLAC, FlacInputFormat, HLS, HLS_FORMATS, IsobmffInputFormat, MATROSKA, MP3, MP4, MPEG_TS, MatroskaInputFormat, Mp3InputFormat, Mp4InputFormat, MpegTsInputFormat, OGG, OggInputFormat, QTFF, QuickTimeInputFormat, WAVE, WEBM, WaveInputFormat, WebMInputFormat

// EXTERNAL MODULE: ./node_modules/mediabunny/dist/modules/shared/aac-misc.js
var aac_misc = __webpack_require__(1299);
// EXTERNAL MODULE: ./node_modules/mediabunny/dist/modules/src/codec.js
var codec = __webpack_require__(1188);
// EXTERNAL MODULE: ./node_modules/mediabunny/dist/modules/src/codec-data.js
var codec_data = __webpack_require__(6297);
// EXTERNAL MODULE: ./node_modules/mediabunny/dist/modules/src/demuxer.js
var demuxer = __webpack_require__(7202);
// EXTERNAL MODULE: ./node_modules/mediabunny/dist/modules/src/misc.js
var misc = __webpack_require__(3912);
// EXTERNAL MODULE: ./node_modules/mediabunny/dist/modules/src/packet.js
var src_packet = __webpack_require__(3936);
// EXTERNAL MODULE: ./node_modules/mediabunny/dist/modules/src/isobmff/isobmff-misc.js
var isobmff_misc = __webpack_require__(1826);
// EXTERNAL MODULE: ./node_modules/mediabunny/dist/modules/src/isobmff/isobmff-reader.js
var isobmff_reader = __webpack_require__(8561);
// EXTERNAL MODULE: ./node_modules/mediabunny/dist/modules/src/reader.js
var src_reader = __webpack_require__(7735);
// EXTERNAL MODULE: ./node_modules/mediabunny/dist/modules/src/metadata.js
var metadata = __webpack_require__(5165);
// EXTERNAL MODULE: ./node_modules/mediabunny/dist/modules/shared/ac3-misc.js
var ac3_misc = __webpack_require__(7553);
// EXTERNAL MODULE: ./node_modules/mediabunny/dist/modules/shared/bitstream.js
var shared_bitstream = __webpack_require__(1390);
;// ./node_modules/mediabunny/dist/modules/src/aes.js
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


// Inspired in part by https://github.com/halloweeks/AES-128-CBC/blob/main/AES_128_CBC.h
const AES_128_BLOCK_SIZE = 16;
const Te4 = new Uint32Array(256);
const Td0 = new Uint32Array(256);
const Td1 = new Uint32Array(256);
const Td2 = new Uint32Array(256);
const Td3 = new Uint32Array(256);
const Td4 = new Uint32Array(256);
const rcon = new Uint32Array(10);
let tablesGenerated = false;
// Generating the tables once is much more bundle size-efficient than shipping them in the bundle (entropy ftw)
const generateAesTables = () => {
    const sbox = new Uint8Array(256);
    const log = new Uint8Array(256);
    const pow = new Uint8Array(256);
    // 1. Generate GF(2^8) log/exp tables
    // Primitive polynomial: x^8 + x^4 + x^3 + x + 1 (0x11B)
    for (let i = 0, p = 1; i < 256; i++) {
        pow[i] = p;
        log[p] = i;
        p = p ^ (p << 1) ^ (p & 0x80 ? 0x11B : 0);
    }
    // Helper: GF(2^8) multiplication
    const mul = (a, b) => (a && b) ? pow[(log[a] + log[b]) % 255] : 0;
    // 2. Generate S-Box and Inverse S-Box
    sbox[0] = 0x63; // Special case for 0
    // Loop for inverse (using log/exp) and Affine Transform
    for (let i = 1; i < 256; i++) {
        const x = pow[255 - log[i]]; // Multiplicative inverse
        let s = x ^ (x << 1) ^ (x << 2) ^ (x << 3) ^ (x << 4);
        s = (s >>> 8) ^ (s & 0xFF) ^ 0x63; // Affine transform
        sbox[i] = s;
    }
    // 3. Fill Tables
    for (let i = 0; i < 256; i++) {
        const s = sbox[i]; // Forward S-Box value
        const is = sbox.indexOf(i); // Inverse S-Box value
        // Te4: Forward S-Box packed
        Te4[i] = (s << 24) | (s << 16) | (s << 8) | s;
        // Td4: Inverse S-Box packed
        Td4[i] = (is << 24) | (is << 16) | (is << 8) | is;
        // Td0-Td3: Inverse MixColumns applied to Inverse S-Box
        // Coefficients: 0x0E, 0x09, 0x0D, 0x0B (Order specific to Td0 structure)
        const b0 = mul(is, 0x0E);
        const b1 = mul(is, 0x09);
        const b2 = mul(is, 0x0D);
        const b3 = mul(is, 0x0B);
        const w = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;
        Td0[i] = w;
        Td1[i] = (w >>> 8) | (w << 24); // Rotate right 8
        Td2[i] = (w >>> 16) | (w << 16); // Rotate right 16
        Td3[i] = (w >>> 24) | (w << 8); // Rotate right 24
    }
    // 4. Generate Rcon
    let r = 1;
    for (let i = 0; i < 10; i++) {
        rcon[i] = r << 24;
        r = (r << 1) ^ (r & 0x80 ? 0x11B : 0);
    }
    tablesGenerated = true;
};
/** A context for doing AES-128-CBC operations. Better than the Web Crypto API since we can stream it. */
class Aes128CbcContext {
    constructor() {
        this.roundkey = new Uint32Array(44);
        this.iv = new Uint32Array(AES_128_BLOCK_SIZE / Uint32Array.BYTES_PER_ELEMENT);
        this.in = new Uint8Array(AES_128_BLOCK_SIZE);
        this.out = new Uint8Array(AES_128_BLOCK_SIZE);
        this.inView = new DataView(this.in.buffer);
        this.outView = new DataView(this.out.buffer);
    }
    init({ key, iv }) {
        (0,misc/* assert */.vA)(key.byteLength === 16);
        (0,misc/* assert */.vA)(iv.byteLength === 16);
        if (!tablesGenerated) {
            generateAesTables();
        }
        const keyView = new DataView(key.buffer, key.byteOffset, key.byteLength);
        const ivView = new DataView(iv.buffer, iv.byteOffset, iv.byteLength);
        this.roundkey[0] = keyView.getUint32(0, false);
        this.roundkey[1] = keyView.getUint32(4, false);
        this.roundkey[2] = keyView.getUint32(8, false);
        this.roundkey[3] = keyView.getUint32(12, false);
        this.iv[0] = ivView.getUint32(0, false);
        this.iv[1] = ivView.getUint32(4, false);
        this.iv[2] = ivView.getUint32(8, false);
        this.iv[3] = ivView.getUint32(12, false);
        for (let index = 4; index < 44; index += 4) {
            const temp = this.roundkey[index - 1];
            this.roundkey[index] = this.roundkey[index - 4]
                ^ (Te4[(temp >>> 16) & 0xff] & 0xff000000)
                ^ (Te4[(temp >>> 8) & 0xff] & 0x00ff0000)
                ^ (Te4[(temp >>> 0) & 0xff] & 0x0000ff00)
                ^ (Te4[(temp >>> 24) & 0xff] & 0x000000ff)
                ^ rcon[(index / 4) - 1];
            this.roundkey[index + 1] = this.roundkey[index - 3] ^ this.roundkey[index];
            this.roundkey[index + 2] = this.roundkey[index - 2] ^ this.roundkey[index + 1];
            this.roundkey[index + 3] = this.roundkey[index - 1] ^ this.roundkey[index + 2];
        }
        // Invert the order of the round keys
        for (let i = 0, j = 40; i < j; i += 4, j -= 4) {
            for (let k = 0; k < 4; k++) {
                const temp = this.roundkey[i + k];
                this.roundkey[i + k] = this.roundkey[j + k];
                this.roundkey[j + k] = temp;
            }
        }
        // Apply Inverse MixColumn transform to all round keys except first and last
        for (let index = 4; index < 40; index += 4) {
            for (let k = 0; k < 4; k++) {
                const rk = this.roundkey[index + k];
                this.roundkey[index + k]
                    = Td0[Te4[(rk >>> 24) & 0xff] & 0xff]
                        ^ Td1[Te4[(rk >>> 16) & 0xff] & 0xff]
                        ^ Td2[Te4[(rk >>> 8) & 0xff] & 0xff]
                        ^ Td3[Te4[(rk >>> 0) & 0xff] & 0xff];
            }
        }
    }
    decrypt() {
        let s0 = this.inView.getUint32(0, false) ^ this.roundkey[0];
        let s1 = this.inView.getUint32(4, false) ^ this.roundkey[1];
        let s2 = this.inView.getUint32(8, false) ^ this.roundkey[2];
        let s3 = this.inView.getUint32(12, false) ^ this.roundkey[3];
        // Store input for CBC XOR later
        const temp0 = this.inView.getUint32(0, false);
        const temp1 = this.inView.getUint32(4, false);
        const temp2 = this.inView.getUint32(8, false);
        const temp3 = this.inView.getUint32(12, false);
        let t0, t1, t2, t3;
        // Rounds 1-9
        for (let round = 1; round < 10; round++) {
            const offset = round * 4;
            t0 = Td0[s0 >>> 24]
                ^ Td1[(s3 >>> 16) & 0xff]
                ^ Td2[(s2 >>> 8) & 0xff]
                ^ Td3[s1 & 0xff]
                ^ this.roundkey[offset];
            t1 = Td0[s1 >>> 24]
                ^ Td1[(s0 >>> 16) & 0xff]
                ^ Td2[(s3 >>> 8) & 0xff]
                ^ Td3[s2 & 0xff]
                ^ this.roundkey[offset + 1];
            t2 = Td0[s2 >>> 24]
                ^ Td1[(s1 >>> 16) & 0xff]
                ^ Td2[(s0 >>> 8) & 0xff]
                ^ Td3[s3 & 0xff]
                ^ this.roundkey[offset + 2];
            t3 = Td0[s3 >>> 24]
                ^ Td1[(s2 >>> 16) & 0xff]
                ^ Td2[(s1 >>> 8) & 0xff]
                ^ Td3[s0 & 0xff]
                ^ this.roundkey[offset + 3];
            s0 = t0;
            s1 = t1;
            s2 = t2;
            s3 = t3;
        }
        // Final Round (10)
        const f0 = (Td4[(s0 >>> 24) & 0xff] & 0xff000000)
            ^ (Td4[(s3 >>> 16) & 0xff] & 0x00ff0000)
            ^ (Td4[(s2 >>> 8) & 0xff] & 0x0000ff00)
            ^ (Td4[(s1 >>> 0) & 0xff] & 0x000000ff)
            ^ this.roundkey[40];
        const f1 = (Td4[(s1 >>> 24) & 0xff] & 0xff000000)
            ^ (Td4[(s0 >>> 16) & 0xff] & 0x00ff0000)
            ^ (Td4[(s3 >>> 8) & 0xff] & 0x0000ff00)
            ^ (Td4[(s2 >>> 0) & 0xff] & 0x000000ff)
            ^ this.roundkey[41];
        const f2 = (Td4[(s2 >>> 24) & 0xff] & 0xff000000)
            ^ (Td4[(s1 >>> 16) & 0xff] & 0x00ff0000)
            ^ (Td4[(s0 >>> 8) & 0xff] & 0x0000ff00)
            ^ (Td4[(s3 >>> 0) & 0xff] & 0x000000ff)
            ^ this.roundkey[42];
        const f3 = (Td4[(s3 >>> 24) & 0xff] & 0xff000000)
            ^ (Td4[(s2 >>> 16) & 0xff] & 0x00ff0000)
            ^ (Td4[(s1 >>> 8) & 0xff] & 0x0000ff00)
            ^ (Td4[(s0 >>> 0) & 0xff] & 0x000000ff)
            ^ this.roundkey[43];
        // CBC XOR and output
        this.outView.setUint32(0, f0 ^ this.iv[0], false);
        this.outView.setUint32(4, f1 ^ this.iv[1], false);
        this.outView.setUint32(8, f2 ^ this.iv[2], false);
        this.outView.setUint32(12, f3 ^ this.iv[3], false);
        // Update IV for next block
        this.iv[0] = temp0;
        this.iv[1] = temp1;
        this.iv[2] = temp2;
        this.iv[3] = temp3;
    }
}
const createAes128CbcDecryptStream = (reader, getInit, close) => {
    let initted = false;
    let pos = 0;
    const CHUNK_SIZE = 2 ** 16;
    const BLOCK_SIZE = 16;
    const aesContext = new Aes128CbcContext();
    return new ReadableStream({
        pull: async (controller) => {
            if (!initted) {
                aesContext.init(await getInit());
                initted = true;
            }
            const requestedLength = CHUNK_SIZE + BLOCK_SIZE;
            let nextSlice = reader.requestSliceRange(pos, 0, requestedLength);
            if (nextSlice instanceof Promise)
                nextSlice = await nextSlice;
            if (!nextSlice || nextSlice.length === 0) {
                // Due to padding, this should never happen
                throw new Error('Invalid ciphertext.');
            }
            const sliceLength = nextSlice.length;
            if (sliceLength % 16 !== 0) {
                throw new Error('Invalid ciphertext.');
            }
            const bytesToRead = sliceLength === requestedLength
                ? sliceLength - BLOCK_SIZE // Don't read the last block
                : sliceLength;
            const input = (0,src_reader/* readBytes */.io)(nextSlice, bytesToRead);
            const output = new Uint8Array(bytesToRead);
            for (let i = 0; i < bytesToRead; i += 16) {
                aesContext.in.set(input.subarray(i, i + 16));
                aesContext.decrypt();
                output.set(aesContext.out, i);
            }
            if (bytesToRead < sliceLength) {
                controller.enqueue(output);
                pos += bytesToRead;
            }
            else {
                // This is the last chunk
                const paddingLength = output[bytesToRead - 1];
                if (paddingLength === 0 || paddingLength > 16) {
                    throw new Error('Invalid PKCS#7 padding. Incorrect key or corrupted data.');
                }
                const trimmedOutput = output.subarray(0, bytesToRead - paddingLength); // PKCS#7 padding
                controller.enqueue(trimmedOutput);
                controller.close();
                close();
            }
        },
        cancel: () => {
            close();
        },
    });
};

;// ./node_modules/mediabunny/dist/modules/src/isobmff/isobmff-demuxer.js
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */













class IsobmffDemuxer extends demuxer/* Demuxer */.B {
    constructor(input) {
        super(input);
        this.moovSlice = null;
        this.currentTrack = null;
        this.tracks = [];
        this.metadataPromise = null;
        this.movieTimescale = -1;
        this.movieDurationInTimescale = -1;
        this.isQuickTime = false;
        this.metadataTags = {};
        this.currentMetadataKeys = null;
        this.isFragmented = false;
        this.fragmentTrackDefaults = [];
        this.psshBoxes = [];
        this.currentFragment = null;
        /**
         * Caches the last fragment that was read. Based on the assumption that there will be multiple reads to the
         * same fragment in quick succession.
         */
        this.lastReadFragment = null;
        this.decryptionKeyCache = new Map();
        this.reader = input._reader;
    }
    async getTrackBackings() {
        await this.readMetadata();
        return this.tracks.map(track => track.trackBacking);
    }
    async getMimeType() {
        await this.readMetadata();
        const backings = await this.getTrackBackings();
        const codecStrings = await Promise.all(backings.map(x => x.getDecoderConfig().then(c => c?.codec ?? null)));
        return (0,isobmff_misc/* buildIsobmffMimeType */.Xh)({
            isQuickTime: this.isQuickTime,
            hasVideo: this.tracks.some(x => x.info?.type === 'video'),
            hasAudio: this.tracks.some(x => x.info?.type === 'audio'),
            codecStrings: codecStrings.filter(Boolean),
        });
    }
    async getMetadataTags() {
        await this.readMetadata();
        return this.metadataTags;
    }
    readMetadata() {
        return this.metadataPromise ??= (async () => {
            let currentPos = 0;
            let lookForMfraBox = false;
            while (true) {
                let slice = this.reader.requestSliceRange(currentPos, isobmff_reader/* MIN_BOX_HEADER_SIZE */.ZM, isobmff_reader/* MAX_BOX_HEADER_SIZE */.Xk);
                if (slice instanceof Promise)
                    slice = await slice;
                if (!slice)
                    break;
                const startPos = currentPos;
                const boxInfo = (0,isobmff_reader/* readBoxHeader */.Vl)(slice);
                if (!boxInfo) {
                    break;
                }
                if (boxInfo.name === 'ftyp' || boxInfo.name === 'styp') {
                    const majorBrand = (0,src_reader/* readAscii */.IT)(slice, 4);
                    this.isQuickTime = majorBrand === 'qt  ';
                }
                else if (boxInfo.name === 'moov') {
                    // Found moov, load it
                    let moovSlice = this.reader.requestSlice(slice.filePos, boxInfo.contentSize);
                    if (moovSlice instanceof Promise)
                        moovSlice = await moovSlice;
                    if (!moovSlice)
                        break;
                    this.moovSlice = moovSlice;
                    this.readContiguousBoxes(this.moovSlice);
                    for (const track of this.tracks) {
                        // Modify the edit list offset based on the previous segment durations. They are in different
                        // timescales, so we first convert to seconds and then into the track timescale.
                        const previousSegmentDurationsInSeconds = track.editListPreviousSegmentDurations / this.movieTimescale;
                        track.editListOffset -= Math.round(previousSegmentDurationsInSeconds * track.timescale);
                    }
                    lookForMfraBox = this.isFragmented
                        && this.reader.fileSize !== null
                        && this.reader.fileSize > startPos + boxInfo.totalSize; // There's more after the moov box
                    break;
                }
                else if (boxInfo.name === 'moof') {
                    if (!this.input._initInput) {
                        throw new Error('"moof" box encountered with no "moov" box present; this file is likely a Segment as'
                            + ' described in ISO/IEC 14496-12 Section 8.16. A separate init file that contains a "moov"'
                            + ' box is required to read this file, please provide it using InputOptions.initInput.');
                    }
                    const initDemuxer = (await this.input._initInput._getDemuxer());
                    if (initDemuxer.constructor !== IsobmffDemuxer) {
                        throw new Error('Init input must match the input\'s format.');
                    }
                    await initDemuxer.readMetadata();
                    this.movieTimescale = initDemuxer.movieTimescale;
                    this.movieDurationInTimescale = initDemuxer.movieDurationInTimescale;
                    this.metadataTags = initDemuxer.metadataTags;
                    this.isFragmented = true;
                    this.fragmentTrackDefaults = initDemuxer.fragmentTrackDefaults;
                    this.psshBoxes = initDemuxer.psshBoxes;
                    // Create tracks from the init input's tracks
                    for (const foreignTrack of initDemuxer.tracks) {
                        const track = {
                            id: foreignTrack.id,
                            demuxer: this,
                            trackBacking: null,
                            disposition: foreignTrack.disposition,
                            timescale: foreignTrack.timescale,
                            durationInMediaTimescale: foreignTrack.durationInMediaTimescale,
                            durationInMovieTimescale: foreignTrack.durationInMovieTimescale,
                            rotation: foreignTrack.rotation,
                            internalCodecId: foreignTrack.internalCodecId,
                            name: foreignTrack.name,
                            languageCode: foreignTrack.languageCode,
                            sampleTableByteOffset: null,
                            sampleTable: null,
                            fragmentLookupTable: [],
                            currentFragmentState: null,
                            fragmentPositionCache: [],
                            editListPreviousSegmentDurations: foreignTrack.editListPreviousSegmentDurations,
                            editListOffset: foreignTrack.editListOffset,
                            encryptionInfo: foreignTrack.encryptionInfo,
                            encryptionAuxInfo: null,
                            frmaCodecString: null,
                            info: foreignTrack.info,
                        };
                        if (foreignTrack.trackBacking) {
                            (0,misc/* assert */.vA)(track.info);
                            if (track.info.type === 'video' && track.info.width !== -1) {
                                const videoTrack = track;
                                track.trackBacking = new IsobmffVideoTrackBacking(videoTrack);
                                this.tracks.push(track);
                            }
                            else if (track.info.type === 'audio' && track.info.numberOfChannels !== -1) {
                                const audioTrack = track;
                                track.trackBacking = new IsobmffAudioTrackBacking(audioTrack);
                                this.tracks.push(track);
                            }
                        }
                        else {
                            // The track didn't have enough info to warrant a backing
                        }
                    }
                    lookForMfraBox = false; // No point in doing it for segment files
                    break;
                }
                currentPos = startPos + boxInfo.totalSize;
            }
            if (lookForMfraBox) {
                (0,misc/* assert */.vA)(this.reader.fileSize !== null);
                // The last 4 bytes may contain the size of the mfra box at the end of the file
                let lastWordSlice = this.reader.requestSlice(this.reader.fileSize - 4, 4);
                if (lastWordSlice instanceof Promise)
                    lastWordSlice = await lastWordSlice;
                (0,misc/* assert */.vA)(lastWordSlice);
                const lastWord = (0,src_reader/* readU32Be */.cN)(lastWordSlice);
                const potentialMfraPos = this.reader.fileSize - lastWord;
                if (potentialMfraPos >= 0 && potentialMfraPos <= this.reader.fileSize - isobmff_reader/* MAX_BOX_HEADER_SIZE */.Xk) {
                    let mfraHeaderSlice = this.reader.requestSliceRange(potentialMfraPos, isobmff_reader/* MIN_BOX_HEADER_SIZE */.ZM, isobmff_reader/* MAX_BOX_HEADER_SIZE */.Xk);
                    if (mfraHeaderSlice instanceof Promise)
                        mfraHeaderSlice = await mfraHeaderSlice;
                    if (mfraHeaderSlice) {
                        const boxInfo = (0,isobmff_reader/* readBoxHeader */.Vl)(mfraHeaderSlice);
                        if (boxInfo && boxInfo.name === 'mfra') {
                            // We found the mfra box, allowing for much better random access. Let's parse it.
                            let mfraSlice = this.reader.requestSlice(mfraHeaderSlice.filePos, boxInfo.contentSize);
                            if (mfraSlice instanceof Promise)
                                mfraSlice = await mfraSlice;
                            if (mfraSlice) {
                                this.readContiguousBoxes(mfraSlice);
                            }
                        }
                    }
                }
            }
        })();
    }
    getSampleTableForTrack(internalTrack) {
        if (internalTrack.sampleTable) {
            return internalTrack.sampleTable;
        }
        const sampleTable = {
            sampleTimingEntries: [],
            sampleCompositionTimeOffsets: [],
            sampleSizes: [],
            keySampleIndices: null,
            chunkOffsets: [],
            sampleToChunk: [],
            presentationTimestamps: null,
            presentationTimestampIndexMap: null,
        };
        internalTrack.sampleTable = sampleTable;
        if (internalTrack.sampleTableByteOffset === null) {
            // There's no sample table to read, it's in another file (happens with segments)
            return sampleTable;
        }
        (0,misc/* assert */.vA)(this.moovSlice);
        const stblContainerSlice = this.moovSlice.slice(internalTrack.sampleTableByteOffset);
        this.currentTrack = internalTrack;
        this.traverseBox(stblContainerSlice);
        this.currentTrack = null;
        const isPcmCodec = internalTrack.info?.type === 'audio'
            && internalTrack.info.codec
            && codec/* PCM_AUDIO_CODECS */.Wq.includes(internalTrack.info.codec);
        if (isPcmCodec && sampleTable.sampleCompositionTimeOffsets.length === 0) {
            // If the audio has PCM samples, the way the samples are defined in the sample table is somewhat
            // suboptimal: Each individual audio sample is its own sample, meaning we can have 48000 samples per second.
            // Because we treat each sample as its own atomic unit that can be decoded, this would lead to a huge
            // amount of very short samples for PCM audio. So instead, we make a transformation: If the audio is in PCM,
            // we say that each chunk (that normally holds many samples) now is one big sample. We can this because
            // the samples in the chunk are contiguous and the format is PCM, so the entire chunk as one thing still
            // encodes valid audio information.
            (0,misc/* assert */.vA)(internalTrack.info?.type === 'audio');
            const pcmInfo = (0,codec/* parsePcmCodec */.Ei)(internalTrack.info.codec);
            const newSampleTimingEntries = [];
            const newSampleSizes = [];
            for (let i = 0; i < sampleTable.sampleToChunk.length; i++) {
                const chunkEntry = sampleTable.sampleToChunk[i];
                const nextEntry = sampleTable.sampleToChunk[i + 1];
                const chunkCount = (nextEntry ? nextEntry.startChunkIndex : sampleTable.chunkOffsets.length)
                    - chunkEntry.startChunkIndex;
                for (let j = 0; j < chunkCount; j++) {
                    const startSampleIndex = chunkEntry.startSampleIndex + j * chunkEntry.samplesPerChunk;
                    const endSampleIndex = startSampleIndex + chunkEntry.samplesPerChunk; // Exclusive, outside of chunk
                    const startTimingEntryIndex = (0,misc/* binarySearchLessOrEqual */.eE)(sampleTable.sampleTimingEntries, startSampleIndex, x => x.startIndex);
                    const startTimingEntry = sampleTable.sampleTimingEntries[startTimingEntryIndex];
                    const endTimingEntryIndex = (0,misc/* binarySearchLessOrEqual */.eE)(sampleTable.sampleTimingEntries, endSampleIndex, x => x.startIndex);
                    const endTimingEntry = sampleTable.sampleTimingEntries[endTimingEntryIndex];
                    const firstSampleTimestamp = startTimingEntry.startDecodeTimestamp
                        + (startSampleIndex - startTimingEntry.startIndex) * startTimingEntry.delta;
                    const lastSampleTimestamp = endTimingEntry.startDecodeTimestamp
                        + (endSampleIndex - endTimingEntry.startIndex) * endTimingEntry.delta;
                    const delta = lastSampleTimestamp - firstSampleTimestamp;
                    const lastSampleTimingEntry = (0,misc/* last */._g)(newSampleTimingEntries);
                    if (lastSampleTimingEntry && lastSampleTimingEntry.delta === delta) {
                        lastSampleTimingEntry.count++;
                    }
                    else {
                        // One sample for the entire chunk
                        newSampleTimingEntries.push({
                            startIndex: chunkEntry.startChunkIndex + j,
                            startDecodeTimestamp: firstSampleTimestamp,
                            count: 1,
                            delta,
                        });
                    }
                    // Instead of determining the chunk's size by looping over the samples sizes in the sample table, we
                    // can directly compute it as we know how many PCM frames are in this chunk, and the size of each
                    // PCM frame. This also improves compatibility with some files which fail to write proper sample
                    // size values into their sample tables in the PCM case.
                    const chunkSize = chunkEntry.samplesPerChunk
                        * pcmInfo.sampleSize
                        * internalTrack.info.numberOfChannels;
                    newSampleSizes.push(chunkSize);
                }
                chunkEntry.startSampleIndex = chunkEntry.startChunkIndex;
                chunkEntry.samplesPerChunk = 1;
            }
            sampleTable.sampleTimingEntries = newSampleTimingEntries;
            sampleTable.sampleSizes = newSampleSizes;
        }
        if (sampleTable.sampleCompositionTimeOffsets.length > 0) {
            // If composition time offsets are defined, we must build a list of all presentation timestamps and then
            // sort them
            sampleTable.presentationTimestamps = [];
            for (const entry of sampleTable.sampleTimingEntries) {
                for (let i = 0; i < entry.count; i++) {
                    sampleTable.presentationTimestamps.push({
                        presentationTimestamp: entry.startDecodeTimestamp + i * entry.delta,
                        sampleIndex: entry.startIndex + i,
                    });
                }
            }
            for (const entry of sampleTable.sampleCompositionTimeOffsets) {
                for (let i = 0; i < entry.count; i++) {
                    const sampleIndex = entry.startIndex + i;
                    const sample = sampleTable.presentationTimestamps[sampleIndex];
                    if (!sample) {
                        continue;
                    }
                    sample.presentationTimestamp += entry.offset;
                }
            }
            sampleTable.presentationTimestamps.sort((a, b) => a.presentationTimestamp - b.presentationTimestamp);
            sampleTable.presentationTimestampIndexMap = Array(sampleTable.presentationTimestamps.length).fill(-1);
            for (let i = 0; i < sampleTable.presentationTimestamps.length; i++) {
                sampleTable.presentationTimestampIndexMap[sampleTable.presentationTimestamps[i].sampleIndex] = i;
            }
        }
        else {
            // If they're not defined, we can simply use the decode timestamps as presentation timestamps
        }
        return sampleTable;
    }
    async readFragment(startPos) {
        if (this.lastReadFragment?.moofOffset === startPos) {
            return this.lastReadFragment;
        }
        let headerSlice = this.reader.requestSliceRange(startPos, isobmff_reader/* MIN_BOX_HEADER_SIZE */.ZM, isobmff_reader/* MAX_BOX_HEADER_SIZE */.Xk);
        if (headerSlice instanceof Promise)
            headerSlice = await headerSlice;
        (0,misc/* assert */.vA)(headerSlice);
        const moofBoxInfo = (0,isobmff_reader/* readBoxHeader */.Vl)(headerSlice);
        (0,misc/* assert */.vA)(moofBoxInfo?.name === 'moof');
        let entireSlice = this.reader.requestSlice(startPos, moofBoxInfo.totalSize);
        if (entireSlice instanceof Promise)
            entireSlice = await entireSlice;
        (0,misc/* assert */.vA)(entireSlice);
        this.traverseBox(entireSlice);
        const fragment = this.lastReadFragment;
        (0,misc/* assert */.vA)(fragment && fragment.moofOffset === startPos);
        for (const [, trackData] of fragment.trackData) {
            const track = trackData.track;
            const { fragmentPositionCache } = track;
            if (!trackData.startTimestampIsFinal) {
                // It may be that some tracks don't define the base decode time, i.e. when the fragment begins. This
                // we'll need to figure out the start timestamp another way. We'll compute the timestamp by accessing
                // the lookup entries and fragment cache, which works out nicely with the lookup algorithm: If these
                // exist, then the lookup will automatically start at the furthest possible point. If they don't, the
                // lookup starts sequentially from the start, incrementally summing up all fragment durations. It's sort
                // of implicit, but it ends up working nicely.
                const lookupEntry = track.fragmentLookupTable.find(x => x.moofOffset === fragment.moofOffset);
                if (lookupEntry) {
                    // There's a lookup entry, let's use its timestamp
                    offsetFragmentTrackDataByTimestamp(trackData, lookupEntry.timestamp);
                }
                else {
                    const lastCacheIndex = (0,misc/* binarySearchLessOrEqual */.eE)(fragmentPositionCache, fragment.moofOffset - 1, x => x.moofOffset);
                    if (lastCacheIndex !== -1) {
                        // Let's use the timestamp of the previous fragment in the cache
                        const lastCache = fragmentPositionCache[lastCacheIndex];
                        offsetFragmentTrackDataByTimestamp(trackData, lastCache.endTimestamp);
                    }
                    else {
                        // We're the first fragment I guess, "offset by 0"
                    }
                }
                trackData.startTimestampIsFinal = true;
            }
            // Let's remember that a fragment with a given timestamp is here, speeding up future lookups if no
            // lookup table exists
            const insertionIndex = (0,misc/* binarySearchLessOrEqual */.eE)(fragmentPositionCache, trackData.startTimestamp, x => x.startTimestamp);
            if (insertionIndex === -1
                || fragmentPositionCache[insertionIndex].moofOffset !== fragment.moofOffset) {
                fragmentPositionCache.splice(insertionIndex + 1, 0, {
                    moofOffset: fragment.moofOffset,
                    startTimestamp: trackData.startTimestamp,
                    endTimestamp: trackData.endTimestamp,
                });
            }
            // If senc wasn't parsed but saiz+saio were, fetch the aux info now and stamp each sample with it
            if (trackData.encryptionAuxInfo && track.encryptionInfo) {
                const entries = await resolveEncryptionAuxInfo(this.reader, track.encryptionInfo, trackData.encryptionAuxInfo);
                for (let i = 0; i < Math.min(trackData.samples.length, entries.length); i++) {
                    const entry = entries[i];
                    trackData.samples[i].encryption = entry;
                }
            }
        }
        return fragment;
    }
    readContiguousBoxes(slice) {
        const startIndex = slice.filePos;
        while (slice.filePos - startIndex <= slice.length - isobmff_reader/* MIN_BOX_HEADER_SIZE */.ZM) {
            const foundBox = this.traverseBox(slice);
            if (!foundBox) {
                break;
            }
        }
    }
    // eslint-disable-next-line @stylistic/generator-star-spacing
    *iterateContiguousBoxes(slice) {
        const startIndex = slice.filePos;
        while (slice.filePos - startIndex <= slice.length - isobmff_reader/* MIN_BOX_HEADER_SIZE */.ZM) {
            const startPos = slice.filePos;
            const boxInfo = (0,isobmff_reader/* readBoxHeader */.Vl)(slice);
            if (!boxInfo) {
                break;
            }
            yield { boxInfo, slice };
            slice.filePos = startPos + boxInfo.totalSize;
        }
    }
    traverseBox(slice) {
        const startPos = slice.filePos;
        const boxInfo = (0,isobmff_reader/* readBoxHeader */.Vl)(slice);
        if (!boxInfo) {
            return false;
        }
        const contentStartPos = slice.filePos;
        const boxEndPos = startPos + boxInfo.totalSize;
        switch (boxInfo.name) {
            case 'mdia':
            case 'minf':
            case 'dinf':
            case 'mfra':
            case 'edts':
            case 'sinf':
            case 'schi':
                {
                    this.readContiguousBoxes(slice.slice(contentStartPos, boxInfo.contentSize));
                }
                ;
                break;
            case 'mvhd':
                {
                    const version = (0,src_reader/* readU8 */.eo)(slice);
                    slice.skip(3); // Flags
                    if (version === 1) {
                        slice.skip(8 + 8);
                        this.movieTimescale = (0,src_reader/* readU32Be */.cN)(slice);
                        this.movieDurationInTimescale = (0,src_reader/* readU64Be */.th)(slice);
                    }
                    else {
                        slice.skip(4 + 4);
                        this.movieTimescale = (0,src_reader/* readU32Be */.cN)(slice);
                        this.movieDurationInTimescale = (0,src_reader/* readU32Be */.cN)(slice);
                    }
                }
                ;
                break;
            case 'trak':
                {
                    const track = {
                        id: -1,
                        demuxer: this,
                        trackBacking: null,
                        disposition: {
                            ...metadata/* DEFAULT_TRACK_DISPOSITION */.gM,
                            primary: false,
                        },
                        info: null,
                        timescale: -1,
                        durationInMovieTimescale: -1,
                        durationInMediaTimescale: -1,
                        rotation: 0,
                        internalCodecId: null,
                        name: null,
                        languageCode: misc/* UNDETERMINED_LANGUAGE */.IR,
                        sampleTableByteOffset: -1,
                        sampleTable: null,
                        fragmentLookupTable: [],
                        currentFragmentState: null,
                        fragmentPositionCache: [],
                        editListPreviousSegmentDurations: 0,
                        editListOffset: 0,
                        encryptionInfo: null,
                        encryptionAuxInfo: null,
                        frmaCodecString: null,
                    };
                    this.currentTrack = track;
                    this.readContiguousBoxes(slice.slice(contentStartPos, boxInfo.contentSize));
                    if (track.id !== -1 && track.timescale !== -1 && track.info !== null) {
                        if (track.info.type === 'video' && track.info.width !== -1) {
                            const videoTrack = track;
                            track.trackBacking = new IsobmffVideoTrackBacking(videoTrack);
                            this.tracks.push(track);
                        }
                        else if (track.info.type === 'audio' && track.info.numberOfChannels !== -1) {
                            const audioTrack = track;
                            track.trackBacking = new IsobmffAudioTrackBacking(audioTrack);
                            this.tracks.push(track);
                        }
                    }
                    this.currentTrack = null;
                }
                ;
                break;
            case 'tkhd':
                {
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    const version = (0,src_reader/* readU8 */.eo)(slice);
                    const flags = (0,src_reader/* readU24Be */.n2)(slice);
                    // Spec says disabled tracks are to be treated like they don't exist, but in practice, they are treated
                    // more like non-default tracks.
                    const trackEnabled = !!(flags & 0x1);
                    track.disposition.default = trackEnabled;
                    // Skip over creation & modification time to reach the track ID
                    if (version === 0) {
                        slice.skip(8);
                        track.id = (0,src_reader/* readU32Be */.cN)(slice);
                        slice.skip(4);
                        track.durationInMovieTimescale = (0,src_reader/* readU32Be */.cN)(slice);
                    }
                    else if (version === 1) {
                        slice.skip(16);
                        track.id = (0,src_reader/* readU32Be */.cN)(slice);
                        slice.skip(4);
                        track.durationInMovieTimescale = (0,src_reader/* readU64Be */.th)(slice);
                    }
                    else {
                        throw new Error(`Incorrect track header version ${version}.`);
                    }
                    slice.skip(2 * 4 + 2 + 2 + 2 + 2);
                    const matrix = [
                        (0,isobmff_reader/* readFixed_16_16 */.vX)(slice),
                        (0,isobmff_reader/* readFixed_16_16 */.vX)(slice),
                        (0,isobmff_reader/* readFixed_2_30 */.IS)(slice),
                        (0,isobmff_reader/* readFixed_16_16 */.vX)(slice),
                        (0,isobmff_reader/* readFixed_16_16 */.vX)(slice),
                        (0,isobmff_reader/* readFixed_2_30 */.IS)(slice),
                        (0,isobmff_reader/* readFixed_16_16 */.vX)(slice),
                        (0,isobmff_reader/* readFixed_16_16 */.vX)(slice),
                        (0,isobmff_reader/* readFixed_2_30 */.IS)(slice),
                    ];
                    const rotation = (0,misc/* normalizeRotation */.qT)((0,misc/* roundToMultiple */["in"])(extractRotationFromMatrix(matrix), 90));
                    (0,misc/* assert */.vA)(rotation === 0 || rotation === 90 || rotation === 180 || rotation === 270);
                    track.rotation = rotation;
                }
                ;
                break;
            case 'elst':
                {
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    const version = (0,src_reader/* readU8 */.eo)(slice);
                    slice.skip(3); // Flags
                    let relevantEntryFound = false;
                    let previousSegmentDurations = 0;
                    const entryCount = (0,src_reader/* readU32Be */.cN)(slice);
                    for (let i = 0; i < entryCount; i++) {
                        const segmentDuration = version === 1
                            ? (0,src_reader/* readU64Be */.th)(slice)
                            : (0,src_reader/* readU32Be */.cN)(slice);
                        const mediaTime = version === 1
                            ? (0,src_reader/* readI64Be */.B5)(slice)
                            : (0,src_reader/* readI32Be */.Ar)(slice);
                        const mediaRate = (0,isobmff_reader/* readFixed_16_16 */.vX)(slice);
                        if (segmentDuration === 0) {
                            // Don't care
                            continue;
                        }
                        if (relevantEntryFound) {
                            console.warn('Unsupported edit list: multiple edits are not currently supported. Only using first edit.');
                            break;
                        }
                        if (mediaTime === -1) {
                            previousSegmentDurations += segmentDuration;
                            continue;
                        }
                        if (mediaRate !== 1) {
                            console.warn('Unsupported edit list entry: media rate must be 1.');
                            break;
                        }
                        track.editListPreviousSegmentDurations = previousSegmentDurations;
                        track.editListOffset = mediaTime;
                        relevantEntryFound = true;
                    }
                }
                ;
                break;
            case 'mdhd':
                {
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    const version = (0,src_reader/* readU8 */.eo)(slice);
                    slice.skip(3); // Flags
                    if (version === 0) {
                        slice.skip(8);
                        track.timescale = (0,src_reader/* readU32Be */.cN)(slice);
                        track.durationInMediaTimescale = (0,src_reader/* readU32Be */.cN)(slice);
                    }
                    else if (version === 1) {
                        slice.skip(16);
                        track.timescale = (0,src_reader/* readU32Be */.cN)(slice);
                        track.durationInMediaTimescale = (0,src_reader/* readU64Be */.th)(slice);
                    }
                    let language = (0,src_reader/* readU16Be */.mH)(slice);
                    if (language > 0) {
                        track.languageCode = '';
                        for (let i = 0; i < 3; i++) {
                            track.languageCode = String.fromCharCode(0x60 + (language & 0b11111)) + track.languageCode;
                            language >>= 5;
                        }
                        if (!(0,misc/* isIso639Dash2LanguageCode */.Nu)(track.languageCode)) {
                            // Sometimes the bytes are garbage
                            track.languageCode = misc/* UNDETERMINED_LANGUAGE */.IR;
                        }
                    }
                }
                ;
                break;
            case 'hdlr':
                {
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    slice.skip(8); // Version + flags + pre-defined
                    const handlerType = (0,src_reader/* readAscii */.IT)(slice, 4);
                    if (handlerType === 'vide') {
                        track.info = {
                            type: 'video',
                            width: -1,
                            height: -1,
                            squarePixelWidth: -1,
                            squarePixelHeight: -1,
                            codec: null,
                            codecDescription: null,
                            colorSpace: null,
                            avcType: null,
                            avcCodecInfo: null,
                            hevcCodecInfo: null,
                            vp9CodecInfo: null,
                            av1CodecInfo: null,
                        };
                    }
                    else if (handlerType === 'soun') {
                        track.info = {
                            type: 'audio',
                            numberOfChannels: -1,
                            sampleRate: -1,
                            codec: null,
                            codecDescription: null,
                            aacCodecInfo: null,
                            pcmLittleEndian: false,
                            pcmSampleSize: null,
                        };
                    }
                }
                ;
                break;
            case 'stbl':
                {
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    track.sampleTableByteOffset = startPos;
                    this.readContiguousBoxes(slice.slice(contentStartPos, boxInfo.contentSize));
                }
                ;
                break;
            case 'stsd':
                {
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    if (track.info === null || track.sampleTable) {
                        break;
                    }
                    const stsdVersion = (0,src_reader/* readU8 */.eo)(slice);
                    slice.skip(3); // Flags
                    const entries = (0,src_reader/* readU32Be */.cN)(slice);
                    for (let i = 0; i < entries; i++) {
                        const sampleBoxStartPos = slice.filePos;
                        const sampleBoxInfo = (0,isobmff_reader/* readBoxHeader */.Vl)(slice);
                        if (!sampleBoxInfo) {
                            break;
                        }
                        track.internalCodecId = sampleBoxInfo.name;
                        const lowercaseBoxName = sampleBoxInfo.name.toLowerCase();
                        if (track.info.type === 'video') {
                            slice.skip(6 * 1 + 2 + 2 + 2 + 3 * 4);
                            track.info.width = (0,src_reader/* readU16Be */.mH)(slice);
                            track.info.height = (0,src_reader/* readU16Be */.mH)(slice);
                            track.info.squarePixelWidth = track.info.width;
                            track.info.squarePixelHeight = track.info.height;
                            slice.skip(4 + 4 + 4 + 2 + 32 + 2 + 2);
                            track.frmaCodecString = null;
                            this.readContiguousBoxes(slice.slice(slice.filePos, (sampleBoxStartPos + sampleBoxInfo.totalSize) - slice.filePos));
                            const codecName = lowercaseBoxName === 'encv'
                                ? track.frmaCodecString
                                : lowercaseBoxName;
                            track.frmaCodecString = null;
                            if (codecName === 'avc1' || codecName === 'avc3') {
                                track.info.codec = 'avc';
                                track.info.avcType = codecName === 'avc1' ? 1 : 3;
                            }
                            else if (codecName === 'hvc1' || codecName === 'hev1') {
                                track.info.codec = 'hevc';
                            }
                            else if (codecName === 'vp08') {
                                track.info.codec = 'vp8';
                            }
                            else if (codecName === 'vp09') {
                                track.info.codec = 'vp9';
                            }
                            else if (codecName === 'av01') {
                                track.info.codec = 'av1';
                            }
                            else if (codecName === null) {
                                console.warn(`Unknown encrypted video codec due to missing frma box.`);
                            }
                            else {
                                console.warn(`Unsupported video codec (sample entry type '${sampleBoxInfo.name}').`);
                            }
                        }
                        else {
                            slice.skip(6 * 1 + 2);
                            const version = (0,src_reader/* readU16Be */.mH)(slice);
                            slice.skip(3 * 2);
                            let channelCount = (0,src_reader/* readU16Be */.mH)(slice);
                            let sampleSize = (0,src_reader/* readU16Be */.mH)(slice);
                            slice.skip(2 * 2);
                            // Can't use fixed16_16 as that's signed
                            let sampleRate = (0,src_reader/* readU32Be */.cN)(slice) / 0x10000;
                            let lpcmFlags = null;
                            if (stsdVersion === 0 && version > 0) {
                                // Additional QuickTime fields
                                if (version === 1) {
                                    slice.skip(4);
                                    sampleSize = 8 * (0,src_reader/* readU32Be */.cN)(slice);
                                    slice.skip(2 * 4);
                                }
                                else if (version === 2) {
                                    slice.skip(4);
                                    sampleRate = (0,src_reader/* readF64Be */._3)(slice);
                                    channelCount = (0,src_reader/* readU32Be */.cN)(slice);
                                    slice.skip(4); // Always 0x7f000000
                                    sampleSize = (0,src_reader/* readU32Be */.cN)(slice);
                                    lpcmFlags = (0,src_reader/* readU32Be */.cN)(slice);
                                    slice.skip(2 * 4);
                                }
                            }
                            track.info.numberOfChannels = channelCount;
                            track.info.sampleRate = sampleRate;
                            track.frmaCodecString = null;
                            this.readContiguousBoxes(slice.slice(slice.filePos, (sampleBoxStartPos + sampleBoxInfo.totalSize) - slice.filePos));
                            const codecName = lowercaseBoxName === 'enca'
                                ? track.frmaCodecString
                                : lowercaseBoxName;
                            track.frmaCodecString = null;
                            // developer.apple.com/documentation/quicktime-file-format/sound_sample_descriptions/
                            if (codecName === 'mp4a') {
                                // The codec is set by the esds box
                            }
                            else if (codecName === 'opus') {
                                track.info.codec = 'opus';
                                track.info.sampleRate = codec/* OPUS_SAMPLE_RATE */.yo; // Always the same
                            }
                            else if (codecName === 'flac') {
                                track.info.codec = 'flac';
                            }
                            else if (codecName === 'ulaw') {
                                track.info.codec = 'ulaw';
                            }
                            else if (codecName === 'alaw') {
                                track.info.codec = 'alaw';
                            }
                            else if (codecName === 'ac-3') {
                                track.info.codec = 'ac3';
                            }
                            else if (codecName === 'ec-3') {
                                track.info.codec = 'eac3';
                            }
                            else if (codecName === 'twos') {
                                if (sampleSize === 8) {
                                    track.info.codec = 'pcm-s8';
                                }
                                else if (sampleSize === 16) {
                                    track.info.codec = track.info.pcmLittleEndian ? 'pcm-s16' : 'pcm-s16be';
                                }
                                else {
                                    console.warn(`Unsupported sample size ${sampleSize} for codec 'twos'.`);
                                    track.info.codec = null;
                                }
                            }
                            else if (codecName === 'sowt') {
                                if (sampleSize === 8) {
                                    track.info.codec = 'pcm-s8';
                                }
                                else if (sampleSize === 16) {
                                    track.info.codec = 'pcm-s16';
                                }
                                else {
                                    console.warn(`Unsupported sample size ${sampleSize} for codec 'sowt'.`);
                                    track.info.codec = null;
                                }
                            }
                            else if (codecName === 'raw ') {
                                track.info.codec = 'pcm-u8';
                            }
                            else if (codecName === 'in24') {
                                track.info.codec = track.info.pcmLittleEndian ? 'pcm-s24' : 'pcm-s24be';
                            }
                            else if (codecName === 'in32') {
                                track.info.codec = track.info.pcmLittleEndian ? 'pcm-s32' : 'pcm-s32be';
                            }
                            else if (codecName === 'fl32') {
                                track.info.codec = track.info.pcmLittleEndian ? 'pcm-f32' : 'pcm-f32be';
                            }
                            else if (codecName === 'fl64') {
                                track.info.codec = track.info.pcmLittleEndian ? 'pcm-f64' : 'pcm-f64be';
                            }
                            else if (codecName === 'ipcm') {
                                const pcmSampleSize = track.info.pcmSampleSize;
                                if (track.info.pcmLittleEndian) {
                                    if (pcmSampleSize === 16) {
                                        track.info.codec = 'pcm-s16';
                                    }
                                    else if (pcmSampleSize === 24) {
                                        track.info.codec = 'pcm-s24';
                                    }
                                    else if (pcmSampleSize === 32) {
                                        track.info.codec = 'pcm-s32';
                                    }
                                    else {
                                        console.warn(`Invalid ipcm sample size ${pcmSampleSize}.`);
                                        track.info.codec = null;
                                    }
                                }
                                else {
                                    if (pcmSampleSize === 16) {
                                        track.info.codec = 'pcm-s16be';
                                    }
                                    else if (pcmSampleSize === 24) {
                                        track.info.codec = 'pcm-s24be';
                                    }
                                    else if (pcmSampleSize === 32) {
                                        track.info.codec = 'pcm-s32be';
                                    }
                                    else {
                                        console.warn(`Invalid ipcm sample size ${pcmSampleSize}.`);
                                        track.info.codec = null;
                                    }
                                }
                            }
                            else if (codecName === 'fpcm') {
                                const pcmSampleSize = track.info.pcmSampleSize;
                                if (track.info.pcmLittleEndian) {
                                    if (pcmSampleSize === 32) {
                                        track.info.codec = 'pcm-f32';
                                    }
                                    else if (pcmSampleSize === 64) {
                                        track.info.codec = 'pcm-f64';
                                    }
                                    else {
                                        console.warn(`Invalid fpcm sample size ${pcmSampleSize}.`);
                                        track.info.codec = null;
                                    }
                                }
                                else {
                                    if (pcmSampleSize === 32) {
                                        track.info.codec = 'pcm-f32be';
                                    }
                                    else if (pcmSampleSize === 64) {
                                        track.info.codec = 'pcm-f64be';
                                    }
                                    else {
                                        console.warn(`Invalid fpcm sample size ${pcmSampleSize}.`);
                                        track.info.codec = null;
                                    }
                                }
                            }
                            else if (codecName === 'lpcm' && lpcmFlags !== null) {
                                const bytesPerSample = (sampleSize + 7) >> 3;
                                const isFloat = Boolean(lpcmFlags & 1);
                                const isBigEndian = Boolean(lpcmFlags & 2);
                                const sFlags = lpcmFlags & 4 ? -1 : 0; // I guess it means "signed flags" or something?
                                if (sampleSize > 0 && sampleSize <= 64) {
                                    if (isFloat) {
                                        if (sampleSize === 32) {
                                            track.info.codec = isBigEndian ? 'pcm-f32be' : 'pcm-f32';
                                        }
                                    }
                                    else {
                                        if (sFlags & (1 << (bytesPerSample - 1))) {
                                            if (bytesPerSample === 1) {
                                                track.info.codec = 'pcm-s8';
                                            }
                                            else if (bytesPerSample === 2) {
                                                track.info.codec = isBigEndian ? 'pcm-s16be' : 'pcm-s16';
                                            }
                                            else if (bytesPerSample === 3) {
                                                track.info.codec = isBigEndian ? 'pcm-s24be' : 'pcm-s24';
                                            }
                                            else if (bytesPerSample === 4) {
                                                track.info.codec = isBigEndian ? 'pcm-s32be' : 'pcm-s32';
                                            }
                                        }
                                        else {
                                            if (bytesPerSample === 1) {
                                                track.info.codec = 'pcm-u8';
                                            }
                                        }
                                    }
                                }
                                if (track.info.codec === null) {
                                    console.warn('Unsupported PCM format.');
                                }
                            }
                            else if (codecName === null) {
                                console.warn(`Unknown encrypted audio codec due to missing frma box.`);
                            }
                            else {
                                console.warn(`Unsupported audio codec (sample entry type '${sampleBoxInfo.name}').`);
                            }
                        }
                        slice.filePos = sampleBoxStartPos + sampleBoxInfo.totalSize;
                    }
                }
                ;
                break;
            case 'frma':
                {
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    const format = (0,src_reader/* readAscii */.IT)(slice, 4);
                    const lowercase = format.toLowerCase();
                    // Tells us what codec the encrypted track actually uses
                    track.frmaCodecString = lowercase;
                }
                ;
                break;
            case 'schm':
                {
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    slice.skip(4); // Version + flags
                    const schemeType = (0,src_reader/* readAscii */.IT)(slice, 4);
                    if (schemeType === 'cenc' || schemeType === 'cens' || schemeType === 'cbcs') {
                        track.encryptionInfo = {
                            scheme: schemeType,
                            defaultKid: null,
                            defaultIsProtected: null,
                            defaultPerSampleIvSize: null,
                            defaultConstantIv: null,
                            defaultCryptByteBlock: null,
                            defaultSkipByteBlock: null,
                        };
                    }
                    else {
                        console.warn(`Unsupported encryption scheme '${schemeType}'.`);
                    }
                }
                ;
                break;
            case 'tenc':
                {
                    const track = this.currentTrack;
                    if (!track || !track.encryptionInfo) {
                        break;
                    }
                    const version = (0,src_reader/* readU8 */.eo)(slice);
                    slice.skip(3); // Flags
                    slice.skip(1); // Reserved
                    const patternByte = (0,src_reader/* readU8 */.eo)(slice);
                    if (version > 0) {
                        track.encryptionInfo.defaultCryptByteBlock = patternByte >> 4;
                        track.encryptionInfo.defaultSkipByteBlock = patternByte & 0xf;
                    }
                    else {
                        track.encryptionInfo.defaultCryptByteBlock = 0;
                        track.encryptionInfo.defaultSkipByteBlock = 0;
                    }
                    track.encryptionInfo.defaultIsProtected = (0,src_reader/* readU8 */.eo)(slice) !== 0;
                    track.encryptionInfo.defaultPerSampleIvSize = (0,src_reader/* readU8 */.eo)(slice);
                    track.encryptionInfo.defaultKid = (0,misc/* bytesToHexString */.Br)((0,src_reader/* readBytes */.io)(slice, 16));
                    if (track.encryptionInfo.defaultIsProtected && track.encryptionInfo.defaultPerSampleIvSize === 0) {
                        const constantIvSize = (0,src_reader/* readU8 */.eo)(slice);
                        const constantIv = new Uint8Array(16);
                        constantIv.set((0,src_reader/* readBytes */.io)(slice, constantIvSize), 0);
                        track.encryptionInfo.defaultConstantIv = constantIv;
                    }
                }
                ;
                break;
            case 'avcC':
                {
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    (0,misc/* assert */.vA)(track.info);
                    track.info.codecDescription = (0,src_reader/* readBytes */.io)(slice, boxInfo.contentSize);
                }
                ;
                break;
            case 'hvcC':
                {
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    (0,misc/* assert */.vA)(track.info);
                    track.info.codecDescription = (0,src_reader/* readBytes */.io)(slice, boxInfo.contentSize);
                }
                ;
                break;
            case 'vpcC':
                {
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    (0,misc/* assert */.vA)(track.info?.type === 'video');
                    slice.skip(4); // Version + flags
                    const profile = (0,src_reader/* readU8 */.eo)(slice);
                    const level = (0,src_reader/* readU8 */.eo)(slice);
                    const thirdByte = (0,src_reader/* readU8 */.eo)(slice);
                    const bitDepth = thirdByte >> 4;
                    const chromaSubsampling = (thirdByte >> 1) & 0b111;
                    const videoFullRangeFlag = thirdByte & 1;
                    const colourPrimaries = (0,src_reader/* readU8 */.eo)(slice);
                    const transferCharacteristics = (0,src_reader/* readU8 */.eo)(slice);
                    const matrixCoefficients = (0,src_reader/* readU8 */.eo)(slice);
                    track.info.vp9CodecInfo = {
                        profile,
                        level,
                        bitDepth,
                        chromaSubsampling,
                        videoFullRangeFlag,
                        colourPrimaries,
                        transferCharacteristics,
                        matrixCoefficients,
                    };
                }
                ;
                break;
            case 'av1C':
                {
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    (0,misc/* assert */.vA)(track.info?.type === 'video');
                    slice.skip(1); // Marker + version
                    const secondByte = (0,src_reader/* readU8 */.eo)(slice);
                    const profile = secondByte >> 5;
                    const level = secondByte & 0b11111;
                    const thirdByte = (0,src_reader/* readU8 */.eo)(slice);
                    const tier = thirdByte >> 7;
                    const highBitDepth = (thirdByte >> 6) & 1;
                    const twelveBit = (thirdByte >> 5) & 1;
                    const monochrome = (thirdByte >> 4) & 1;
                    const chromaSubsamplingX = (thirdByte >> 3) & 1;
                    const chromaSubsamplingY = (thirdByte >> 2) & 1;
                    const chromaSamplePosition = thirdByte & 0b11;
                    // Logic from https://aomediacodec.github.io/av1-spec/av1-spec.pdf
                    const bitDepth = profile === 2 && highBitDepth ? (twelveBit ? 12 : 10) : (highBitDepth ? 10 : 8);
                    track.info.av1CodecInfo = {
                        profile,
                        level,
                        tier,
                        bitDepth,
                        monochrome,
                        chromaSubsamplingX,
                        chromaSubsamplingY,
                        chromaSamplePosition,
                    };
                }
                ;
                break;
            case 'colr':
                {
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    (0,misc/* assert */.vA)(track.info?.type === 'video');
                    const colourType = (0,src_reader/* readAscii */.IT)(slice, 4);
                    if (colourType !== 'nclx') {
                        break;
                    }
                    const colourPrimaries = (0,src_reader/* readU16Be */.mH)(slice);
                    const transferCharacteristics = (0,src_reader/* readU16Be */.mH)(slice);
                    const matrixCoefficients = (0,src_reader/* readU16Be */.mH)(slice);
                    const fullRangeFlag = Boolean((0,src_reader/* readU8 */.eo)(slice) & 0x80);
                    track.info.colorSpace = {
                        primaries: misc/* COLOR_PRIMARIES_MAP_INVERSE */.BL[colourPrimaries],
                        transfer: misc/* TRANSFER_CHARACTERISTICS_MAP_INVERSE */.x_[transferCharacteristics],
                        matrix: misc/* MATRIX_COEFFICIENTS_MAP_INVERSE */.fl[matrixCoefficients],
                        fullRange: fullRangeFlag,
                    };
                }
                ;
                break;
            case 'pasp':
                {
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    (0,misc/* assert */.vA)(track.info?.type === 'video');
                    const num = (0,src_reader/* readU32Be */.cN)(slice);
                    const den = (0,src_reader/* readU32Be */.cN)(slice);
                    if (num > den) {
                        track.info.squarePixelWidth = Math.round(track.info.width * num / den);
                    }
                    else {
                        track.info.squarePixelHeight = Math.round(track.info.height * den / num);
                    }
                }
                ;
                break;
            case 'wave':
                {
                    this.readContiguousBoxes(slice.slice(contentStartPos, boxInfo.contentSize));
                }
                ;
                break;
            case 'esds':
                {
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    (0,misc/* assert */.vA)(track.info?.type === 'audio');
                    slice.skip(4); // Version + flags
                    const tag = (0,src_reader/* readU8 */.eo)(slice);
                    (0,misc/* assert */.vA)(tag === 0x03); // ES Descriptor
                    (0,isobmff_reader/* readIsomVariableInteger */.hs)(slice); // Length
                    slice.skip(2); // ES ID
                    const mixed = (0,src_reader/* readU8 */.eo)(slice);
                    const streamDependenceFlag = (mixed & 0x80) !== 0;
                    const urlFlag = (mixed & 0x40) !== 0;
                    const ocrStreamFlag = (mixed & 0x20) !== 0;
                    if (streamDependenceFlag) {
                        slice.skip(2);
                    }
                    if (urlFlag) {
                        const urlLength = (0,src_reader/* readU8 */.eo)(slice);
                        slice.skip(urlLength);
                    }
                    if (ocrStreamFlag) {
                        slice.skip(2);
                    }
                    const decoderConfigTag = (0,src_reader/* readU8 */.eo)(slice);
                    (0,misc/* assert */.vA)(decoderConfigTag === 0x04); // DecoderConfigDescriptor
                    const decoderConfigDescriptorLength = (0,isobmff_reader/* readIsomVariableInteger */.hs)(slice); // Length
                    const payloadStart = slice.filePos;
                    const objectTypeIndication = (0,src_reader/* readU8 */.eo)(slice);
                    if (objectTypeIndication === 0x40 || objectTypeIndication === 0x67) {
                        track.info.codec = 'aac';
                        track.info.aacCodecInfo = {
                            isMpeg2: objectTypeIndication === 0x67,
                            objectType: null,
                        };
                    }
                    else if (objectTypeIndication === 0x69 || objectTypeIndication === 0x6b) {
                        track.info.codec = 'mp3';
                    }
                    else if (objectTypeIndication === 0xdd) {
                        track.info.codec = 'vorbis'; // "nonstandard, gpac uses it" - FFmpeg
                    }
                    else {
                        console.warn(`Unsupported audio codec (objectTypeIndication ${objectTypeIndication}) - discarding track.`);
                    }
                    slice.skip(1 + 3 + 4 + 4);
                    if (decoderConfigDescriptorLength > slice.filePos - payloadStart) {
                        // There's a DecoderSpecificInfo at the end, let's read it
                        const decoderSpecificInfoTag = (0,src_reader/* readU8 */.eo)(slice);
                        (0,misc/* assert */.vA)(decoderSpecificInfoTag === 0x05); // DecoderSpecificInfo
                        const decoderSpecificInfoLength = (0,isobmff_reader/* readIsomVariableInteger */.hs)(slice);
                        track.info.codecDescription = (0,src_reader/* readBytes */.io)(slice, decoderSpecificInfoLength);
                        if (track.info.codec === 'aac') {
                            // Let's try to deduce more accurate values directly from the AudioSpecificConfig:
                            const audioSpecificConfig = (0,aac_misc/* parseAacAudioSpecificConfig */.zF)(track.info.codecDescription);
                            if (audioSpecificConfig.numberOfChannels !== null) {
                                track.info.numberOfChannels = audioSpecificConfig.numberOfChannels;
                            }
                            if (audioSpecificConfig.sampleRate !== null) {
                                track.info.sampleRate = audioSpecificConfig.sampleRate;
                            }
                        }
                    }
                }
                ;
                break;
            case 'enda':
                {
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    (0,misc/* assert */.vA)(track.info?.type === 'audio');
                    track.info.pcmLittleEndian = !!((0,src_reader/* readU16Be */.mH)(slice) & 0xff); // 0xff is from FFmpeg
                }
                ;
                break;
            case 'pcmC':
                {
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    (0,misc/* assert */.vA)(track.info?.type === 'audio');
                    slice.skip(1 + 3); // Version + flags
                    // ISO/IEC 23003-5
                    const formatFlags = (0,src_reader/* readU8 */.eo)(slice);
                    track.info.pcmLittleEndian = Boolean(formatFlags & 0x01);
                    track.info.pcmSampleSize = (0,src_reader/* readU8 */.eo)(slice);
                }
                ;
                break;
            case 'dOps':
                { // Used for Opus audio
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    (0,misc/* assert */.vA)(track.info?.type === 'audio');
                    slice.skip(1); // Version
                    // https://www.opus-codec.org/docs/opus_in_isobmff.html
                    const outputChannelCount = (0,src_reader/* readU8 */.eo)(slice);
                    const preSkip = (0,src_reader/* readU16Be */.mH)(slice);
                    const inputSampleRate = (0,src_reader/* readU32Be */.cN)(slice);
                    const outputGain = (0,src_reader/* readI16Be */.iH)(slice);
                    const channelMappingFamily = (0,src_reader/* readU8 */.eo)(slice);
                    let channelMappingTable;
                    if (channelMappingFamily !== 0) {
                        channelMappingTable = (0,src_reader/* readBytes */.io)(slice, 2 + outputChannelCount);
                    }
                    else {
                        channelMappingTable = new Uint8Array(0);
                    }
                    // https://datatracker.ietf.org/doc/html/draft-ietf-codec-oggopus-06
                    const description = new Uint8Array(8 + 1 + 1 + 2 + 4 + 2 + 1 + channelMappingTable.byteLength);
                    const view = new DataView(description.buffer);
                    view.setUint32(0, 0x4f707573, false); // 'Opus'
                    view.setUint32(4, 0x48656164, false); // 'Head'
                    view.setUint8(8, 1); // Version
                    view.setUint8(9, outputChannelCount);
                    view.setUint16(10, preSkip, true);
                    view.setUint32(12, inputSampleRate, true);
                    view.setInt16(16, outputGain, true);
                    view.setUint8(18, channelMappingFamily);
                    description.set(channelMappingTable, 19);
                    track.info.codecDescription = description;
                    track.info.numberOfChannels = outputChannelCount;
                    // Don't copy the input sample rate, irrelevant, and output sample rate is fixed
                }
                ;
                break;
            case 'dfLa':
                { // Used for FLAC audio
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    (0,misc/* assert */.vA)(track.info?.type === 'audio');
                    slice.skip(4); // Version + flags
                    // https://datatracker.ietf.org/doc/rfc9639/
                    const BLOCK_TYPE_MASK = 0x7f;
                    const LAST_METADATA_BLOCK_FLAG_MASK = 0x80;
                    const startPos = slice.filePos;
                    while (slice.filePos < boxEndPos) {
                        const flagAndType = (0,src_reader/* readU8 */.eo)(slice);
                        const metadataBlockLength = (0,src_reader/* readU24Be */.n2)(slice);
                        const type = flagAndType & BLOCK_TYPE_MASK;
                        // It's a STREAMINFO block; let's extract the actual sample rate and channel count
                        if (type === codec_data/* FlacBlockType */.A3.STREAMINFO) {
                            slice.skip(10);
                            // Extract sample rate and channel count
                            const word = (0,src_reader/* readU32Be */.cN)(slice);
                            const sampleRate = word >>> 12;
                            const numberOfChannels = ((word >> 9) & 0b111) + 1;
                            track.info.sampleRate = sampleRate;
                            track.info.numberOfChannels = numberOfChannels;
                            slice.skip(20);
                        }
                        else {
                            // Simply skip ahead to the next block
                            slice.skip(metadataBlockLength);
                        }
                        if (flagAndType & LAST_METADATA_BLOCK_FLAG_MASK) {
                            break;
                        }
                    }
                    const endPos = slice.filePos;
                    slice.filePos = startPos;
                    const bytes = (0,src_reader/* readBytes */.io)(slice, endPos - startPos);
                    const description = new Uint8Array(4 + bytes.byteLength);
                    const view = new DataView(description.buffer);
                    view.setUint32(0, 0x664c6143, false); // 'fLaC'
                    description.set(bytes, 4);
                    // Set the codec description to be 'fLaC' + all metadata blocks
                    track.info.codecDescription = description;
                }
                ;
                break;
            case 'dac3':
                { // AC3SpecificBox
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    (0,misc/* assert */.vA)(track.info?.type === 'audio');
                    const bytes = (0,src_reader/* readBytes */.io)(slice, 3);
                    const bitstream = new shared_bitstream/* Bitstream */._(bytes);
                    const fscod = bitstream.readBits(2);
                    bitstream.skipBits(5 + 3); // Skip bsid and bsmod
                    const acmod = bitstream.readBits(3);
                    const lfeon = bitstream.readBits(1);
                    if (fscod < 3) {
                        track.info.sampleRate = ac3_misc/* AC3_SAMPLE_RATES */.N[fscod];
                    }
                    track.info.numberOfChannels = codec_data/* AC3_ACMOD_CHANNEL_COUNTS */.ux[acmod] + lfeon;
                }
                ;
                break;
            case 'dec3':
                { // EC3SpecificBox
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    (0,misc/* assert */.vA)(track.info?.type === 'audio');
                    const bytes = (0,src_reader/* readBytes */.io)(slice, boxInfo.contentSize);
                    const config = (0,codec_data/* parseEac3Config */.Sd)(bytes);
                    if (!config) {
                        console.warn('Invalid dec3 box contents, ignoring.');
                        break;
                    }
                    const sampleRate = (0,codec_data/* getEac3SampleRate */.PK)(config);
                    if (sampleRate !== null) {
                        track.info.sampleRate = sampleRate;
                    }
                    track.info.numberOfChannels = (0,codec_data/* getEac3ChannelCount */.zV)(config);
                }
                ;
                break;
            case 'stts':
                {
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    if (!track.sampleTable) {
                        break;
                    }
                    slice.skip(4); // Version + flags
                    const entryCount = (0,src_reader/* readU32Be */.cN)(slice);
                    let currentIndex = 0;
                    let currentTimestamp = 0;
                    for (let i = 0; i < entryCount; i++) {
                        const sampleCount = (0,src_reader/* readU32Be */.cN)(slice);
                        const sampleDelta = (0,src_reader/* readU32Be */.cN)(slice);
                        track.sampleTable.sampleTimingEntries.push({
                            startIndex: currentIndex,
                            startDecodeTimestamp: currentTimestamp,
                            count: sampleCount,
                            delta: sampleDelta,
                        });
                        currentIndex += sampleCount;
                        currentTimestamp += sampleCount * sampleDelta;
                    }
                }
                ;
                break;
            case 'ctts':
                {
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    if (!track.sampleTable) {
                        break;
                    }
                    slice.skip(1 + 3); // Version + flags
                    const entryCount = (0,src_reader/* readU32Be */.cN)(slice);
                    let sampleIndex = 0;
                    for (let i = 0; i < entryCount; i++) {
                        const sampleCount = (0,src_reader/* readU32Be */.cN)(slice);
                        const sampleOffset = (0,src_reader/* readI32Be */.Ar)(slice);
                        track.sampleTable.sampleCompositionTimeOffsets.push({
                            startIndex: sampleIndex,
                            count: sampleCount,
                            offset: sampleOffset,
                        });
                        sampleIndex += sampleCount;
                    }
                }
                ;
                break;
            case 'stsz':
                {
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    if (!track.sampleTable) {
                        break;
                    }
                    slice.skip(4); // Version + flags
                    const sampleSize = (0,src_reader/* readU32Be */.cN)(slice);
                    const sampleCount = (0,src_reader/* readU32Be */.cN)(slice);
                    if (sampleSize === 0) {
                        for (let i = 0; i < sampleCount; i++) {
                            const sampleSize = (0,src_reader/* readU32Be */.cN)(slice);
                            track.sampleTable.sampleSizes.push(sampleSize);
                        }
                    }
                    else {
                        track.sampleTable.sampleSizes.push(sampleSize);
                    }
                }
                ;
                break;
            case 'stz2':
                {
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    if (!track.sampleTable) {
                        break;
                    }
                    slice.skip(4); // Version + flags
                    slice.skip(3); // Reserved
                    const fieldSize = (0,src_reader/* readU8 */.eo)(slice); // in bits
                    const sampleCount = (0,src_reader/* readU32Be */.cN)(slice);
                    const bytes = (0,src_reader/* readBytes */.io)(slice, Math.ceil(sampleCount * fieldSize / 8));
                    const bitstream = new shared_bitstream/* Bitstream */._(bytes);
                    for (let i = 0; i < sampleCount; i++) {
                        const sampleSize = bitstream.readBits(fieldSize);
                        track.sampleTable.sampleSizes.push(sampleSize);
                    }
                }
                ;
                break;
            case 'stss':
                {
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    if (!track.sampleTable) {
                        break;
                    }
                    slice.skip(4); // Version + flags
                    track.sampleTable.keySampleIndices = [];
                    const entryCount = (0,src_reader/* readU32Be */.cN)(slice);
                    for (let i = 0; i < entryCount; i++) {
                        const sampleIndex = (0,src_reader/* readU32Be */.cN)(slice) - 1; // Convert to 0-indexed
                        track.sampleTable.keySampleIndices.push(sampleIndex);
                    }
                    if (track.sampleTable.keySampleIndices[0] !== 0) {
                        // Some files don't mark the first sample a key sample, which is basically almost always incorrect.
                        // Here, we correct for that mistake:
                        track.sampleTable.keySampleIndices.unshift(0);
                    }
                }
                ;
                break;
            case 'stsc':
                {
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    if (!track.sampleTable) {
                        break;
                    }
                    slice.skip(4);
                    const entryCount = (0,src_reader/* readU32Be */.cN)(slice);
                    for (let i = 0; i < entryCount; i++) {
                        const startChunkIndex = (0,src_reader/* readU32Be */.cN)(slice) - 1; // Convert to 0-indexed
                        const samplesPerChunk = (0,src_reader/* readU32Be */.cN)(slice);
                        const sampleDescriptionIndex = (0,src_reader/* readU32Be */.cN)(slice);
                        track.sampleTable.sampleToChunk.push({
                            startSampleIndex: -1,
                            startChunkIndex,
                            samplesPerChunk,
                            sampleDescriptionIndex,
                        });
                    }
                    let startSampleIndex = 0;
                    for (let i = 0; i < track.sampleTable.sampleToChunk.length; i++) {
                        track.sampleTable.sampleToChunk[i].startSampleIndex = startSampleIndex;
                        if (i < track.sampleTable.sampleToChunk.length - 1) {
                            const nextChunk = track.sampleTable.sampleToChunk[i + 1];
                            const chunkCount = nextChunk.startChunkIndex
                                - track.sampleTable.sampleToChunk[i].startChunkIndex;
                            startSampleIndex += chunkCount * track.sampleTable.sampleToChunk[i].samplesPerChunk;
                        }
                    }
                }
                ;
                break;
            case 'stco':
                {
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    if (!track.sampleTable) {
                        break;
                    }
                    slice.skip(4); // Version + flags
                    const entryCount = (0,src_reader/* readU32Be */.cN)(slice);
                    for (let i = 0; i < entryCount; i++) {
                        const chunkOffset = (0,src_reader/* readU32Be */.cN)(slice);
                        track.sampleTable.chunkOffsets.push(chunkOffset);
                    }
                }
                ;
                break;
            case 'co64':
                {
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    if (!track.sampleTable) {
                        break;
                    }
                    slice.skip(4); // Version + flags
                    const entryCount = (0,src_reader/* readU32Be */.cN)(slice);
                    for (let i = 0; i < entryCount; i++) {
                        const chunkOffset = (0,src_reader/* readU64Be */.th)(slice);
                        track.sampleTable.chunkOffsets.push(chunkOffset);
                    }
                }
                ;
                break;
            case 'mvex':
                {
                    this.isFragmented = true;
                    this.readContiguousBoxes(slice.slice(contentStartPos, boxInfo.contentSize));
                }
                ;
                break;
            case 'mehd':
                {
                    const version = (0,src_reader/* readU8 */.eo)(slice);
                    slice.skip(3); // Flags
                    const fragmentDuration = version === 1 ? (0,src_reader/* readU64Be */.th)(slice) : (0,src_reader/* readU32Be */.cN)(slice);
                    this.movieDurationInTimescale = fragmentDuration;
                }
                ;
                break;
            case 'trex':
                {
                    slice.skip(4); // Version + flags
                    const trackId = (0,src_reader/* readU32Be */.cN)(slice);
                    const defaultSampleDescriptionIndex = (0,src_reader/* readU32Be */.cN)(slice);
                    const defaultSampleDuration = (0,src_reader/* readU32Be */.cN)(slice);
                    const defaultSampleSize = (0,src_reader/* readU32Be */.cN)(slice);
                    const defaultSampleFlags = (0,src_reader/* readU32Be */.cN)(slice);
                    // We store these separately rather than in the tracks since the tracks may not exist yet
                    this.fragmentTrackDefaults.push({
                        trackId,
                        defaultSampleDescriptionIndex,
                        defaultSampleDuration,
                        defaultSampleSize,
                        defaultSampleFlags,
                    });
                }
                ;
                break;
            case 'tfra':
                {
                    const version = (0,src_reader/* readU8 */.eo)(slice);
                    slice.skip(3); // Flags
                    const trackId = (0,src_reader/* readU32Be */.cN)(slice);
                    const track = this.tracks.find(x => x.id === trackId);
                    if (!track) {
                        break;
                    }
                    const word = (0,src_reader/* readU32Be */.cN)(slice);
                    const lengthSizeOfTrafNum = (word & 0b110000) >> 4;
                    const lengthSizeOfTrunNum = (word & 0b001100) >> 2;
                    const lengthSizeOfSampleNum = word & 0b000011;
                    const functions = [src_reader/* readU8 */.eo, src_reader/* readU16Be */.mH, src_reader/* readU24Be */.n2, src_reader/* readU32Be */.cN];
                    const readTrafNum = functions[lengthSizeOfTrafNum];
                    const readTrunNum = functions[lengthSizeOfTrunNum];
                    const readSampleNum = functions[lengthSizeOfSampleNum];
                    const numberOfEntries = (0,src_reader/* readU32Be */.cN)(slice);
                    for (let i = 0; i < numberOfEntries; i++) {
                        const time = version === 1 ? (0,src_reader/* readU64Be */.th)(slice) : (0,src_reader/* readU32Be */.cN)(slice);
                        const moofOffset = version === 1 ? (0,src_reader/* readU64Be */.th)(slice) : (0,src_reader/* readU32Be */.cN)(slice);
                        readTrafNum(slice);
                        readTrunNum(slice);
                        readSampleNum(slice);
                        track.fragmentLookupTable.push({
                            timestamp: time,
                            moofOffset,
                        });
                    }
                    // Sort by timestamp in case it's not naturally sorted
                    track.fragmentLookupTable.sort((a, b) => a.timestamp - b.timestamp);
                    // Remove multiple entries for the same time
                    for (let i = 0; i < track.fragmentLookupTable.length - 1; i++) {
                        const entry1 = track.fragmentLookupTable[i];
                        const entry2 = track.fragmentLookupTable[i + 1];
                        if (entry1.timestamp === entry2.timestamp) {
                            track.fragmentLookupTable.splice(i + 1, 1);
                            i--;
                        }
                    }
                }
                ;
                break;
            case 'moof':
                {
                    this.currentFragment = {
                        moofOffset: startPos,
                        moofSize: boxInfo.totalSize,
                        implicitBaseDataOffset: startPos,
                        trackData: new Map(),
                        psshBoxes: [],
                    };
                    this.readContiguousBoxes(slice.slice(contentStartPos, boxInfo.contentSize));
                    this.lastReadFragment = this.currentFragment;
                    this.currentFragment = null;
                }
                ;
                break;
            case 'traf':
                {
                    (0,misc/* assert */.vA)(this.currentFragment);
                    this.readContiguousBoxes(slice.slice(contentStartPos, boxInfo.contentSize));
                    // It is possible that there is no current track, for example when we don't care about the track
                    // referenced in the track fragment header.
                    if (this.currentTrack) {
                        const trackData = this.currentFragment.trackData.get(this.currentTrack.id);
                        if (trackData) {
                            this.currentFragment.implicitBaseDataOffset = trackData.currentOffset;
                            trackData.presentationTimestamps = trackData.samples
                                .map((x, i) => ({ presentationTimestamp: x.presentationTimestamp, sampleIndex: i }))
                                .sort((a, b) => a.presentationTimestamp - b.presentationTimestamp);
                            for (let i = 0; i < trackData.presentationTimestamps.length; i++) {
                                const currentEntry = trackData.presentationTimestamps[i];
                                const currentSample = trackData.samples[currentEntry.sampleIndex];
                                if (trackData.firstKeyFrameTimestamp === null && currentSample.isKeyFrame) {
                                    trackData.firstKeyFrameTimestamp = currentSample.presentationTimestamp;
                                }
                                if (i < trackData.presentationTimestamps.length - 1) {
                                    // Update sample durations based on presentation order
                                    const nextEntry = trackData.presentationTimestamps[i + 1];
                                    const duration = nextEntry.presentationTimestamp - currentEntry.presentationTimestamp;
                                    currentSample.duration = duration;
                                }
                            }
                            const firstSample = trackData.samples[trackData.presentationTimestamps[0].sampleIndex];
                            const lastSample = trackData.samples[(0,misc/* last */._g)(trackData.presentationTimestamps).sampleIndex];
                            trackData.startTimestamp = firstSample.presentationTimestamp;
                            trackData.endTimestamp = lastSample.presentationTimestamp + lastSample.duration;
                            const { currentFragmentState } = this.currentTrack;
                            (0,misc/* assert */.vA)(currentFragmentState);
                            if (currentFragmentState.startTimestamp !== null) {
                                offsetFragmentTrackDataByTimestamp(trackData, currentFragmentState.startTimestamp);
                                trackData.startTimestampIsFinal = true;
                            }
                            // Transfer the buffered saiz+saio state onto the track data, so readFragment can resolve it
                            // once all boxes are parsed. Only relevant if senc wasn't already used to populate samples.
                            if (currentFragmentState.encryptionAuxInfo && !trackData.samples[0].encryption) {
                                trackData.encryptionAuxInfo = currentFragmentState.encryptionAuxInfo;
                            }
                        }
                        this.currentTrack.currentFragmentState = null;
                        this.currentTrack = null;
                    }
                }
                ;
                break;
            case 'pssh':
                {
                    if (this.input._formatOptions.isobmff?._suppressPsshParsing) {
                        break;
                    }
                    const psshBox = (0,isobmff_misc/* parsePsshBoxContents */.j1)((0,src_reader/* readBytes */.io)(slice, boxInfo.contentSize));
                    if (this.currentFragment) {
                        this.currentFragment.psshBoxes.push(psshBox);
                    }
                    else if (!this.currentTrack) {
                        this.psshBoxes.push(psshBox);
                    }
                }
                ;
                break;
            case 'tfhd':
                {
                    (0,misc/* assert */.vA)(this.currentFragment);
                    slice.skip(1); // Version
                    const flags = (0,src_reader/* readU24Be */.n2)(slice);
                    const baseDataOffsetPresent = Boolean(flags & 0x000001);
                    const sampleDescriptionIndexPresent = Boolean(flags & 0x000002);
                    const defaultSampleDurationPresent = Boolean(flags & 0x000008);
                    const defaultSampleSizePresent = Boolean(flags & 0x000010);
                    const defaultSampleFlagsPresent = Boolean(flags & 0x000020);
                    const durationIsEmpty = Boolean(flags & 0x010000);
                    const defaultBaseIsMoof = Boolean(flags & 0x020000);
                    const trackId = (0,src_reader/* readU32Be */.cN)(slice);
                    const track = this.tracks.find(x => x.id === trackId);
                    if (!track) {
                        // We don't care about this track
                        break;
                    }
                    const defaults = this.fragmentTrackDefaults.find(x => x.trackId === trackId);
                    this.currentTrack = track;
                    track.currentFragmentState = {
                        baseDataOffset: this.currentFragment.implicitBaseDataOffset,
                        sampleDescriptionIndex: defaults?.defaultSampleDescriptionIndex ?? null,
                        defaultSampleDuration: defaults?.defaultSampleDuration ?? null,
                        defaultSampleSize: defaults?.defaultSampleSize ?? null,
                        defaultSampleFlags: defaults?.defaultSampleFlags ?? null,
                        startTimestamp: null,
                        encryptionAuxInfo: null,
                    };
                    if (baseDataOffsetPresent) {
                        track.currentFragmentState.baseDataOffset = (0,src_reader/* readU64Be */.th)(slice);
                    }
                    else if (defaultBaseIsMoof) {
                        track.currentFragmentState.baseDataOffset = this.currentFragment.moofOffset;
                    }
                    if (sampleDescriptionIndexPresent) {
                        track.currentFragmentState.sampleDescriptionIndex = (0,src_reader/* readU32Be */.cN)(slice);
                    }
                    if (defaultSampleDurationPresent) {
                        track.currentFragmentState.defaultSampleDuration = (0,src_reader/* readU32Be */.cN)(slice);
                    }
                    if (defaultSampleSizePresent) {
                        track.currentFragmentState.defaultSampleSize = (0,src_reader/* readU32Be */.cN)(slice);
                    }
                    if (defaultSampleFlagsPresent) {
                        track.currentFragmentState.defaultSampleFlags = (0,src_reader/* readU32Be */.cN)(slice);
                    }
                    if (durationIsEmpty) {
                        track.currentFragmentState.defaultSampleDuration = 0;
                    }
                }
                ;
                break;
            case 'tfdt':
                {
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    (0,misc/* assert */.vA)(track.currentFragmentState);
                    const version = (0,src_reader/* readU8 */.eo)(slice);
                    slice.skip(3); // Flags
                    const baseMediaDecodeTime = version === 0 ? (0,src_reader/* readU32Be */.cN)(slice) : (0,src_reader/* readU64Be */.th)(slice);
                    track.currentFragmentState.startTimestamp = baseMediaDecodeTime;
                }
                ;
                break;
            case 'trun':
                {
                    const track = this.currentTrack;
                    if (!track) {
                        break;
                    }
                    (0,misc/* assert */.vA)(this.currentFragment);
                    (0,misc/* assert */.vA)(track.currentFragmentState);
                    const version = (0,src_reader/* readU8 */.eo)(slice);
                    const flags = (0,src_reader/* readU24Be */.n2)(slice);
                    const dataOffsetPresent = Boolean(flags & 0x000001);
                    const firstSampleFlagsPresent = Boolean(flags & 0x000004);
                    const sampleDurationPresent = Boolean(flags & 0x000100);
                    const sampleSizePresent = Boolean(flags & 0x000200);
                    const sampleFlagsPresent = Boolean(flags & 0x000400);
                    const sampleCompositionTimeOffsetsPresent = Boolean(flags & 0x000800);
                    const sampleCount = (0,src_reader/* readU32Be */.cN)(slice);
                    let dataOffset = null;
                    if (dataOffsetPresent) {
                        dataOffset = (0,src_reader/* readI32Be */.Ar)(slice);
                    }
                    let firstSampleFlags = null;
                    if (firstSampleFlagsPresent) {
                        firstSampleFlags = (0,src_reader/* readU32Be */.cN)(slice);
                    }
                    let trackData;
                    if (this.currentFragment.trackData.has(track.id)) {
                        trackData = this.currentFragment.trackData.get(track.id);
                        if (dataOffset !== null) {
                            trackData.currentOffset = track.currentFragmentState.baseDataOffset + dataOffset;
                        }
                        else {
                            // "If the data-offset is not present, then the data for this run starts immediately after the
                            // data of the previous run"
                        }
                    }
                    else {
                        trackData = {
                            track,
                            currentTimestamp: 0,
                            currentOffset: track.currentFragmentState.baseDataOffset + (dataOffset ?? 0),
                            startTimestamp: 0,
                            endTimestamp: 0,
                            firstKeyFrameTimestamp: null,
                            samples: [],
                            presentationTimestamps: [],
                            startTimestampIsFinal: false,
                            encryptionAuxInfo: null,
                        };
                        this.currentFragment.trackData.set(track.id, trackData);
                    }
                    if (sampleCount === 0) {
                        // Don't associate the fragment with the track if it has no samples, this simplifies other code
                        this.currentFragment.implicitBaseDataOffset = trackData.currentOffset;
                        break;
                    }
                    for (let i = 0; i < sampleCount; i++) {
                        let sampleDuration;
                        if (sampleDurationPresent) {
                            sampleDuration = (0,src_reader/* readU32Be */.cN)(slice);
                        }
                        else {
                            (0,misc/* assert */.vA)(track.currentFragmentState.defaultSampleDuration !== null);
                            sampleDuration = track.currentFragmentState.defaultSampleDuration;
                        }
                        let sampleSize;
                        if (sampleSizePresent) {
                            sampleSize = (0,src_reader/* readU32Be */.cN)(slice);
                        }
                        else {
                            (0,misc/* assert */.vA)(track.currentFragmentState.defaultSampleSize !== null);
                            sampleSize = track.currentFragmentState.defaultSampleSize;
                        }
                        let sampleFlags;
                        if (sampleFlagsPresent) {
                            sampleFlags = (0,src_reader/* readU32Be */.cN)(slice);
                        }
                        else {
                            (0,misc/* assert */.vA)(track.currentFragmentState.defaultSampleFlags !== null);
                            sampleFlags = track.currentFragmentState.defaultSampleFlags;
                        }
                        if (i === 0 && firstSampleFlags !== null) {
                            sampleFlags = firstSampleFlags;
                        }
                        let sampleCompositionTimeOffset = 0;
                        if (sampleCompositionTimeOffsetsPresent) {
                            if (version === 0) {
                                sampleCompositionTimeOffset = (0,src_reader/* readU32Be */.cN)(slice);
                            }
                            else {
                                sampleCompositionTimeOffset = (0,src_reader/* readI32Be */.Ar)(slice);
                            }
                        }
                        const isKeyFrame = !(sampleFlags & 0x00010000);
                        trackData.samples.push({
                            presentationTimestamp: trackData.currentTimestamp + sampleCompositionTimeOffset,
                            duration: sampleDuration,
                            byteOffset: trackData.currentOffset,
                            byteSize: sampleSize,
                            isKeyFrame,
                            encryption: null,
                        });
                        trackData.currentOffset += sampleSize;
                        trackData.currentTimestamp += sampleDuration;
                    }
                }
                ;
                break;
            case 'saiz':
                {
                    // Sample Auxiliary Information Sizes - per-sample sizes of (typically) the encryption aux info.
                    const track = this.currentTrack;
                    if (!track || !track.encryptionInfo) {
                        break;
                    }
                    slice.skip(1); // Version
                    const flags = (0,src_reader/* readU24Be */.n2)(slice);
                    if (flags & 0x01) {
                        const auxInfoType = (0,src_reader/* readAscii */.IT)(slice, 4);
                        const auxInfoTypeParam = (0,src_reader/* readU32Be */.cN)(slice);
                        if (auxInfoType !== track.encryptionInfo.scheme || auxInfoTypeParam !== 0) {
                            // Not the encryption aux info
                            break;
                        }
                    }
                    const defaultSampleInfoSize = (0,src_reader/* readU8 */.eo)(slice);
                    const sampleCount = (0,src_reader/* readU32Be */.cN)(slice);
                    let sampleSizes = null;
                    if (defaultSampleInfoSize === 0 && sampleCount > 0) {
                        sampleSizes = (0,src_reader/* readBytes */.io)(slice, sampleCount);
                    }
                    const aux = getOrCreateEncryptionAuxInfo(track);
                    aux.defaultSampleInfoSize = defaultSampleInfoSize;
                    aux.sampleSizes = sampleSizes;
                    aux.sampleCount = sampleCount;
                }
                ;
                break;
            case 'saio':
                {
                    // Sample Auxiliary Information Offsets - file offset(s) where the aux info lives.
                    const track = this.currentTrack;
                    if (!track || !track.encryptionInfo) {
                        break;
                    }
                    const version = (0,src_reader/* readU8 */.eo)(slice);
                    const flags = (0,src_reader/* readU24Be */.n2)(slice);
                    if (flags & 0x01) {
                        const auxInfoType = (0,src_reader/* readAscii */.IT)(slice, 4);
                        const auxInfoTypeParam = (0,src_reader/* readU32Be */.cN)(slice);
                        if (auxInfoType !== track.encryptionInfo.scheme || auxInfoTypeParam !== 0) {
                            break;
                        }
                    }
                    const entryCount = (0,src_reader/* readU32Be */.cN)(slice);
                    if (entryCount === 0) {
                        break;
                    }
                    if (entryCount > 1) {
                        console.warn('Multiple saio entries are not supported; using the first offset only.');
                    }
                    let offset = version === 0 ? (0,src_reader/* readU32Be */.cN)(slice) : Number((0,src_reader/* readU64Be */.th)(slice));
                    // Per ISO/IEC 23001-7: when saio is inside a moof, offsets are relative to the start of the moof box.
                    if (this.currentFragment) {
                        offset += this.currentFragment.moofOffset;
                    }
                    const aux = getOrCreateEncryptionAuxInfo(track);
                    aux.offset = offset;
                }
                ;
                break;
            case 'senc':
                {
                    // Per-sample encryption info inside a 'traf'. Holds per-sample IV and optional subsample breakdown
                    // for CENC-protected samples
                    const track = this.currentTrack;
                    if (!track || !track.encryptionInfo) {
                        break;
                    }
                    (0,misc/* assert */.vA)(this.currentFragment);
                    const trackData = this.currentFragment.trackData.get(track.id);
                    if (!trackData) {
                        break;
                    }
                    slice.skip(1); // Version
                    const flags = (0,src_reader/* readU24Be */.n2)(slice);
                    const useSubsamples = Boolean(flags & 0x000002);
                    const sampleCount = (0,src_reader/* readU32Be */.cN)(slice);
                    const ivSize = track.encryptionInfo.defaultPerSampleIvSize;
                    (0,misc/* assert */.vA)(ivSize !== null);
                    for (let i = 0; i < Math.min(sampleCount, trackData.samples.length); i++) {
                        // Normalize the IV to 16 bytes so downstream code can assume a full-length buffer. For CTR with
                        // an 8-byte per-sample IV the lower 8 bytes are zero (that's the CENC spec's block counter start);
                        // for CBC/cbcs the IV is always 16 bytes by spec.
                        const iv = new Uint8Array(16);
                        if (ivSize > 0) {
                            iv.set((0,src_reader/* readBytes */.io)(slice, ivSize), 0);
                        }
                        else {
                            iv.set(track.encryptionInfo.defaultConstantIv, 0);
                        }
                        let subsamples = null;
                        if (useSubsamples) {
                            const subsampleCount = (0,src_reader/* readU16Be */.mH)(slice);
                            subsamples = [];
                            for (let j = 0; j < subsampleCount; j++) {
                                const clearLen = (0,src_reader/* readU16Be */.mH)(slice);
                                const protectedLen = (0,src_reader/* readU32Be */.cN)(slice);
                                subsamples.push({ clearLen, protectedLen });
                            }
                        }
                        const sample = trackData.samples[i];
                        sample.encryption = { iv, subsamples };
                    }
                }
                ;
                break;
            // Metadata section
            // https://exiftool.org/TagNames/QuickTime.html
            // https://mp4workshop.com/about
            case 'udta':
                { // Contains either movie metadata or track metadata
                    const iterator = this.iterateContiguousBoxes(slice.slice(contentStartPos, boxInfo.contentSize));
                    for (const { boxInfo, slice } of iterator) {
                        if (boxInfo.name !== 'meta' && !this.currentTrack) {
                            const startPos = slice.filePos;
                            this.metadataTags.raw ??= {};
                            if (boxInfo.name[0] === '©') {
                                // https://mp4workshop.com/about
                                // Box name starting with © indicates "international text"
                                this.metadataTags.raw[boxInfo.name] ??= (0,isobmff_reader/* readMetadataStringShort */.$L)(slice);
                            }
                            else {
                                this.metadataTags.raw[boxInfo.name] ??= (0,src_reader/* readBytes */.io)(slice, boxInfo.contentSize);
                            }
                            slice.filePos = startPos;
                        }
                        switch (boxInfo.name) {
                            case 'meta':
                                {
                                    slice.skip(-boxInfo.headerSize);
                                    this.traverseBox(slice);
                                }
                                ;
                                break;
                            case '©nam':
                            case 'name':
                                {
                                    if (this.currentTrack) {
                                        this.currentTrack.name = misc/* textDecoder */.su.decode((0,src_reader/* readBytes */.io)(slice, boxInfo.contentSize));
                                    }
                                    else {
                                        this.metadataTags.title ??= (0,isobmff_reader/* readMetadataStringShort */.$L)(slice);
                                    }
                                }
                                ;
                                break;
                            case '©des':
                                {
                                    if (!this.currentTrack) {
                                        this.metadataTags.description ??= (0,isobmff_reader/* readMetadataStringShort */.$L)(slice);
                                    }
                                }
                                ;
                                break;
                            case '©ART':
                                {
                                    if (!this.currentTrack) {
                                        this.metadataTags.artist ??= (0,isobmff_reader/* readMetadataStringShort */.$L)(slice);
                                    }
                                }
                                ;
                                break;
                            case '©alb':
                                {
                                    if (!this.currentTrack) {
                                        this.metadataTags.album ??= (0,isobmff_reader/* readMetadataStringShort */.$L)(slice);
                                    }
                                }
                                ;
                                break;
                            case 'albr':
                                {
                                    if (!this.currentTrack) {
                                        this.metadataTags.albumArtist ??= (0,isobmff_reader/* readMetadataStringShort */.$L)(slice);
                                    }
                                }
                                ;
                                break;
                            case '©gen':
                                {
                                    if (!this.currentTrack) {
                                        this.metadataTags.genre ??= (0,isobmff_reader/* readMetadataStringShort */.$L)(slice);
                                    }
                                }
                                ;
                                break;
                            case '©day':
                                {
                                    if (!this.currentTrack) {
                                        const date = new Date((0,isobmff_reader/* readMetadataStringShort */.$L)(slice));
                                        if (!Number.isNaN(date.getTime())) {
                                            this.metadataTags.date ??= date;
                                        }
                                    }
                                }
                                ;
                                break;
                            case '©cmt':
                                {
                                    if (!this.currentTrack) {
                                        this.metadataTags.comment ??= (0,isobmff_reader/* readMetadataStringShort */.$L)(slice);
                                    }
                                }
                                ;
                                break;
                            case '©lyr':
                                {
                                    if (!this.currentTrack) {
                                        this.metadataTags.lyrics ??= (0,isobmff_reader/* readMetadataStringShort */.$L)(slice);
                                    }
                                }
                                ;
                                break;
                        }
                    }
                }
                ;
                break;
            case 'meta':
                {
                    if (this.currentTrack) {
                        break; // Only care about movie-level metadata for now
                    }
                    // The 'meta' box comes in two flavors, one with flags/version and one without. To know which is which,
                    // let's read the next 4 bytes, which are either the version or the size of the first subbox.
                    const word = (0,src_reader/* readU32Be */.cN)(slice);
                    const isQuickTime = word !== 0;
                    this.currentMetadataKeys = new Map();
                    if (isQuickTime) {
                        this.readContiguousBoxes(slice.slice(contentStartPos, boxInfo.contentSize));
                    }
                    else {
                        this.readContiguousBoxes(slice.slice(contentStartPos + 4, boxInfo.contentSize - 4));
                    }
                    this.currentMetadataKeys = null;
                }
                ;
                break;
            case 'keys':
                {
                    if (!this.currentMetadataKeys) {
                        break;
                    }
                    slice.skip(4); // Version + flags
                    const entryCount = (0,src_reader/* readU32Be */.cN)(slice);
                    for (let i = 0; i < entryCount; i++) {
                        const keySize = (0,src_reader/* readU32Be */.cN)(slice);
                        slice.skip(4); // Key namespace
                        const keyName = misc/* textDecoder */.su.decode((0,src_reader/* readBytes */.io)(slice, keySize - 8));
                        this.currentMetadataKeys.set(i + 1, keyName);
                    }
                }
                ;
                break;
            case 'ilst':
                {
                    if (!this.currentMetadataKeys) {
                        break;
                    }
                    const iterator = this.iterateContiguousBoxes(slice.slice(contentStartPos, boxInfo.contentSize));
                    for (const { boxInfo, slice } of iterator) {
                        let metadataKey = boxInfo.name;
                        // Interpret the box name as a u32be
                        const nameAsNumber = (metadataKey.charCodeAt(0) << 24)
                            + (metadataKey.charCodeAt(1) << 16)
                            + (metadataKey.charCodeAt(2) << 8)
                            + metadataKey.charCodeAt(3);
                        if (this.currentMetadataKeys.has(nameAsNumber)) {
                            // An entry exists for this number
                            metadataKey = this.currentMetadataKeys.get(nameAsNumber);
                        }
                        const data = (0,isobmff_reader/* readDataBox */.Cp)(slice);
                        this.metadataTags.raw ??= {};
                        this.metadataTags.raw[metadataKey] ??= data;
                        switch (metadataKey) {
                            case '©nam':
                            case 'titl':
                            case 'com.apple.quicktime.title':
                            case 'title':
                                {
                                    if (typeof data === 'string') {
                                        this.metadataTags.title ??= data;
                                    }
                                }
                                ;
                                break;
                            case '©des':
                            case 'desc':
                            case 'dscp':
                            case 'com.apple.quicktime.description':
                            case 'description':
                                {
                                    if (typeof data === 'string') {
                                        this.metadataTags.description ??= data;
                                    }
                                }
                                ;
                                break;
                            case '©ART':
                            case 'com.apple.quicktime.artist':
                            case 'artist':
                                {
                                    if (typeof data === 'string') {
                                        this.metadataTags.artist ??= data;
                                    }
                                }
                                ;
                                break;
                            case '©alb':
                            case 'albm':
                            case 'com.apple.quicktime.album':
                            case 'album':
                                {
                                    if (typeof data === 'string') {
                                        this.metadataTags.album ??= data;
                                    }
                                }
                                ;
                                break;
                            case 'aART':
                            case 'album_artist':
                                {
                                    if (typeof data === 'string') {
                                        this.metadataTags.albumArtist ??= data;
                                    }
                                }
                                ;
                                break;
                            case '©cmt':
                            case 'com.apple.quicktime.comment':
                            case 'comment':
                                {
                                    if (typeof data === 'string') {
                                        this.metadataTags.comment ??= data;
                                    }
                                }
                                ;
                                break;
                            case '©gen':
                            case 'gnre':
                            case 'com.apple.quicktime.genre':
                            case 'genre':
                                {
                                    if (typeof data === 'string') {
                                        this.metadataTags.genre ??= data;
                                    }
                                }
                                ;
                                break;
                            case '©lyr':
                            case 'lyrics':
                                {
                                    if (typeof data === 'string') {
                                        this.metadataTags.lyrics ??= data;
                                    }
                                }
                                ;
                                break;
                            case '©day':
                            case 'rldt':
                            case 'com.apple.quicktime.creationdate':
                            case 'date':
                                {
                                    if (typeof data === 'string') {
                                        const date = new Date(data);
                                        if (!Number.isNaN(date.getTime())) {
                                            this.metadataTags.date ??= date;
                                        }
                                    }
                                }
                                ;
                                break;
                            case 'covr':
                            case 'com.apple.quicktime.artwork':
                                {
                                    if (data instanceof metadata/* RichImageData */.sF) {
                                        this.metadataTags.images ??= [];
                                        this.metadataTags.images.push({
                                            data: data.data,
                                            kind: 'coverFront',
                                            mimeType: data.mimeType,
                                        });
                                    }
                                    else if (data instanceof Uint8Array) {
                                        this.metadataTags.images ??= [];
                                        this.metadataTags.images.push({
                                            data,
                                            kind: 'coverFront',
                                            mimeType: 'image/*',
                                        });
                                    }
                                }
                                ;
                                break;
                            case 'track':
                                {
                                    if (typeof data === 'string') {
                                        const parts = data.split('/');
                                        const trackNum = Number.parseInt(parts[0], 10);
                                        const tracksTotal = parts[1] && Number.parseInt(parts[1], 10);
                                        if (Number.isInteger(trackNum) && trackNum > 0) {
                                            this.metadataTags.trackNumber ??= trackNum;
                                        }
                                        if (tracksTotal && Number.isInteger(tracksTotal) && tracksTotal > 0) {
                                            this.metadataTags.tracksTotal ??= tracksTotal;
                                        }
                                    }
                                }
                                ;
                                break;
                            case 'trkn':
                                {
                                    if (data instanceof Uint8Array && data.length >= 6) {
                                        const view = (0,misc/* toDataView */.Zc)(data);
                                        const trackNumber = view.getUint16(2, false);
                                        const tracksTotal = view.getUint16(4, false);
                                        if (trackNumber > 0) {
                                            this.metadataTags.trackNumber ??= trackNumber;
                                        }
                                        if (tracksTotal > 0) {
                                            this.metadataTags.tracksTotal ??= tracksTotal;
                                        }
                                    }
                                }
                                ;
                                break;
                            case 'disc':
                            case 'disk':
                                {
                                    if (data instanceof Uint8Array && data.length >= 6) {
                                        const view = (0,misc/* toDataView */.Zc)(data);
                                        const discNumber = view.getUint16(2, false);
                                        const discNumberMax = view.getUint16(4, false);
                                        if (discNumber > 0) {
                                            this.metadataTags.discNumber ??= discNumber;
                                        }
                                        if (discNumberMax > 0) {
                                            this.metadataTags.discsTotal ??= discNumberMax;
                                        }
                                    }
                                }
                                ;
                                break;
                        }
                    }
                }
                ;
                break;
        }
        slice.filePos = boxEndPos;
        return true;
    }
}
class IsobmffTrackBacking {
    constructor(internalTrack) {
        this.internalTrack = internalTrack;
        this.packetToSampleIndex = new WeakMap();
        this.packetToFragmentLocation = new WeakMap();
    }
    getId() {
        return this.internalTrack.id;
    }
    getNumber() {
        const demuxer = this.internalTrack.demuxer;
        const trackType = this.internalTrack.trackBacking.getType();
        let number = 0;
        for (const track of demuxer.tracks) {
            if (track.trackBacking.getType() === trackType) {
                number++;
            }
            if (track === this.internalTrack) {
                break;
            }
        }
        return number;
    }
    getCodec() {
        throw new Error('Not implemented on base class.');
    }
    getInternalCodecId() {
        return this.internalTrack.internalCodecId;
    }
    getName() {
        return this.internalTrack.name;
    }
    getLanguageCode() {
        return this.internalTrack.languageCode;
    }
    getTimeResolution() {
        return this.internalTrack.timescale;
    }
    isRelativeToUnixEpoch() {
        return false;
    }
    getDisposition() {
        return this.internalTrack.disposition;
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
        const track = this.internalTrack;
        if (track.durationInMediaTimescale <= 0) {
            // The duration is often zero for fragmented files for example; return `null` to signal that the duration
            // must be computed instead.
            return null;
        }
        (0,misc/* assert */.vA)(track.trackBacking);
        const firstPacket = await track.trackBacking.getFirstPacket({ metadataOnly: true });
        return (firstPacket?.timestamp ?? 0) + track.durationInMediaTimescale / track.timescale;
    }
    async getLiveRefreshInterval() {
        return null;
    }
    async getFirstPacket(options) {
        const regularPacket = await this.fetchPacketForSampleIndex(0, options);
        if (regularPacket || !this.internalTrack.demuxer.isFragmented) {
            // If there's a non-fragmented packet, always prefer that
            return regularPacket;
        }
        return this.performFragmentedLookup(null, (fragment) => {
            const trackData = fragment.trackData.get(this.internalTrack.id);
            if (trackData) {
                return {
                    sampleIndex: 0,
                    correctSampleFound: true,
                };
            }
            return {
                sampleIndex: -1,
                correctSampleFound: false,
            };
        }, -Infinity, // Use -Infinity as a search timestamp to avoid using the lookup entries
        Infinity, options);
    }
    mapTimestampIntoTimescale(timestamp) {
        // Do a little rounding to catch cases where the result is very close to an integer. If it is, it's likely
        // that the number was originally an integer divided by the timescale. For stability, it's best
        // to return the integer in this case.
        return (0,misc/* roundIfAlmostInteger */.aI)(timestamp * this.internalTrack.timescale) + this.internalTrack.editListOffset;
    }
    async getPacket(timestamp, options) {
        const timestampInTimescale = this.mapTimestampIntoTimescale(timestamp);
        const sampleTable = this.internalTrack.demuxer.getSampleTableForTrack(this.internalTrack);
        const sampleIndex = getSampleIndexForTimestamp(sampleTable, timestampInTimescale);
        const regularPacket = await this.fetchPacketForSampleIndex(sampleIndex, options);
        if (!sampleTableIsEmpty(sampleTable) || !this.internalTrack.demuxer.isFragmented) {
            // Prefer the non-fragmented packet
            return regularPacket;
        }
        return this.performFragmentedLookup(null, (fragment) => {
            const trackData = fragment.trackData.get(this.internalTrack.id);
            if (!trackData) {
                return { sampleIndex: -1, correctSampleFound: false };
            }
            const index = (0,misc/* binarySearchLessOrEqual */.eE)(trackData.presentationTimestamps, timestampInTimescale, x => x.presentationTimestamp);
            const sampleIndex = index !== -1 ? trackData.presentationTimestamps[index].sampleIndex : -1;
            const correctSampleFound = index !== -1 && timestampInTimescale < trackData.endTimestamp;
            return { sampleIndex, correctSampleFound };
        }, timestampInTimescale, timestampInTimescale, options);
    }
    async getNextPacket(packet, options) {
        const regularSampleIndex = this.packetToSampleIndex.get(packet);
        if (regularSampleIndex !== undefined) {
            // Prefer the non-fragmented packet
            return this.fetchPacketForSampleIndex(regularSampleIndex + 1, options);
        }
        const locationInFragment = this.packetToFragmentLocation.get(packet);
        if (locationInFragment === undefined) {
            throw new Error('Packet was not created from this track.');
        }
        return this.performFragmentedLookup(locationInFragment.fragment, (fragment) => {
            if (fragment === locationInFragment.fragment) {
                const trackData = fragment.trackData.get(this.internalTrack.id);
                if (locationInFragment.sampleIndex + 1 < trackData.samples.length) {
                    // We can simply take the next sample in the fragment
                    return {
                        sampleIndex: locationInFragment.sampleIndex + 1,
                        correctSampleFound: true,
                    };
                }
            }
            else {
                const trackData = fragment.trackData.get(this.internalTrack.id);
                if (trackData) {
                    return {
                        sampleIndex: 0,
                        correctSampleFound: true,
                    };
                }
            }
            return {
                sampleIndex: -1,
                correctSampleFound: false,
            };
        }, -Infinity, // Use -Infinity as a search timestamp to avoid using the lookup entries
        Infinity, options);
    }
    async getKeyPacket(timestamp, options) {
        const timestampInTimescale = this.mapTimestampIntoTimescale(timestamp);
        const sampleTable = this.internalTrack.demuxer.getSampleTableForTrack(this.internalTrack);
        const sampleIndex = getKeyframeSampleIndexForTimestamp(sampleTable, timestampInTimescale);
        const regularPacket = await this.fetchPacketForSampleIndex(sampleIndex, options);
        if (!sampleTableIsEmpty(sampleTable) || !this.internalTrack.demuxer.isFragmented) {
            // Prefer the non-fragmented packet
            return regularPacket;
        }
        return this.performFragmentedLookup(null, (fragment) => {
            const trackData = fragment.trackData.get(this.internalTrack.id);
            if (!trackData) {
                return { sampleIndex: -1, correctSampleFound: false };
            }
            const index = (0,misc/* findLastIndex */.Kl)(trackData.presentationTimestamps, (x) => {
                const sample = trackData.samples[x.sampleIndex];
                return sample.isKeyFrame && x.presentationTimestamp <= timestampInTimescale;
            });
            const sampleIndex = index !== -1 ? trackData.presentationTimestamps[index].sampleIndex : -1;
            const correctSampleFound = index !== -1 && timestampInTimescale < trackData.endTimestamp;
            return { sampleIndex, correctSampleFound };
        }, timestampInTimescale, timestampInTimescale, options);
    }
    async getNextKeyPacket(packet, options) {
        const regularSampleIndex = this.packetToSampleIndex.get(packet);
        if (regularSampleIndex !== undefined) {
            // Prefer the non-fragmented packet
            const sampleTable = this.internalTrack.demuxer.getSampleTableForTrack(this.internalTrack);
            const nextKeyFrameSampleIndex = getNextKeyframeIndexForSample(sampleTable, regularSampleIndex);
            return this.fetchPacketForSampleIndex(nextKeyFrameSampleIndex, options);
        }
        const locationInFragment = this.packetToFragmentLocation.get(packet);
        if (locationInFragment === undefined) {
            throw new Error('Packet was not created from this track.');
        }
        return this.performFragmentedLookup(locationInFragment.fragment, (fragment) => {
            if (fragment === locationInFragment.fragment) {
                const trackData = fragment.trackData.get(this.internalTrack.id);
                const nextKeyFrameIndex = trackData.samples.findIndex((x, i) => x.isKeyFrame && i > locationInFragment.sampleIndex);
                if (nextKeyFrameIndex !== -1) {
                    // We can simply take the next key frame in the fragment
                    return {
                        sampleIndex: nextKeyFrameIndex,
                        correctSampleFound: true,
                    };
                }
            }
            else {
                const trackData = fragment.trackData.get(this.internalTrack.id);
                if (trackData && trackData.firstKeyFrameTimestamp !== null) {
                    const keyFrameIndex = trackData.samples.findIndex(x => x.isKeyFrame);
                    (0,misc/* assert */.vA)(keyFrameIndex !== -1); // There must be one
                    return {
                        sampleIndex: keyFrameIndex,
                        correctSampleFound: true,
                    };
                }
            }
            return {
                sampleIndex: -1,
                correctSampleFound: false,
            };
        }, -Infinity, // Use -Infinity as a search timestamp to avoid using the lookup entries
        Infinity, options);
    }
    async fetchPacketForSampleIndex(sampleIndex, options) {
        if (sampleIndex === -1) {
            return null;
        }
        const sampleTable = this.internalTrack.demuxer.getSampleTableForTrack(this.internalTrack);
        const sampleInfo = getSampleInfo(sampleTable, sampleIndex);
        if (!sampleInfo) {
            return null;
        }
        let data;
        if (options.metadataOnly) {
            data = src_packet/* PLACEHOLDER_DATA */.T;
        }
        else {
            let slice = this.internalTrack.demuxer.reader.requestSlice(sampleInfo.sampleOffset, sampleInfo.sampleSize);
            if (slice instanceof Promise)
                slice = await slice;
            if (!slice) {
                return null; // Data is outside
            }
            data = (0,src_reader/* readBytes */.io)(slice, sampleInfo.sampleSize);
            if (this.internalTrack.encryptionAuxInfo) {
                (0,misc/* assert */.vA)(this.internalTrack.encryptionInfo);
                const entries = await resolveEncryptionAuxInfo(this.internalTrack.demuxer.reader, this.internalTrack.encryptionInfo, this.internalTrack.encryptionAuxInfo);
                if (sampleIndex < entries.length) {
                    data = await decryptSample(this.internalTrack, entries[sampleIndex], data, null);
                }
            }
        }
        const timestamp = (sampleInfo.presentationTimestamp - this.internalTrack.editListOffset)
            / this.internalTrack.timescale;
        const duration = sampleInfo.duration / this.internalTrack.timescale;
        const packet = new src_packet/* EncodedPacket */.Z(data, sampleInfo.isKeyFrame ? 'key' : 'delta', timestamp, duration, sampleIndex, sampleInfo.sampleSize);
        this.packetToSampleIndex.set(packet, sampleIndex);
        return packet;
    }
    async fetchPacketInFragment(fragment, sampleIndex, options) {
        if (sampleIndex === -1) {
            return null;
        }
        const trackData = fragment.trackData.get(this.internalTrack.id);
        const fragmentSample = trackData.samples[sampleIndex];
        (0,misc/* assert */.vA)(fragmentSample);
        let data;
        if (options.metadataOnly) {
            data = src_packet/* PLACEHOLDER_DATA */.T;
        }
        else {
            let slice = this.internalTrack.demuxer.reader.requestSlice(fragmentSample.byteOffset, fragmentSample.byteSize);
            if (slice instanceof Promise)
                slice = await slice;
            if (!slice) {
                return null; // Data is outside
            }
            data = (0,src_reader/* readBytes */.io)(slice, fragmentSample.byteSize);
            if (fragmentSample.encryption) {
                data = await decryptSample(this.internalTrack, fragmentSample.encryption, data, fragment);
            }
        }
        const timestamp = (fragmentSample.presentationTimestamp - this.internalTrack.editListOffset)
            / this.internalTrack.timescale;
        const duration = fragmentSample.duration / this.internalTrack.timescale;
        const packet = new src_packet/* EncodedPacket */.Z(data, fragmentSample.isKeyFrame ? 'key' : 'delta', timestamp, duration, fragment.moofOffset + sampleIndex, fragmentSample.byteSize);
        this.packetToFragmentLocation.set(packet, { fragment, sampleIndex });
        return packet;
    }
    /** Looks for a packet in the fragments while trying to load as few fragments as possible to retrieve it. */
    async performFragmentedLookup(
    // The fragment where we start looking
    startFragment, 
    // This function returns the best-matching sample in a given fragment
    getMatchInFragment, 
    // The timestamp with which we can search the lookup table
    searchTimestamp, 
    // The timestamp for which we know the correct sample will not come after it
    latestTimestamp, options) {
        const demuxer = this.internalTrack.demuxer;
        let currentFragment = null;
        let bestFragment = null;
        let bestSampleIndex = -1;
        if (startFragment) {
            const { sampleIndex, correctSampleFound } = getMatchInFragment(startFragment);
            if (correctSampleFound) {
                return this.fetchPacketInFragment(startFragment, sampleIndex, options);
            }
            if (sampleIndex !== -1) {
                bestFragment = startFragment;
                bestSampleIndex = sampleIndex;
            }
        }
        // Search for a lookup entry; this way, we won't need to start searching from the start of the file
        // but can jump right into the correct fragment (or at least nearby).
        const lookupEntryIndex = (0,misc/* binarySearchLessOrEqual */.eE)(this.internalTrack.fragmentLookupTable, searchTimestamp, x => x.timestamp);
        const lookupEntry = lookupEntryIndex !== -1
            ? this.internalTrack.fragmentLookupTable[lookupEntryIndex]
            : null;
        const positionCacheIndex = (0,misc/* binarySearchLessOrEqual */.eE)(this.internalTrack.fragmentPositionCache, searchTimestamp, x => x.startTimestamp);
        const positionCacheEntry = positionCacheIndex !== -1
            ? this.internalTrack.fragmentPositionCache[positionCacheIndex]
            : null;
        const lookupEntryPosition = Math.max(lookupEntry?.moofOffset ?? 0, positionCacheEntry?.moofOffset ?? 0) || null;
        let currentPos;
        if (!startFragment) {
            currentPos = lookupEntryPosition ?? 0;
        }
        else {
            if (lookupEntryPosition === null || startFragment.moofOffset >= lookupEntryPosition) {
                currentPos = startFragment.moofOffset + startFragment.moofSize;
                currentFragment = startFragment;
            }
            else {
                // Use the lookup entry
                currentPos = lookupEntryPosition;
            }
        }
        while (true) {
            if (currentFragment) {
                const trackData = currentFragment.trackData.get(this.internalTrack.id);
                if (trackData && trackData.startTimestamp > latestTimestamp) {
                    // We're already past the upper bound, no need to keep searching
                    break;
                }
            }
            // Load the header
            let slice = demuxer.reader.requestSliceRange(currentPos, isobmff_reader/* MIN_BOX_HEADER_SIZE */.ZM, isobmff_reader/* MAX_BOX_HEADER_SIZE */.Xk);
            if (slice instanceof Promise)
                slice = await slice;
            if (!slice)
                break;
            const boxStartPos = currentPos;
            const boxInfo = (0,isobmff_reader/* readBoxHeader */.Vl)(slice);
            if (!boxInfo) {
                break;
            }
            if (boxInfo.name === 'moof') {
                currentFragment = await demuxer.readFragment(boxStartPos);
                const { sampleIndex, correctSampleFound } = getMatchInFragment(currentFragment);
                if (correctSampleFound) {
                    return this.fetchPacketInFragment(currentFragment, sampleIndex, options);
                }
                if (sampleIndex !== -1) {
                    bestFragment = currentFragment;
                    bestSampleIndex = sampleIndex;
                }
            }
            currentPos = boxStartPos + boxInfo.totalSize;
        }
        // Catch faulty lookup table entries
        if (lookupEntry && (!bestFragment || bestFragment.moofOffset < lookupEntry.moofOffset)) {
            // The lookup table entry lied to us! We found a lookup entry but no fragment there that satisfied
            // the match. In this case, let's search again but using the lookup entry before that.
            const previousLookupEntry = this.internalTrack.fragmentLookupTable[lookupEntryIndex - 1];
            (0,misc/* assert */.vA)(!previousLookupEntry || previousLookupEntry.timestamp < lookupEntry.timestamp);
            const newSearchTimestamp = previousLookupEntry?.timestamp ?? -Infinity;
            return this.performFragmentedLookup(null, getMatchInFragment, newSearchTimestamp, latestTimestamp, options);
        }
        if (bestFragment) {
            // If we finished looping but didn't find a perfect match, still return the best match we found
            return this.fetchPacketInFragment(bestFragment, bestSampleIndex, options);
        }
        return null;
    }
}
class IsobmffVideoTrackBacking extends IsobmffTrackBacking {
    constructor(internalTrack) {
        super(internalTrack);
        this.decoderConfigPromise = null;
        this.internalTrack = internalTrack;
    }
    getType() {
        return 'video';
    }
    getCodec() {
        return this.internalTrack.info.codec;
    }
    getCodedWidth() {
        return this.internalTrack.info.width;
    }
    getCodedHeight() {
        return this.internalTrack.info.height;
    }
    getSquarePixelWidth() {
        return this.internalTrack.info.squarePixelWidth;
    }
    getSquarePixelHeight() {
        return this.internalTrack.info.squarePixelHeight;
    }
    getRotation() {
        return this.internalTrack.rotation;
    }
    async getColorSpace() {
        return {
            primaries: this.internalTrack.info.colorSpace?.primaries,
            transfer: this.internalTrack.info.colorSpace?.transfer,
            matrix: this.internalTrack.info.colorSpace?.matrix,
            fullRange: this.internalTrack.info.colorSpace?.fullRange,
        };
    }
    async canBeTransparent() {
        return false;
    }
    async getDecoderConfig() {
        if (!this.internalTrack.info.codec) {
            return null;
        }
        return this.decoderConfigPromise ??= (async () => {
            if (this.internalTrack.info.codec === 'vp9' && !this.internalTrack.info.vp9CodecInfo) {
                const firstPacket = await this.getFirstPacket({});
                this.internalTrack.info.vp9CodecInfo = firstPacket && (0,codec_data/* extractVp9CodecInfoFromPacket */.bs)(firstPacket.data);
            }
            else if (this.internalTrack.info.codec === 'av1' && !this.internalTrack.info.av1CodecInfo) {
                const firstPacket = await this.getFirstPacket({});
                this.internalTrack.info.av1CodecInfo = firstPacket && (0,codec_data/* extractAv1CodecInfoFromPacket */.UU)(firstPacket.data);
            }
            const config = {
                codec: (0,codec/* extractVideoCodecString */.QP)(this.internalTrack.info),
                codedWidth: this.internalTrack.info.width,
                codedHeight: this.internalTrack.info.height,
                description: this.internalTrack.info.codecDescription ?? undefined,
                colorSpace: this.internalTrack.info.colorSpace ?? undefined,
            };
            if (this.internalTrack.info.width !== this.internalTrack.info.squarePixelWidth
                || this.internalTrack.info.height !== this.internalTrack.info.squarePixelHeight) {
                config.displayAspectWidth = this.internalTrack.info.squarePixelWidth;
                config.displayAspectHeight = this.internalTrack.info.squarePixelHeight;
            }
            return config;
        })();
    }
}
class IsobmffAudioTrackBacking extends IsobmffTrackBacking {
    constructor(internalTrack) {
        super(internalTrack);
        this.decoderConfig = null;
        this.internalTrack = internalTrack;
    }
    getType() {
        return 'audio';
    }
    getCodec() {
        return this.internalTrack.info.codec;
    }
    getNumberOfChannels() {
        return this.internalTrack.info.numberOfChannels;
    }
    getSampleRate() {
        return this.internalTrack.info.sampleRate;
    }
    async getDecoderConfig() {
        if (!this.internalTrack.info.codec) {
            return null;
        }
        return this.decoderConfig ??= {
            codec: (0,codec/* extractAudioCodecString */.X0)(this.internalTrack.info),
            numberOfChannels: this.internalTrack.info.numberOfChannels,
            sampleRate: this.internalTrack.info.sampleRate,
            description: this.internalTrack.info.codecDescription ?? undefined,
        };
    }
}
const getSampleIndexForTimestamp = (sampleTable, timescaleUnits) => {
    if (sampleTable.presentationTimestamps) {
        const index = (0,misc/* binarySearchLessOrEqual */.eE)(sampleTable.presentationTimestamps, timescaleUnits, x => x.presentationTimestamp);
        if (index === -1) {
            return -1;
        }
        return sampleTable.presentationTimestamps[index].sampleIndex;
    }
    else {
        const index = (0,misc/* binarySearchLessOrEqual */.eE)(sampleTable.sampleTimingEntries, timescaleUnits, x => x.startDecodeTimestamp);
        if (index === -1) {
            return -1;
        }
        const entry = sampleTable.sampleTimingEntries[index];
        return entry.startIndex
            + Math.min(Math.floor((timescaleUnits - entry.startDecodeTimestamp) / entry.delta), entry.count - 1);
    }
};
const getKeyframeSampleIndexForTimestamp = (sampleTable, timescaleUnits) => {
    if (!sampleTable.keySampleIndices) {
        // Every sample is a keyframe
        return getSampleIndexForTimestamp(sampleTable, timescaleUnits);
    }
    if (sampleTable.presentationTimestamps) {
        const index = (0,misc/* binarySearchLessOrEqual */.eE)(sampleTable.presentationTimestamps, timescaleUnits, x => x.presentationTimestamp);
        if (index === -1) {
            return -1;
        }
        // Walk the samples in presentation order until we find one that's a keyframe
        for (let i = index; i >= 0; i--) {
            const sampleIndex = sampleTable.presentationTimestamps[i].sampleIndex;
            const isKeyFrame = (0,misc/* binarySearchExact */.pl)(sampleTable.keySampleIndices, sampleIndex, x => x) !== -1;
            if (isKeyFrame) {
                return sampleIndex;
            }
        }
        return -1;
    }
    else {
        const sampleIndex = getSampleIndexForTimestamp(sampleTable, timescaleUnits);
        const index = (0,misc/* binarySearchLessOrEqual */.eE)(sampleTable.keySampleIndices, sampleIndex, x => x);
        return sampleTable.keySampleIndices[index] ?? -1;
    }
};
const getSampleInfo = (sampleTable, sampleIndex) => {
    const timingEntryIndex = (0,misc/* binarySearchLessOrEqual */.eE)(sampleTable.sampleTimingEntries, sampleIndex, x => x.startIndex);
    const timingEntry = sampleTable.sampleTimingEntries[timingEntryIndex];
    if (!timingEntry || timingEntry.startIndex + timingEntry.count <= sampleIndex) {
        return null;
    }
    const decodeTimestamp = timingEntry.startDecodeTimestamp
        + (sampleIndex - timingEntry.startIndex) * timingEntry.delta;
    let presentationTimestamp = decodeTimestamp;
    const offsetEntryIndex = (0,misc/* binarySearchLessOrEqual */.eE)(sampleTable.sampleCompositionTimeOffsets, sampleIndex, x => x.startIndex);
    const offsetEntry = sampleTable.sampleCompositionTimeOffsets[offsetEntryIndex];
    if (offsetEntry && sampleIndex - offsetEntry.startIndex < offsetEntry.count) {
        presentationTimestamp += offsetEntry.offset;
    }
    const sampleSize = sampleTable.sampleSizes[Math.min(sampleIndex, sampleTable.sampleSizes.length - 1)];
    const chunkEntryIndex = (0,misc/* binarySearchLessOrEqual */.eE)(sampleTable.sampleToChunk, sampleIndex, x => x.startSampleIndex);
    const chunkEntry = sampleTable.sampleToChunk[chunkEntryIndex];
    (0,misc/* assert */.vA)(chunkEntry);
    const chunkIndex = chunkEntry.startChunkIndex
        + Math.floor((sampleIndex - chunkEntry.startSampleIndex) / chunkEntry.samplesPerChunk);
    const chunkOffset = sampleTable.chunkOffsets[chunkIndex];
    const startSampleIndexOfChunk = chunkEntry.startSampleIndex
        + (chunkIndex - chunkEntry.startChunkIndex) * chunkEntry.samplesPerChunk;
    let chunkSize = 0;
    let sampleOffset = chunkOffset;
    if (sampleTable.sampleSizes.length === 1) {
        sampleOffset += sampleSize * (sampleIndex - startSampleIndexOfChunk);
        chunkSize += sampleSize * chunkEntry.samplesPerChunk;
    }
    else {
        for (let i = startSampleIndexOfChunk; i < startSampleIndexOfChunk + chunkEntry.samplesPerChunk; i++) {
            const sampleSize = sampleTable.sampleSizes[i];
            if (i < sampleIndex) {
                sampleOffset += sampleSize;
            }
            chunkSize += sampleSize;
        }
    }
    let duration = timingEntry.delta;
    if (sampleTable.presentationTimestamps) {
        // In order to accurately compute the duration, we need to take the duration to the next sample in presentation
        // order, not in decode order
        const presentationIndex = sampleTable.presentationTimestampIndexMap[sampleIndex];
        (0,misc/* assert */.vA)(presentationIndex !== undefined);
        if (presentationIndex < sampleTable.presentationTimestamps.length - 1) {
            const nextEntry = sampleTable.presentationTimestamps[presentationIndex + 1];
            const nextPresentationTimestamp = nextEntry.presentationTimestamp;
            duration = nextPresentationTimestamp - presentationTimestamp;
        }
    }
    return {
        presentationTimestamp,
        duration,
        sampleOffset,
        sampleSize,
        chunkOffset,
        chunkSize,
        isKeyFrame: sampleTable.keySampleIndices
            ? (0,misc/* binarySearchExact */.pl)(sampleTable.keySampleIndices, sampleIndex, x => x) !== -1
            : true,
    };
};
const getNextKeyframeIndexForSample = (sampleTable, sampleIndex) => {
    if (!sampleTable.keySampleIndices) {
        return sampleIndex + 1;
    }
    const index = (0,misc/* binarySearchLessOrEqual */.eE)(sampleTable.keySampleIndices, sampleIndex, x => x);
    return sampleTable.keySampleIndices[index + 1] ?? -1;
};
const offsetFragmentTrackDataByTimestamp = (trackData, timestamp) => {
    trackData.startTimestamp += timestamp;
    trackData.endTimestamp += timestamp;
    for (const sample of trackData.samples) {
        sample.presentationTimestamp += timestamp;
    }
    for (const entry of trackData.presentationTimestamps) {
        entry.presentationTimestamp += timestamp;
    }
};
/** Extracts the rotation component from a transformation matrix, in degrees. */
const extractRotationFromMatrix = (matrix) => {
    const [a, b] = matrix; // (1, 0) projects onto (a, b), so that's all we need
    const radians = Math.atan2(b, a);
    if (!Number.isFinite(radians)) {
        // Can happen if the entire matrix is 0, for example
        return 0;
    }
    return radians * (180 / Math.PI);
};
const sampleTableIsEmpty = (sampleTable) => {
    return sampleTable.sampleSizes.length === 0;
};
const getOrCreateEncryptionAuxInfo = (track) => {
    if (track.currentFragmentState) {
        return track.currentFragmentState.encryptionAuxInfo ??= {
            defaultSampleInfoSize: 0,
            sampleSizes: null,
            sampleCount: 0,
            offset: null,
            resolved: null,
        };
    }
    else {
        return track.encryptionAuxInfo ??= {
            defaultSampleInfoSize: 0,
            sampleSizes: null,
            sampleCount: 0,
            offset: null,
            resolved: null,
        };
    }
};
const resolveEncryptionAuxInfo = async (reader, encryptionInfo, aux) => {
    if (aux.resolved) {
        return aux.resolved;
    }
    if (aux.offset === null || aux.sampleCount === 0) {
        throw new Error('Incomplete saiz/saio info; cannot resolve encryption data.');
    }
    let totalSize = 0;
    if (aux.defaultSampleInfoSize > 0) {
        totalSize = aux.defaultSampleInfoSize * aux.sampleCount;
    }
    else {
        (0,misc/* assert */.vA)(aux.sampleSizes);
        for (let i = 0; i < aux.sampleCount; i++) {
            totalSize += aux.sampleSizes[i];
        }
    }
    let slice = reader.requestSlice(aux.offset, totalSize);
    if (slice instanceof Promise)
        slice = await slice;
    if (!slice) {
        throw new Error('Failed to read auxiliary encryption info.');
    }
    const ivSize = encryptionInfo.defaultPerSampleIvSize;
    (0,misc/* assert */.vA)(ivSize !== null);
    // Each aux entry has the same byte layout as a senc entry: IV (of size ivSize, or the constant IV from tenc
    // when ivSize is 0), then optionally subsample count + [clearLen, protectedLen] pairs. Subsamples are present
    // iff the entry is larger than the IV.
    const entries = [];
    for (let i = 0; i < aux.sampleCount; i++) {
        const entrySize = aux.defaultSampleInfoSize > 0
            ? aux.defaultSampleInfoSize
            : aux.sampleSizes[i];
        const iv = new Uint8Array(16);
        if (ivSize > 0) {
            iv.set((0,src_reader/* readBytes */.io)(slice, ivSize), 0);
        }
        else {
            iv.set(encryptionInfo.defaultConstantIv, 0);
        }
        let subsamples = null;
        if (entrySize > ivSize) {
            const subsampleCount = (0,src_reader/* readU16Be */.mH)(slice);
            subsamples = [];
            for (let j = 0; j < subsampleCount; j++) {
                const clearLen = (0,src_reader/* readU16Be */.mH)(slice);
                const protectedLen = (0,src_reader/* readU32Be */.cN)(slice);
                subsamples.push({ clearLen, protectedLen });
            }
        }
        entries.push({ iv, subsamples });
    }
    aux.resolved = entries;
    return entries;
};
const decryptSample = async (track, sampleEncryption, data, fragment) => {
    (0,misc/* assert */.vA)(track.encryptionInfo);
    const encryptionInfo = track.encryptionInfo;
    (0,misc/* assert */.vA)(encryptionInfo.defaultKid !== null);
    const keyId = encryptionInfo.defaultKid;
    let keyBytes;
    const cacheEntry = track.demuxer.decryptionKeyCache.get(keyId);
    if (cacheEntry) {
        keyBytes = await cacheEntry;
    }
    else {
        if (!track.demuxer.input._formatOptions.isobmff?.resolveKeyId) {
            throw new Error('Encrypted media samples encountered. To decrypt them, please provide a callback for'
                + ' InputOptions.formatOptions.isobmff.resolveKeyId.');
        }
        const promise = (async () => {
            let psshBoxes = track.demuxer.psshBoxes;
            if (fragment) {
                psshBoxes = [
                    ...psshBoxes,
                    ...fragment.psshBoxes,
                ].filter(x => x.keyIds === null || x.keyIds.includes(keyId));
                // Filter out duplicates
                for (let i = 0; i < psshBoxes.length - 1; i++) {
                    for (let j = i + 1; j < psshBoxes.length; j++) {
                        if ((0,isobmff_misc/* psshBoxesAreEqual */.MG)(psshBoxes[i], psshBoxes[j])) {
                            psshBoxes.splice(j, 1);
                            j--;
                        }
                    }
                }
            }
            const keyResult = await track.demuxer.input._formatOptions.isobmff.resolveKeyId({ keyId, psshBoxes });
            if (!((typeof keyResult === 'string' && keyResult.length === 32 && misc/* HEX_STRING_REGEX */.Sn.test(keyResult))
                || (keyResult instanceof Uint8Array && keyResult.byteLength === 16))) {
                throw new TypeError('resolveKeyId must return a 32-character hex string or a 16-byte Uint8Array containing the'
                    + ' decryption key.');
            }
            return keyResult instanceof Uint8Array
                ? keyResult
                : (0,misc/* hexStringToBytes */.ZY)(keyResult);
        })();
        track.demuxer.decryptionKeyCache.set(keyId, promise);
        keyBytes = await promise;
    }
    if (encryptionInfo.scheme === 'cenc' || encryptionInfo.scheme === 'cens') {
        return decryptCtr(keyBytes, encryptionInfo, sampleEncryption, data);
    }
    else {
        return decryptCbcs(keyBytes, encryptionInfo, sampleEncryption, data);
    }
};
const decryptCtr = async (key, encryptionInfo, sampleEncryption, data) => {
    const counter = new Uint8Array(16);
    counter.set(sampleEncryption.iv, 0);
    const cryptoKey = await crypto.subtle.importKey('raw', key, { name: 'AES-CTR' }, false, ['decrypt']);
    const cryptApply = async (input) => {
        const plaintext = await crypto.subtle.decrypt({ name: 'AES-CTR', counter, length: 64 }, cryptoKey, input);
        return new Uint8Array(plaintext);
    };
    if (!sampleEncryption.subsamples) {
        // Whole sample is protected, no pattern
        return cryptApply(data);
    }
    (0,misc/* assert */.vA)(encryptionInfo.defaultCryptByteBlock !== null && encryptionInfo.defaultSkipByteBlock !== null);
    const cryptRanges = collectCryptRanges(sampleEncryption.subsamples, encryptionInfo.defaultCryptByteBlock, encryptionInfo.defaultSkipByteBlock);
    // Concatenate all crypt ranges into a single buffer so the continuous CTR counter behavior is preserved
    let totalCryptLen = 0;
    for (const range of cryptRanges) {
        for (const seg of range.perSubsample) {
            totalCryptLen += seg.length;
        }
    }
    const cryptBuffer = new Uint8Array(totalCryptLen);
    let writePos = 0;
    for (const range of cryptRanges) {
        for (const seg of range.perSubsample) {
            cryptBuffer.set(data.subarray(seg.offset, seg.offset + seg.length), writePos);
            writePos += seg.length;
        }
    }
    const plain = await cryptApply(cryptBuffer);
    // Now let's build the output
    const output = new Uint8Array(data);
    let readPos = 0;
    for (const range of cryptRanges) {
        for (const seg of range.perSubsample) {
            output.set(plain.subarray(readPos, readPos + seg.length), seg.offset);
            readPos += seg.length;
        }
    }
    return output;
};
const decryptCbcs = (key, encryptionInfo, sampleEncryption, data) => {
    const ctx = new Aes128CbcContext();
    ctx.init({ key, iv: sampleEncryption.iv });
    const cryptByteBlock = encryptionInfo.defaultCryptByteBlock;
    const skipByteBlock = encryptionInfo.defaultSkipByteBlock;
    (0,misc/* assert */.vA)(cryptByteBlock !== null && skipByteBlock !== null);
    if (!sampleEncryption.subsamples) {
        // Whole-sample encryption: straightforward CBC over floor(size / 16) blocks, any trailing bytes stay clear
        const output = new Uint8Array(data);
        const numBlocks = Math.floor(data.length / 16);
        for (let b = 0; b < numBlocks; b++) {
            const off = b * 16;
            ctx.in.set(data.subarray(off, off + 16));
            ctx.decrypt();
            output.set(ctx.out, off);
        }
        return output;
    }
    if (cryptByteBlock === 0 && skipByteBlock === 0) {
        throw new Error('cbcs with subsamples requires pattern encryption.');
    }
    const output = new Uint8Array(data);
    // Pattern decryption: IV is reset at the start of each subsample. Within a subsample, the CBC chain continues
    // across skipped blocks (the IV after a crypt group carries over to the next crypt group's first block).
    const cryptRanges = collectCryptRanges(sampleEncryption.subsamples, cryptByteBlock, skipByteBlock);
    const ivView = new DataView(sampleEncryption.iv.buffer, sampleEncryption.iv.byteOffset, 16);
    for (const range of cryptRanges) {
        // Reset IV per subsample
        ctx.iv[0] = ivView.getUint32(0, false);
        ctx.iv[1] = ivView.getUint32(4, false);
        ctx.iv[2] = ivView.getUint32(8, false);
        ctx.iv[3] = ivView.getUint32(12, false);
        for (const seg of range.perSubsample) {
            // Decrypt length / 16 blocks at this offset
            const numBlocks = seg.length / 16;
            for (let b = 0; b < numBlocks; b++) {
                const offset = seg.offset + b * 16;
                ctx.in.set(data.subarray(offset, offset + 16));
                ctx.decrypt();
                output.set(ctx.out, offset);
            }
        }
    }
    return output;
};
const collectCryptRanges = (subsamples, cryptByteBlock, skipByteBlock) => {
    const ranges = [];
    const hasPattern = cryptByteBlock !== 0 || skipByteBlock !== 0;
    let cursor = 0;
    for (const subsample of subsamples) {
        cursor += subsample.clearLen;
        const perSubsample = [];
        if (!hasPattern) {
            if (subsample.protectedLen > 0) {
                perSubsample.push({ offset: cursor, length: subsample.protectedLen });
            }
            cursor += subsample.protectedLen;
        }
        else {
            let remaining = subsample.protectedLen;
            let pos = cursor;
            while (remaining > 0) {
                if (remaining < 16 * cryptByteBlock) {
                    break; // Partial final crypt group stays clear
                }
                const cryptBytes = 16 * cryptByteBlock;
                perSubsample.push({ offset: pos, length: cryptBytes });
                pos += cryptBytes;
                remaining -= cryptBytes;
                const skipBytes = Math.min(16 * skipByteBlock, remaining);
                pos += skipBytes;
                remaining -= skipBytes;
            }
            cursor += subsample.protectedLen;
        }
        ranges.push({ perSubsample });
    }
    return ranges;
};

// EXTERNAL MODULE: ./node_modules/mediabunny/dist/modules/src/matroska/ebml.js
var ebml = __webpack_require__(6411);
// EXTERNAL MODULE: ./node_modules/mediabunny/dist/modules/src/matroska/matroska-misc.js
var matroska_misc = __webpack_require__(3616);
;// ./node_modules/mediabunny/dist/modules/src/matroska/matroska-demuxer.js
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */









var BlockLacing;
(function (BlockLacing) {
    BlockLacing[BlockLacing["None"] = 0] = "None";
    BlockLacing[BlockLacing["Xiph"] = 1] = "Xiph";
    BlockLacing[BlockLacing["FixedSize"] = 2] = "FixedSize";
    BlockLacing[BlockLacing["Ebml"] = 3] = "Ebml";
})(BlockLacing || (BlockLacing = {}));
var ContentEncodingScope;
(function (ContentEncodingScope) {
    ContentEncodingScope[ContentEncodingScope["Block"] = 1] = "Block";
    ContentEncodingScope[ContentEncodingScope["Private"] = 2] = "Private";
    ContentEncodingScope[ContentEncodingScope["Next"] = 4] = "Next";
})(ContentEncodingScope || (ContentEncodingScope = {}));
var ContentCompAlgo;
(function (ContentCompAlgo) {
    ContentCompAlgo[ContentCompAlgo["Zlib"] = 0] = "Zlib";
    ContentCompAlgo[ContentCompAlgo["Bzlib"] = 1] = "Bzlib";
    ContentCompAlgo[ContentCompAlgo["lzo1x"] = 2] = "lzo1x";
    ContentCompAlgo[ContentCompAlgo["HeaderStripping"] = 3] = "HeaderStripping";
})(ContentCompAlgo || (ContentCompAlgo = {}));
const METADATA_ELEMENTS = [
    { id: ebml/* EBMLId */.Cl.SeekHead, flag: 'seekHeadSeen' },
    { id: ebml/* EBMLId */.Cl.Info, flag: 'infoSeen' },
    { id: ebml/* EBMLId */.Cl.Tracks, flag: 'tracksSeen' },
    { id: ebml/* EBMLId */.Cl.Cues, flag: 'cuesSeen' },
];
const MAX_RESYNC_LENGTH = 10 * 2 ** 20; // 10 MiB
class MatroskaDemuxer extends demuxer/* Demuxer */.B {
    constructor(input) {
        super(input);
        this.readMetadataPromise = null;
        this.segments = [];
        this.currentSegment = null;
        this.currentTrack = null;
        this.currentCluster = null;
        this.currentBlock = null;
        this.currentBlockAdditional = null;
        this.currentCueTime = null;
        this.currentDecodingInstruction = null;
        this.currentTagTargetIsMovie = true;
        this.currentSimpleTagName = null;
        this.currentAttachedFile = null;
        this.isWebM = false;
        this.reader = input._reader;
    }
    async getTrackBackings() {
        await this.readMetadata();
        return this.segments.flatMap(segment => segment.tracks.map(track => track.trackBacking));
    }
    async getMimeType() {
        await this.readMetadata();
        const backings = await this.getTrackBackings();
        const codecStrings = await Promise.all(backings.map(x => x.getDecoderConfig().then(c => c?.codec ?? null)));
        return (0,matroska_misc/* buildMatroskaMimeType */.V)({
            isWebM: this.isWebM,
            hasVideo: this.segments.some(segment => segment.tracks.some(x => x.info?.type === 'video')),
            hasAudio: this.segments.some(segment => segment.tracks.some(x => x.info?.type === 'audio')),
            codecStrings: codecStrings.filter(Boolean),
        });
    }
    async getMetadataTags() {
        await this.readMetadata();
        // Load metadata tags from each segment lazily (only once)
        for (const segment of this.segments) {
            if (!segment.metadataTagsCollected) {
                if (this.reader.fileSize !== null) {
                    await this.loadSegmentMetadata(segment);
                }
                else {
                    // The seeking would be too crazy, let's not
                }
                segment.metadataTagsCollected = true;
            }
        }
        // This is kinda handwavy, and how we handle multiple segments isn't suuuuper well-defined anyway; so we just
        // shallow-merge metadata tags from all (usually just one) segments.
        let metadataTags = {};
        for (const segment of this.segments) {
            metadataTags = { ...metadataTags, ...segment.metadataTags };
        }
        return metadataTags;
    }
    readMetadata() {
        return this.readMetadataPromise ??= (async () => {
            let currentPos = 0;
            // Loop over all top-level elements in the file
            while (true) {
                let slice = this.reader.requestSliceRange(currentPos, ebml/* MIN_HEADER_SIZE */.De, ebml/* MAX_HEADER_SIZE */.r1);
                if (slice instanceof Promise)
                    slice = await slice;
                if (!slice)
                    break;
                const header = (0,ebml/* readElementHeader */.ur)(slice);
                if (!header) {
                    break; // Zero padding at the end of the file triggers this, for example
                }
                const id = header.id;
                let size = header.size;
                const dataStartPos = slice.filePos;
                if (id === ebml/* EBMLId */.Cl.EBML) {
                    (0,ebml/* assertDefinedSize */.p)(size);
                    let slice = this.reader.requestSlice(dataStartPos, size);
                    if (slice instanceof Promise)
                        slice = await slice;
                    if (!slice)
                        break;
                    this.readContiguousElements(slice);
                }
                else if (id === ebml/* EBMLId */.Cl.Segment) { // Segment found!
                    await this.readSegment(dataStartPos, size);
                    if (size === undefined) {
                        // Segment sizes can be undefined (common in livestreamed files), so assume this is the last
                        // and only segment
                        break;
                    }
                    if (this.reader.fileSize === null) {
                        break; // Stop at the first segment
                    }
                }
                else if (id === ebml/* EBMLId */.Cl.Cluster) {
                    if (this.reader.fileSize === null) {
                        break; // Shouldn't be reached anyway, since we stop at the first segment
                    }
                    // Clusters are not a top-level element in Matroska, but some files contain a Segment whose size
                    // doesn't contain any of the clusters that follow it. In the case, we apply the following logic: if
                    // we find a top-level cluster, attribute it to the previous segment.
                    if (size === undefined) {
                        // Just in case this is one of those weird sizeless clusters, let's do our best and still try to
                        // determine its size.
                        const nextElementPos = await (0,ebml/* searchForNextElementId */.IQ)(this.reader, dataStartPos, ebml/* LEVEL_0_AND_1_EBML_IDS */.K9, this.reader.fileSize);
                        size = nextElementPos.pos - dataStartPos;
                    }
                    const lastSegment = (0,misc/* last */._g)(this.segments);
                    if (lastSegment) {
                        // Extend the previous segment's size
                        lastSegment.elementEndPos = dataStartPos + size;
                    }
                }
                (0,ebml/* assertDefinedSize */.p)(size);
                currentPos = dataStartPos + size;
            }
        })();
    }
    async readSegment(segmentDataStart, dataSize) {
        this.currentSegment = {
            seekHeadSeen: false,
            infoSeen: false,
            tracksSeen: false,
            cuesSeen: false,
            tagsSeen: false,
            attachmentsSeen: false,
            timestampScale: -1,
            timestampFactor: -1,
            duration: -1,
            seekEntries: [],
            tracks: [],
            cuePoints: [],
            dataStartPos: segmentDataStart,
            elementEndPos: dataSize === undefined
                ? null // Assume it goes until the end of the file
                : segmentDataStart + dataSize,
            clusterSeekStartPos: segmentDataStart,
            lastReadCluster: null,
            metadataTags: {},
            metadataTagsCollected: false,
        };
        this.segments.push(this.currentSegment);
        let currentPos = segmentDataStart;
        while (this.currentSegment.elementEndPos === null || currentPos < this.currentSegment.elementEndPos) {
            let slice = this.reader.requestSliceRange(currentPos, ebml/* MIN_HEADER_SIZE */.De, ebml/* MAX_HEADER_SIZE */.r1);
            if (slice instanceof Promise)
                slice = await slice;
            if (!slice)
                break;
            const elementStartPos = currentPos;
            const header = (0,ebml/* readElementHeader */.ur)(slice);
            if (!header || (!ebml/* LEVEL_1_EBML_IDS */.VE.includes(header.id) && header.id !== ebml/* EBMLId */.Cl.Void)) {
                // Potential junk. Let's try to resync
                const nextPos = await (0,ebml/* resync */.nE)(this.reader, elementStartPos, ebml/* LEVEL_1_EBML_IDS */.VE, Math.min(this.currentSegment.elementEndPos ?? Infinity, elementStartPos + MAX_RESYNC_LENGTH));
                if (nextPos) {
                    currentPos = nextPos;
                    continue;
                }
                else {
                    break; // Resync failed
                }
            }
            const { id, size } = header;
            const dataStartPos = slice.filePos;
            const metadataElementIndex = METADATA_ELEMENTS.findIndex(x => x.id === id);
            if (metadataElementIndex !== -1) {
                const field = METADATA_ELEMENTS[metadataElementIndex].flag;
                this.currentSegment[field] = true;
                (0,ebml/* assertDefinedSize */.p)(size);
                let slice = this.reader.requestSlice(dataStartPos, size);
                if (slice instanceof Promise)
                    slice = await slice;
                if (slice) {
                    this.readContiguousElements(slice);
                }
            }
            else if (id === ebml/* EBMLId */.Cl.Tags || id === ebml/* EBMLId */.Cl.Attachments) {
                // Metadata found at the beginning of the segment, great, let's parse it
                if (id === ebml/* EBMLId */.Cl.Tags) {
                    this.currentSegment.tagsSeen = true;
                }
                else {
                    this.currentSegment.attachmentsSeen = true;
                }
                (0,ebml/* assertDefinedSize */.p)(size);
                let slice = this.reader.requestSlice(dataStartPos, size);
                if (slice instanceof Promise)
                    slice = await slice;
                if (slice) {
                    this.readContiguousElements(slice);
                }
            }
            else if (id === ebml/* EBMLId */.Cl.Cluster) {
                this.currentSegment.clusterSeekStartPos = elementStartPos;
                break; // Stop at the first cluster
            }
            if (size === undefined) {
                break;
            }
            else {
                currentPos = dataStartPos + size;
            }
        }
        // Sort the seek entries by file position so reading them exhibits a sequential pattern
        this.currentSegment.seekEntries.sort((a, b) => a.segmentPosition - b.segmentPosition);
        if (this.reader.fileSize !== null) {
            // Use the seek head to read missing metadata elements
            for (const seekEntry of this.currentSegment.seekEntries) {
                const target = METADATA_ELEMENTS.find(x => x.id === seekEntry.id);
                if (!target) {
                    continue;
                }
                if (this.currentSegment[target.flag])
                    continue;
                let slice = this.reader.requestSliceRange(segmentDataStart + seekEntry.segmentPosition, ebml/* MIN_HEADER_SIZE */.De, ebml/* MAX_HEADER_SIZE */.r1);
                if (slice instanceof Promise)
                    slice = await slice;
                if (!slice)
                    continue;
                const header = (0,ebml/* readElementHeader */.ur)(slice);
                if (!header)
                    continue;
                const { id, size } = header;
                if (id !== target.id)
                    continue;
                (0,ebml/* assertDefinedSize */.p)(size);
                this.currentSegment[target.flag] = true;
                let dataSlice = this.reader.requestSlice(slice.filePos, size);
                if (dataSlice instanceof Promise)
                    dataSlice = await dataSlice;
                if (!dataSlice)
                    continue;
                this.readContiguousElements(dataSlice);
            }
        }
        if (this.currentSegment.timestampScale === -1) {
            // TimestampScale element is missing. Technically an invalid file, but let's default to the typical value,
            // which is 1e6.
            this.currentSegment.timestampScale = 1e6;
            this.currentSegment.timestampFactor = 1e9 / 1e6;
        }
        // Compute default duration for all tracks now that we have the timestamp factor
        for (const track of this.currentSegment.tracks) {
            if (track.defaultDurationNs !== null) {
                track.defaultDuration = (this.currentSegment.timestampFactor * track.defaultDurationNs) / 1e9;
            }
        }
        // Now, let's distribute the cue points to the tracks
        const idToTrack = new Map(this.currentSegment.tracks.map(x => [x.id, x]));
        // Assign cue points to their respective tracks
        for (const cuePoint of this.currentSegment.cuePoints) {
            const track = idToTrack.get(cuePoint.trackId);
            if (track) {
                track.cuePoints.push(cuePoint);
            }
        }
        for (const track of this.currentSegment.tracks) {
            // Sort cue points by time
            track.cuePoints.sort((a, b) => a.time - b.time);
            // Remove multiple cue points for the same time
            for (let i = 0; i < track.cuePoints.length - 1; i++) {
                const cuePoint1 = track.cuePoints[i];
                const cuePoint2 = track.cuePoints[i + 1];
                if (cuePoint1.time === cuePoint2.time) {
                    track.cuePoints.splice(i + 1, 1);
                    i--;
                }
            }
        }
        let trackWithMostCuePoints = null;
        let maxCuePointCount = -Infinity;
        for (const track of this.currentSegment.tracks) {
            if (track.cuePoints.length > maxCuePointCount) {
                maxCuePointCount = track.cuePoints.length;
                trackWithMostCuePoints = track;
            }
        }
        // For every track that has received 0 cue points (can happen, often only the video track receives cue points),
        // we still want to have better seeking. Therefore, let's give it the cue points of the track with the most cue
        // points, which should provide us with the most fine-grained seeking.
        for (const track of this.currentSegment.tracks) {
            if (track.cuePoints.length === 0) {
                track.cuePoints = trackWithMostCuePoints.cuePoints;
            }
        }
        this.currentSegment = null;
    }
    async readCluster(startPos, segment) {
        if (segment.lastReadCluster?.elementStartPos === startPos) {
            return segment.lastReadCluster;
        }
        let headerSlice = this.reader.requestSliceRange(startPos, ebml/* MIN_HEADER_SIZE */.De, ebml/* MAX_HEADER_SIZE */.r1);
        if (headerSlice instanceof Promise)
            headerSlice = await headerSlice;
        (0,misc/* assert */.vA)(headerSlice);
        const elementStartPos = startPos;
        const elementHeader = (0,ebml/* readElementHeader */.ur)(headerSlice);
        (0,misc/* assert */.vA)(elementHeader);
        const id = elementHeader.id;
        (0,misc/* assert */.vA)(id === ebml/* EBMLId */.Cl.Cluster);
        let size = elementHeader.size;
        const dataStartPos = headerSlice.filePos;
        if (size === undefined) {
            // The cluster's size is undefined (can happen in livestreamed files). We'd still like to know the size of
            // it, so we have no other choice but to iterate over the EBML structure until we find an element at level
            // 0 or 1, indicating the end of the cluster (all elements inside the cluster are at level 2).
            const nextElementPos = await (0,ebml/* searchForNextElementId */.IQ)(this.reader, dataStartPos, ebml/* LEVEL_0_AND_1_EBML_IDS */.K9, segment.elementEndPos);
            size = nextElementPos.pos - dataStartPos;
        }
        // Load the entire cluster
        let dataSlice = this.reader.requestSlice(dataStartPos, size);
        if (dataSlice instanceof Promise)
            dataSlice = await dataSlice;
        const cluster = {
            segment,
            elementStartPos,
            elementEndPos: dataStartPos + size,
            dataStartPos,
            timestamp: -1,
            trackData: new Map(),
        };
        this.currentCluster = cluster;
        if (dataSlice) {
            // Read the children of the cluster, stopping early at level 0 or 1 EBML elements. We do this because some
            // clusters have incorrect sizes that are too large
            const endPos = this.readContiguousElements(dataSlice, ebml/* LEVEL_0_AND_1_EBML_IDS */.K9);
            cluster.elementEndPos = endPos;
        }
        for (const [, trackData] of cluster.trackData) {
            const track = trackData.track;
            // This must hold, as track datas only get created if a block for that track is encountered
            (0,misc/* assert */.vA)(trackData.blocks.length > 0);
            let hasLacedBlocks = false;
            for (let i = 0; i < trackData.blocks.length; i++) {
                const block = trackData.blocks[i];
                block.timestamp += cluster.timestamp;
                hasLacedBlocks ||= block.lacing !== BlockLacing.None;
            }
            trackData.presentationTimestamps = trackData.blocks
                .map((block, i) => ({ timestamp: block.timestamp, blockIndex: i }))
                .sort((a, b) => a.timestamp - b.timestamp);
            for (let i = 0; i < trackData.presentationTimestamps.length; i++) {
                const currentEntry = trackData.presentationTimestamps[i];
                const currentBlock = trackData.blocks[currentEntry.blockIndex];
                if (trackData.firstKeyFrameTimestamp === null && currentBlock.isKeyFrame) {
                    trackData.firstKeyFrameTimestamp = currentBlock.timestamp;
                }
                if (i < trackData.presentationTimestamps.length - 1) {
                    // Update block durations based on presentation order
                    const nextEntry = trackData.presentationTimestamps[i + 1];
                    currentBlock.duration = nextEntry.timestamp - currentBlock.timestamp;
                }
                else if (currentBlock.duration === 0) {
                    if (track.defaultDuration != null) {
                        if (currentBlock.lacing === BlockLacing.None) {
                            currentBlock.duration = track.defaultDuration;
                        }
                        else {
                            // Handled by the lace resolution code
                        }
                    }
                }
            }
            if (hasLacedBlocks) {
                // Perform lace resolution. Here, we expand each laced block into multiple blocks where each contains
                // one frame of the lace. We do this after determining block timestamps so we can properly distribute
                // the block's duration across the laced frames.
                this.expandLacedBlocks(trackData.blocks, track);
                // Recompute since blocks have changed
                trackData.presentationTimestamps = trackData.blocks
                    .map((block, i) => ({ timestamp: block.timestamp, blockIndex: i }))
                    .sort((a, b) => a.timestamp - b.timestamp);
            }
            const firstBlock = trackData.blocks[trackData.presentationTimestamps[0].blockIndex];
            const lastBlock = trackData.blocks[(0,misc/* last */._g)(trackData.presentationTimestamps).blockIndex];
            trackData.startTimestamp = firstBlock.timestamp;
            trackData.endTimestamp = lastBlock.timestamp + lastBlock.duration;
            // Let's remember that a cluster with a given timestamp is here, speeding up future lookups if no cues exist
            const insertionIndex = (0,misc/* binarySearchLessOrEqual */.eE)(track.clusterPositionCache, trackData.startTimestamp, x => x.startTimestamp);
            if (insertionIndex === -1
                || track.clusterPositionCache[insertionIndex].elementStartPos !== elementStartPos) {
                track.clusterPositionCache.splice(insertionIndex + 1, 0, {
                    elementStartPos: cluster.elementStartPos,
                    startTimestamp: trackData.startTimestamp,
                });
            }
        }
        segment.lastReadCluster = cluster;
        return cluster;
    }
    getTrackDataInCluster(cluster, trackNumber) {
        let trackData = cluster.trackData.get(trackNumber);
        if (!trackData) {
            const track = cluster.segment.tracks.find(x => x.id === trackNumber);
            if (!track) {
                return null;
            }
            trackData = {
                track,
                startTimestamp: 0,
                endTimestamp: 0,
                firstKeyFrameTimestamp: null,
                blocks: [],
                presentationTimestamps: [],
            };
            cluster.trackData.set(trackNumber, trackData);
        }
        return trackData;
    }
    expandLacedBlocks(blocks, track) {
        // https://www.matroska.org/technical/notes.html#block-lacing
        for (let blockIndex = 0; blockIndex < blocks.length; blockIndex++) {
            const originalBlock = blocks[blockIndex];
            if (originalBlock.lacing === BlockLacing.None) {
                continue;
            }
            // Decode the block data if it hasn't been decoded yet (needed for lacing expansion)
            if (!originalBlock.decoded) {
                originalBlock.data = this.decodeBlockData(track, originalBlock.data);
                originalBlock.decoded = true;
            }
            const slice = src_reader/* FileSlice */.x$.tempFromBytes(originalBlock.data);
            const frameSizes = [];
            const frameCount = (0,src_reader/* readU8 */.eo)(slice) + 1;
            switch (originalBlock.lacing) {
                case BlockLacing.Xiph:
                    {
                        let totalUsedSize = 0;
                        // Xiph lacing, just like in Ogg
                        for (let i = 0; i < frameCount - 1; i++) {
                            let frameSize = 0;
                            while (slice.bufferPos < slice.length) {
                                const value = (0,src_reader/* readU8 */.eo)(slice);
                                frameSize += value;
                                if (value < 255) {
                                    frameSizes.push(frameSize);
                                    totalUsedSize += frameSize;
                                    break;
                                }
                            }
                        }
                        // Compute the last frame's size from whatever's left
                        frameSizes.push(slice.length - (slice.bufferPos + totalUsedSize));
                    }
                    ;
                    break;
                case BlockLacing.FixedSize:
                    {
                        // Fixed size lacing: all frames have same size
                        const totalDataSize = slice.length - 1; // Minus the frame count byte
                        const frameSize = Math.floor(totalDataSize / frameCount);
                        for (let i = 0; i < frameCount; i++) {
                            frameSizes.push(frameSize);
                        }
                    }
                    ;
                    break;
                case BlockLacing.Ebml:
                    {
                        // EBML lacing: first size absolute, subsequent ones are coded as signed differences from the last
                        const firstResult = (0,ebml/* readVarInt */.pT)(slice);
                        (0,misc/* assert */.vA)(firstResult !== null); // Assume it's not an invalid VINT
                        let currentSize = firstResult;
                        frameSizes.push(currentSize);
                        let totalUsedSize = currentSize;
                        for (let i = 1; i < frameCount - 1; i++) {
                            const startPos = slice.bufferPos;
                            const diffResult = (0,ebml/* readVarInt */.pT)(slice);
                            (0,misc/* assert */.vA)(diffResult !== null);
                            const unsignedDiff = diffResult;
                            const width = slice.bufferPos - startPos;
                            const bias = (1 << (width * 7 - 1)) - 1; // Typo-corrected version of 2^((7*n)-1)^-1
                            const diff = unsignedDiff - bias;
                            currentSize += diff;
                            frameSizes.push(currentSize);
                            totalUsedSize += currentSize;
                        }
                        // Compute the last frame's size from whatever's left
                        frameSizes.push(slice.length - (slice.bufferPos + totalUsedSize));
                    }
                    ;
                    break;
                default: (0,misc/* assert */.vA)(false);
            }
            (0,misc/* assert */.vA)(frameSizes.length === frameCount);
            blocks.splice(blockIndex, 1); // Remove the original block
            const blockDuration = originalBlock.duration || frameCount * (track.defaultDuration ?? 0);
            // Now, let's insert each frame as its own block
            for (let i = 0; i < frameCount; i++) {
                const frameSize = frameSizes[i];
                const frameData = (0,src_reader/* readBytes */.io)(slice, frameSize);
                // Distribute timestamps evenly across the block duration
                const frameTimestamp = originalBlock.timestamp + (blockDuration * i / frameCount);
                const frameDuration = blockDuration / frameCount;
                blocks.splice(blockIndex + i, 0, {
                    timestamp: frameTimestamp,
                    duration: frameDuration,
                    isKeyFrame: originalBlock.isKeyFrame,
                    data: frameData,
                    lacing: BlockLacing.None,
                    decoded: true,
                    mainAdditional: originalBlock.mainAdditional,
                });
            }
            blockIndex += frameCount; // Skip the blocks we just added
            blockIndex--;
        }
    }
    async loadSegmentMetadata(segment) {
        for (const seekEntry of segment.seekEntries) {
            if (seekEntry.id === ebml/* EBMLId */.Cl.Tags && !segment.tagsSeen) {
                // We need to load the tags
            }
            else if (seekEntry.id === ebml/* EBMLId */.Cl.Attachments && !segment.attachmentsSeen) {
                // We need to load the attachments
            }
            else {
                continue;
            }
            let slice = this.reader.requestSliceRange(segment.dataStartPos + seekEntry.segmentPosition, ebml/* MIN_HEADER_SIZE */.De, ebml/* MAX_HEADER_SIZE */.r1);
            if (slice instanceof Promise)
                slice = await slice;
            if (!slice)
                continue;
            const header = (0,ebml/* readElementHeader */.ur)(slice);
            if (!header || header.id !== seekEntry.id)
                continue;
            const { size } = header;
            (0,ebml/* assertDefinedSize */.p)(size);
            (0,misc/* assert */.vA)(!this.currentSegment);
            this.currentSegment = segment;
            let dataSlice = this.reader.requestSlice(slice.filePos, size);
            if (dataSlice instanceof Promise)
                dataSlice = await dataSlice;
            if (dataSlice) {
                this.readContiguousElements(dataSlice);
            }
            this.currentSegment = null;
            // Mark as seen
            if (seekEntry.id === ebml/* EBMLId */.Cl.Tags) {
                segment.tagsSeen = true;
            }
            else if (seekEntry.id === ebml/* EBMLId */.Cl.Attachments) {
                segment.attachmentsSeen = true;
            }
        }
    }
    readContiguousElements(slice, stopIds) {
        while (slice.remainingLength >= ebml/* MIN_HEADER_SIZE */.De) {
            const startPos = slice.filePos;
            const foundElement = this.traverseElement(slice, stopIds);
            if (!foundElement) {
                return startPos;
            }
        }
        return slice.filePos;
    }
    traverseElement(slice, stopIds) {
        const header = (0,ebml/* readElementHeader */.ur)(slice);
        if (!header) {
            return false;
        }
        if (stopIds && stopIds.includes(header.id)) {
            return false;
        }
        const { id, size } = header;
        const dataStartPos = slice.filePos;
        (0,ebml/* assertDefinedSize */.p)(size);
        switch (id) {
            case ebml/* EBMLId */.Cl.DocType:
                {
                    this.isWebM = (0,ebml/* readAsciiString */.IX)(slice, size) === 'webm';
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.Seek:
                {
                    if (!this.currentSegment)
                        break;
                    const seekEntry = { id: -1, segmentPosition: -1 };
                    this.currentSegment.seekEntries.push(seekEntry);
                    this.readContiguousElements(slice.slice(dataStartPos, size));
                    if (seekEntry.id === -1 || seekEntry.segmentPosition === -1) {
                        this.currentSegment.seekEntries.pop();
                    }
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.SeekID:
                {
                    const lastSeekEntry = this.currentSegment?.seekEntries[this.currentSegment.seekEntries.length - 1];
                    if (!lastSeekEntry)
                        break;
                    lastSeekEntry.id = (0,ebml/* readUnsignedInt */.dl)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.SeekPosition:
                {
                    const lastSeekEntry = this.currentSegment?.seekEntries[this.currentSegment.seekEntries.length - 1];
                    if (!lastSeekEntry)
                        break;
                    lastSeekEntry.segmentPosition = (0,ebml/* readUnsignedInt */.dl)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.TimestampScale:
                {
                    if (!this.currentSegment)
                        break;
                    this.currentSegment.timestampScale = (0,ebml/* readUnsignedInt */.dl)(slice, size);
                    this.currentSegment.timestampFactor = 1e9 / this.currentSegment.timestampScale;
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.Duration:
                {
                    if (!this.currentSegment)
                        break;
                    this.currentSegment.duration = (0,ebml/* readFloat */.zH)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.TrackEntry:
                {
                    if (!this.currentSegment)
                        break;
                    this.currentTrack = {
                        id: -1,
                        segment: this.currentSegment,
                        demuxer: this,
                        clusterPositionCache: [],
                        cuePoints: [],
                        disposition: {
                            ...metadata/* DEFAULT_TRACK_DISPOSITION */.gM,
                            primary: false,
                        },
                        trackBacking: null,
                        codecId: null,
                        codecPrivate: null,
                        defaultDuration: null,
                        defaultDurationNs: null,
                        name: null,
                        languageCode: 'eng', // The default in Matroska
                        hasLanguageBcp47: false,
                        decodingInstructions: [],
                        info: null,
                    };
                    this.readContiguousElements(slice.slice(dataStartPos, size));
                    // Check if track was disabled during parsing (e.g., by FlagEnabled being 0)
                    if (!this.currentTrack) {
                        break;
                    }
                    if (this.currentTrack.decodingInstructions.some((instruction) => {
                        return instruction.data?.type !== 'decompress'
                            || instruction.scope !== ContentEncodingScope.Block
                            || instruction.data.algorithm !== ContentCompAlgo.HeaderStripping;
                    })) {
                        console.warn(`Track #${this.currentTrack.id} has an unsupported content encoding; dropping.`);
                        this.currentTrack = null;
                    }
                    if (this.currentTrack
                        && this.currentTrack.id !== -1
                        && this.currentTrack.codecId
                        && this.currentTrack.info) {
                        const slashIndex = this.currentTrack.codecId.indexOf('/');
                        const codecIdWithoutSuffix = slashIndex === -1
                            ? this.currentTrack.codecId
                            : this.currentTrack.codecId.slice(0, slashIndex);
                        if (this.currentTrack.info.type === 'video'
                            && this.currentTrack.info.width !== -1
                            && this.currentTrack.info.height !== -1) {
                            this.currentTrack.info.squarePixelWidth = this.currentTrack.info.width;
                            this.currentTrack.info.squarePixelHeight = this.currentTrack.info.height;
                            if (this.currentTrack.info.displayWidth !== null
                                && this.currentTrack.info.displayHeight !== null) {
                                const num = this.currentTrack.info.displayWidth * this.currentTrack.info.height;
                                const den = this.currentTrack.info.displayHeight * this.currentTrack.info.width;
                                if (num > den) {
                                    this.currentTrack.info.squarePixelWidth = Math.round(this.currentTrack.info.width * num / den);
                                }
                                else {
                                    this.currentTrack.info.squarePixelHeight = Math.round(this.currentTrack.info.height * den / num);
                                }
                            }
                            if (this.currentTrack.codecId === ebml/* CODEC_STRING_MAP */.oo.avc) {
                                this.currentTrack.info.codec = 'avc';
                                this.currentTrack.info.codecDescription = this.currentTrack.codecPrivate;
                            }
                            else if (this.currentTrack.codecId === ebml/* CODEC_STRING_MAP */.oo.hevc) {
                                this.currentTrack.info.codec = 'hevc';
                                this.currentTrack.info.codecDescription = this.currentTrack.codecPrivate;
                            }
                            else if (codecIdWithoutSuffix === ebml/* CODEC_STRING_MAP */.oo.vp8) {
                                this.currentTrack.info.codec = 'vp8';
                            }
                            else if (codecIdWithoutSuffix === ebml/* CODEC_STRING_MAP */.oo.vp9) {
                                this.currentTrack.info.codec = 'vp9';
                            }
                            else if (codecIdWithoutSuffix === ebml/* CODEC_STRING_MAP */.oo.av1) {
                                this.currentTrack.info.codec = 'av1';
                            }
                            const videoTrack = this.currentTrack;
                            this.currentTrack.trackBacking = new MatroskaVideoTrackBacking(videoTrack);
                            this.currentSegment.tracks.push(this.currentTrack);
                        }
                        else if (this.currentTrack.info.type === 'audio') {
                            if (codecIdWithoutSuffix === ebml/* CODEC_STRING_MAP */.oo.aac) {
                                this.currentTrack.info.codec = 'aac';
                                this.currentTrack.info.aacCodecInfo = {
                                    isMpeg2: this.currentTrack.codecId.includes('MPEG2'),
                                    objectType: null,
                                };
                                this.currentTrack.info.codecDescription = this.currentTrack.codecPrivate;
                            }
                            else if (this.currentTrack.codecId === ebml/* CODEC_STRING_MAP */.oo.mp3) {
                                this.currentTrack.info.codec = 'mp3';
                            }
                            else if (codecIdWithoutSuffix === ebml/* CODEC_STRING_MAP */.oo.opus) {
                                this.currentTrack.info.codec = 'opus';
                                this.currentTrack.info.codecDescription = this.currentTrack.codecPrivate;
                                this.currentTrack.info.sampleRate = codec/* OPUS_SAMPLE_RATE */.yo; // Always the same
                            }
                            else if (codecIdWithoutSuffix === ebml/* CODEC_STRING_MAP */.oo.vorbis) {
                                this.currentTrack.info.codec = 'vorbis';
                                this.currentTrack.info.codecDescription = this.currentTrack.codecPrivate;
                            }
                            else if (codecIdWithoutSuffix === ebml/* CODEC_STRING_MAP */.oo.flac) {
                                this.currentTrack.info.codec = 'flac';
                                this.currentTrack.info.codecDescription = this.currentTrack.codecPrivate;
                            }
                            else if (codecIdWithoutSuffix === ebml/* CODEC_STRING_MAP */.oo.ac3) {
                                this.currentTrack.info.codec = 'ac3';
                                this.currentTrack.info.codecDescription = this.currentTrack.codecPrivate;
                            }
                            else if (codecIdWithoutSuffix === ebml/* CODEC_STRING_MAP */.oo.eac3) {
                                this.currentTrack.info.codec = 'eac3';
                                this.currentTrack.info.codecDescription = this.currentTrack.codecPrivate;
                            }
                            else if (this.currentTrack.codecId === 'A_PCM/INT/LIT') {
                                if (this.currentTrack.info.bitDepth === 8) {
                                    this.currentTrack.info.codec = 'pcm-u8';
                                }
                                else if (this.currentTrack.info.bitDepth === 16) {
                                    this.currentTrack.info.codec = 'pcm-s16';
                                }
                                else if (this.currentTrack.info.bitDepth === 24) {
                                    this.currentTrack.info.codec = 'pcm-s24';
                                }
                                else if (this.currentTrack.info.bitDepth === 32) {
                                    this.currentTrack.info.codec = 'pcm-s32';
                                }
                            }
                            else if (this.currentTrack.codecId === 'A_PCM/INT/BIG') {
                                if (this.currentTrack.info.bitDepth === 8) {
                                    this.currentTrack.info.codec = 'pcm-u8';
                                }
                                else if (this.currentTrack.info.bitDepth === 16) {
                                    this.currentTrack.info.codec = 'pcm-s16be';
                                }
                                else if (this.currentTrack.info.bitDepth === 24) {
                                    this.currentTrack.info.codec = 'pcm-s24be';
                                }
                                else if (this.currentTrack.info.bitDepth === 32) {
                                    this.currentTrack.info.codec = 'pcm-s32be';
                                }
                            }
                            else if (this.currentTrack.codecId === 'A_PCM/FLOAT/IEEE') {
                                if (this.currentTrack.info.bitDepth === 32) {
                                    this.currentTrack.info.codec = 'pcm-f32';
                                }
                                else if (this.currentTrack.info.bitDepth === 64) {
                                    this.currentTrack.info.codec = 'pcm-f64';
                                }
                            }
                            const audioTrack = this.currentTrack;
                            this.currentTrack.trackBacking = new MatroskaAudioTrackBacking(audioTrack);
                            this.currentSegment.tracks.push(this.currentTrack);
                        }
                    }
                    this.currentTrack = null;
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.TrackNumber:
                {
                    if (!this.currentTrack)
                        break;
                    this.currentTrack.id = (0,ebml/* readUnsignedInt */.dl)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.TrackType:
                {
                    if (!this.currentTrack)
                        break;
                    const type = (0,ebml/* readUnsignedInt */.dl)(slice, size);
                    if (type === 1) {
                        this.currentTrack.info = {
                            type: 'video',
                            width: -1,
                            height: -1,
                            displayWidth: null,
                            displayHeight: null,
                            displayUnit: null,
                            squarePixelWidth: -1,
                            squarePixelHeight: -1,
                            rotation: 0,
                            codec: null,
                            codecDescription: null,
                            colorSpace: null,
                            alphaMode: false,
                        };
                    }
                    else if (type === 2) {
                        this.currentTrack.info = {
                            type: 'audio',
                            numberOfChannels: 1, // Default value
                            sampleRate: 8000, // Default value
                            bitDepth: -1,
                            codec: null,
                            codecDescription: null,
                            aacCodecInfo: null,
                        };
                    }
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.FlagEnabled:
                {
                    if (!this.currentTrack)
                        break;
                    const enabled = (0,ebml/* readUnsignedInt */.dl)(slice, size);
                    if (!enabled) {
                        this.currentTrack = null;
                    }
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.FlagDefault:
                {
                    if (!this.currentTrack)
                        break;
                    this.currentTrack.disposition.default = !!(0,ebml/* readUnsignedInt */.dl)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.FlagForced:
                {
                    if (!this.currentTrack)
                        break;
                    this.currentTrack.disposition.forced = !!(0,ebml/* readUnsignedInt */.dl)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.FlagOriginal:
                {
                    if (!this.currentTrack)
                        break;
                    this.currentTrack.disposition.original = !!(0,ebml/* readUnsignedInt */.dl)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.FlagHearingImpaired:
                {
                    if (!this.currentTrack)
                        break;
                    this.currentTrack.disposition.hearingImpaired = !!(0,ebml/* readUnsignedInt */.dl)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.FlagVisualImpaired:
                {
                    if (!this.currentTrack)
                        break;
                    this.currentTrack.disposition.visuallyImpaired = !!(0,ebml/* readUnsignedInt */.dl)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.FlagCommentary:
                {
                    if (!this.currentTrack)
                        break;
                    this.currentTrack.disposition.commentary = !!(0,ebml/* readUnsignedInt */.dl)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.CodecID:
                {
                    if (!this.currentTrack)
                        break;
                    this.currentTrack.codecId = (0,ebml/* readAsciiString */.IX)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.CodecPrivate:
                {
                    if (!this.currentTrack)
                        break;
                    this.currentTrack.codecPrivate = (0,src_reader/* readBytes */.io)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.DefaultDuration:
                {
                    if (!this.currentTrack)
                        break;
                    this.currentTrack.defaultDurationNs = (0,ebml/* readUnsignedInt */.dl)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.Name:
                {
                    if (!this.currentTrack)
                        break;
                    this.currentTrack.name = (0,ebml/* readUnicodeString */.jR)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.Language:
                {
                    if (!this.currentTrack)
                        break;
                    if (this.currentTrack.hasLanguageBcp47) {
                        // LanguageBCP47 was present, which takes precedence
                        break;
                    }
                    this.currentTrack.languageCode = (0,ebml/* readAsciiString */.IX)(slice, size);
                    if (!(0,misc/* isIso639Dash2LanguageCode */.Nu)(this.currentTrack.languageCode)) {
                        this.currentTrack.languageCode = misc/* UNDETERMINED_LANGUAGE */.IR;
                    }
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.LanguageBCP47:
                {
                    if (!this.currentTrack)
                        break;
                    const bcp47 = (0,ebml/* readAsciiString */.IX)(slice, size);
                    const languageSubtag = bcp47.split('-')[0];
                    if (languageSubtag) {
                        // Technically invalid, for now: The language subtag might be a language code from ISO 639-1,
                        // ISO 639-2, ISO 639-3, ISO 639-5 or some other thing (source: Wikipedia). But, `languageCode` is
                        // documented as ISO 639-2. Changing the definition would be a breaking change. This will get
                        // cleaned up in the future by defining languageCode to be BCP 47 instead.
                        this.currentTrack.languageCode = languageSubtag;
                    }
                    else {
                        this.currentTrack.languageCode = misc/* UNDETERMINED_LANGUAGE */.IR;
                    }
                    this.currentTrack.hasLanguageBcp47 = true;
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.Video:
                {
                    if (this.currentTrack?.info?.type !== 'video')
                        break;
                    this.readContiguousElements(slice.slice(dataStartPos, size));
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.PixelWidth:
                {
                    if (this.currentTrack?.info?.type !== 'video')
                        break;
                    this.currentTrack.info.width = (0,ebml/* readUnsignedInt */.dl)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.PixelHeight:
                {
                    if (this.currentTrack?.info?.type !== 'video')
                        break;
                    this.currentTrack.info.height = (0,ebml/* readUnsignedInt */.dl)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.DisplayWidth:
                {
                    if (this.currentTrack?.info?.type !== 'video')
                        break;
                    this.currentTrack.info.displayWidth = (0,ebml/* readUnsignedInt */.dl)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.DisplayHeight:
                {
                    if (this.currentTrack?.info?.type !== 'video')
                        break;
                    this.currentTrack.info.displayHeight = (0,ebml/* readUnsignedInt */.dl)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.DisplayUnit:
                {
                    if (this.currentTrack?.info?.type !== 'video')
                        break;
                    this.currentTrack.info.displayUnit = (0,ebml/* readUnsignedInt */.dl)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.AlphaMode:
                {
                    if (this.currentTrack?.info?.type !== 'video')
                        break;
                    this.currentTrack.info.alphaMode = (0,ebml/* readUnsignedInt */.dl)(slice, size) === 1;
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.Colour:
                {
                    if (this.currentTrack?.info?.type !== 'video')
                        break;
                    this.currentTrack.info.colorSpace = {};
                    this.readContiguousElements(slice.slice(dataStartPos, size));
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.MatrixCoefficients:
                {
                    if (this.currentTrack?.info?.type !== 'video' || !this.currentTrack.info.colorSpace)
                        break;
                    const matrixCoefficients = (0,ebml/* readUnsignedInt */.dl)(slice, size);
                    const mapped = misc/* MATRIX_COEFFICIENTS_MAP_INVERSE */.fl[matrixCoefficients] ?? null;
                    this.currentTrack.info.colorSpace.matrix = mapped;
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.Range:
                {
                    if (this.currentTrack?.info?.type !== 'video' || !this.currentTrack.info.colorSpace)
                        break;
                    this.currentTrack.info.colorSpace.fullRange = (0,ebml/* readUnsignedInt */.dl)(slice, size) === 2;
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.TransferCharacteristics:
                {
                    if (this.currentTrack?.info?.type !== 'video' || !this.currentTrack.info.colorSpace)
                        break;
                    const transferCharacteristics = (0,ebml/* readUnsignedInt */.dl)(slice, size);
                    const mapped = misc/* TRANSFER_CHARACTERISTICS_MAP_INVERSE */.x_[transferCharacteristics] ?? null;
                    this.currentTrack.info.colorSpace.transfer = mapped;
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.Primaries:
                {
                    if (this.currentTrack?.info?.type !== 'video' || !this.currentTrack.info.colorSpace)
                        break;
                    const primaries = (0,ebml/* readUnsignedInt */.dl)(slice, size);
                    const mapped = misc/* COLOR_PRIMARIES_MAP_INVERSE */.BL[primaries] ?? null;
                    this.currentTrack.info.colorSpace.primaries = mapped;
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.Projection:
                {
                    if (this.currentTrack?.info?.type !== 'video')
                        break;
                    this.readContiguousElements(slice.slice(dataStartPos, size));
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.ProjectionPoseRoll:
                {
                    if (this.currentTrack?.info?.type !== 'video')
                        break;
                    const rotation = (0,ebml/* readFloat */.zH)(slice, size);
                    const flippedRotation = -rotation; // Convert counter-clockwise to clockwise
                    try {
                        this.currentTrack.info.rotation = (0,misc/* normalizeRotation */.qT)(flippedRotation);
                    }
                    catch {
                        // It wasn't a valid rotation
                    }
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.Audio:
                {
                    if (this.currentTrack?.info?.type !== 'audio')
                        break;
                    this.readContiguousElements(slice.slice(dataStartPos, size));
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.SamplingFrequency:
                {
                    if (this.currentTrack?.info?.type !== 'audio')
                        break;
                    this.currentTrack.info.sampleRate = (0,ebml/* readFloat */.zH)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.Channels:
                {
                    if (this.currentTrack?.info?.type !== 'audio')
                        break;
                    this.currentTrack.info.numberOfChannels = (0,ebml/* readUnsignedInt */.dl)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.BitDepth:
                {
                    if (this.currentTrack?.info?.type !== 'audio')
                        break;
                    this.currentTrack.info.bitDepth = (0,ebml/* readUnsignedInt */.dl)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.CuePoint:
                {
                    if (!this.currentSegment)
                        break;
                    this.readContiguousElements(slice.slice(dataStartPos, size));
                    this.currentCueTime = null;
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.CueTime:
                {
                    this.currentCueTime = (0,ebml/* readUnsignedInt */.dl)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.CueTrackPositions:
                {
                    if (this.currentCueTime === null)
                        break;
                    (0,misc/* assert */.vA)(this.currentSegment);
                    const cuePoint = { time: this.currentCueTime, trackId: -1, clusterPosition: -1 };
                    this.currentSegment.cuePoints.push(cuePoint);
                    this.readContiguousElements(slice.slice(dataStartPos, size));
                    if (cuePoint.trackId === -1 || cuePoint.clusterPosition === -1) {
                        this.currentSegment.cuePoints.pop();
                    }
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.CueTrack:
                {
                    const lastCuePoint = this.currentSegment?.cuePoints[this.currentSegment.cuePoints.length - 1];
                    if (!lastCuePoint)
                        break;
                    lastCuePoint.trackId = (0,ebml/* readUnsignedInt */.dl)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.CueClusterPosition:
                {
                    const lastCuePoint = this.currentSegment?.cuePoints[this.currentSegment.cuePoints.length - 1];
                    if (!lastCuePoint)
                        break;
                    (0,misc/* assert */.vA)(this.currentSegment);
                    lastCuePoint.clusterPosition = this.currentSegment.dataStartPos + (0,ebml/* readUnsignedInt */.dl)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.Timestamp:
                {
                    if (!this.currentCluster)
                        break;
                    this.currentCluster.timestamp = (0,ebml/* readUnsignedInt */.dl)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.SimpleBlock:
                {
                    if (!this.currentCluster)
                        break;
                    const trackNumber = (0,ebml/* readVarInt */.pT)(slice);
                    if (trackNumber === null)
                        break;
                    const trackData = this.getTrackDataInCluster(this.currentCluster, trackNumber);
                    if (!trackData)
                        break; // Not a track we care about
                    const relativeTimestamp = (0,src_reader/* readI16Be */.iH)(slice);
                    const flags = (0,src_reader/* readU8 */.eo)(slice);
                    const lacing = (flags >> 1) & 0x3; // If the block is laced, we'll expand it later
                    let isKeyFrame = !!(flags & 0x80);
                    if (trackData.track.info?.type === 'audio' && trackData.track.info.codec) {
                        // Some files don't mark their audio packets as key packets (I'm looking at you, Firefox). But, we
                        // can fix this in most cases: if we recognize the codec of the track, then we know every packet is
                        // necessarily a key packet, no matter what the container says.
                        // https://github.com/Vanilagy/mediabunny/issues/192
                        isKeyFrame = true;
                    }
                    const blockData = (0,src_reader/* readBytes */.io)(slice, size - (slice.filePos - dataStartPos));
                    const hasDecodingInstructions = trackData.track.decodingInstructions.length > 0;
                    trackData.blocks.push({
                        timestamp: relativeTimestamp, // We'll add the cluster's timestamp to this later
                        duration: 0, // Will set later
                        isKeyFrame,
                        data: blockData,
                        lacing,
                        decoded: !hasDecodingInstructions,
                        mainAdditional: null,
                    });
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.BlockGroup:
                {
                    if (!this.currentCluster)
                        break;
                    this.readContiguousElements(slice.slice(dataStartPos, size));
                    this.currentBlock = null;
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.Block:
                {
                    if (!this.currentCluster)
                        break;
                    const trackNumber = (0,ebml/* readVarInt */.pT)(slice);
                    if (trackNumber === null)
                        break;
                    const trackData = this.getTrackDataInCluster(this.currentCluster, trackNumber);
                    if (!trackData)
                        break;
                    const relativeTimestamp = (0,src_reader/* readI16Be */.iH)(slice);
                    const flags = (0,src_reader/* readU8 */.eo)(slice);
                    const lacing = (flags >> 1) & 0x3; // If the block is laced, we'll expand it later
                    const blockData = (0,src_reader/* readBytes */.io)(slice, size - (slice.filePos - dataStartPos));
                    const hasDecodingInstructions = trackData.track.decodingInstructions.length > 0;
                    this.currentBlock = {
                        timestamp: relativeTimestamp, // We'll add the cluster's timestamp to this later
                        duration: 0, // Will set later
                        isKeyFrame: true,
                        data: blockData,
                        lacing,
                        decoded: !hasDecodingInstructions,
                        mainAdditional: null,
                    };
                    trackData.blocks.push(this.currentBlock);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.BlockAdditions:
                {
                    this.readContiguousElements(slice.slice(dataStartPos, size));
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.BlockMore:
                {
                    if (!this.currentBlock)
                        break;
                    this.currentBlockAdditional = {
                        addId: 1,
                        data: null,
                    };
                    this.readContiguousElements(slice.slice(dataStartPos, size));
                    if (this.currentBlockAdditional.data && this.currentBlockAdditional.addId === 1) {
                        this.currentBlock.mainAdditional = this.currentBlockAdditional.data;
                    }
                    this.currentBlockAdditional = null;
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.BlockAdditional:
                {
                    if (!this.currentBlockAdditional)
                        break;
                    this.currentBlockAdditional.data = (0,src_reader/* readBytes */.io)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.BlockAddID:
                {
                    if (!this.currentBlockAdditional)
                        break;
                    this.currentBlockAdditional.addId = (0,ebml/* readUnsignedInt */.dl)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.BlockDuration:
                {
                    if (!this.currentBlock)
                        break;
                    this.currentBlock.duration = (0,ebml/* readUnsignedInt */.dl)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.ReferenceBlock:
                {
                    if (!this.currentBlock)
                        break;
                    this.currentBlock.isKeyFrame = false;
                    // We ignore the actual value here, we just use the reference as an indicator for "not a key frame".
                    // This is in line with FFmpeg's behavior.
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.Tag:
                {
                    this.currentTagTargetIsMovie = true;
                    this.readContiguousElements(slice.slice(dataStartPos, size));
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.Targets:
                {
                    this.readContiguousElements(slice.slice(dataStartPos, size));
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.TargetTypeValue:
                {
                    const targetTypeValue = (0,ebml/* readUnsignedInt */.dl)(slice, size);
                    if (targetTypeValue !== 50) {
                        this.currentTagTargetIsMovie = false;
                    }
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.TagTrackUID:
            case ebml/* EBMLId */.Cl.TagEditionUID:
            case ebml/* EBMLId */.Cl.TagChapterUID:
            case ebml/* EBMLId */.Cl.TagAttachmentUID:
                {
                    this.currentTagTargetIsMovie = false;
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.SimpleTag:
                {
                    if (!this.currentTagTargetIsMovie)
                        break;
                    this.currentSimpleTagName = null;
                    this.readContiguousElements(slice.slice(dataStartPos, size));
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.TagName:
                {
                    this.currentSimpleTagName = (0,ebml/* readUnicodeString */.jR)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.TagString:
                {
                    if (!this.currentSimpleTagName)
                        break;
                    const value = (0,ebml/* readUnicodeString */.jR)(slice, size);
                    this.processTagValue(this.currentSimpleTagName, value);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.TagBinary:
                {
                    if (!this.currentSimpleTagName)
                        break;
                    const value = (0,src_reader/* readBytes */.io)(slice, size);
                    this.processTagValue(this.currentSimpleTagName, value);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.AttachedFile:
                {
                    if (!this.currentSegment)
                        break;
                    this.currentAttachedFile = {
                        fileUid: null,
                        fileName: null,
                        fileMediaType: null,
                        fileData: null,
                        fileDescription: null,
                    };
                    this.readContiguousElements(slice.slice(dataStartPos, size));
                    const tags = this.currentSegment.metadataTags;
                    if (this.currentAttachedFile.fileUid && this.currentAttachedFile.fileData) {
                        // All attached files get surfaced in the `raw` metadata tags
                        tags.raw ??= {};
                        tags.raw[this.currentAttachedFile.fileUid.toString()] = new metadata/* AttachedFile */.VF(this.currentAttachedFile.fileData, this.currentAttachedFile.fileMediaType ?? undefined, this.currentAttachedFile.fileName ?? undefined, this.currentAttachedFile.fileDescription ?? undefined);
                    }
                    // Only process image attachments
                    if (this.currentAttachedFile.fileMediaType?.startsWith('image/') && this.currentAttachedFile.fileData) {
                        const fileName = this.currentAttachedFile.fileName;
                        let kind = 'unknown';
                        if (fileName) {
                            const lowerName = fileName.toLowerCase();
                            if (lowerName.startsWith('cover.')) {
                                kind = 'coverFront';
                            }
                            else if (lowerName.startsWith('back.')) {
                                kind = 'coverBack';
                            }
                        }
                        tags.images ??= [];
                        tags.images.push({
                            data: this.currentAttachedFile.fileData,
                            mimeType: this.currentAttachedFile.fileMediaType,
                            kind,
                            name: this.currentAttachedFile.fileName ?? undefined,
                            description: this.currentAttachedFile.fileDescription ?? undefined,
                        });
                    }
                    this.currentAttachedFile = null;
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.FileUID:
                {
                    if (!this.currentAttachedFile)
                        break;
                    this.currentAttachedFile.fileUid = (0,ebml/* readUnsignedBigInt */.Ry)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.FileName:
                {
                    if (!this.currentAttachedFile)
                        break;
                    this.currentAttachedFile.fileName = (0,ebml/* readUnicodeString */.jR)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.FileMediaType:
                {
                    if (!this.currentAttachedFile)
                        break;
                    this.currentAttachedFile.fileMediaType = (0,ebml/* readAsciiString */.IX)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.FileData:
                {
                    if (!this.currentAttachedFile)
                        break;
                    this.currentAttachedFile.fileData = (0,src_reader/* readBytes */.io)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.FileDescription:
                {
                    if (!this.currentAttachedFile)
                        break;
                    this.currentAttachedFile.fileDescription = (0,ebml/* readUnicodeString */.jR)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.ContentEncodings:
                {
                    if (!this.currentTrack)
                        break;
                    this.readContiguousElements(slice.slice(dataStartPos, size));
                    // "**MUST** start with the `ContentEncoding` with the highest `ContentEncodingOrder`"
                    this.currentTrack.decodingInstructions.sort((a, b) => b.order - a.order);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.ContentEncoding:
                {
                    this.currentDecodingInstruction = {
                        order: 0,
                        scope: ContentEncodingScope.Block,
                        data: null,
                    };
                    this.readContiguousElements(slice.slice(dataStartPos, size));
                    if (this.currentDecodingInstruction.data) {
                        this.currentTrack.decodingInstructions.push(this.currentDecodingInstruction);
                    }
                    this.currentDecodingInstruction = null;
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.ContentEncodingOrder:
                {
                    if (!this.currentDecodingInstruction)
                        break;
                    this.currentDecodingInstruction.order = (0,ebml/* readUnsignedInt */.dl)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.ContentEncodingScope:
                {
                    if (!this.currentDecodingInstruction)
                        break;
                    this.currentDecodingInstruction.scope = (0,ebml/* readUnsignedInt */.dl)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.ContentCompression:
                {
                    if (!this.currentDecodingInstruction)
                        break;
                    this.currentDecodingInstruction.data = {
                        type: 'decompress',
                        algorithm: ContentCompAlgo.Zlib,
                        settings: null,
                    };
                    this.readContiguousElements(slice.slice(dataStartPos, size));
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.ContentCompAlgo:
                {
                    if (this.currentDecodingInstruction?.data?.type !== 'decompress')
                        break;
                    this.currentDecodingInstruction.data.algorithm = (0,ebml/* readUnsignedInt */.dl)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.ContentCompSettings:
                {
                    if (this.currentDecodingInstruction?.data?.type !== 'decompress')
                        break;
                    this.currentDecodingInstruction.data.settings = (0,src_reader/* readBytes */.io)(slice, size);
                }
                ;
                break;
            case ebml/* EBMLId */.Cl.ContentEncryption:
                {
                    if (!this.currentDecodingInstruction)
                        break;
                    this.currentDecodingInstruction.data = {
                        type: 'decrypt',
                    };
                }
                ;
                break;
        }
        slice.filePos = dataStartPos + size;
        return true;
    }
    decodeBlockData(track, rawData) {
        (0,misc/* assert */.vA)(track.decodingInstructions.length > 0); // This method shouldn't be called otherwise
        let currentData = rawData;
        for (const instruction of track.decodingInstructions) {
            (0,misc/* assert */.vA)(instruction.data);
            switch (instruction.data.type) {
                case 'decompress':
                    {
                        switch (instruction.data.algorithm) {
                            case ContentCompAlgo.HeaderStripping:
                                {
                                    if (instruction.data.settings && instruction.data.settings.length > 0) {
                                        const prefix = instruction.data.settings;
                                        const newData = new Uint8Array(prefix.length + currentData.length);
                                        newData.set(prefix, 0);
                                        newData.set(currentData, prefix.length);
                                        currentData = newData;
                                    }
                                }
                                ;
                                break;
                            default:
                                {
                                    // Unhandled
                                }
                                ;
                        }
                    }
                    ;
                    break;
                default:
                    {
                        // Unhandled
                    }
                    ;
            }
        }
        return currentData;
    }
    processTagValue(name, value) {
        if (!this.currentSegment?.metadataTags)
            return;
        const metadataTags = this.currentSegment.metadataTags;
        metadataTags.raw ??= {};
        metadataTags.raw[name] ??= value;
        if (typeof value === 'string') {
            switch (name.toLowerCase()) {
                case 'title':
                    {
                        metadataTags.title ??= value;
                    }
                    ;
                    break;
                case 'description':
                    {
                        metadataTags.description ??= value;
                    }
                    ;
                    break;
                case 'artist':
                    {
                        metadataTags.artist ??= value;
                    }
                    ;
                    break;
                case 'album':
                    {
                        metadataTags.album ??= value;
                    }
                    ;
                    break;
                case 'album_artist':
                    {
                        metadataTags.albumArtist ??= value;
                    }
                    ;
                    break;
                case 'genre':
                    {
                        metadataTags.genre ??= value;
                    }
                    ;
                    break;
                case 'comment':
                    {
                        metadataTags.comment ??= value;
                    }
                    ;
                    break;
                case 'lyrics':
                    {
                        metadataTags.lyrics ??= value;
                    }
                    ;
                    break;
                case 'date':
                    {
                        const date = new Date(value);
                        if (!Number.isNaN(date.getTime())) {
                            metadataTags.date ??= date;
                        }
                    }
                    ;
                    break;
                case 'track_number':
                case 'part_number':
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
                case 'disc_number':
                case 'disc':
                    {
                        const discParts = value.split('/');
                        const discNum = Number.parseInt(discParts[0], 10);
                        const discsTotal = discParts[1] && Number.parseInt(discParts[1], 10);
                        if (Number.isInteger(discNum) && discNum > 0) {
                            metadataTags.discNumber ??= discNum;
                        }
                        if (discsTotal && Number.isInteger(discsTotal) && discsTotal > 0) {
                            metadataTags.discsTotal ??= discsTotal;
                        }
                    }
                    ;
                    break;
            }
        }
    }
}
class MatroskaTrackBacking {
    constructor(internalTrack) {
        this.internalTrack = internalTrack;
        this.packetToClusterLocation = new WeakMap();
    }
    getId() {
        return this.internalTrack.id;
    }
    getNumber() {
        const demuxer = this.internalTrack.demuxer;
        const trackType = this.internalTrack.trackBacking.getType();
        let number = 0;
        for (const segment of demuxer.segments) {
            for (const track of segment.tracks) {
                if (track.trackBacking.getType() === trackType) {
                    number++;
                }
                if (track === this.internalTrack) {
                    break;
                }
            }
        }
        return number;
    }
    getCodec() {
        throw new Error('Not implemented on base class.');
    }
    getInternalCodecId() {
        return this.internalTrack.codecId;
    }
    getName() {
        return this.internalTrack.name;
    }
    getLanguageCode() {
        return this.internalTrack.languageCode;
    }
    getTimeResolution() {
        return this.internalTrack.segment.timestampFactor;
    }
    isRelativeToUnixEpoch() {
        return false;
    }
    getDisposition() {
        return this.internalTrack.disposition;
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
        const segment = this.internalTrack.segment;
        if (segment.duration <= 0) {
            return null;
        }
        let endTimestamp = segment.duration / segment.timestampFactor;
        const firstPacket = await this.getFirstPacket({ metadataOnly: true });
        endTimestamp += firstPacket?.timestamp ?? 0;
        return endTimestamp;
    }
    async getLiveRefreshInterval() {
        return null;
    }
    async getFirstPacket(options) {
        return this.performClusterLookup(null, (cluster) => {
            const trackData = cluster.trackData.get(this.internalTrack.id);
            if (trackData) {
                return {
                    blockIndex: 0,
                    correctBlockFound: true,
                };
            }
            return {
                blockIndex: -1,
                correctBlockFound: false,
            };
        }, -Infinity, // Use -Infinity as a search timestamp to avoid using the cues
        Infinity, options);
    }
    intoTimescale(timestamp) {
        // Do a little rounding to catch cases where the result is very close to an integer. If it is, it's likely
        // that the number was originally an integer divided by the timescale. For stability, it's best
        // to return the integer in this case.
        return (0,misc/* roundIfAlmostInteger */.aI)(timestamp * this.internalTrack.segment.timestampFactor);
    }
    async getPacket(timestamp, options) {
        const timestampInTimescale = this.intoTimescale(timestamp);
        return this.performClusterLookup(null, (cluster) => {
            const trackData = cluster.trackData.get(this.internalTrack.id);
            if (!trackData) {
                return { blockIndex: -1, correctBlockFound: false };
            }
            const index = (0,misc/* binarySearchLessOrEqual */.eE)(trackData.presentationTimestamps, timestampInTimescale, x => x.timestamp);
            const blockIndex = index !== -1 ? trackData.presentationTimestamps[index].blockIndex : -1;
            const correctBlockFound = index !== -1 && timestampInTimescale < trackData.endTimestamp;
            return { blockIndex, correctBlockFound };
        }, timestampInTimescale, timestampInTimescale, options);
    }
    async getNextPacket(packet, options) {
        const locationInCluster = this.packetToClusterLocation.get(packet);
        if (locationInCluster === undefined) {
            throw new Error('Packet was not created from this track.');
        }
        return this.performClusterLookup(locationInCluster.cluster, (cluster) => {
            if (cluster === locationInCluster.cluster) {
                const trackData = cluster.trackData.get(this.internalTrack.id);
                if (locationInCluster.blockIndex + 1 < trackData.blocks.length) {
                    // We can simply take the next block in the cluster
                    return {
                        blockIndex: locationInCluster.blockIndex + 1,
                        correctBlockFound: true,
                    };
                }
            }
            else {
                const trackData = cluster.trackData.get(this.internalTrack.id);
                if (trackData) {
                    return {
                        blockIndex: 0,
                        correctBlockFound: true,
                    };
                }
            }
            return {
                blockIndex: -1,
                correctBlockFound: false,
            };
        }, -Infinity, // Use -Infinity as a search timestamp to avoid using the cues
        Infinity, options);
    }
    async getKeyPacket(timestamp, options) {
        const timestampInTimescale = this.intoTimescale(timestamp);
        return this.performClusterLookup(null, (cluster) => {
            const trackData = cluster.trackData.get(this.internalTrack.id);
            if (!trackData) {
                return { blockIndex: -1, correctBlockFound: false };
            }
            const index = (0,misc/* findLastIndex */.Kl)(trackData.presentationTimestamps, (x) => {
                const block = trackData.blocks[x.blockIndex];
                return block.isKeyFrame && x.timestamp <= timestampInTimescale;
            });
            const blockIndex = index !== -1 ? trackData.presentationTimestamps[index].blockIndex : -1;
            const correctBlockFound = index !== -1 && timestampInTimescale < trackData.endTimestamp;
            return { blockIndex, correctBlockFound };
        }, timestampInTimescale, timestampInTimescale, options);
    }
    async getNextKeyPacket(packet, options) {
        const locationInCluster = this.packetToClusterLocation.get(packet);
        if (locationInCluster === undefined) {
            throw new Error('Packet was not created from this track.');
        }
        return this.performClusterLookup(locationInCluster.cluster, (cluster) => {
            if (cluster === locationInCluster.cluster) {
                const trackData = cluster.trackData.get(this.internalTrack.id);
                const nextKeyFrameIndex = trackData.blocks.findIndex((x, i) => x.isKeyFrame && i > locationInCluster.blockIndex);
                if (nextKeyFrameIndex !== -1) {
                    // We can simply take the next key frame in the cluster
                    return {
                        blockIndex: nextKeyFrameIndex,
                        correctBlockFound: true,
                    };
                }
            }
            else {
                const trackData = cluster.trackData.get(this.internalTrack.id);
                if (trackData && trackData.firstKeyFrameTimestamp !== null) {
                    const keyFrameIndex = trackData.blocks.findIndex(x => x.isKeyFrame);
                    (0,misc/* assert */.vA)(keyFrameIndex !== -1); // There must be one
                    return {
                        blockIndex: keyFrameIndex,
                        correctBlockFound: true,
                    };
                }
            }
            return {
                blockIndex: -1,
                correctBlockFound: false,
            };
        }, -Infinity, // Use -Infinity as a search timestamp to avoid using the cues
        Infinity, options);
    }
    async fetchPacketInCluster(cluster, blockIndex, options) {
        if (blockIndex === -1) {
            return null;
        }
        const trackData = cluster.trackData.get(this.internalTrack.id);
        const block = trackData.blocks[blockIndex];
        (0,misc/* assert */.vA)(block);
        // Perform lazy decoding if needed
        if (!block.decoded) {
            block.data = this.internalTrack.demuxer.decodeBlockData(this.internalTrack, block.data);
            block.decoded = true;
        }
        const data = options.metadataOnly ? src_packet/* PLACEHOLDER_DATA */.T : block.data;
        const timestamp = block.timestamp / this.internalTrack.segment.timestampFactor;
        const duration = block.duration / this.internalTrack.segment.timestampFactor;
        const sideData = {};
        if (block.mainAdditional && this.internalTrack.info?.type === 'video' && this.internalTrack.info.alphaMode) {
            sideData.alpha = options.metadataOnly ? src_packet/* PLACEHOLDER_DATA */.T : block.mainAdditional;
            sideData.alphaByteLength = block.mainAdditional.byteLength;
        }
        const packet = new src_packet/* EncodedPacket */.Z(data, block.isKeyFrame ? 'key' : 'delta', timestamp, duration, cluster.dataStartPos + blockIndex, block.data.byteLength, sideData);
        this.packetToClusterLocation.set(packet, { cluster, blockIndex });
        return packet;
    }
    /** Looks for a packet in the clusters while trying to load as few clusters as possible to retrieve it. */
    async performClusterLookup(
    // The cluster where we start looking
    startCluster, 
    // This function returns the best-matching block in a given cluster
    getMatchInCluster, 
    // The timestamp with which we can search the lookup table
    searchTimestamp, 
    // The timestamp for which we know the correct block will not come after it
    latestTimestamp, options) {
        const { demuxer, segment } = this.internalTrack;
        let currentCluster = null;
        let bestCluster = null;
        let bestBlockIndex = -1;
        if (startCluster) {
            const { blockIndex, correctBlockFound } = getMatchInCluster(startCluster);
            if (correctBlockFound) {
                return this.fetchPacketInCluster(startCluster, blockIndex, options);
            }
            if (blockIndex !== -1) {
                bestCluster = startCluster;
                bestBlockIndex = blockIndex;
            }
        }
        // Search for a cue point; this way, we won't need to start searching from the start of the file
        // but can jump right into the correct cluster (or at least nearby).
        const cuePointIndex = (0,misc/* binarySearchLessOrEqual */.eE)(this.internalTrack.cuePoints, searchTimestamp, x => x.time);
        const cuePoint = cuePointIndex !== -1
            ? this.internalTrack.cuePoints[cuePointIndex]
            : null;
        // Also check the position cache
        const positionCacheIndex = (0,misc/* binarySearchLessOrEqual */.eE)(this.internalTrack.clusterPositionCache, searchTimestamp, x => x.startTimestamp);
        const positionCacheEntry = positionCacheIndex !== -1
            ? this.internalTrack.clusterPositionCache[positionCacheIndex]
            : null;
        const lookupEntryPosition = Math.max(cuePoint?.clusterPosition ?? 0, positionCacheEntry?.elementStartPos ?? 0) || null;
        let currentPos;
        if (!startCluster) {
            currentPos = lookupEntryPosition ?? segment.clusterSeekStartPos;
        }
        else {
            if (lookupEntryPosition === null || startCluster.elementStartPos >= lookupEntryPosition) {
                currentPos = startCluster.elementEndPos;
                currentCluster = startCluster;
            }
            else {
                // Use the lookup entry
                currentPos = lookupEntryPosition;
            }
        }
        while (segment.elementEndPos === null || currentPos <= segment.elementEndPos - ebml/* MIN_HEADER_SIZE */.De) {
            if (currentCluster) {
                const trackData = currentCluster.trackData.get(this.internalTrack.id);
                if (trackData && trackData.startTimestamp > latestTimestamp) {
                    // We're already past the upper bound, no need to keep searching
                    break;
                }
            }
            // Load the header
            let slice = demuxer.reader.requestSliceRange(currentPos, ebml/* MIN_HEADER_SIZE */.De, ebml/* MAX_HEADER_SIZE */.r1);
            if (slice instanceof Promise)
                slice = await slice;
            if (!slice)
                break;
            const elementStartPos = currentPos;
            const elementHeader = (0,ebml/* readElementHeader */.ur)(slice);
            if (!elementHeader
                || (!ebml/* LEVEL_1_EBML_IDS */.VE.includes(elementHeader.id) && elementHeader.id !== ebml/* EBMLId */.Cl.Void)) {
                // There's an element here that shouldn't be here. Might be garbage. In this case, let's
                // try and resync to the next valid element.
                const nextPos = await (0,ebml/* resync */.nE)(demuxer.reader, elementStartPos, ebml/* LEVEL_1_EBML_IDS */.VE, Math.min(segment.elementEndPos ?? Infinity, elementStartPos + MAX_RESYNC_LENGTH));
                if (nextPos) {
                    currentPos = nextPos;
                    continue;
                }
                else {
                    break; // Resync failed
                }
            }
            const id = elementHeader.id;
            let size = elementHeader.size;
            const dataStartPos = slice.filePos;
            if (id === ebml/* EBMLId */.Cl.Cluster) {
                currentCluster = await demuxer.readCluster(elementStartPos, segment);
                // readCluster computes the proper size even if it's undefined in the header, so let's use that instead
                size = currentCluster.elementEndPos - dataStartPos;
                const { blockIndex, correctBlockFound } = getMatchInCluster(currentCluster);
                if (correctBlockFound) {
                    return this.fetchPacketInCluster(currentCluster, blockIndex, options);
                }
                if (blockIndex !== -1) {
                    bestCluster = currentCluster;
                    bestBlockIndex = blockIndex;
                }
            }
            if (size === undefined) {
                // Undefined element size (can happen in livestreamed files). In this case, we need to do some
                // searching to determine the actual size of the element.
                (0,misc/* assert */.vA)(id !== ebml/* EBMLId */.Cl.Cluster); // Undefined cluster sizes are fixed further up
                // Search for the next element at level 0 or 1
                const nextElementPos = await (0,ebml/* searchForNextElementId */.IQ)(demuxer.reader, dataStartPos, ebml/* LEVEL_0_AND_1_EBML_IDS */.K9, segment.elementEndPos);
                size = nextElementPos.pos - dataStartPos;
            }
            const endPos = dataStartPos + size;
            if (segment.elementEndPos === null) {
                // Check the next element. If it's a new segment, we know this segment ends here. The new
                // segment is just ignored, since we're likely in a livestreamed file and thus only care about
                // the first segment.
                let slice = demuxer.reader.requestSliceRange(endPos, ebml/* MIN_HEADER_SIZE */.De, ebml/* MAX_HEADER_SIZE */.r1);
                if (slice instanceof Promise)
                    slice = await slice;
                if (!slice)
                    break;
                const elementId = (0,ebml/* readElementId */.SR)(slice);
                if (elementId === ebml/* EBMLId */.Cl.Segment) {
                    segment.elementEndPos = endPos; // We now know the segment's size
                    break;
                }
            }
            currentPos = endPos;
        }
        // Catch faulty cue points
        if (cuePoint && (!bestCluster || bestCluster.elementStartPos < cuePoint.clusterPosition)) {
            // The cue point lied to us! We found a cue point but no cluster there that satisfied the match. In this
            // case, let's search again but using the cue point before that.
            const previousCuePoint = this.internalTrack.cuePoints[cuePointIndex - 1];
            (0,misc/* assert */.vA)(!previousCuePoint || previousCuePoint.time < cuePoint.time);
            const newSearchTimestamp = previousCuePoint?.time ?? -Infinity;
            return this.performClusterLookup(null, getMatchInCluster, newSearchTimestamp, latestTimestamp, options);
        }
        if (bestCluster) {
            // If we finished looping but didn't find a perfect match, still return the best match we found
            return this.fetchPacketInCluster(bestCluster, bestBlockIndex, options);
        }
        return null;
    }
}
class MatroskaVideoTrackBacking extends MatroskaTrackBacking {
    constructor(internalTrack) {
        super(internalTrack);
        this.decoderConfigPromise = null;
        this.internalTrack = internalTrack;
    }
    getType() {
        return 'video';
    }
    getCodec() {
        return this.internalTrack.info.codec;
    }
    getCodedWidth() {
        return this.internalTrack.info.width;
    }
    getCodedHeight() {
        return this.internalTrack.info.height;
    }
    getSquarePixelWidth() {
        return this.internalTrack.info.squarePixelWidth;
    }
    getSquarePixelHeight() {
        return this.internalTrack.info.squarePixelHeight;
    }
    getRotation() {
        return this.internalTrack.info.rotation;
    }
    async getColorSpace() {
        return {
            primaries: this.internalTrack.info.colorSpace?.primaries,
            transfer: this.internalTrack.info.colorSpace?.transfer,
            matrix: this.internalTrack.info.colorSpace?.matrix,
            fullRange: this.internalTrack.info.colorSpace?.fullRange,
        };
    }
    async canBeTransparent() {
        return this.internalTrack.info.alphaMode;
    }
    async getDecoderConfig() {
        if (!this.internalTrack.info.codec) {
            return null;
        }
        return this.decoderConfigPromise ??= (async () => {
            let firstPacket = null;
            const needsPacketForAdditionalInfo = this.internalTrack.info.codec === 'vp9'
                || this.internalTrack.info.codec === 'av1'
                // Packets are in Annex B format:
                || (this.internalTrack.info.codec === 'avc' && !this.internalTrack.info.codecDescription)
                // Packets are in Annex B format:
                || (this.internalTrack.info.codec === 'hevc' && !this.internalTrack.info.codecDescription);
            if (needsPacketForAdditionalInfo) {
                firstPacket = await this.getFirstPacket({});
            }
            const config = {
                codec: (0,codec/* extractVideoCodecString */.QP)({
                    width: this.internalTrack.info.width,
                    height: this.internalTrack.info.height,
                    codec: this.internalTrack.info.codec,
                    codecDescription: this.internalTrack.info.codecDescription,
                    colorSpace: this.internalTrack.info.colorSpace,
                    avcType: 1, // We don't know better (or do we?) so just assume 'avc1'
                    avcCodecInfo: this.internalTrack.info.codec === 'avc' && firstPacket
                        ? (0,codec_data/* extractAvcDecoderConfigurationRecord */.fH)(firstPacket.data)
                        : null,
                    hevcCodecInfo: this.internalTrack.info.codec === 'hevc' && firstPacket
                        ? (0,codec_data/* extractHevcDecoderConfigurationRecord */.D5)(firstPacket.data)
                        : null,
                    vp9CodecInfo: this.internalTrack.info.codec === 'vp9' && firstPacket
                        ? (0,codec_data/* extractVp9CodecInfoFromPacket */.bs)(firstPacket.data)
                        : null,
                    av1CodecInfo: this.internalTrack.info.codec === 'av1' && firstPacket
                        ? (0,codec_data/* extractAv1CodecInfoFromPacket */.UU)(firstPacket.data)
                        : null,
                }),
                codedWidth: this.internalTrack.info.width,
                codedHeight: this.internalTrack.info.height,
                description: this.internalTrack.info.codecDescription ?? undefined,
                colorSpace: this.internalTrack.info.colorSpace ?? undefined,
            };
            if (this.internalTrack.info.width !== this.internalTrack.info.squarePixelWidth
                || this.internalTrack.info.height !== this.internalTrack.info.squarePixelHeight) {
                config.displayAspectWidth = this.internalTrack.info.squarePixelWidth;
                config.displayAspectHeight = this.internalTrack.info.squarePixelHeight;
            }
            return config;
        })();
    }
}
class MatroskaAudioTrackBacking extends MatroskaTrackBacking {
    constructor(internalTrack) {
        super(internalTrack);
        this.decoderConfig = null;
        this.internalTrack = internalTrack;
    }
    getType() {
        return 'audio';
    }
    getCodec() {
        return this.internalTrack.info.codec;
    }
    getNumberOfChannels() {
        return this.internalTrack.info.numberOfChannels;
    }
    getSampleRate() {
        return this.internalTrack.info.sampleRate;
    }
    async getDecoderConfig() {
        if (!this.internalTrack.info.codec) {
            return null;
        }
        return this.decoderConfig ??= {
            codec: (0,codec/* extractAudioCodecString */.X0)({
                codec: this.internalTrack.info.codec,
                codecDescription: this.internalTrack.info.codecDescription,
                aacCodecInfo: this.internalTrack.info.aacCodecInfo,
            }),
            numberOfChannels: this.internalTrack.info.numberOfChannels,
            sampleRate: this.internalTrack.info.sampleRate,
            description: this.internalTrack.info.codecDescription ?? undefined,
        };
    }
}

// EXTERNAL MODULE: ./node_modules/mediabunny/dist/modules/shared/mp3-misc.js
var mp3_misc = __webpack_require__(2788);
// EXTERNAL MODULE: ./node_modules/mediabunny/dist/modules/src/id3.js
var id3 = __webpack_require__(7576);
;// ./node_modules/mediabunny/dist/modules/src/mp3/mp3-reader.js
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


const readNextMp3FrameHeader = async (reader, startPos, until) => {
    const CHUNK_SIZE = 2 ** 16; // So we don't need to grab thousands of slices
    let currentPos = startPos;
    while (until === null || currentPos < until) {
        const maxLength = until !== null
            ? Math.min(CHUNK_SIZE, until - currentPos)
            : CHUNK_SIZE;
        let slice = reader.requestSliceRange(currentPos, mp3_misc/* FRAME_HEADER_SIZE */.Yq, maxLength);
        if (slice instanceof Promise)
            slice = await slice;
        if (!slice || slice.length < mp3_misc/* FRAME_HEADER_SIZE */.Yq)
            break;
        while (slice.remainingLength >= mp3_misc/* FRAME_HEADER_SIZE */.Yq) {
            const posBeforeRead = slice.filePos;
            const word = (0,src_reader/* readU32Be */.cN)(slice);
            const remainingBytes = reader.fileSize !== null
                ? reader.fileSize - currentPos
                : null;
            const result = (0,mp3_misc/* readMp3FrameHeader */.P8)(word, remainingBytes);
            if (result.header) {
                return { header: result.header, startPos: currentPos };
            }
            slice.filePos = posBeforeRead + result.bytesAdvanced;
            currentPos = slice.filePos;
        }
    }
    return null;
};

;// ./node_modules/mediabunny/dist/modules/src/mp3/mp3-demuxer.js
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */








class Mp3Demuxer extends demuxer/* Demuxer */.B {
    constructor(input) {
        super(input);
        this.metadataPromise = null;
        this.firstFrameHeader = null;
        this.firstFrameHeaderPos = null;
        this.loadedSamples = []; // All samples from the start of the file to lastLoadedPos
        this.metadataTags = null;
        this.xingData = null;
        this.trackBackings = [];
        this.readingMutex = new misc/* AsyncMutex */.aD();
        this.lastSampleLoaded = false;
        this.lastLoadedPos = 0;
        this.nextTimestampInSamples = 0;
        this.reader = input._reader;
    }
    async readMetadata() {
        return this.metadataPromise ??= (async () => {
            // Keep loading until we find the first frame header
            while (!this.firstFrameHeader && !this.lastSampleLoaded) {
                await this.advanceReader();
            }
            if (!this.firstFrameHeader) {
                throw new Error('No valid MP3 frame found.');
            }
            this.trackBackings = [new Mp3AudioTrackBacking(this)];
        })();
    }
    async advanceReader() {
        if (this.lastLoadedPos === 0) {
            // Let's skip all ID3v2 tags at the start of the file
            while (true) {
                let slice = this.reader.requestSlice(this.lastLoadedPos, id3/* ID3_V2_HEADER_SIZE */.sY);
                if (slice instanceof Promise)
                    slice = await slice;
                if (!slice) {
                    this.lastSampleLoaded = true;
                    return;
                }
                const id3V2Header = (0,id3/* readId3V2Header */.IX)(slice);
                if (!id3V2Header) {
                    break;
                }
                this.lastLoadedPos = slice.filePos + id3V2Header.size;
            }
        }
        const result = await readNextMp3FrameHeader(this.reader, this.lastLoadedPos, this.reader.fileSize);
        if (!result) {
            this.lastSampleLoaded = true;
            return;
        }
        const header = result.header;
        this.lastLoadedPos = result.startPos + header.totalSize - 1; // -1 in case the frame is 1 byte too short
        const xingOffset = (0,mp3_misc/* getXingOffset */.EZ)(header.mpegVersionId, header.channel);
        let slice = this.reader.requestSlice(result.startPos + xingOffset, 4);
        if (slice instanceof Promise)
            slice = await slice;
        if (slice) {
            const word = (0,src_reader/* readU32Be */.cN)(slice);
            const isXing = word === mp3_misc/* XING */.hY || word === mp3_misc/* INFO */.rD;
            if (isXing) {
                // There's no actual audio data in this frame, so let's skip it
                if (!this.xingData) {
                    let xingDataSlice = this.reader.requestSlice(result.startPos + xingOffset + 4, 12);
                    if (xingDataSlice instanceof Promise)
                        xingDataSlice = await xingDataSlice;
                    if (xingDataSlice) {
                        const xingData = (0,src_reader/* readBytes */.io)(xingDataSlice, 12);
                        const view = (0,misc/* toDataView */.Zc)(xingData);
                        const flags = view.getUint32(0, false);
                        this.xingData = {
                            frameCount: (flags & mp3_misc/* XingFlags */.MJ.FrameCount)
                                ? view.getUint32(4, false)
                                : null,
                            fileSize: (flags & mp3_misc/* XingFlags */.MJ.FileSize)
                                ? view.getUint32(8, false)
                                : null,
                        };
                    }
                }
                return;
            }
        }
        if (!this.firstFrameHeader) {
            this.firstFrameHeader = header;
            this.firstFrameHeaderPos = result.startPos;
        }
        if (header.sampleRate !== this.firstFrameHeader.sampleRate) {
            console.warn(`MP3 changed sample rate mid-file: ${this.firstFrameHeader.sampleRate} Hz to ${header.sampleRate} Hz.`
                + ` Might be a bug, so please report this file.`);
        }
        const sampleDuration = header.audioSamplesInFrame / this.firstFrameHeader.sampleRate;
        const sample = {
            timestamp: this.nextTimestampInSamples / this.firstFrameHeader.sampleRate,
            duration: sampleDuration,
            dataStart: result.startPos,
            dataSize: header.totalSize,
        };
        this.loadedSamples.push(sample);
        this.nextTimestampInSamples += header.audioSamplesInFrame;
        return;
    }
    async getMimeType() {
        return 'audio/mpeg';
    }
    async getTrackBackings() {
        await this.readMetadata();
        return this.trackBackings;
    }
    async getMetadataTags() {
        const release = await this.readingMutex.acquire();
        try {
            await this.readMetadata();
            if (this.metadataTags) {
                return this.metadataTags;
            }
            this.metadataTags = {};
            let currentPos = 0;
            let id3V2HeaderFound = false;
            while (true) {
                let headerSlice = this.reader.requestSlice(currentPos, id3/* ID3_V2_HEADER_SIZE */.sY);
                if (headerSlice instanceof Promise)
                    headerSlice = await headerSlice;
                if (!headerSlice)
                    break;
                const id3V2Header = (0,id3/* readId3V2Header */.IX)(headerSlice);
                if (!id3V2Header) {
                    break;
                }
                id3V2HeaderFound = true;
                let contentSlice = this.reader.requestSlice(headerSlice.filePos, id3V2Header.size);
                if (contentSlice instanceof Promise)
                    contentSlice = await contentSlice;
                if (!contentSlice)
                    break;
                (0,id3/* parseId3V2Tag */.cG)(contentSlice, id3V2Header, this.metadataTags);
                currentPos = headerSlice.filePos + id3V2Header.size;
            }
            if (!id3V2HeaderFound && this.reader.fileSize !== null && this.reader.fileSize >= id3/* ID3_V1_TAG_SIZE */.aU) {
                // Try reading an ID3v1 tag at the end of the file
                let slice = this.reader.requestSlice(this.reader.fileSize - id3/* ID3_V1_TAG_SIZE */.aU, id3/* ID3_V1_TAG_SIZE */.aU);
                if (slice instanceof Promise)
                    slice = await slice;
                (0,misc/* assert */.vA)(slice);
                const tag = (0,src_reader/* readAscii */.IT)(slice, 3);
                if (tag === 'TAG') {
                    (0,id3/* parseId3V1Tag */.p_)(slice, this.metadataTags);
                }
            }
            return this.metadataTags;
        }
        finally {
            release();
        }
    }
}
class Mp3AudioTrackBacking {
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
    getTimeResolution() {
        (0,misc/* assert */.vA)(this.demuxer.firstFrameHeader);
        return this.demuxer.firstFrameHeader.sampleRate / this.demuxer.firstFrameHeader.audioSamplesInFrame;
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
        const demuxer = this.demuxer;
        (0,misc/* assert */.vA)(demuxer.firstFrameHeader !== null);
        (0,misc/* assert */.vA)(demuxer.firstFrameHeaderPos !== null);
        if (demuxer.xingData) {
            if (demuxer.xingData.frameCount !== null) {
                return demuxer.xingData.frameCount
                    * demuxer.firstFrameHeader.audioSamplesInFrame
                    / demuxer.firstFrameHeader.sampleRate;
            }
        }
        else {
            // No Xing, assuming CBR
            if (demuxer.reader.fileSize !== null) {
                const averageFrameSize = (0,mp3_misc/* computeAverageMp3FrameSize */.hD)(demuxer.firstFrameHeader.lowSamplingFrequency, demuxer.firstFrameHeader.layer, demuxer.firstFrameHeader.bitrate, demuxer.firstFrameHeader.sampleRate);
                const frameCount = (demuxer.reader.fileSize - demuxer.firstFrameHeaderPos) / averageFrameSize;
                return Math.round(frameCount)
                    * demuxer.firstFrameHeader.audioSamplesInFrame
                    / demuxer.firstFrameHeader.sampleRate;
            }
        }
        return null;
    }
    async getLiveRefreshInterval() {
        return null;
    }
    getName() {
        return null;
    }
    getLanguageCode() {
        return misc/* UNDETERMINED_LANGUAGE */.IR;
    }
    getCodec() {
        return 'mp3';
    }
    getInternalCodecId() {
        return null;
    }
    getNumberOfChannels() {
        (0,misc/* assert */.vA)(this.demuxer.firstFrameHeader);
        return this.demuxer.firstFrameHeader.channel === 3 ? 1 : 2;
    }
    getSampleRate() {
        (0,misc/* assert */.vA)(this.demuxer.firstFrameHeader);
        return this.demuxer.firstFrameHeader.sampleRate;
    }
    getDisposition() {
        return {
            ...metadata/* DEFAULT_TRACK_DISPOSITION */.gM,
        };
    }
    async getDecoderConfig() {
        (0,misc/* assert */.vA)(this.demuxer.firstFrameHeader);
        return {
            codec: 'mp3',
            numberOfChannels: this.demuxer.firstFrameHeader.channel === 3 ? 1 : 2,
            sampleRate: this.demuxer.firstFrameHeader.sampleRate,
        };
    }
    async getPacketAtIndex(sampleIndex, options) {
        if (sampleIndex === -1) {
            return null;
        }
        const rawSample = this.demuxer.loadedSamples[sampleIndex];
        if (!rawSample) {
            return null;
        }
        let data;
        if (options.metadataOnly) {
            data = src_packet/* PLACEHOLDER_DATA */.T;
        }
        else {
            let slice = this.demuxer.reader.requestSlice(rawSample.dataStart, rawSample.dataSize);
            if (slice instanceof Promise)
                slice = await slice;
            if (!slice) {
                return null; // Data didn't fit into the rest of the file
            }
            data = (0,src_reader/* readBytes */.io)(slice, rawSample.dataSize);
        }
        return new src_packet/* EncodedPacket */.Z(data, 'key', rawSample.timestamp, rawSample.duration, sampleIndex, rawSample.dataSize);
    }
    getFirstPacket(options) {
        return this.getPacketAtIndex(0, options);
    }
    async getNextPacket(packet, options) {
        const release = await this.demuxer.readingMutex.acquire();
        try {
            const sampleIndex = (0,misc/* binarySearchExact */.pl)(this.demuxer.loadedSamples, packet.timestamp, x => x.timestamp);
            if (sampleIndex === -1) {
                throw new Error('Packet was not created from this track.');
            }
            const nextIndex = sampleIndex + 1;
            // Ensure the next sample exists
            while (nextIndex >= this.demuxer.loadedSamples.length
                && !this.demuxer.lastSampleLoaded) {
                await this.demuxer.advanceReader();
            }
            return this.getPacketAtIndex(nextIndex, options);
        }
        finally {
            release();
        }
    }
    async getPacket(timestamp, options) {
        const release = await this.demuxer.readingMutex.acquire();
        try {
            while (true) {
                const index = (0,misc/* binarySearchLessOrEqual */.eE)(this.demuxer.loadedSamples, timestamp, x => x.timestamp);
                if (index === -1 && this.demuxer.loadedSamples.length > 0) {
                    // We're before the first sample
                    return null;
                }
                if (this.demuxer.lastSampleLoaded) {
                    // All data is loaded, return what we found
                    return this.getPacketAtIndex(index, options);
                }
                if (index >= 0 && index + 1 < this.demuxer.loadedSamples.length) {
                    // The next packet also exists, we're done
                    return this.getPacketAtIndex(index, options);
                }
                // Otherwise, keep loading data
                await this.demuxer.advanceReader();
            }
        }
        finally {
            release();
        }
    }
    getKeyPacket(timestamp, options) {
        return this.getPacket(timestamp, options);
    }
    getNextKeyPacket(packet, options) {
        return this.getNextPacket(packet, options);
    }
}

// EXTERNAL MODULE: ./node_modules/mediabunny/dist/modules/src/ogg/ogg-misc.js
var ogg_misc = __webpack_require__(9730);
// EXTERNAL MODULE: ./node_modules/mediabunny/dist/modules/src/ogg/ogg-reader.js
var ogg_reader = __webpack_require__(9841);
;// ./node_modules/mediabunny/dist/modules/src/ogg/ogg-demuxer.js
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */









class OggDemuxer extends demuxer/* Demuxer */.B {
    constructor(input) {
        super(input);
        this.metadataPromise = null;
        this.bitstreams = [];
        this.trackBackings = [];
        this.metadataTags = {};
        this.reader = input._reader;
    }
    async readMetadata() {
        return this.metadataPromise ??= (async () => {
            let currentPos = 0;
            while (true) {
                let slice = this.reader.requestSliceRange(currentPos, ogg_reader/* MIN_PAGE_HEADER_SIZE */.b0, ogg_reader/* MAX_PAGE_HEADER_SIZE */.H9);
                if (slice instanceof Promise)
                    slice = await slice;
                if (!slice)
                    break;
                const page = (0,ogg_reader/* readPageHeader */.BF)(slice);
                if (!page) {
                    break;
                }
                const isBos = !!(page.headerType & 0x02);
                if (!isBos) {
                    // All bos pages for all bitstreams are required to be at the start, so if the page is not bos then
                    // we know we've seen all bitstreams (minus chaining)
                    break;
                }
                this.bitstreams.push({
                    serialNumber: page.serialNumber,
                    bosPage: page,
                    description: null,
                    numberOfChannels: -1,
                    sampleRate: -1,
                    codecInfo: {
                        codec: null,
                        vorbisInfo: null,
                        opusInfo: null,
                    },
                    lastMetadataPacket: null,
                });
                currentPos = page.headerStartPos + page.totalSize;
            }
            for (const bitstream of this.bitstreams) {
                const firstPacket = await this.readPacket(bitstream.bosPage, 0);
                if (!firstPacket) {
                    continue;
                }
                if (
                // Check for Vorbis
                firstPacket.data.byteLength >= 7
                    && firstPacket.data[0] === 0x01 // Packet type 1 = identification header
                    && firstPacket.data[1] === 0x76 // 'v'
                    && firstPacket.data[2] === 0x6f // 'o'
                    && firstPacket.data[3] === 0x72 // 'r'
                    && firstPacket.data[4] === 0x62 // 'b'
                    && firstPacket.data[5] === 0x69 // 'i'
                    && firstPacket.data[6] === 0x73 // 's'
                ) {
                    await this.readVorbisMetadata(firstPacket, bitstream);
                }
                else if (
                // Check for Opus
                firstPacket.data.byteLength >= 8
                    && firstPacket.data[0] === 0x4f // 'O'
                    && firstPacket.data[1] === 0x70 // 'p'
                    && firstPacket.data[2] === 0x75 // 'u'
                    && firstPacket.data[3] === 0x73 // 's'
                    && firstPacket.data[4] === 0x48 // 'H'
                    && firstPacket.data[5] === 0x65 // 'e'
                    && firstPacket.data[6] === 0x61 // 'a'
                    && firstPacket.data[7] === 0x64 // 'd'
                ) {
                    await this.readOpusMetadata(firstPacket, bitstream);
                }
                if (bitstream.codecInfo.codec !== null) {
                    this.trackBackings.push(new OggAudioTrackBacking(bitstream, this));
                }
            }
        })();
    }
    async readVorbisMetadata(firstPacket, bitstream) {
        let nextPacketPosition = await this.findNextPacketStart(firstPacket);
        if (!nextPacketPosition) {
            return;
        }
        const secondPacket = await this.readPacket(nextPacketPosition.startPage, nextPacketPosition.startSegmentIndex);
        if (!secondPacket) {
            return;
        }
        nextPacketPosition = await this.findNextPacketStart(secondPacket);
        if (!nextPacketPosition) {
            return;
        }
        const thirdPacket = await this.readPacket(nextPacketPosition.startPage, nextPacketPosition.startSegmentIndex);
        if (!thirdPacket) {
            return;
        }
        if (secondPacket.data[0] !== 0x03 || thirdPacket.data[0] !== 0x05) {
            return;
        }
        const lacingValues = [];
        const addBytesToSegmentTable = (bytes) => {
            while (true) {
                lacingValues.push(Math.min(255, bytes));
                if (bytes < 255) {
                    break;
                }
                bytes -= 255;
            }
        };
        addBytesToSegmentTable(firstPacket.data.length);
        addBytesToSegmentTable(secondPacket.data.length);
        // We don't add the last packet to the segment table, as it is assumed to be whatever bytes remain
        const description = new Uint8Array(1 + lacingValues.length
            + firstPacket.data.length + secondPacket.data.length + thirdPacket.data.length);
        description[0] = 2; // Num entries in the segment table
        description.set(lacingValues, 1);
        description.set(firstPacket.data, 1 + lacingValues.length);
        description.set(secondPacket.data, 1 + lacingValues.length + firstPacket.data.length);
        description.set(thirdPacket.data, 1 + lacingValues.length + firstPacket.data.length + secondPacket.data.length);
        bitstream.codecInfo.codec = 'vorbis';
        bitstream.description = description;
        bitstream.lastMetadataPacket = thirdPacket;
        const view = (0,misc/* toDataView */.Zc)(firstPacket.data);
        bitstream.numberOfChannels = view.getUint8(11);
        bitstream.sampleRate = view.getUint32(12, true);
        const blockSizeByte = view.getUint8(28);
        bitstream.codecInfo.vorbisInfo = {
            blocksizes: [
                1 << (blockSizeByte & 0xf),
                1 << (blockSizeByte >> 4),
            ],
            modeBlockflags: (0,codec_data/* parseModesFromVorbisSetupPacket */.Co)(thirdPacket.data).modeBlockflags,
        };
        (0,codec_data/* readVorbisComments */.Oc)(secondPacket.data.subarray(7), this.metadataTags); // Skip header type and 'vorbis'
    }
    async readOpusMetadata(firstPacket, bitstream) {
        // From https://datatracker.ietf.org/doc/html/rfc7845#section-5:
        // "An Ogg Opus logical stream contains exactly two mandatory header packets: an identification header and a
        // comment header."
        const nextPacketPosition = await this.findNextPacketStart(firstPacket);
        if (!nextPacketPosition) {
            return;
        }
        const secondPacket = await this.readPacket(nextPacketPosition.startPage, nextPacketPosition.startSegmentIndex);
        if (!secondPacket) {
            return;
        }
        bitstream.codecInfo.codec = 'opus';
        bitstream.description = firstPacket.data;
        bitstream.lastMetadataPacket = secondPacket;
        const header = (0,codec_data/* parseOpusIdentificationHeader */.Qf)(firstPacket.data);
        bitstream.numberOfChannels = header.outputChannelCount;
        bitstream.sampleRate = codec/* OPUS_SAMPLE_RATE */.yo; // Always the same
        bitstream.codecInfo.opusInfo = {
            preSkip: header.preSkip,
        };
        (0,codec_data/* readVorbisComments */.Oc)(secondPacket.data.subarray(8), this.metadataTags); // Skip 'OpusTags'
    }
    async readPacket(startPage, startSegmentIndex) {
        (0,misc/* assert */.vA)(startSegmentIndex < startPage.lacingValues.length);
        let startDataOffset = 0;
        for (let i = 0; i < startSegmentIndex; i++) {
            startDataOffset += startPage.lacingValues[i];
        }
        let currentPage = startPage;
        let currentDataOffset = startDataOffset;
        let currentSegmentIndex = startSegmentIndex;
        const chunks = [];
        outer: while (true) {
            // Load the entire page data
            let pageSlice = this.reader.requestSlice(currentPage.dataStartPos, currentPage.dataSize);
            if (pageSlice instanceof Promise)
                pageSlice = await pageSlice;
            (0,misc/* assert */.vA)(pageSlice);
            const pageData = (0,src_reader/* readBytes */.io)(pageSlice, currentPage.dataSize);
            while (true) {
                if (currentSegmentIndex === currentPage.lacingValues.length) {
                    chunks.push(pageData.subarray(startDataOffset, currentDataOffset));
                    break;
                }
                const lacingValue = currentPage.lacingValues[currentSegmentIndex];
                currentDataOffset += lacingValue;
                if (lacingValue < 255) {
                    chunks.push(pageData.subarray(startDataOffset, currentDataOffset));
                    break outer;
                }
                currentSegmentIndex++;
            }
            // The packet extends to the next page; let's find it
            let currentPos = currentPage.headerStartPos + currentPage.totalSize;
            while (true) {
                let headerSlice = this.reader.requestSliceRange(currentPos, ogg_reader/* MIN_PAGE_HEADER_SIZE */.b0, ogg_reader/* MAX_PAGE_HEADER_SIZE */.H9);
                if (headerSlice instanceof Promise)
                    headerSlice = await headerSlice;
                if (!headerSlice) {
                    return null;
                }
                const nextPage = (0,ogg_reader/* readPageHeader */.BF)(headerSlice);
                if (!nextPage) {
                    return null;
                }
                currentPage = nextPage;
                if (currentPage.serialNumber === startPage.serialNumber) {
                    break;
                }
                currentPos = currentPage.headerStartPos + currentPage.totalSize;
            }
            startDataOffset = 0;
            currentDataOffset = 0;
            currentSegmentIndex = 0;
        }
        const totalPacketSize = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
        if (totalPacketSize === 0) {
            return null; // Invalid packet, treat it as end of stream
        }
        const packetData = new Uint8Array(totalPacketSize);
        let offset = 0;
        for (let i = 0; i < chunks.length; i++) {
            const chunk = chunks[i];
            packetData.set(chunk, offset);
            offset += chunk.length;
        }
        return {
            data: packetData,
            endPage: currentPage,
            endSegmentIndex: currentSegmentIndex,
        };
    }
    async findNextPacketStart(lastPacket) {
        // If there's another segment in the same page, return it
        if (lastPacket.endSegmentIndex < lastPacket.endPage.lacingValues.length - 1) {
            return { startPage: lastPacket.endPage, startSegmentIndex: lastPacket.endSegmentIndex + 1 };
        }
        const isEos = !!(lastPacket.endPage.headerType & 0x04);
        if (isEos) {
            // The page is marked as the last page of the logical bitstream, so we won't find anything beyond it
            return null;
        }
        // Otherwise, search for the next page belonging to the same bitstream
        let currentPos = lastPacket.endPage.headerStartPos + lastPacket.endPage.totalSize;
        while (true) {
            let slice = this.reader.requestSliceRange(currentPos, ogg_reader/* MIN_PAGE_HEADER_SIZE */.b0, ogg_reader/* MAX_PAGE_HEADER_SIZE */.H9);
            if (slice instanceof Promise)
                slice = await slice;
            if (!slice) {
                return null;
            }
            const nextPage = (0,ogg_reader/* readPageHeader */.BF)(slice);
            if (!nextPage) {
                return null;
            }
            if (nextPage.serialNumber === lastPacket.endPage.serialNumber) {
                return { startPage: nextPage, startSegmentIndex: 0 };
            }
            currentPos = nextPage.headerStartPos + nextPage.totalSize;
        }
    }
    async getMimeType() {
        await this.readMetadata();
        const codecStrings = await Promise.all(this.trackBackings.map(x => x.getDecoderConfig().then(c => c?.codec ?? null)));
        return (0,ogg_misc/* buildOggMimeType */.Ob)({
            codecStrings: codecStrings.filter(Boolean),
        });
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
class OggAudioTrackBacking {
    constructor(bitstream, demuxer) {
        this.bitstream = bitstream;
        this.demuxer = demuxer;
        this.encodedPacketToMetadata = new WeakMap();
        this.sequentialScanCache = [];
        this.sequentialScanMutex = new misc/* AsyncMutex */.aD();
        // Opus always uses a fixed sample rate for its internal calculations, even if the actual rate is different
        this.internalSampleRate = bitstream.codecInfo.codec === 'opus'
            ? codec/* OPUS_SAMPLE_RATE */.yo
            : bitstream.sampleRate;
    }
    getType() {
        return 'audio';
    }
    getId() {
        return this.bitstream.serialNumber;
    }
    getNumber() {
        // All Ogg tracks are audio, so the track's index + 1 is its number
        const index = this.demuxer.trackBackings.findIndex(x => x.bitstream === this.bitstream);
        (0,misc/* assert */.vA)(index !== -1);
        return index + 1;
    }
    getNumberOfChannels() {
        return this.bitstream.numberOfChannels;
    }
    getSampleRate() {
        return this.bitstream.sampleRate;
    }
    getTimeResolution() {
        return this.bitstream.sampleRate;
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
        return null; // Not stored anywhere
    }
    async getLiveRefreshInterval() {
        return null;
    }
    getCodec() {
        return this.bitstream.codecInfo.codec;
    }
    getInternalCodecId() {
        return null;
    }
    async getDecoderConfig() {
        (0,misc/* assert */.vA)(this.bitstream.codecInfo.codec);
        return {
            codec: this.bitstream.codecInfo.codec,
            numberOfChannels: this.bitstream.numberOfChannels,
            sampleRate: this.bitstream.sampleRate,
            description: this.bitstream.description ?? undefined,
        };
    }
    getName() {
        return null;
    }
    getLanguageCode() {
        return misc/* UNDETERMINED_LANGUAGE */.IR;
    }
    getDisposition() {
        return {
            ...metadata/* DEFAULT_TRACK_DISPOSITION */.gM,
            primary: false,
        };
    }
    granulePositionToTimestampInSamples(granulePosition) {
        if (this.bitstream.codecInfo.codec === 'opus') {
            (0,misc/* assert */.vA)(this.bitstream.codecInfo.opusInfo);
            return granulePosition - this.bitstream.codecInfo.opusInfo.preSkip;
        }
        return granulePosition;
    }
    createEncodedPacketFromOggPacket(packet, additional, options) {
        if (!packet) {
            return null;
        }
        const { durationInSamples, vorbisBlockSize } = (0,ogg_misc/* extractSampleMetadata */.nL)(packet.data, this.bitstream.codecInfo, additional.vorbisLastBlocksize);
        const encodedPacket = new src_packet/* EncodedPacket */.Z(options.metadataOnly ? src_packet/* PLACEHOLDER_DATA */.T : packet.data, 'key', Math.max(0, additional.timestampInSamples) / this.internalSampleRate, durationInSamples / this.internalSampleRate, packet.endPage.headerStartPos + packet.endSegmentIndex, packet.data.byteLength);
        this.encodedPacketToMetadata.set(encodedPacket, {
            packet,
            timestampInSamples: additional.timestampInSamples,
            durationInSamples,
            vorbisLastBlockSize: additional.vorbisLastBlocksize,
            vorbisBlockSize,
        });
        return encodedPacket;
    }
    async getFirstPacket(options) {
        (0,misc/* assert */.vA)(this.bitstream.lastMetadataPacket);
        const packetPosition = await this.demuxer.findNextPacketStart(this.bitstream.lastMetadataPacket);
        if (!packetPosition) {
            return null;
        }
        let timestampInSamples = 0;
        if (this.bitstream.codecInfo.codec === 'opus') {
            (0,misc/* assert */.vA)(this.bitstream.codecInfo.opusInfo);
            timestampInSamples -= this.bitstream.codecInfo.opusInfo.preSkip;
        }
        const packet = await this.demuxer.readPacket(packetPosition.startPage, packetPosition.startSegmentIndex);
        return this.createEncodedPacketFromOggPacket(packet, {
            timestampInSamples,
            vorbisLastBlocksize: null,
        }, options);
    }
    async getNextPacket(prevPacket, options) {
        const prevMetadata = this.encodedPacketToMetadata.get(prevPacket);
        if (!prevMetadata) {
            throw new Error('Packet was not created from this track.');
        }
        const packetPosition = await this.demuxer.findNextPacketStart(prevMetadata.packet);
        if (!packetPosition) {
            return null;
        }
        const timestampInSamples = prevMetadata.timestampInSamples + prevMetadata.durationInSamples;
        const packet = await this.demuxer.readPacket(packetPosition.startPage, packetPosition.startSegmentIndex);
        return this.createEncodedPacketFromOggPacket(packet, {
            timestampInSamples,
            vorbisLastBlocksize: prevMetadata.vorbisBlockSize,
        }, options);
    }
    async getPacket(timestamp, options) {
        if (this.demuxer.reader.fileSize === null) {
            // No file size known, can't do binary search, but fall back to sequential algo instead
            return this.getPacketSequential(timestamp, options);
        }
        const timestampInSamples = (0,misc/* roundIfAlmostInteger */.aI)(timestamp * this.internalSampleRate);
        if (timestampInSamples === 0) {
            // Fast path for timestamp 0 - avoids binary search when playing back from the start
            return this.getFirstPacket(options);
        }
        if (timestampInSamples < 0) {
            // There's nothing here
            return null;
        }
        (0,misc/* assert */.vA)(this.bitstream.lastMetadataPacket);
        const startPosition = await this.demuxer.findNextPacketStart(this.bitstream.lastMetadataPacket);
        if (!startPosition) {
            return null;
        }
        let lowPage = startPosition.startPage;
        let high = this.demuxer.reader.fileSize;
        const lowPages = [lowPage];
        // First, let's perform a binary serach (bisection search) on the file to find the approximate page where
        // we'll find the packet. We want to find a page whose end packet position is less than or equal to the
        // packet position we're searching for.
        // Outer loop: Does the binary serach
        outer: while (lowPage.headerStartPos + lowPage.totalSize < high) {
            const low = lowPage.headerStartPos;
            const mid = Math.floor((low + high) / 2);
            let searchStartPos = mid;
            // Inner loop: Does a linear forward scan if the page cannot be found immediately
            while (true) {
                const until = Math.min(searchStartPos + ogg_reader/* MAX_PAGE_SIZE */.H4, high - ogg_reader/* MIN_PAGE_HEADER_SIZE */.b0);
                let searchSlice = this.demuxer.reader.requestSlice(searchStartPos, until - searchStartPos);
                if (searchSlice instanceof Promise)
                    searchSlice = await searchSlice;
                (0,misc/* assert */.vA)(searchSlice);
                const found = (0,ogg_reader/* findNextPageHeader */.v5)(searchSlice, until);
                if (!found) {
                    high = mid + ogg_reader/* MIN_PAGE_HEADER_SIZE */.b0;
                    continue outer;
                }
                let headerSlice = this.demuxer.reader.requestSliceRange(searchSlice.filePos, ogg_reader/* MIN_PAGE_HEADER_SIZE */.b0, ogg_reader/* MAX_PAGE_HEADER_SIZE */.H9);
                if (headerSlice instanceof Promise)
                    headerSlice = await headerSlice;
                (0,misc/* assert */.vA)(headerSlice);
                const page = (0,ogg_reader/* readPageHeader */.BF)(headerSlice);
                (0,misc/* assert */.vA)(page);
                let pageValid = false;
                if (page.serialNumber === this.bitstream.serialNumber) {
                    // Serial numbers are basically random numbers, and the chance of finding a fake page with
                    // matching serial number is astronomically low, so we can be pretty sure this page is legit.
                    pageValid = true;
                }
                else {
                    let pageSlice = this.demuxer.reader.requestSlice(page.headerStartPos, page.totalSize);
                    if (pageSlice instanceof Promise)
                        pageSlice = await pageSlice;
                    (0,misc/* assert */.vA)(pageSlice);
                    // Validate the page by checking checksum
                    const bytes = (0,src_reader/* readBytes */.io)(pageSlice, page.totalSize);
                    const crc = (0,ogg_misc/* computeOggPageCrc */._S)(bytes);
                    pageValid = crc === page.checksum;
                }
                if (!pageValid) {
                    // Keep searching for a valid page
                    searchStartPos = page.headerStartPos + 4; // 'OggS' is 4 bytes
                    continue;
                }
                if (pageValid && page.serialNumber !== this.bitstream.serialNumber) {
                    // Page is valid but from a different bitstream, so keep searching forward until we find one
                    // belonging to the our bitstream
                    searchStartPos = page.headerStartPos + page.totalSize;
                    continue;
                }
                const isContinuationPage = page.granulePosition === -1;
                if (isContinuationPage) {
                    // No packet ends on this page - keep looking
                    searchStartPos = page.headerStartPos + page.totalSize;
                    continue;
                }
                // The page is valid and belongs to our bitstream; let's check its granule position to see where we
                // need to take the bisection search.
                if (this.granulePositionToTimestampInSamples(page.granulePosition) > timestampInSamples) {
                    high = page.headerStartPos;
                }
                else {
                    lowPage = page;
                    lowPages.push(page);
                }
                continue outer;
            }
        }
        // Now we have the last page with a packet position <= the packet position we're looking for, but there
        // might be multiple pages with the packet position, in which case we actually need to find the first of
        // such pages. We'll do this in two steps: First, let's find the latest page we know with an earlier packet
        // position, and then linear scan ourselves forward until we find the correct page.
        let lowerPage = startPosition.startPage;
        for (const otherLowPage of lowPages) {
            if (otherLowPage.granulePosition === lowPage.granulePosition) {
                break;
            }
            if (!lowerPage || otherLowPage.headerStartPos > lowerPage.headerStartPos) {
                lowerPage = otherLowPage;
            }
        }
        let currentPage = lowerPage;
        // Keep track of the pages we traversed, we need these later for backwards seeking
        const previousPages = [currentPage];
        while (true) {
            // This loop must terminate as we'll eventually reach lowPage
            if (currentPage.serialNumber === this.bitstream.serialNumber
                && currentPage.granulePosition === lowPage.granulePosition) {
                break;
            }
            const nextPos = currentPage.headerStartPos + currentPage.totalSize;
            let slice = this.demuxer.reader.requestSliceRange(nextPos, ogg_reader/* MIN_PAGE_HEADER_SIZE */.b0, ogg_reader/* MAX_PAGE_HEADER_SIZE */.H9);
            if (slice instanceof Promise)
                slice = await slice;
            (0,misc/* assert */.vA)(slice);
            const nextPage = (0,ogg_reader/* readPageHeader */.BF)(slice);
            (0,misc/* assert */.vA)(nextPage);
            currentPage = nextPage;
            if (currentPage.serialNumber === this.bitstream.serialNumber) {
                previousPages.push(currentPage);
            }
        }
        (0,misc/* assert */.vA)(currentPage.granulePosition !== -1);
        let currentSegmentIndex = null;
        let currentTimestampInSamples;
        let currentTimestampIsCorrect;
        // These indicate the end position of the packet that the granule position belongs to
        let endPage = currentPage;
        let endSegmentIndex = 0;
        if (currentPage.headerStartPos === startPosition.startPage.headerStartPos) {
            currentTimestampInSamples = this.granulePositionToTimestampInSamples(0);
            currentTimestampIsCorrect = true;
            currentSegmentIndex = 0;
        }
        else {
            currentTimestampInSamples = 0; // Placeholder value! We'll refine it once we can
            currentTimestampIsCorrect = false;
            // Find the segment index of the next packet
            for (let i = currentPage.lacingValues.length - 1; i >= 0; i--) {
                const value = currentPage.lacingValues[i];
                if (value < 255) {
                    // We know the last packet ended at i, so the next one starts at i + 1
                    currentSegmentIndex = i + 1;
                    break;
                }
            }
            // This must hold: Since this page has a granule position set, that means there must be a packet that
            // ends in this page.
            if (currentSegmentIndex === null) {
                throw new Error('Invalid page with granule position: no packets end on this page.');
            }
            endSegmentIndex = currentSegmentIndex - 1;
            const pseudopacket = {
                data: src_packet/* PLACEHOLDER_DATA */.T,
                endPage,
                endSegmentIndex,
            };
            const nextPosition = await this.demuxer.findNextPacketStart(pseudopacket);
            if (nextPosition) {
                // Let's rewind a single step (packet) - this previous packet ensures that we'll correctly compute
                // the duration for the packet we're looking for.
                const endPosition = findPreviousPacketEndPosition(previousPages, currentPage, currentSegmentIndex);
                (0,misc/* assert */.vA)(endPosition);
                const startPosition = findPacketStartPosition(previousPages, endPosition.page, endPosition.segmentIndex);
                if (startPosition) {
                    currentPage = startPosition.page;
                    currentSegmentIndex = startPosition.segmentIndex;
                }
            }
            else {
                // There is no next position, which means we're looking for the last packet in the bitstream. The
                // granule position on the last page tends to be fucky, so let's instead start the search on the
                // page before that. So let's loop until we find a packet that ends in a previous page.
                while (true) {
                    const endPosition = findPreviousPacketEndPosition(previousPages, currentPage, currentSegmentIndex);
                    if (!endPosition) {
                        break;
                    }
                    const startPosition = findPacketStartPosition(previousPages, endPosition.page, endPosition.segmentIndex);
                    if (!startPosition) {
                        break;
                    }
                    currentPage = startPosition.page;
                    currentSegmentIndex = startPosition.segmentIndex;
                    if (endPosition.page.headerStartPos !== endPage.headerStartPos) {
                        endPage = endPosition.page;
                        endSegmentIndex = endPosition.segmentIndex;
                        break;
                    }
                }
            }
        }
        let lastEncodedPacket = null;
        let lastEncodedPacketMetadata = null;
        // Alright, now it's time for the final, granular seek: We keep iterating over packets until we've found the
        // one with the correct timestamp - i.e., the last one with a timestamp <= the timestamp we're looking for.
        while (currentPage !== null) {
            (0,misc/* assert */.vA)(currentSegmentIndex !== null);
            const packet = await this.demuxer.readPacket(currentPage, currentSegmentIndex);
            if (!packet) {
                break;
            }
            // We might need to skip the packet if it's a metadata one
            const skipPacket = currentPage.headerStartPos === startPosition.startPage.headerStartPos
                && currentSegmentIndex < startPosition.startSegmentIndex;
            if (!skipPacket) {
                let encodedPacket = this.createEncodedPacketFromOggPacket(packet, {
                    timestampInSamples: currentTimestampInSamples,
                    vorbisLastBlocksize: lastEncodedPacketMetadata?.vorbisBlockSize ?? null,
                }, options);
                (0,misc/* assert */.vA)(encodedPacket);
                let encodedPacketMetadata = this.encodedPacketToMetadata.get(encodedPacket);
                (0,misc/* assert */.vA)(encodedPacketMetadata);
                if (!currentTimestampIsCorrect
                    && packet.endPage.headerStartPos === endPage.headerStartPos
                    && packet.endSegmentIndex === endSegmentIndex) {
                    // We know this packet end timestamp can be derived from the page's granule position
                    currentTimestampInSamples = this.granulePositionToTimestampInSamples(currentPage.granulePosition);
                    currentTimestampIsCorrect = true;
                    // Let's backpatch the packet we just created with the correct timestamp
                    encodedPacket = this.createEncodedPacketFromOggPacket(packet, {
                        timestampInSamples: currentTimestampInSamples - encodedPacketMetadata.durationInSamples,
                        vorbisLastBlocksize: lastEncodedPacketMetadata?.vorbisBlockSize ?? null,
                    }, options);
                    (0,misc/* assert */.vA)(encodedPacket);
                    encodedPacketMetadata = this.encodedPacketToMetadata.get(encodedPacket);
                    (0,misc/* assert */.vA)(encodedPacketMetadata);
                }
                else {
                    currentTimestampInSamples += encodedPacketMetadata.durationInSamples;
                }
                lastEncodedPacket = encodedPacket;
                lastEncodedPacketMetadata = encodedPacketMetadata;
                if (currentTimestampIsCorrect
                    && (
                    // Next timestamp will be too late
                    Math.max(currentTimestampInSamples, 0) > timestampInSamples
                        // This timestamp already matches
                        || Math.max(encodedPacketMetadata.timestampInSamples, 0) === timestampInSamples)) {
                    break;
                }
            }
            const nextPosition = await this.demuxer.findNextPacketStart(packet);
            if (!nextPosition) {
                break;
            }
            currentPage = nextPosition.startPage;
            currentSegmentIndex = nextPosition.startSegmentIndex;
        }
        return lastEncodedPacket;
    }
    // A slower but simpler and sequential algorithm for finding a packet in a file
    async getPacketSequential(timestamp, options) {
        const release = await this.sequentialScanMutex.acquire(); // Requires exclusivity because we write to a cache
        try {
            const timestampInSamples = (0,misc/* roundIfAlmostInteger */.aI)(timestamp * this.internalSampleRate);
            timestamp = timestampInSamples / this.internalSampleRate;
            const index = (0,misc/* binarySearchLessOrEqual */.eE)(this.sequentialScanCache, timestampInSamples, x => x.timestampInSamples);
            let currentPacket;
            if (index !== -1) {
                // We don't need to start from the beginning, we can start at a previous scan point
                const cacheEntry = this.sequentialScanCache[index];
                currentPacket = this.createEncodedPacketFromOggPacket(cacheEntry.packet, {
                    timestampInSamples: cacheEntry.timestampInSamples,
                    vorbisLastBlocksize: cacheEntry.vorbisLastBlockSize,
                }, options);
            }
            else {
                currentPacket = await this.getFirstPacket(options);
            }
            let i = 0;
            while (currentPacket && currentPacket.timestamp < timestamp) {
                const nextPacket = await this.getNextPacket(currentPacket, options);
                if (!nextPacket || nextPacket.timestamp > timestamp) {
                    break;
                }
                currentPacket = nextPacket;
                i++;
                if (i === 100) {
                    // Add "checkpoints" every once in a while to speed up subsequent random accesses
                    i = 0;
                    const metadata = this.encodedPacketToMetadata.get(currentPacket);
                    (0,misc/* assert */.vA)(metadata);
                    if (this.sequentialScanCache.length > 0) {
                        // If we reach this case, we must be at the end of the cache
                        (0,misc/* assert */.vA)((0,misc/* last */._g)(this.sequentialScanCache).timestampInSamples <= metadata.timestampInSamples);
                    }
                    this.sequentialScanCache.push(metadata);
                }
            }
            return currentPacket;
        }
        finally {
            release();
        }
    }
    getKeyPacket(timestamp, options) {
        return this.getPacket(timestamp, options);
    }
    getNextKeyPacket(packet, options) {
        return this.getNextPacket(packet, options);
    }
}
/** Finds the start position of a packet given its end position. */
const findPacketStartPosition = (pageList, endPage, endSegmentIndex) => {
    let page = endPage;
    let segmentIndex = endSegmentIndex;
    outer: while (true) {
        segmentIndex--;
        for (segmentIndex; segmentIndex >= 0; segmentIndex--) {
            const lacingValue = page.lacingValues[segmentIndex];
            if (lacingValue < 255) {
                segmentIndex++; // We know the last packet starts here
                break outer;
            }
        }
        (0,misc/* assert */.vA)(segmentIndex === -1);
        const pageStartsWithFreshPacket = !(page.headerType & 0x01);
        if (pageStartsWithFreshPacket) {
            // Fast exit: We know we don't need to look in the previous page
            segmentIndex = 0;
            break;
        }
        const previousPage = (0,misc/* findLast */.Uk)(pageList, x => x.headerStartPos < page.headerStartPos);
        if (!previousPage) {
            return null;
        }
        page = previousPage;
        segmentIndex = page.lacingValues.length;
    }
    (0,misc/* assert */.vA)(segmentIndex !== -1);
    if (segmentIndex === page.lacingValues.length) {
        // Wrap back around to the first segment of the next page
        const nextPage = pageList[pageList.indexOf(page) + 1];
        (0,misc/* assert */.vA)(nextPage);
        page = nextPage;
        segmentIndex = 0;
    }
    return { page, segmentIndex };
};
/** Finds the end position of a packet given the start position of the following packet. */
const findPreviousPacketEndPosition = (pageList, startPage, startSegmentIndex) => {
    if (startSegmentIndex > 0) {
        // Easy
        return { page: startPage, segmentIndex: startSegmentIndex - 1 };
    }
    const previousPage = (0,misc/* findLast */.Uk)(pageList, x => x.headerStartPos < startPage.headerStartPos);
    if (!previousPage) {
        return null;
    }
    return { page: previousPage, segmentIndex: previousPage.lacingValues.length - 1 };
};

// EXTERNAL MODULE: ./node_modules/mediabunny/dist/modules/src/wave/wave-demuxer.js
var wave_demuxer = __webpack_require__(260);
// EXTERNAL MODULE: ./node_modules/mediabunny/dist/modules/src/adts/adts-reader.js
var adts_reader = __webpack_require__(8475);
;// ./node_modules/mediabunny/dist/modules/src/adts/adts-demuxer.js
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */








const SAMPLES_PER_AAC_FRAME = 1024;
class AdtsDemuxer extends demuxer/* Demuxer */.B {
    constructor(input) {
        super(input);
        this.metadataPromise = null;
        this.firstFrameHeader = null;
        this.loadedSamples = [];
        this.metadataTags = null;
        this.trackBackings = [];
        this.readingMutex = new misc/* AsyncMutex */.aD();
        this.lastSampleLoaded = false;
        this.lastLoadedPos = 0;
        this.nextTimestampInSamples = 0;
        this.reader = input._reader;
    }
    async readMetadata() {
        return this.metadataPromise ??= (async () => {
            // Keep loading until we find the first frame header
            while (!this.firstFrameHeader && !this.lastSampleLoaded) {
                await this.advanceReader();
            }
            // There has to be a frame if this demuxer got selected
            (0,misc/* assert */.vA)(this.firstFrameHeader);
            // Create the single audio track
            this.trackBackings = [new AdtsAudioTrackBacking(this)];
        })();
    }
    async advanceReader() {
        if (this.lastLoadedPos === 0) {
            // Skip all ID3v2 tags at the start of the file
            while (true) {
                let slice = this.reader.requestSlice(this.lastLoadedPos, id3/* ID3_V2_HEADER_SIZE */.sY);
                if (slice instanceof Promise)
                    slice = await slice;
                if (!slice) {
                    this.lastSampleLoaded = true;
                    return;
                }
                const id3V2Header = (0,id3/* readId3V2Header */.IX)(slice);
                if (!id3V2Header) {
                    break;
                }
                this.lastLoadedPos = slice.filePos + id3V2Header.size;
            }
        }
        let slice = this.reader.requestSliceRange(this.lastLoadedPos, adts_reader/* MIN_ADTS_FRAME_HEADER_SIZE */.gc, adts_reader/* MAX_ADTS_FRAME_HEADER_SIZE */.Y$);
        if (slice instanceof Promise)
            slice = await slice;
        if (!slice) {
            this.lastSampleLoaded = true;
            return;
        }
        const header = (0,adts_reader/* readAdtsFrameHeader */.lh)(slice);
        if (!header) {
            this.lastSampleLoaded = true;
            return;
        }
        if (this.reader.fileSize !== null && header.startPos + header.frameLength > this.reader.fileSize) {
            // Frame doesn't fit in the rest of the file
            this.lastSampleLoaded = true;
            return;
        }
        if (!this.firstFrameHeader) {
            this.firstFrameHeader = header;
        }
        const sampleRate = aac_misc/* aacFrequencyTable */.Im[header.samplingFrequencyIndex];
        (0,misc/* assert */.vA)(sampleRate !== undefined);
        const sampleDuration = SAMPLES_PER_AAC_FRAME / sampleRate;
        const sample = {
            timestamp: this.nextTimestampInSamples / sampleRate,
            duration: sampleDuration,
            dataStart: header.startPos,
            dataSize: header.frameLength,
        };
        this.loadedSamples.push(sample);
        this.nextTimestampInSamples += SAMPLES_PER_AAC_FRAME;
        this.lastLoadedPos = header.startPos + header.frameLength;
    }
    async getMimeType() {
        return 'audio/aac';
    }
    async getTrackBackings() {
        await this.readMetadata();
        return this.trackBackings;
    }
    async getMetadataTags() {
        const release = await this.readingMutex.acquire();
        try {
            await this.readMetadata();
            if (this.metadataTags) {
                return this.metadataTags;
            }
            this.metadataTags = {};
            let currentPos = 0;
            while (true) {
                let headerSlice = this.reader.requestSlice(currentPos, id3/* ID3_V2_HEADER_SIZE */.sY);
                if (headerSlice instanceof Promise)
                    headerSlice = await headerSlice;
                if (!headerSlice)
                    break;
                const id3V2Header = (0,id3/* readId3V2Header */.IX)(headerSlice);
                if (!id3V2Header) {
                    break;
                }
                let contentSlice = this.reader.requestSlice(headerSlice.filePos, id3V2Header.size);
                if (contentSlice instanceof Promise)
                    contentSlice = await contentSlice;
                if (!contentSlice)
                    break;
                (0,id3/* parseId3V2Tag */.cG)(contentSlice, id3V2Header, this.metadataTags);
                currentPos = headerSlice.filePos + id3V2Header.size;
            }
            return this.metadataTags;
        }
        finally {
            release();
        }
    }
}
class AdtsAudioTrackBacking {
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
    getTimeResolution() {
        const sampleRate = this.getSampleRate();
        return sampleRate / SAMPLES_PER_AAC_FRAME;
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
        return null; // No way
    }
    async getLiveRefreshInterval() {
        return null;
    }
    getName() {
        return null;
    }
    getLanguageCode() {
        return misc/* UNDETERMINED_LANGUAGE */.IR;
    }
    getCodec() {
        return 'aac';
    }
    getInternalCodecId() {
        (0,misc/* assert */.vA)(this.demuxer.firstFrameHeader);
        return this.demuxer.firstFrameHeader.objectType;
    }
    getNumberOfChannels() {
        (0,misc/* assert */.vA)(this.demuxer.firstFrameHeader);
        const numberOfChannels = aac_misc/* aacChannelMap */.Ti[this.demuxer.firstFrameHeader.channelConfiguration];
        (0,misc/* assert */.vA)(numberOfChannels !== undefined);
        return numberOfChannels;
    }
    getSampleRate() {
        (0,misc/* assert */.vA)(this.demuxer.firstFrameHeader);
        const sampleRate = aac_misc/* aacFrequencyTable */.Im[this.demuxer.firstFrameHeader.samplingFrequencyIndex];
        (0,misc/* assert */.vA)(sampleRate !== undefined);
        return sampleRate;
    }
    getDisposition() {
        return {
            ...metadata/* DEFAULT_TRACK_DISPOSITION */.gM,
        };
    }
    async getDecoderConfig() {
        (0,misc/* assert */.vA)(this.demuxer.firstFrameHeader);
        return {
            codec: `mp4a.40.${this.demuxer.firstFrameHeader.objectType}`,
            numberOfChannels: this.getNumberOfChannels(),
            sampleRate: this.getSampleRate(),
        };
    }
    async getPacketAtIndex(sampleIndex, options) {
        if (sampleIndex === -1) {
            return null;
        }
        const rawSample = this.demuxer.loadedSamples[sampleIndex];
        if (!rawSample) {
            return null;
        }
        let data;
        if (options.metadataOnly) {
            data = src_packet/* PLACEHOLDER_DATA */.T;
        }
        else {
            let slice = this.demuxer.reader.requestSlice(rawSample.dataStart, rawSample.dataSize);
            if (slice instanceof Promise)
                slice = await slice;
            if (!slice) {
                return null; // Data didn't fit into the rest of the file
            }
            data = (0,src_reader/* readBytes */.io)(slice, rawSample.dataSize);
        }
        return new src_packet/* EncodedPacket */.Z(data, 'key', rawSample.timestamp, rawSample.duration, sampleIndex, rawSample.dataSize);
    }
    getFirstPacket(options) {
        return this.getPacketAtIndex(0, options);
    }
    async getNextPacket(packet, options) {
        const release = await this.demuxer.readingMutex.acquire();
        try {
            const sampleIndex = (0,misc/* binarySearchExact */.pl)(this.demuxer.loadedSamples, packet.timestamp, x => x.timestamp);
            if (sampleIndex === -1) {
                throw new Error('Packet was not created from this track.');
            }
            const nextIndex = sampleIndex + 1;
            // Ensure the next sample exists
            while (nextIndex >= this.demuxer.loadedSamples.length
                && !this.demuxer.lastSampleLoaded) {
                await this.demuxer.advanceReader();
            }
            return this.getPacketAtIndex(nextIndex, options);
        }
        finally {
            release();
        }
    }
    async getPacket(timestamp, options) {
        const release = await this.demuxer.readingMutex.acquire();
        try {
            while (true) {
                const index = (0,misc/* binarySearchLessOrEqual */.eE)(this.demuxer.loadedSamples, timestamp, x => x.timestamp);
                if (index === -1 && this.demuxer.loadedSamples.length > 0) {
                    // We're before the first sample
                    return null;
                }
                if (this.demuxer.lastSampleLoaded) {
                    // All data is loaded, return what we found
                    return this.getPacketAtIndex(index, options);
                }
                if (index >= 0 && index + 1 < this.demuxer.loadedSamples.length) {
                    // The next packet also exists, we're done
                    return this.getPacketAtIndex(index, options);
                }
                // Otherwise, keep loading data
                await this.demuxer.advanceReader();
            }
        }
        finally {
            release();
        }
    }
    getKeyPacket(timestamp, options) {
        return this.getPacket(timestamp, options);
    }
    getNextKeyPacket(packet, options) {
        return this.getNextPacket(packet, options);
    }
}

// EXTERNAL MODULE: ./node_modules/mediabunny/dist/modules/src/flac/flac-misc.js
var flac_misc = __webpack_require__(5828);
;// ./node_modules/mediabunny/dist/modules/src/flac/flac-demuxer.js
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */








class FlacDemuxer extends demuxer/* Demuxer */.B {
    constructor(input) {
        super(input);
        this.loadedSamples = []; // All samples from the start of the file to lastLoadedPos
        this.metadataPromise = null;
        this.trackBacking = null;
        this.metadataTags = {};
        this.audioInfo = null;
        this.lastLoadedPos = null;
        this.blockingBit = null;
        this.readingMutex = new misc/* AsyncMutex */.aD();
        this.lastSampleLoaded = false;
        this.reader = input._reader;
    }
    async getMetadataTags() {
        await this.readMetadata();
        return this.metadataTags;
    }
    async getTrackBackings() {
        await this.readMetadata();
        (0,misc/* assert */.vA)(this.trackBacking);
        return [this.trackBacking];
    }
    async getMimeType() {
        return 'audio/flac';
    }
    async readMetadata() {
        let currentPos = 4; // Skip 'fLaC'
        return (this.metadataPromise ??= (async () => {
            while (this.reader.fileSize === null
                || currentPos < this.reader.fileSize) {
                let sizeSlice = this.reader.requestSlice(currentPos, 4);
                if (sizeSlice instanceof Promise)
                    sizeSlice = await sizeSlice;
                currentPos += 4;
                if (sizeSlice === null) {
                    throw new Error(`Metadata block at position ${currentPos} is too small! Corrupted file.`);
                }
                (0,misc/* assert */.vA)(sizeSlice);
                const byte = (0,src_reader/* readU8 */.eo)(sizeSlice); // first bit: isLastMetadata, remaining 7 bits: metaBlockType
                const size = (0,src_reader/* readU24Be */.n2)(sizeSlice);
                const isLastMetadata = (byte & 0x80) !== 0;
                const metaBlockType = byte & 0x7f;
                switch (metaBlockType) {
                    case codec_data/* FlacBlockType */.A3.STREAMINFO: {
                        // Parse streaminfo block
                        // https://www.rfc-editor.org/rfc/rfc9639.html#section-8.2
                        let streamInfoBlock = this.reader.requestSlice(currentPos, size);
                        if (streamInfoBlock instanceof Promise)
                            streamInfoBlock = await streamInfoBlock;
                        (0,misc/* assert */.vA)(streamInfoBlock);
                        if (streamInfoBlock === null) {
                            throw new Error(`StreamInfo block at position ${currentPos} is too small! Corrupted file.`);
                        }
                        const streamInfoBytes = (0,src_reader/* readBytes */.io)(streamInfoBlock, 34);
                        const bitstream = new shared_bitstream/* Bitstream */._(streamInfoBytes);
                        const minimumBlockSize = bitstream.readBits(16);
                        const maximumBlockSize = bitstream.readBits(16);
                        const minimumFrameSize = bitstream.readBits(24);
                        const maximumFrameSize = bitstream.readBits(24);
                        const sampleRate = bitstream.readBits(20);
                        const numberOfChannels = bitstream.readBits(3) + 1;
                        bitstream.readBits(5); // bitsPerSample - 1
                        const totalSamples = bitstream.readBits(36);
                        // https://www.w3.org/TR/webcodecs-flac-codec-registration/#audiodecoderconfig-description
                        // description is required, and has to be the following:
                        // 1. The bytes 0x66 0x4C 0x61 0x43 ("fLaC" in ASCII)
                        // 2. A metadata block (called the STREAMINFO block) as described in section 7 of [FLAC]
                        // 3. Optionaly (sic) other metadata blocks, that are not used by the specification
                        bitstream.skipBits(16 * 8); // md5 hash
                        const description = new Uint8Array(42);
                        // 1. "fLaC"
                        description.set(new Uint8Array([0x66, 0x4c, 0x61, 0x43]), 0);
                        // 2. STREAMINFO block
                        description.set(new Uint8Array([128, 0, 0, 34]), 4);
                        // 3. Other metadata blocks
                        description.set(streamInfoBytes, 8);
                        this.audioInfo = {
                            numberOfChannels,
                            sampleRate,
                            totalSamples,
                            minimumBlockSize,
                            maximumBlockSize,
                            minimumFrameSize,
                            maximumFrameSize,
                            description,
                        };
                        this.trackBacking = new FlacAudioTrackBacking(this);
                        break;
                    }
                    case codec_data/* FlacBlockType */.A3.VORBIS_COMMENT: {
                        // Parse vorbis comment block
                        // https://www.rfc-editor.org/rfc/rfc9639.html#name-vorbis-comment
                        let vorbisCommentBlock = this.reader.requestSlice(currentPos, size);
                        if (vorbisCommentBlock instanceof Promise)
                            vorbisCommentBlock = await vorbisCommentBlock;
                        (0,misc/* assert */.vA)(vorbisCommentBlock);
                        (0,codec_data/* readVorbisComments */.Oc)((0,src_reader/* readBytes */.io)(vorbisCommentBlock, size), this.metadataTags);
                        break;
                    }
                    case codec_data/* FlacBlockType */.A3.PICTURE: {
                        // Parse picture block
                        // https://www.rfc-editor.org/rfc/rfc9639.html#name-picture
                        let pictureBlock = this.reader.requestSlice(currentPos, size);
                        if (pictureBlock instanceof Promise)
                            pictureBlock = await pictureBlock;
                        (0,misc/* assert */.vA)(pictureBlock);
                        const pictureType = (0,src_reader/* readU32Be */.cN)(pictureBlock);
                        const mediaTypeLength = (0,src_reader/* readU32Be */.cN)(pictureBlock);
                        const mediaType = misc/* textDecoder */.su.decode((0,src_reader/* readBytes */.io)(pictureBlock, mediaTypeLength));
                        const descriptionLength = (0,src_reader/* readU32Be */.cN)(pictureBlock);
                        const description = misc/* textDecoder */.su.decode((0,src_reader/* readBytes */.io)(pictureBlock, descriptionLength));
                        pictureBlock.skip(4 + 4 + 4 + 4); // Skip width, height, color depth, number of indexed colors
                        const dataLength = (0,src_reader/* readU32Be */.cN)(pictureBlock);
                        const data = (0,src_reader/* readBytes */.io)(pictureBlock, dataLength);
                        this.metadataTags.images ??= [];
                        this.metadataTags.images.push({
                            data,
                            mimeType: mediaType,
                            // https://www.rfc-editor.org/rfc/rfc9639.html#table13
                            kind: pictureType === 3
                                ? 'coverFront'
                                : pictureType === 4
                                    ? 'coverBack'
                                    : 'unknown',
                            description,
                        });
                        break;
                    }
                    default:
                        break;
                }
                currentPos += size;
                if (isLastMetadata) {
                    this.lastLoadedPos = currentPos;
                    break;
                }
            }
            if (!this.audioInfo) {
                throw new Error('Missing STREAMINFO metadata block! Corrupted FLAC file.');
            }
        })());
    }
    async readNextFlacFrame({ startPos, isFirstPacket, }) {
        (0,misc/* assert */.vA)(this.audioInfo);
        // we expect that there are at least `minimumFrameSize` bytes left in the file
        // Ideally we also want to validate the next header is valid
        // to throw out an accidential sync word
        // The shortest valid FLAC header I can think of, based off the code
        // of readFlacFrameHeader:
        // 4 bytes used for bitstream from syncword to bit depth
        // 1 byte coded number
        // (uncommon values, no bytes read)
        // 1 byte crc
        // --> 6 bytes
        const minimumHeaderLength = 6;
        // If we read everything in readFlacFrameHeader, we read 16 bytes
        const maximumHeaderLength = 16;
        // The shortest valid FLAC frame per RFC 9639:
        // 6 bytes header (see minimumHeaderLength above)
        // 2 bytes subframe (constant subframe with minimum bit depth,
        //   padded to byte boundary)
        // 2 bytes footer (CRC-16)
        // --> 10 bytes
        const minimumFrameLength = 10;
        // The longest valid FLAC frame per RFC 9639:
        // https://www.rfc-editor.org/rfc/rfc9639.html#name-prediction
        // https://www.rfc-editor.org/rfc/rfc9639.html#name-frame-structure
        // maximumBlockSize * numberOfChannels * 4 bytes (max 32 bps verbatim)
        // + 16 bytes header (see maximumHeaderSize above)
        // + 2 bytes footer (CRC-16)
        const maximumFrameLength = this.audioInfo.maximumBlockSize
            * this.audioInfo.numberOfChannels
            * 4
            + maximumHeaderLength
            + 2;
        // Per RFC 9639, a value of 0 means "unknown" for frame sizes.
        const effectiveMinFrameSize = this.audioInfo.minimumFrameSize || minimumFrameLength;
        const effectiveMaxFrameSize = this.audioInfo.maximumFrameSize || maximumFrameLength;
        const maximumSliceLength = effectiveMaxFrameSize + maximumHeaderLength;
        const slice = await this.reader.requestSliceRange(startPos, maximumHeaderLength, maximumSliceLength);
        if (!slice) {
            return null;
        }
        const frameHeader = this.readFlacFrameHeader({
            slice,
            isFirstPacket: isFirstPacket,
        });
        if (!frameHeader) {
            return null;
        }
        // We don't know exactly how long the packet is, we only know the `minimumFrameSize` and `maximumFrameSize`
        // The packet is over if the next 2 bytes are the sync word followed by a valid header
        // or the end of the file is reached
        // The next sync word is expected at earliest when `minimumFrameSize` is reached,
        // we can skip over anything before that
        slice.filePos = startPos + effectiveMinFrameSize;
        while (true) {
            // Reached end of the file, packet is over
            if (slice.filePos > slice.end - minimumHeaderLength) {
                return {
                    num: frameHeader.num,
                    blockSize: frameHeader.blockSize,
                    sampleRate: frameHeader.sampleRate,
                    size: slice.end - startPos,
                    isLastFrame: true,
                };
            }
            const nextByte = (0,src_reader/* readU8 */.eo)(slice);
            if (nextByte === 0xff) {
                const positionBeforeReading = slice.filePos;
                const byteAfterNextByte = (0,src_reader/* readU8 */.eo)(slice);
                const expected = this.blockingBit === 1 ? 0b1111_1001 : 0b1111_1000;
                if (byteAfterNextByte !== expected) {
                    slice.filePos = positionBeforeReading;
                    continue;
                }
                slice.skip(-2);
                const lengthIfNextFlacFrameHeaderIsLegit = slice.filePos - startPos;
                const nextFrameHeader = this.readFlacFrameHeader({
                    slice,
                    isFirstPacket: false,
                });
                if (!nextFrameHeader) {
                    slice.filePos = positionBeforeReading;
                    continue;
                }
                // Ensure the frameOrSampleNum is consecutive.
                // https://github.com/Vanilagy/mediabunny/issues/194
                if (this.blockingBit === 0) {
                    // Case A: If the stream is fixed block size, this is the frame number, which increments by 1
                    if (nextFrameHeader.num - frameHeader.num !== 1) {
                        slice.filePos = positionBeforeReading;
                        continue;
                    }
                }
                else {
                    // Case B: If the stream is variable block size, this is the sample number, which increments by
                    // amount of samples in a frame.
                    if (nextFrameHeader.num - frameHeader.num !== frameHeader.blockSize) {
                        slice.filePos = positionBeforeReading;
                        continue;
                    }
                }
                return {
                    num: frameHeader.num,
                    blockSize: frameHeader.blockSize,
                    sampleRate: frameHeader.sampleRate,
                    size: lengthIfNextFlacFrameHeaderIsLegit,
                    isLastFrame: false,
                };
            }
        }
    }
    readFlacFrameHeader({ slice, isFirstPacket, }) {
        // In this function, generally it is not safe to throw errors.
        // We might end up here because we stumbled upon a syncword,
        // but the data might not actually be a FLAC frame, it might be random bitstream
        // data, in that case we should return null and continue.
        const startOffset = slice.filePos;
        // https://www.rfc-editor.org/rfc/rfc9639.html#section-9.1
        // Each frame MUST start on a byte boundary and start with the 15-bit frame
        // sync code 0b111111111111100. Following the sync code is the blocking strategy
        // bit, which MUST NOT change during the audio stream.
        const bytes = (0,src_reader/* readBytes */.io)(slice, 4);
        const bitstream = new shared_bitstream/* Bitstream */._(bytes);
        const bits = bitstream.readBits(15);
        if (bits !== 0b111111111111100) {
            // This cannot be a valid FLAC frame, must start with the syncword
            return null;
        }
        if (this.blockingBit === null) {
            (0,misc/* assert */.vA)(isFirstPacket);
            const newBlockingBit = bitstream.readBits(1);
            this.blockingBit = newBlockingBit;
        }
        else if (this.blockingBit === 1) {
            (0,misc/* assert */.vA)(!isFirstPacket);
            const newBlockingBit = bitstream.readBits(1);
            if (newBlockingBit !== 1) {
                // This cannot be a valid FLAC frame, expected 1 but got 0
                return null;
            }
        }
        else if (this.blockingBit === 0) {
            (0,misc/* assert */.vA)(!isFirstPacket);
            const newBlockingBit = bitstream.readBits(1);
            if (newBlockingBit !== 0) {
                // This cannot be a valid FLAC frame, expected 0 but got 1
                return null;
            }
        }
        else {
            throw new Error('Invalid blocking bit');
        }
        const blockSizeOrUncommon = (0,flac_misc/* getBlockSizeOrUncommon */.iv)(bitstream.readBits(4));
        if (!blockSizeOrUncommon) {
            // This cannot be a valid FLAC frame, the syncword was just coincidental
            return null;
        }
        (0,misc/* assert */.vA)(this.audioInfo);
        const sampleRateOrUncommon = (0,flac_misc/* getSampleRateOrUncommon */.oP)(bitstream.readBits(4), this.audioInfo.sampleRate);
        if (!sampleRateOrUncommon) {
            // This cannot be a valid FLAC frame, the syncword was just coincidental
            return null;
        }
        bitstream.readBits(4); // channel count
        bitstream.readBits(3); // bit depth
        const reservedZero = bitstream.readBits(1); // reserved zero
        if (reservedZero !== 0) {
            // This cannot be a valid FLAC frame, the syncword was just coincidental
            return null;
        }
        const num = (0,flac_misc/* readCodedNumber */.X7)(slice);
        const blockSize = (0,flac_misc/* readBlockSize */.f6)(slice, blockSizeOrUncommon);
        const sampleRate = (0,flac_misc/* readSampleRate */.Ld)(slice, sampleRateOrUncommon);
        if (sampleRate === null) {
            // This cannot be a valid FLAC frame, the syncword was just coincidental
            return null;
        }
        if (sampleRate !== this.audioInfo.sampleRate) {
            // This cannot be a valid FLAC frame, the sample rate is not the same as in the stream info
            return null;
        }
        const size = slice.filePos - startOffset;
        const crc = (0,src_reader/* readU8 */.eo)(slice);
        slice.skip(-size);
        slice.skip(-1);
        const crcCalculated = (0,flac_misc/* calculateCrc8 */.Be)((0,src_reader/* readBytes */.io)(slice, size));
        if (crc !== crcCalculated) {
            // Maybe this wasn't a FLAC frame at all, the syncword was just coincidentally
            // in the bitstream
            return null;
        }
        return { num, blockSize, sampleRate };
    }
    async advanceReader() {
        await this.readMetadata();
        (0,misc/* assert */.vA)(this.lastLoadedPos !== null);
        (0,misc/* assert */.vA)(this.audioInfo);
        const startPos = this.lastLoadedPos;
        const frame = await this.readNextFlacFrame({
            startPos,
            isFirstPacket: this.loadedSamples.length === 0,
        });
        if (!frame) {
            // Unexpected case, failed to read next FLAC frame
            // handling gracefully
            this.lastSampleLoaded = true;
            return;
        }
        const lastSample = this.loadedSamples[this.loadedSamples.length - 1];
        const blockOffset = lastSample
            ? lastSample.blockOffset + lastSample.blockSize
            : 0;
        const sample = {
            blockOffset,
            blockSize: frame.blockSize,
            byteOffset: startPos,
            byteSize: frame.size,
        };
        this.lastLoadedPos = this.lastLoadedPos + frame.size;
        this.loadedSamples.push(sample);
        if (frame.isLastFrame) {
            this.lastSampleLoaded = true;
            return;
        }
    }
}
class FlacAudioTrackBacking {
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
        return 'flac';
    }
    getInternalCodecId() {
        return null;
    }
    getNumberOfChannels() {
        (0,misc/* assert */.vA)(this.demuxer.audioInfo);
        return this.demuxer.audioInfo.numberOfChannels;
    }
    getSampleRate() {
        (0,misc/* assert */.vA)(this.demuxer.audioInfo);
        return this.demuxer.audioInfo.sampleRate;
    }
    getName() {
        return null;
    }
    getLanguageCode() {
        return misc/* UNDETERMINED_LANGUAGE */.IR;
    }
    getTimeResolution() {
        (0,misc/* assert */.vA)(this.demuxer.audioInfo);
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
        (0,misc/* assert */.vA)(this.demuxer.audioInfo);
        if (this.demuxer.audioInfo.totalSamples === 0) {
            return null;
        }
        return this.demuxer.audioInfo.totalSamples / this.demuxer.audioInfo.sampleRate;
    }
    async getLiveRefreshInterval() {
        return null;
    }
    getDisposition() {
        return {
            ...metadata/* DEFAULT_TRACK_DISPOSITION */.gM,
        };
    }
    async getDecoderConfig() {
        (0,misc/* assert */.vA)(this.demuxer.audioInfo);
        return {
            codec: 'flac',
            numberOfChannels: this.demuxer.audioInfo.numberOfChannels,
            sampleRate: this.demuxer.audioInfo.sampleRate,
            description: this.demuxer.audioInfo.description,
        };
    }
    async getPacket(timestamp, options) {
        (0,misc/* assert */.vA)(this.demuxer.audioInfo);
        if (timestamp < 0) {
            throw new Error('Timestamp cannot be negative');
        }
        const release = await this.demuxer.readingMutex.acquire();
        try {
            while (true) {
                const packetIndex = (0,misc/* binarySearchLessOrEqual */.eE)(this.demuxer.loadedSamples, timestamp, x => x.blockOffset / this.demuxer.audioInfo.sampleRate);
                if (packetIndex === -1) {
                    await this.demuxer.advanceReader();
                    continue;
                }
                const packet = this.demuxer.loadedSamples[packetIndex];
                const sampleTimestamp = packet.blockOffset / this.demuxer.audioInfo.sampleRate;
                const sampleDuration = packet.blockSize / this.demuxer.audioInfo.sampleRate;
                if (sampleTimestamp + sampleDuration <= timestamp) {
                    if (this.demuxer.lastSampleLoaded) {
                        return this.getPacketAtIndex(this.demuxer.loadedSamples.length - 1, options);
                    }
                    await this.demuxer.advanceReader();
                    continue;
                }
                return this.getPacketAtIndex(packetIndex, options);
            }
        }
        finally {
            release();
        }
    }
    async getNextPacket(packet, options) {
        const release = await this.demuxer.readingMutex.acquire();
        try {
            const nextIndex = packet.sequenceNumber + 1;
            if (this.demuxer.lastSampleLoaded
                && nextIndex >= this.demuxer.loadedSamples.length) {
                return null;
            }
            // Ensure the next sample exists
            while (nextIndex >= this.demuxer.loadedSamples.length
                && !this.demuxer.lastSampleLoaded) {
                await this.demuxer.advanceReader();
            }
            return this.getPacketAtIndex(nextIndex, options);
        }
        finally {
            release();
        }
    }
    getKeyPacket(timestamp, options) {
        return this.getPacket(timestamp, options);
    }
    getNextKeyPacket(packet, options) {
        return this.getNextPacket(packet, options);
    }
    async getPacketAtIndex(sampleIndex, options) {
        const rawSample = this.demuxer.loadedSamples[sampleIndex];
        if (!rawSample) {
            return null;
        }
        let data;
        if (options.metadataOnly) {
            data = src_packet/* PLACEHOLDER_DATA */.T;
        }
        else {
            let slice = this.demuxer.reader.requestSlice(rawSample.byteOffset, rawSample.byteSize);
            if (slice instanceof Promise)
                slice = await slice;
            if (!slice) {
                return null; // Data didn't fit into the rest of the file
            }
            data = (0,src_reader/* readBytes */.io)(slice, rawSample.byteSize);
        }
        (0,misc/* assert */.vA)(this.demuxer.audioInfo);
        const timestamp = rawSample.blockOffset / this.demuxer.audioInfo.sampleRate;
        const duration = rawSample.blockSize / this.demuxer.audioInfo.sampleRate;
        return new src_packet/* EncodedPacket */.Z(data, 'key', timestamp, duration, sampleIndex, rawSample.byteSize);
    }
    async getFirstPacket(options) {
        // Ensure the next sample exists
        while (this.demuxer.loadedSamples.length === 0
            && !this.demuxer.lastSampleLoaded) {
            await this.demuxer.advanceReader();
        }
        return this.getPacketAtIndex(0, options);
    }
}

// EXTERNAL MODULE: ./node_modules/mediabunny/dist/modules/src/mpeg-ts/mpeg-ts-misc.js
var mpeg_ts_misc = __webpack_require__(2490);
;// ./node_modules/mediabunny/dist/modules/src/mpeg-ts/mpeg-ts-demuxer.js
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */














// Resources:
// ISO/IEC 13818-1
const MISSING_PTS_ERROR_MESSAGE = 'PES packet is missing PTS where it was expected. PES packets without PTS are not'
    + ' currently supported. If you think this file should be supported, please report it.';
// Remember them so the warning doesn't get spammed
const ignoredStreamTypes = new Set();
class MpegTsDemuxer extends demuxer/* Demuxer */.B {
    constructor(input) {
        super(input);
        this.metadataPromise = null;
        this.elementaryStreams = [];
        this.trackBackingEntries = [];
        this.packetOffset = 0;
        this.packetStride = -1;
        this.sectionEndPositions = [];
        this.seekChunkSize = 5 * 1024 * 1024; // 5 MiB, picked because most HLS segments are below this size
        this.minReferencePointByteDistance = -1;
        this.reader = input._reader;
    }
    async readMetadata() {
        return this.metadataPromise ??= (async () => {
            const lengthToCheck = mpeg_ts_misc/* TS_PACKET_SIZE */.ZT + 16 + 1;
            let startingSlice = this.reader.requestSlice(0, lengthToCheck);
            if (startingSlice instanceof Promise)
                startingSlice = await startingSlice;
            (0,misc/* assert */.vA)(startingSlice);
            const startingBytes = (0,src_reader/* readBytes */.io)(startingSlice, lengthToCheck);
            if (startingBytes[0] === 0x47 && startingBytes[mpeg_ts_misc/* TS_PACKET_SIZE */.ZT] === 0x47) {
                // Regular MPEG-TS
                this.packetOffset = 0;
                this.packetStride = mpeg_ts_misc/* TS_PACKET_SIZE */.ZT;
            }
            else if (startingBytes[0] === 0x47 && startingBytes[mpeg_ts_misc/* TS_PACKET_SIZE */.ZT + 16] === 0x47) {
                // MPEG-TS with Forward Error Correction
                this.packetOffset = 0;
                this.packetStride = mpeg_ts_misc/* TS_PACKET_SIZE */.ZT + 16;
            }
            else if (startingBytes[4] === 0x47 && startingBytes[4 + mpeg_ts_misc/* TS_PACKET_SIZE */.ZT + 4] === 0x47) {
                // MPEG-2-TS (DVHS)
                this.packetOffset = 4;
                this.packetStride = mpeg_ts_misc/* TS_PACKET_SIZE */.ZT + 4;
            }
            else {
                throw new Error('Unreachable.');
            }
            const MIN_REFERENCE_POINT_PACKET_DISTANCE = 256;
            this.minReferencePointByteDistance = MIN_REFERENCE_POINT_PACKET_DISTANCE * this.packetStride;
            let currentPos = this.packetOffset;
            let programMapPid = null;
            // Some files contain these multiple times, but we only care about their first appearance
            let hasProgramAssociationTable = false;
            let hasProgramMap = false;
            while (true) {
                const packetHeader = await this.readPacketHeader(currentPos);
                if (!packetHeader) {
                    break;
                }
                if (packetHeader.payloadUnitStartIndicator === 0) {
                    // Not the start of a section
                    currentPos += this.packetStride;
                    continue;
                }
                const section = await this.readSection(currentPos, true, !hasProgramMap);
                if (!section) {
                    break;
                }
                const BYTES_BEFORE_SECTION_LENGTH = 3;
                const BITS_IN_CRC_32 = 32; // Duh
                // Some streams don't contain a PAT for some reason, so we must do some guesswork to figure out where
                // the PMT is.
                let isProbablyProgramMap = false;
                if (!hasProgramMap && section.pid !== 0) {
                    const isPesPacket = section.payload[0] === 0x00 && section.payload[1] === 0x00 && section.payload[2] === 0x01;
                    if (!isPesPacket) {
                        // Assume it's a PSI
                        const bitstream = new shared_bitstream/* Bitstream */._(section.payload);
                        const pointerField = bitstream.readAlignedByte();
                        bitstream.skipBits(8 * pointerField);
                        const tableId = bitstream.readBits(8);
                        isProbablyProgramMap = tableId === 0x02; // 0x02 == TS_program_map_section
                    }
                }
                if (section.pid === 0 && !hasProgramAssociationTable) {
                    const bitstream = new shared_bitstream/* Bitstream */._(section.payload);
                    const pointerField = bitstream.readAlignedByte();
                    bitstream.skipBits(8 * pointerField);
                    bitstream.skipBits(14);
                    const sectionLength = bitstream.readBits(10);
                    bitstream.skipBits(40);
                    while (8 * (sectionLength + BYTES_BEFORE_SECTION_LENGTH) - bitstream.pos > BITS_IN_CRC_32) {
                        const programNumber = bitstream.readBits(16);
                        bitstream.skipBits(3); // Reserved
                        const id = bitstream.readBits(13);
                        if (programNumber !== 0) {
                            if (programMapPid !== null) {
                                throw new Error('Only files with a single program are supported.');
                            }
                            else {
                                programMapPid = id;
                            }
                        }
                    }
                    if (programMapPid === null) {
                        throw new Error('Program Association Table must link to a Program Map Table.');
                    }
                    hasProgramAssociationTable = true;
                }
                else if ((section.pid === programMapPid || isProbablyProgramMap) && !hasProgramMap) {
                    const bitstream = new shared_bitstream/* Bitstream */._(section.payload);
                    const pointerField = bitstream.readAlignedByte();
                    bitstream.skipBits(8 * pointerField);
                    bitstream.skipBits(12);
                    const sectionLength = bitstream.readBits(12);
                    bitstream.skipBits(43);
                    // eslint-disable-next-line @typescript-eslint/no-unused-vars
                    const pcrPid = bitstream.readBits(13);
                    bitstream.skipBits(6);
                    // "The remaining 10 bits specify the number of bytes of the descriptors immediately following the
                    // program_info_length field"
                    const programInfoLength = bitstream.readBits(10);
                    bitstream.skipBits(8 * programInfoLength);
                    while (8 * (sectionLength + BYTES_BEFORE_SECTION_LENGTH) - bitstream.pos > BITS_IN_CRC_32) {
                        const streamType = bitstream.readBits(8);
                        bitstream.skipBits(3);
                        const elementaryPid = bitstream.readBits(13);
                        bitstream.skipBits(6);
                        const esInfoLength = bitstream.readBits(10);
                        // Check ES descriptors to detect AC-3/E-AC-3 in System B
                        const esInfoEndPos = bitstream.pos + 8 * esInfoLength;
                        let hasAc3Descriptor = false;
                        let hasEac3Descriptor = false;
                        while (bitstream.pos < esInfoEndPos) {
                            const descriptorTag = bitstream.readBits(8);
                            const descriptorLength = bitstream.readBits(8);
                            if (descriptorTag === 0x6a) {
                                hasAc3Descriptor = true;
                            }
                            else if (descriptorTag === 0x7a || descriptorTag === 0xcc) {
                                hasEac3Descriptor = true;
                            }
                            bitstream.skipBits(8 * descriptorLength);
                        }
                        let info = null;
                        switch (streamType) {
                            case 27 /* MpegTsStreamType.AVC */:
                            case 36 /* MpegTsStreamType.HEVC */:
                                {
                                    const codec = streamType === 27 /* MpegTsStreamType.AVC */ ? 'avc' : 'hevc';
                                    info = {
                                        type: 'video',
                                        codec,
                                        decoderConfig: null,
                                        avcCodecInfo: null,
                                        hevcCodecInfo: null,
                                        colorSpace: {
                                            primaries: null,
                                            transfer: null,
                                            matrix: null,
                                            fullRange: null,
                                        },
                                        width: -1,
                                        height: -1,
                                        squarePixelWidth: -1,
                                        squarePixelHeight: -1,
                                        reorderSize: -1,
                                    };
                                }
                                ;
                                break;
                            case 3 /* MpegTsStreamType.MP3_MPEG1 */:
                            case 4 /* MpegTsStreamType.MP3_MPEG2 */:
                            case 15 /* MpegTsStreamType.AAC */:
                            case 129 /* MpegTsStreamType.AC3_SYSTEM_A */:
                            case 135 /* MpegTsStreamType.EAC3_SYSTEM_A */:
                                {
                                    let codec;
                                    if (streamType === 3 /* MpegTsStreamType.MP3_MPEG1 */
                                        || streamType === 4 /* MpegTsStreamType.MP3_MPEG2 */) {
                                        codec = 'mp3';
                                    }
                                    else if (streamType === 15 /* MpegTsStreamType.AAC */) {
                                        codec = 'aac';
                                    }
                                    else if (streamType === 129 /* MpegTsStreamType.AC3_SYSTEM_A */) {
                                        codec = 'ac3';
                                    }
                                    else if (streamType === 135 /* MpegTsStreamType.EAC3_SYSTEM_A */) {
                                        codec = 'eac3';
                                    }
                                    else {
                                        throw new Error('Unreachable.');
                                    }
                                    info = {
                                        type: 'audio',
                                        codec,
                                        decoderConfig: null,
                                        aacCodecInfo: null,
                                        numberOfChannels: -1,
                                        sampleRate: -1,
                                    };
                                }
                                ;
                                break;
                            case 6 /* MpegTsStreamType.PRIVATE_DATA */:
                                {
                                    if (hasEac3Descriptor) {
                                        info = {
                                            type: 'audio',
                                            codec: 'eac3',
                                            decoderConfig: null,
                                            aacCodecInfo: null,
                                            numberOfChannels: -1,
                                            sampleRate: -1,
                                        };
                                    }
                                    else if (hasAc3Descriptor) {
                                        info = {
                                            type: 'audio',
                                            codec: 'ac3',
                                            decoderConfig: null,
                                            aacCodecInfo: null,
                                            numberOfChannels: -1,
                                            sampleRate: -1,
                                        };
                                    }
                                }
                                ;
                                break;
                            default: {
                                // If we don't recognize the codec, we don't surface the track at all. This is because
                                // we can't determine its metadata and also have no idea how to packetize its data.
                                if (!ignoredStreamTypes.has(streamType)) {
                                    console.warn(`Note: MPEG-TS streams with stream_type 0x${streamType.toString(16)} are not`
                                        + ` currently supported.`);
                                    ignoredStreamTypes.add(streamType);
                                }
                            }
                        }
                        if (info) {
                            this.elementaryStreams.push({
                                demuxer: this,
                                pid: elementaryPid,
                                streamType,
                                initialized: false,
                                firstSection: null,
                                canBeTrustedWithKeyPackets: false,
                                info,
                                referencePesPackets: [],
                            });
                        }
                    }
                    hasProgramMap = true;
                }
                else {
                    const elementaryStream = this.elementaryStreams.find(x => x.pid === section.pid);
                    outer: if (elementaryStream && !elementaryStream.initialized) {
                        const pesPacket = readPesPacket(section, true);
                        if (!pesPacket) {
                            throw new Error(`Couldn't read first PES packet for Elementary Stream with PID ${elementaryStream.pid}`);
                        }
                        elementaryStream.firstSection = section;
                        elementaryStream.canBeTrustedWithKeyPackets = section.randomAccessIndicator === 1;
                        if (this.input._initInput) {
                            const initDemuxer = (await this.input._initInput._getDemuxer());
                            const matchingStream = initDemuxer.elementaryStreams.find(x => (x.pid === section.pid && x.info.codec === elementaryStream.info.codec));
                            if (matchingStream) {
                                elementaryStream.info = matchingStream.info;
                                elementaryStream.initialized = true;
                                break outer; // We have the stream info, we're done
                            }
                        }
                        const context = new PacketReadingContext(elementaryStream, pesPacket);
                        if (elementaryStream.info.type === 'video') {
                            // We loop because in some files, the video parameters are not in the first packet
                            while (true) {
                                const contextAlias = context; // TyyyyypeScript 😩
                                contextAlias.suppliedPacket = null;
                                await context.markNextPacket();
                                if (elementaryStream.info.codec === 'avc') {
                                    if (!context.suppliedPacket) {
                                        throw new Error('Invalid AVC video stream; could not extract AVCDecoderConfigurationRecord'
                                            + ' from any packet.');
                                    }
                                    elementaryStream.info.avcCodecInfo
                                        = (0,codec_data/* extractAvcDecoderConfigurationRecord */.fH)(context.suppliedPacket.data);
                                    if (!elementaryStream.info.avcCodecInfo) {
                                        continue; // Search the next packet for it
                                    }
                                    const spsUnit = elementaryStream.info.avcCodecInfo.sequenceParameterSets[0];
                                    (0,misc/* assert */.vA)(spsUnit);
                                    const spsInfo = (0,codec_data/* parseAvcSps */.eM)(spsUnit);
                                    elementaryStream.info.width = spsInfo.displayWidth;
                                    elementaryStream.info.height = spsInfo.displayHeight;
                                    if (spsInfo.pixelAspectRatio.num > spsInfo.pixelAspectRatio.den) {
                                        elementaryStream.info.squarePixelWidth = Math.round(elementaryStream.info.width
                                            * spsInfo.pixelAspectRatio.num / spsInfo.pixelAspectRatio.den);
                                        elementaryStream.info.squarePixelHeight = elementaryStream.info.height;
                                    }
                                    else {
                                        elementaryStream.info.squarePixelWidth = elementaryStream.info.width;
                                        elementaryStream.info.squarePixelHeight = Math.round(elementaryStream.info.height
                                            * spsInfo.pixelAspectRatio.den / spsInfo.pixelAspectRatio.num);
                                    }
                                    elementaryStream.info.colorSpace = {
                                        primaries: misc/* COLOR_PRIMARIES_MAP_INVERSE */.BL[spsInfo.colourPrimaries],
                                        transfer: misc/* TRANSFER_CHARACTERISTICS_MAP_INVERSE */.x_[spsInfo.transferCharacteristics],
                                        matrix: misc/* MATRIX_COEFFICIENTS_MAP_INVERSE */.fl[spsInfo.matrixCoefficients],
                                        fullRange: !!spsInfo.fullRangeFlag,
                                    };
                                    elementaryStream.info.reorderSize = spsInfo.maxDecFrameBuffering;
                                    break;
                                }
                                else if (elementaryStream.info.codec === 'hevc') {
                                    if (!context.suppliedPacket) {
                                        throw new Error('Invalid HEVC video stream; could not extract HVCDecoderConfigurationRecord'
                                            + ' from first packet.');
                                    }
                                    elementaryStream.info.hevcCodecInfo
                                        = (0,codec_data/* extractHevcDecoderConfigurationRecord */.D5)(context.suppliedPacket.data);
                                    if (!elementaryStream.info.hevcCodecInfo) {
                                        continue; // Search the next packet for it
                                    }
                                    const spsArray = elementaryStream.info.hevcCodecInfo.arrays.find(a => a.nalUnitType === codec_data/* HevcNalUnitType */.iJ.SPS_NUT);
                                    const spsUnit = spsArray.nalUnits[0];
                                    (0,misc/* assert */.vA)(spsUnit);
                                    const spsInfo = (0,codec_data/* parseHevcSps */.gT)(spsUnit);
                                    elementaryStream.info.width = spsInfo.displayWidth;
                                    elementaryStream.info.height = spsInfo.displayHeight;
                                    if (spsInfo.pixelAspectRatio.num > spsInfo.pixelAspectRatio.den) {
                                        elementaryStream.info.squarePixelWidth = Math.round(elementaryStream.info.width
                                            * spsInfo.pixelAspectRatio.num / spsInfo.pixelAspectRatio.den);
                                        elementaryStream.info.squarePixelHeight = elementaryStream.info.height;
                                    }
                                    else {
                                        elementaryStream.info.squarePixelWidth = elementaryStream.info.width;
                                        elementaryStream.info.squarePixelHeight = Math.round(elementaryStream.info.height
                                            * spsInfo.pixelAspectRatio.den / spsInfo.pixelAspectRatio.num);
                                    }
                                    elementaryStream.info.colorSpace = {
                                        primaries: misc/* COLOR_PRIMARIES_MAP_INVERSE */.BL[spsInfo.colourPrimaries],
                                        transfer: misc/* TRANSFER_CHARACTERISTICS_MAP_INVERSE */.x_[spsInfo.transferCharacteristics],
                                        matrix: misc/* MATRIX_COEFFICIENTS_MAP_INVERSE */.fl[spsInfo.matrixCoefficients],
                                        fullRange: !!spsInfo.fullRangeFlag,
                                    };
                                    elementaryStream.info.reorderSize = spsInfo.maxDecFrameBuffering;
                                    break;
                                }
                                else {
                                    throw new Error('Unhandled.');
                                }
                            }
                            elementaryStream.info.decoderConfig = {
                                codec: (0,codec/* extractVideoCodecString */.QP)({
                                    width: elementaryStream.info.width,
                                    height: elementaryStream.info.height,
                                    codec: elementaryStream.info.codec,
                                    codecDescription: null,
                                    colorSpace: elementaryStream.info.colorSpace,
                                    avcType: 1,
                                    avcCodecInfo: elementaryStream.info.avcCodecInfo,
                                    hevcCodecInfo: elementaryStream.info.hevcCodecInfo,
                                    vp9CodecInfo: null,
                                    av1CodecInfo: null,
                                }),
                                codedWidth: elementaryStream.info.width,
                                codedHeight: elementaryStream.info.height,
                                colorSpace: elementaryStream.info.colorSpace,
                            };
                            if (elementaryStream.info.width !== elementaryStream.info.squarePixelWidth
                                || elementaryStream.info.height !== elementaryStream.info.squarePixelHeight) {
                                elementaryStream.info.decoderConfig.displayAspectWidth
                                    = elementaryStream.info.squarePixelWidth;
                                elementaryStream.info.decoderConfig.displayAspectHeight
                                    = elementaryStream.info.squarePixelHeight;
                            }
                            elementaryStream.initialized = true;
                        }
                        else {
                            await context.markNextPacket();
                            if (!context.suppliedPacket) {
                                throw new Error(`Couldn't parse first media packet for Elementary Stream with`
                                    + ` PID ${elementaryStream.pid}`);
                            }
                            if (elementaryStream.info.codec === 'aac') {
                                const slice = src_reader/* FileSlice */.x$.tempFromBytes(context.suppliedPacket.data);
                                const header = (0,adts_reader/* readAdtsFrameHeader */.lh)(slice);
                                if (!header) {
                                    throw new Error('Invalid AAC audio stream; could not read ADTS frame header from first packet.');
                                }
                                elementaryStream.info.aacCodecInfo = {
                                    isMpeg2: false,
                                    objectType: header.objectType,
                                };
                                elementaryStream.info.numberOfChannels
                                    = aac_misc/* aacChannelMap */.Ti[header.channelConfiguration];
                                elementaryStream.info.sampleRate
                                    = aac_misc/* aacFrequencyTable */.Im[header.samplingFrequencyIndex];
                            }
                            else if (elementaryStream.info.codec === 'mp3') {
                                const word = (0,src_reader/* readU32Be */.cN)(src_reader/* FileSlice */.x$.tempFromBytes(context.suppliedPacket.data));
                                const result = (0,mp3_misc/* readMp3FrameHeader */.P8)(word, context.suppliedPacket.data.byteLength);
                                if (!result.header) {
                                    throw new Error('Invalid MP3 audio stream; could not read frame header from first packet.');
                                }
                                elementaryStream.info.numberOfChannels = result.header.channel === 3 ? 1 : 2;
                                elementaryStream.info.sampleRate = result.header.sampleRate;
                            }
                            else if (elementaryStream.info.codec === 'ac3') {
                                const frameInfo = (0,codec_data/* parseAc3SyncFrame */.LM)(context.suppliedPacket.data);
                                if (!frameInfo) {
                                    throw new Error('Invalid AC-3 audio stream; could not read sync frame from first packet.');
                                }
                                if (frameInfo.fscod === 3) {
                                    throw new Error('Invalid AC-3 audio stream; reserved sample rate code found in first packet.');
                                }
                                elementaryStream.info.numberOfChannels
                                    = codec_data/* AC3_ACMOD_CHANNEL_COUNTS */.ux[frameInfo.acmod] + frameInfo.lfeon;
                                elementaryStream.info.sampleRate = ac3_misc/* AC3_SAMPLE_RATES */.N[frameInfo.fscod];
                            }
                            else if (elementaryStream.info.codec === 'eac3') {
                                const frameInfo = (0,codec_data/* parseEac3SyncFrame */.oL)(context.suppliedPacket.data);
                                if (!frameInfo) {
                                    throw new Error('Invalid E-AC-3 audio stream; could not read sync frame from first packet.');
                                }
                                const sampleRate = (0,codec_data/* getEac3SampleRate */.PK)(frameInfo);
                                if (sampleRate === null) {
                                    throw new Error('Invalid E-AC-3 audio stream; reserved sample rate code found in first packet.');
                                }
                                elementaryStream.info.numberOfChannels = (0,codec_data/* getEac3ChannelCount */.zV)(frameInfo);
                                elementaryStream.info.sampleRate = sampleRate;
                            }
                            else {
                                throw new Error('Unhandled.');
                            }
                            elementaryStream.info.decoderConfig = {
                                codec: (0,codec/* extractAudioCodecString */.X0)({
                                    codec: elementaryStream.info.codec,
                                    codecDescription: null,
                                    aacCodecInfo: elementaryStream.info.aacCodecInfo,
                                }),
                                numberOfChannels: elementaryStream.info.numberOfChannels,
                                sampleRate: elementaryStream.info.sampleRate,
                            };
                            elementaryStream.initialized = true;
                        }
                    }
                }
                const isDone = hasProgramMap && this.elementaryStreams.every(x => x.initialized);
                if (isDone) {
                    break;
                }
                currentPos += this.packetStride;
            }
            if (!hasProgramMap) {
                if (!hasProgramAssociationTable) {
                    throw new Error('No Program Association Table found in the file.');
                }
                throw new Error('No Program Map Table found in the file.');
            }
            for (const stream of this.elementaryStreams) {
                if (stream.info.type === 'video') {
                    this.trackBackingEntries.push(new MpegTsVideoTrackBacking(stream));
                }
                else {
                    this.trackBackingEntries.push(new MpegTsAudioTrackBacking(stream));
                }
            }
        })();
    }
    async getTrackBackings() {
        await this.readMetadata();
        return this.trackBackingEntries;
    }
    async getMetadataTags() {
        return {}; // Nothing for now
    }
    async getMimeType() {
        await this.readMetadata();
        const codecStrings = await Promise.all(this.trackBackingEntries.map(x => x.getDecoderConfig().then(c => c?.codec ?? null)));
        return (0,mpeg_ts_misc/* buildMpegTsMimeType */.Vx)(codecStrings);
    }
    async readSection(startPos, full, contiguous = false) {
        let endPos = startPos;
        let currentPos = startPos;
        const chunks = [];
        let chunksByteLength = 0;
        let firstPacket = null;
        let mustAddSectionEnd = true;
        let randomAccessIndicator = 0;
        while (true) {
            const packet = await this.readPacket(currentPos);
            currentPos += this.packetStride;
            if (!packet) {
                break;
            }
            if (!firstPacket) {
                if (packet.payloadUnitStartIndicator === 0) {
                    break;
                }
                firstPacket = packet;
            }
            else {
                if (packet.pid !== firstPacket.pid) {
                    if (contiguous) {
                        break; // End of section
                    }
                    else {
                        continue; // Ignore this packet
                    }
                }
                if (packet.payloadUnitStartIndicator === 1) {
                    break;
                }
            }
            const hasAdaptationField = !!(packet.adaptationFieldControl & 0b10);
            const hasPayload = !!(packet.adaptationFieldControl & 0b01);
            let adaptationFieldLength = 0;
            if (hasAdaptationField) {
                adaptationFieldLength = 1 + packet.body[0];
                // Extract random_access_indicator from first packet's adaptation field
                if (packet === firstPacket && adaptationFieldLength > 1) {
                    randomAccessIndicator = (packet.body[1] >> 6) & 1;
                }
            }
            if (hasPayload) {
                if (adaptationFieldLength === 0) {
                    chunks.push(packet.body);
                    chunksByteLength += packet.body.byteLength;
                }
                else {
                    chunks.push(packet.body.subarray(adaptationFieldLength));
                    chunksByteLength += packet.body.byteLength - adaptationFieldLength;
                }
            }
            endPos = currentPos;
            // 64 is just "a bit of data", enough for the PES packet header
            if (!full && chunksByteLength >= 64) {
                mustAddSectionEnd = false; // Not the actual section end
                break;
            }
            // Check if we already know this is a section end
            const isKnownSectionEnd = (0,misc/* binarySearchExact */.pl)(this.sectionEndPositions, endPos, x => x) !== -1;
            if (isKnownSectionEnd) {
                mustAddSectionEnd = false;
                break;
            }
        }
        if (mustAddSectionEnd) {
            const index = (0,misc/* binarySearchLessOrEqual */.eE)(this.sectionEndPositions, endPos, x => x);
            this.sectionEndPositions.splice(index + 1, 0, endPos);
        }
        if (!firstPacket) {
            return null;
        }
        let merged;
        if (chunks.length === 1) {
            merged = chunks[0];
        }
        else {
            const totalLength = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
            merged = new Uint8Array(totalLength);
            let offset = 0;
            for (const chunk of chunks) {
                merged.set(chunk, offset);
                offset += chunk.length;
            }
        }
        return {
            startPos,
            endPos: full ? endPos : null,
            pid: firstPacket.pid,
            payload: merged,
            randomAccessIndicator,
        };
    }
    async readPacketHeader(pos) {
        let slice = this.reader.requestSlice(pos, 4);
        if (slice instanceof Promise)
            slice = await slice;
        if (!slice) {
            return null;
        }
        const syncByte = (0,src_reader/* readU8 */.eo)(slice);
        if (syncByte !== 0x47) {
            throw new Error('Invalid TS packet sync byte. Likely an internal bug, please report this file.');
        }
        const nextTwoBytes = (0,src_reader/* readU16Be */.mH)(slice);
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        const transportErrorIndicator = nextTwoBytes >> 15;
        const payloadUnitStartIndicator = (nextTwoBytes >> 14) & 0x1;
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        const transportPriority = (nextTwoBytes >> 13) & 0x1;
        const pid = nextTwoBytes & 0x1FFF;
        const nextByte = (0,src_reader/* readU8 */.eo)(slice);
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        const transportScramblingControl = nextByte >> 6;
        const adaptationFieldControl = (nextByte >> 4) & 0x3;
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        const continuityCounter = nextByte & 0xF;
        return {
            payloadUnitStartIndicator,
            pid,
            adaptationFieldControl,
        };
    }
    async readPacket(pos) {
        // Code in here is duplicated from readPacketHeader for performance reasons
        let slice = this.reader.requestSlice(pos, mpeg_ts_misc/* TS_PACKET_SIZE */.ZT);
        if (slice instanceof Promise)
            slice = await slice;
        if (!slice) {
            return null;
        }
        const bytes = (0,src_reader/* readBytes */.io)(slice, mpeg_ts_misc/* TS_PACKET_SIZE */.ZT);
        const syncByte = bytes[0];
        if (syncByte !== 0x47) {
            throw new Error('Invalid TS packet sync byte. Likely an internal bug, please report this file.');
        }
        const nextTwoBytes = (bytes[1] << 8) + bytes[2];
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        const transportErrorIndicator = nextTwoBytes >> 15;
        const payloadUnitStartIndicator = (nextTwoBytes >> 14) & 0x1;
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        const transportPriority = (nextTwoBytes >> 13) & 0x1;
        const pid = nextTwoBytes & 0x1FFF;
        const nextByte = bytes[3];
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        const transportScramblingControl = nextByte >> 6;
        const adaptationFieldControl = (nextByte >> 4) & 0x3;
        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        const continuityCounter = nextByte & 0xF;
        return {
            payloadUnitStartIndicator,
            pid,
            adaptationFieldControl,
            body: bytes.subarray(4),
        };
    }
}
const readPesPacketHeader = (section, expectPts) => {
    if (section.payload.byteLength < 3) {
        return null;
    }
    const bitstream = new shared_bitstream/* Bitstream */._(section.payload);
    const startCodePrefix = bitstream.readBits(24);
    if (startCodePrefix !== 0x000001) {
        return null;
    }
    const streamId = bitstream.readBits(8);
    bitstream.skipBits(16);
    if (streamId === 0b10111100 // program_stream_map
        || streamId === 0b10111110 // padding_stream
        || streamId === 0b10111111 // private_stream_2
        || streamId === 0b11110000 // ECM
        || streamId === 0b11110001 // EMM
        || streamId === 0b11111111 // program_stream_directory
        || streamId === 0b11110010 // DSMCC_stream
        || streamId === 0b11111000 // ITU-T Rec. H.222.1 type E stream
    ) {
        return null;
    }
    bitstream.skipBits(8);
    const ptsDtsFlags = bitstream.readBits(2);
    bitstream.skipBits(14);
    let pts = null;
    if (ptsDtsFlags === 0b10 || ptsDtsFlags === 0b11) {
        pts = 0;
        bitstream.skipBits(4);
        pts += bitstream.readBits(3) * (1 << 30);
        bitstream.skipBits(1);
        pts += bitstream.readBits(15) * (1 << 15);
        bitstream.skipBits(1);
        pts += bitstream.readBits(15);
    }
    else {
        if (expectPts) {
            throw new Error(MISSING_PTS_ERROR_MESSAGE);
        }
    }
    return {
        sectionStartPos: section.startPos,
        sectionEndPos: section.endPos,
        pts,
        randomAccessIndicator: section.randomAccessIndicator,
    };
};
const readPesPacket = (section, expectPts) => {
    (0,misc/* assert */.vA)(section.endPos !== null); // Can only read full PES packets from fully read sections
    const header = readPesPacketHeader(section, expectPts);
    if (!header) {
        return null;
    }
    const bitstream = new shared_bitstream/* Bitstream */._(section.payload);
    bitstream.skipBits(32);
    const pesPacketLength = bitstream.readBits(16);
    const BYTES_UNTIL_END_OF_PES_PACKET_LENGTH = 6;
    bitstream.skipBits(16);
    const pesHeaderDataLength = bitstream.readBits(8);
    const pesHeaderEndPos = bitstream.pos + 8 * pesHeaderDataLength;
    bitstream.pos = pesHeaderEndPos;
    const bytePos = pesHeaderEndPos / 8;
    (0,misc/* assert */.vA)(Number.isInteger(bytePos));
    const data = section.payload.subarray(bytePos, 
    // "A value of 0 indicates that the PES packet length is neither specified nor bounded and is allowed only in
    // PES packets whose payload consists of bytes from a video elementary stream contained in
    // transport stream packets."
    pesPacketLength > 0
        ? BYTES_UNTIL_END_OF_PES_PACKET_LENGTH + pesPacketLength
        : section.payload.byteLength);
    return {
        ...header,
        data,
    };
};
class MpegTsTrackBacking {
    constructor(elementaryStream) {
        this.elementaryStream = elementaryStream;
        this.packetBuffers = new WeakMap();
        /** Used for recreating PacketBuffers if necessary. */
        this.packetSectionStarts = new WeakMap();
    }
    getId() {
        return this.elementaryStream.pid;
    }
    getNumber() {
        const demuxer = this.elementaryStream.demuxer;
        const trackType = this.elementaryStream.info.type;
        let number = 0;
        for (const backing of demuxer.trackBackingEntries) {
            if (backing.getType() === trackType) {
                number++;
            }
            (0,misc/* assert */.vA)(backing instanceof MpegTsTrackBacking);
            if (backing.elementaryStream === this.elementaryStream) {
                break;
            }
        }
        return number;
    }
    getCodec() {
        throw new Error('Not implemented on base class.');
    }
    getInternalCodecId() {
        return this.elementaryStream.streamType;
    }
    getName() {
        return null;
    }
    getLanguageCode() {
        return misc/* UNDETERMINED_LANGUAGE */.IR;
    }
    getDisposition() {
        return {
            ...metadata/* DEFAULT_TRACK_DISPOSITION */.gM,
            primary: false,
        };
    }
    getTimeResolution() {
        return mpeg_ts_misc/* TIMESCALE */.cS;
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
        return null;
    }
    async getLiveRefreshInterval() {
        return null;
    }
    createEncodedPacket(suppliedPacket, duration, options) {
        let packetType;
        if (this.allPacketsAreKeyPackets()) {
            packetType = 'key';
        }
        else {
            packetType = suppliedPacket.randomAccessIndicator === 1
                ? 'key'
                : 'delta';
        }
        return new src_packet/* EncodedPacket */.Z(options.metadataOnly ? src_packet/* PLACEHOLDER_DATA */.T : suppliedPacket.data, packetType, suppliedPacket.pts / mpeg_ts_misc/* TIMESCALE */.cS, Math.max(duration / mpeg_ts_misc/* TIMESCALE */.cS, 0), suppliedPacket.sequenceNumber, suppliedPacket.data.byteLength);
    }
    async getFirstPacket(options) {
        const section = this.elementaryStream.firstSection;
        (0,misc/* assert */.vA)(section);
        const pesPacket = readPesPacket(section, true);
        (0,misc/* assert */.vA)(pesPacket);
        const context = new PacketReadingContext(this.elementaryStream, pesPacket);
        const buffer = new PacketBuffer(this, context);
        const result = await buffer.readNext();
        if (!result) {
            return null;
        }
        const packet = this.createEncodedPacket(result.packet, result.duration, options);
        this.packetBuffers.set(packet, buffer);
        this.packetSectionStarts.set(packet, result.packet.sectionStartPos);
        return packet;
    }
    async getNextPacket(packet, options) {
        let buffer = this.packetBuffers.get(packet);
        if (buffer) {
            // Fast path
            const result = await buffer.readNext();
            if (!result) {
                return null;
            }
            // Remove PacketBuffer access from the old packet, it belongs to the next packet now
            this.packetBuffers.delete(packet);
            const newPacket = this.createEncodedPacket(result.packet, result.duration, options);
            this.packetBuffers.set(newPacket, buffer);
            this.packetSectionStarts.set(newPacket, result.packet.sectionStartPos);
            return newPacket;
        }
        // No buffer, we gotta do some rereading
        const sectionStartPos = this.packetSectionStarts.get(packet);
        if (sectionStartPos === undefined) {
            throw new Error('Packet was not created from this track.');
        }
        const demuxer = this.elementaryStream.demuxer;
        const section = await demuxer.readSection(sectionStartPos, true);
        (0,misc/* assert */.vA)(section);
        const pesPacket = readPesPacket(section, true);
        (0,misc/* assert */.vA)(pesPacket);
        const context = new PacketReadingContext(this.elementaryStream, pesPacket);
        buffer = new PacketBuffer(this, context);
        // Advance until we pass the current packet's sequence number
        const targetSequenceNumber = packet.sequenceNumber;
        while (true) {
            const result = await buffer.readNext();
            if (!result) {
                return null;
            }
            if (result.packet.sequenceNumber > targetSequenceNumber) {
                // We found the next packet!
                const newPacket = this.createEncodedPacket(result.packet, result.duration, options);
                this.packetBuffers.set(newPacket, buffer);
                this.packetSectionStarts.set(newPacket, result.packet.sectionStartPos);
                return newPacket;
            }
        }
    }
    async getNextKeyPacket(packet, options) {
        let currentPacket = packet;
        // Just loop until we hit one
        while (true) {
            currentPacket = await this.getNextPacket(currentPacket, options);
            if (!currentPacket) {
                return null;
            }
            if (currentPacket.type === 'key') {
                return currentPacket;
            }
        }
    }
    getPacket(timestamp, options) {
        return this.doPacketLookup(timestamp, false, options);
    }
    getKeyPacket(timestamp, options) {
        return this.doPacketLookup(timestamp, true, options);
    }
    /**
     * Searches for the packet with the largest timestamp not larger than `timestamp` in the file, using a combination
     * of chunk-based binary search and linear refinement. The reason the coarse search is done in large chunks is to
     * make it more performant for small files and over high-latency readers such as the network.
     */
    async doPacketLookup(timestamp, keyframesOnly, options) {
        const searchPts = (0,misc/* roundIfAlmostInteger */.aI)(timestamp * mpeg_ts_misc/* TIMESCALE */.cS);
        const demuxer = this.elementaryStream.demuxer;
        const { reader, seekChunkSize } = demuxer;
        const pid = this.elementaryStream.pid;
        const findFirstPesPacketHeaderInChunk = async (startPos, endPos, readSectionInFull) => {
            let currentPos = startPos;
            while (currentPos < endPos) {
                const packetHeader = await demuxer.readPacketHeader(currentPos);
                if (!packetHeader) {
                    return null;
                }
                if (packetHeader.pid === pid && packetHeader.payloadUnitStartIndicator === 1) {
                    const section = await demuxer.readSection(currentPos, readSectionInFull);
                    if (!section) {
                        return null;
                    }
                    const pesPacketHeader = readPesPacketHeader(section, false);
                    if (pesPacketHeader && pesPacketHeader.pts !== null) {
                        return {
                            pesPacketHeader: pesPacketHeader,
                            section,
                        };
                    }
                }
                currentPos += demuxer.packetStride;
            }
            return null;
        };
        // Get the first PES packet of the track
        const firstSection = this.elementaryStream.firstSection;
        (0,misc/* assert */.vA)(firstSection);
        const firstPesPacketHeader = readPesPacketHeader(firstSection, true);
        (0,misc/* assert */.vA)(firstPesPacketHeader);
        if (searchPts < firstPesPacketHeader.pts) {
            // We're before the first packet, definitely nothing here
            return null;
        }
        let scanStartPos;
        const referencePesPackets = this.elementaryStream.referencePesPackets;
        const referencePointIndex = (0,misc/* binarySearchLessOrEqual */.eE)(referencePesPackets, searchPts, x => x.pts);
        const referencePoint = referencePointIndex !== -1 ? referencePesPackets[referencePointIndex] : null;
        if (referencePoint && searchPts - referencePoint.pts < mpeg_ts_misc/* TIMESCALE */.cS / 2) {
            // Reference point ain't too far away, prefer it over the chunk search
            scanStartPos = referencePoint.sectionStartPos;
        }
        else {
            let startChunkIndex = 0;
            if (reader.fileSize !== null) {
                const numChunks = Math.ceil(reader.fileSize / seekChunkSize);
                if (numChunks > 1) {
                    // Binary search to find the chunk with highest index whose first PES has pts <= searchPts
                    let low = 0;
                    let high = numChunks - 1;
                    startChunkIndex = low;
                    while (low <= high) {
                        const mid = Math.floor((low + high) / 2);
                        const chunkStartPos = (0,misc/* floorToMultiple */.Q5)(mid * seekChunkSize, demuxer.packetStride)
                            + firstPesPacketHeader.sectionStartPos;
                        const chunkEndPos = chunkStartPos + seekChunkSize;
                        const result = await findFirstPesPacketHeaderInChunk(chunkStartPos, chunkEndPos, false);
                        if (!result) {
                            // No PES packet found in this chunk, search left
                            high = mid - 1;
                            continue;
                        }
                        if (result.pesPacketHeader.pts <= searchPts) {
                            // This chunk's first PES is <= searchPts, it's a candidate
                            startChunkIndex = mid;
                            low = mid + 1; // Search right
                        }
                        else {
                            // Search left
                            high = mid - 1;
                        }
                    }
                }
            }
            scanStartPos = (0,misc/* floorToMultiple */.Q5)(startChunkIndex * seekChunkSize, demuxer.packetStride) + firstPesPacketHeader.sectionStartPos;
        }
        // Find the first PES packet at or after scanStartPos
        const result = await findFirstPesPacketHeaderInChunk(scanStartPos, reader.fileSize ?? Infinity, false);
        let currentPesHeader = result?.pesPacketHeader ?? null;
        if (!currentPesHeader) {
            // Fall back to first packet
            currentPesHeader = firstPesPacketHeader;
        }
        const reorderSize = this.getReorderSize();
        const retrieveEncodedPacket = async (sectionStartPos, predicate) => {
            // Load the relevant section in full
            const section = await demuxer.readSection(sectionStartPos, true);
            (0,misc/* assert */.vA)(section);
            const pesPacket = readPesPacket(section, true);
            (0,misc/* assert */.vA)(pesPacket);
            const context = new PacketReadingContext(this.elementaryStream, pesPacket);
            const buffer = new PacketBuffer(this, context);
            // Advance until the top-most presentation timestamp crosses or equals searchPts
            while (true) {
                const topPts = (0,misc/* last */._g)(buffer.presentationOrderPackets)?.pts ?? -Infinity;
                if (topPts >= searchPts) {
                    break;
                }
                const didRead = await buffer.readNextPacket();
                if (!didRead) {
                    break;
                }
            }
            const targetIndex = (0,misc/* findLastIndex */.Kl)(buffer.presentationOrderPackets, predicate);
            if (targetIndex === -1) {
                return null;
            }
            const targetPacket = buffer.presentationOrderPackets[targetIndex];
            const lastDuration = targetIndex === 0
                ? 0
                : targetPacket.pts - buffer.presentationOrderPackets[targetIndex - 1].pts;
            // Pop packets in decode order until we hit the target packet
            while (buffer.decodeOrderPackets[0] !== targetPacket) {
                buffer.decodeOrderPackets.shift();
            }
            buffer.lastDuration = lastDuration; // Kinda ugly but necessary fix
            const result = await buffer.readNext();
            (0,misc/* assert */.vA)(result);
            const packet = this.createEncodedPacket(result.packet, result.duration, options);
            this.packetBuffers.set(packet, buffer);
            this.packetSectionStarts.set(packet, result.packet.sectionStartPos);
            return packet;
        };
        if (!keyframesOnly || this.allPacketsAreKeyPackets()) {
            // Normat packet lookup case. Slightly easier since we just need to search (mostly) forward to find the
            // packet.
            // Linear scan to find the PES packet with largest pts <= searchPts. This will be used as the "midpoint"
            // of the next refinement step (which is needed because of B-frames).
            outer: while (true) {
                let currentPos = currentPesHeader.sectionStartPos + demuxer.packetStride;
                while (true) {
                    const packetHeader = await demuxer.readPacketHeader(currentPos);
                    if (!packetHeader) {
                        break outer; // End of file
                    }
                    if (packetHeader.pid === pid && packetHeader.payloadUnitStartIndicator === 1) {
                        const section = await demuxer.readSection(currentPos, false);
                        if (section) {
                            const nextPesHeader = readPesPacketHeader(section, false);
                            if (nextPesHeader && nextPesHeader.pts !== null) {
                                if (nextPesHeader.pts > searchPts) {
                                    break outer;
                                }
                                currentPesHeader = nextPesHeader;
                                maybeInsertReferencePacket(this.elementaryStream, currentPesHeader);
                                break;
                            }
                        }
                    }
                    currentPos += demuxer.packetStride;
                }
            }
            // Rewind by reorderSize + 1 PES packets (even for audio! To ensure proper durations)
            outer: for (let i = 0; i < reorderSize + 1; i++) {
                let pos = currentPesHeader.sectionStartPos - demuxer.packetStride;
                while (pos >= demuxer.packetOffset) {
                    const packetHeader = await demuxer.readPacketHeader(pos);
                    if (!packetHeader) {
                        break outer;
                    }
                    if (packetHeader.pid === pid && packetHeader.payloadUnitStartIndicator === 1) {
                        const section = await demuxer.readSection(pos, false);
                        if (section) {
                            const header = readPesPacketHeader(section, false);
                            if (header && header.pts !== null) {
                                currentPesHeader = header;
                                break;
                            }
                        }
                    }
                    pos -= demuxer.packetStride;
                }
            }
            return retrieveEncodedPacket(currentPesHeader.sectionStartPos, p => p.pts <= searchPts);
        }
        else {
            // Key packet lookup case. Slightly harder since the starting chunk may not have a key packet at all, which
            // means we might need to search the previous chunks until we find something.
            let currentChunkStartPos = scanStartPos;
            let nextChunkStartPos = null; // "next" as in later in the file, even tho we scan backwards
            const readSectionsInFull = !this.elementaryStream.canBeTrustedWithKeyPackets;
            while (true) {
                let bestKeyPesHeader = null;
                const isFirstChunk = currentChunkStartPos <= firstPesPacketHeader.sectionStartPos;
                let pesHeader;
                let pesHeaderSection = null;
                if (isFirstChunk) {
                    pesHeader = firstPesPacketHeader;
                    pesHeaderSection = firstSection;
                }
                else {
                    const result = await findFirstPesPacketHeaderInChunk(currentChunkStartPos, reader.fileSize ?? Infinity, readSectionsInFull);
                    pesHeader = result?.pesPacketHeader ?? null;
                    pesHeaderSection = result?.section ?? null;
                }
                let passedSearchPts = false;
                let lookaheadCount = 0;
                outer: while (pesHeader) {
                    if (nextChunkStartPos !== null && pesHeader.sectionStartPos >= nextChunkStartPos) {
                        // Stop at the next chunk boundary
                        break;
                    }
                    if (pesHeader.pts <= searchPts) {
                        let isKeyPacket;
                        if (this.elementaryStream.canBeTrustedWithKeyPackets) {
                            isKeyPacket = pesHeader.randomAccessIndicator === 1;
                        }
                        else {
                            (0,misc/* assert */.vA)(pesHeaderSection);
                            const pesPacket = readPesPacket(pesHeaderSection, true);
                            (0,misc/* assert */.vA)(pesPacket);
                            const context = new PacketReadingContext(this.elementaryStream, pesPacket);
                            await context.markNextPacket();
                            isKeyPacket = context.suppliedPacket?.randomAccessIndicator === 1;
                        }
                        if (isKeyPacket) {
                            bestKeyPesHeader = pesHeader;
                        }
                    }
                    if (pesHeader.pts > searchPts) {
                        passedSearchPts = true;
                    }
                    // If we've passed searchPts, do lookahead for reorderSize more packets just to be sure
                    if (passedSearchPts) {
                        lookaheadCount++;
                        if (lookaheadCount > reorderSize) {
                            break;
                        }
                    }
                    // Find next PES packet
                    let currentPos = pesHeader.sectionStartPos + demuxer.packetStride;
                    while (true) {
                        const packetHeader = await demuxer.readPacketHeader(currentPos);
                        if (!packetHeader) {
                            break outer; // End of file
                        }
                        if (packetHeader.pid === pid && packetHeader.payloadUnitStartIndicator === 1) {
                            const section = await demuxer.readSection(currentPos, readSectionsInFull);
                            if (section) {
                                const nextPesHeader = readPesPacketHeader(section, false);
                                if (nextPesHeader && nextPesHeader.pts !== null) {
                                    pesHeader = nextPesHeader;
                                    pesHeaderSection = section;
                                    maybeInsertReferencePacket(this.elementaryStream, pesHeader);
                                    break;
                                }
                            }
                        }
                        currentPos += demuxer.packetStride;
                    }
                }
                if (bestKeyPesHeader) {
                    let startPesHeader = bestKeyPesHeader;
                    if (lookaheadCount === 0) {
                        // Packet is at the end of stream, let's rewind a little to obtain the correct packet duration
                        outer: for (let i = 0; i < reorderSize; i++) {
                            let pos = startPesHeader.sectionStartPos - demuxer.packetStride;
                            while (pos >= demuxer.packetOffset) {
                                const packetHeader = await demuxer.readPacketHeader(pos);
                                if (!packetHeader) {
                                    break outer;
                                }
                                if (packetHeader.pid === pid && packetHeader.payloadUnitStartIndicator === 1) {
                                    const section = await demuxer.readSection(pos, readSectionsInFull);
                                    if (section) {
                                        const header = readPesPacketHeader(section, false);
                                        if (header && header.pts !== null) {
                                            startPesHeader = header;
                                            break;
                                        }
                                    }
                                }
                                pos -= demuxer.packetStride;
                            }
                        }
                    }
                    const encodedPacket = await retrieveEncodedPacket(startPesHeader.sectionStartPos, p => p.pts <= searchPts && p.randomAccessIndicator === 1);
                    (0,misc/* assert */.vA)(encodedPacket); // There must be one
                    return encodedPacket;
                }
                if (isFirstChunk) {
                    return null;
                }
                // No key frame found in this chunk, move one chunk to the left
                nextChunkStartPos = currentChunkStartPos;
                currentChunkStartPos = Math.max((0,misc/* floorToMultiple */.Q5)(currentChunkStartPos - firstPesPacketHeader.sectionStartPos - seekChunkSize, demuxer.packetStride) + firstPesPacketHeader.sectionStartPos, firstPesPacketHeader.sectionStartPos);
            }
        }
    }
}
class MpegTsVideoTrackBacking extends MpegTsTrackBacking {
    getType() {
        return 'video';
    }
    getCodec() {
        return this.elementaryStream.info.codec;
    }
    getCodedWidth() {
        return this.elementaryStream.info.width;
    }
    getCodedHeight() {
        return this.elementaryStream.info.height;
    }
    getSquarePixelWidth() {
        return this.elementaryStream.info.squarePixelWidth;
    }
    getSquarePixelHeight() {
        return this.elementaryStream.info.squarePixelHeight;
    }
    getRotation() {
        return 0;
    }
    async getColorSpace() {
        return this.elementaryStream.info.colorSpace;
    }
    async canBeTransparent() {
        return false;
    }
    async getDecoderConfig() {
        (0,misc/* assert */.vA)(this.elementaryStream.info.decoderConfig);
        return this.elementaryStream.info.decoderConfig;
    }
    allPacketsAreKeyPackets() {
        return false;
    }
    getReorderSize() {
        return this.elementaryStream.info.reorderSize;
    }
}
class MpegTsAudioTrackBacking extends MpegTsTrackBacking {
    getType() {
        return 'audio';
    }
    getCodec() {
        return this.elementaryStream.info.codec;
    }
    getNumberOfChannels() {
        return this.elementaryStream.info.numberOfChannels;
    }
    getSampleRate() {
        return this.elementaryStream.info.sampleRate;
    }
    async getDecoderConfig() {
        (0,misc/* assert */.vA)(this.elementaryStream.info.decoderConfig);
        return this.elementaryStream.info.decoderConfig;
    }
    allPacketsAreKeyPackets() {
        return true;
    }
    getReorderSize() {
        return 0; // No reordering, since no B-frames because goated
    }
}
const maybeInsertReferencePacket = (elementaryStream, pesPacketHeader) => {
    const referencePesPackets = elementaryStream.referencePesPackets;
    const index = (0,misc/* binarySearchLessOrEqual */.eE)(referencePesPackets, pesPacketHeader.sectionStartPos, x => x.sectionStartPos);
    if (index >= 0) {
        // Since pts and file position don't necessarily have a monotonic relationship (since pts can go crazy),
        // let's see if inserting at the given index would violate the pts order. If so, return.
        const entry = referencePesPackets[index];
        if (pesPacketHeader.pts <= entry.pts) {
            return false;
        }
        const minByteDistance = elementaryStream.demuxer.minReferencePointByteDistance;
        if (pesPacketHeader.sectionStartPos - entry.sectionStartPos < minByteDistance) {
            // Too close
            return false;
        }
        if (index < referencePesPackets.length - 1) {
            const nextEntry = referencePesPackets[index + 1];
            if (nextEntry.pts < pesPacketHeader.pts) {
                // Out of order
                return false;
            }
            if (nextEntry.sectionStartPos - pesPacketHeader.sectionStartPos < minByteDistance) {
                // Too close
                return false;
            }
        }
    }
    referencePesPackets.splice(index + 1, 0, pesPacketHeader);
    return true;
};
/** Stateful context used to extract exact encoded packets from the underlying data stream. */
class PacketReadingContext {
    constructor(elementaryStream, startingPesPacket) {
        this.currentPos = 0; // Relative to the data in startingPesPacket
        this.pesPackets = [];
        this.currentPesPacketIndex = 0;
        this.currentPesPacketPos = 0;
        this.endPos = 0;
        this.lastSuppliedPesPacket = null;
        this.nextPts = null;
        this.suppliedPacket = null;
        this.elementaryStream = elementaryStream;
        this.pid = elementaryStream.pid;
        this.demuxer = elementaryStream.demuxer;
        this.startingPesPacket = startingPesPacket;
    }
    ensureBuffered(length) {
        const remaining = this.endPos - this.currentPos;
        if (remaining >= length) {
            return length;
        }
        return this.bufferData(length - remaining)
            .then(() => Math.min(this.endPos - this.currentPos, length));
    }
    getCurrentPesPacket() {
        const packet = this.pesPackets[this.currentPesPacketIndex];
        (0,misc/* assert */.vA)(packet);
        return packet;
    }
    async bufferData(length) {
        const targetEndPos = this.endPos + length;
        while (this.endPos < targetEndPos) {
            let pesPacket;
            if (this.pesPackets.length === 0) {
                pesPacket = this.startingPesPacket;
            }
            else {
                // Find the next PES packet
                let currentPos = (0,misc/* last */._g)(this.pesPackets).sectionEndPos;
                (0,misc/* assert */.vA)(currentPos !== null);
                while (true) {
                    const packetHeader = await this.demuxer.readPacketHeader(currentPos);
                    if (!packetHeader) {
                        return;
                    }
                    if (packetHeader.pid === this.pid) {
                        const nextSection = await this.demuxer.readSection(currentPos, true);
                        if (!nextSection) {
                            return;
                        }
                        const nextPesPacket = readPesPacket(nextSection, false);
                        if (nextPesPacket) {
                            pesPacket = nextPesPacket;
                            break;
                        }
                    }
                    currentPos += this.demuxer.packetStride;
                }
            }
            this.pesPackets.push(pesPacket);
            this.endPos += pesPacket.data.byteLength;
        }
    }
    readBytes(length) {
        const currentPesPacket = this.getCurrentPesPacket();
        const relativeStartOffset = this.currentPos - this.currentPesPacketPos;
        const relativeEndOffset = relativeStartOffset + length;
        this.currentPos += length;
        if (relativeEndOffset <= currentPesPacket.data.byteLength) {
            // Request can be satisfied with one PES packet
            return currentPesPacket.data.subarray(relativeStartOffset, relativeEndOffset);
        }
        // Data spans multiple PES packets, we must do some merging
        const result = new Uint8Array(length);
        result.set(currentPesPacket.data.subarray(relativeStartOffset));
        let offset = currentPesPacket.data.byteLength - relativeStartOffset;
        while (true) {
            this.advanceCurrentPacket();
            const currentPesPacket = this.getCurrentPesPacket();
            const relativeEndOffset = length - offset;
            if (relativeEndOffset <= currentPesPacket.data.byteLength) {
                result.set(currentPesPacket.data.subarray(0, relativeEndOffset), offset);
                break;
            }
            result.set(currentPesPacket.data, offset);
            offset += currentPesPacket.data.byteLength;
        }
        return result;
    }
    readU8() {
        let currentPesPacket = this.getCurrentPesPacket();
        const relativeOffset = this.currentPos - this.currentPesPacketPos;
        this.currentPos++;
        if (relativeOffset < currentPesPacket.data.byteLength) {
            return currentPesPacket.data[relativeOffset];
        }
        this.advanceCurrentPacket();
        currentPesPacket = this.getCurrentPesPacket();
        return currentPesPacket.data[0];
    }
    seekTo(pos) {
        if (pos === this.currentPos) {
            return;
        }
        if (pos < this.currentPos) {
            while (pos < this.currentPesPacketPos) {
                // Move to the previous PES packet
                this.currentPesPacketIndex--;
                const currentPacket = this.getCurrentPesPacket();
                this.currentPesPacketPos -= currentPacket.data.byteLength;
            }
        }
        else {
            while (true) {
                // Move to the next PES packet
                const currentPesPacket = this.getCurrentPesPacket();
                const currentEndPos = this.currentPesPacketPos + currentPesPacket.data.byteLength;
                if (pos < currentEndPos) {
                    break;
                }
                this.currentPesPacketPos += currentPesPacket.data.byteLength;
                this.currentPesPacketIndex++;
            }
        }
        this.currentPos = pos;
    }
    skip(n) {
        this.seekTo(this.currentPos + n);
    }
    advanceCurrentPacket() {
        this.currentPesPacketPos += this.getCurrentPesPacket().data.byteLength;
        this.currentPesPacketIndex++;
    }
    async markNextPacket() {
        (0,misc/* assert */.vA)(!this.suppliedPacket);
        const elementaryStream = this.elementaryStream;
        if (elementaryStream.info.type === 'video') {
            const codec = elementaryStream.info.codec;
            const CHUNK_SIZE = 1024;
            if (codec !== 'avc' && codec !== 'hevc') {
                throw new Error('Unhandled.');
            }
            let packetStartPos = null;
            while (true) {
                let remaining = this.ensureBuffered(CHUNK_SIZE);
                if (remaining instanceof Promise)
                    remaining = await remaining;
                if (remaining === 0) {
                    break;
                }
                const chunkStartPos = this.currentPos;
                const chunk = this.readBytes(remaining);
                const length = chunk.byteLength;
                let i = 0;
                while (i < length) {
                    const zeroIndex = chunk.indexOf(0, i);
                    if (zeroIndex === -1 || zeroIndex >= length) {
                        break;
                    }
                    i = zeroIndex;
                    // Check if we have enough bytes to identify a start code
                    const posBeforeZero = chunkStartPos + i;
                    // Need at least 4 more bytes after the 0x00 to check for start code + NAL type
                    if (i + 4 >= length) {
                        // Not enough data in current chunk, seek back and let the next iteration handle it
                        this.seekTo(posBeforeZero);
                        break;
                    }
                    const b1 = chunk[i + 1];
                    const b2 = chunk[i + 2];
                    const b3 = chunk[i + 3];
                    let startCodeLength = 0;
                    let nalUnitTypeByte = null;
                    // Check for 4-byte start code (0x00000001)
                    if (b1 === 0x00 && b2 === 0x00 && b3 === 0x01) {
                        startCodeLength = 4;
                        nalUnitTypeByte = chunk[i + 4];
                    }
                    else if (b1 === 0x00 && b2 === 0x01) {
                        // 3-byte start code (0x000001)
                        startCodeLength = 3;
                        nalUnitTypeByte = b3;
                    }
                    if (startCodeLength === 0) {
                        // Not a start code, continue
                        i++;
                        continue;
                    }
                    const startCodePos = posBeforeZero;
                    if (packetStartPos === null) {
                        // This is our first start code, mark packet start
                        packetStartPos = startCodePos;
                        i += startCodeLength;
                        continue;
                    }
                    // We have a second start code. Check if it's an AUD.
                    if (nalUnitTypeByte !== null) {
                        const nalUnitType = codec === 'avc'
                            ? (0,codec_data/* extractNalUnitTypeForAvc */.uN)(nalUnitTypeByte)
                            : (0,codec_data/* extractNalUnitTypeForHevc */.O9)(nalUnitTypeByte);
                        const isAud = codec === 'avc'
                            ? nalUnitType === codec_data/* AvcNalUnitType */.mY.AUD
                            : nalUnitType === codec_data/* HevcNalUnitType */.iJ.AUD_NUT;
                        if (isAud) {
                            // End the packet at this start code (before the AUD)
                            const packetLength = startCodePos - packetStartPos;
                            this.seekTo(packetStartPos);
                            return this.supplyPacket(packetLength, 0);
                        }
                    }
                    // Not an AUD, continue searching
                    i += startCodeLength;
                }
                if (remaining < CHUNK_SIZE) {
                    // End of stream
                    break;
                }
            }
            // End of stream - return remaining data if we have a packet start
            if (packetStartPos !== null) {
                const packetLength = this.endPos - packetStartPos;
                this.seekTo(packetStartPos);
                return this.supplyPacket(packetLength, 0);
            }
        }
        else {
            const codec = elementaryStream.info.codec;
            const CHUNK_SIZE = 128;
            while (true) {
                let remaining = this.ensureBuffered(CHUNK_SIZE);
                if (remaining instanceof Promise)
                    remaining = await remaining;
                const startPos = this.currentPos;
                while (this.currentPos - startPos < remaining) {
                    const byte = this.readU8();
                    if (codec === 'aac') {
                        if (byte !== 0xff) {
                            continue;
                        }
                        this.skip(-1);
                        const possibleHeaderStartPos = this.currentPos;
                        let remaining = this.ensureBuffered(adts_reader/* MAX_ADTS_FRAME_HEADER_SIZE */.Y$);
                        if (remaining instanceof Promise)
                            remaining = await remaining;
                        if (remaining < adts_reader/* MAX_ADTS_FRAME_HEADER_SIZE */.Y$) {
                            return;
                        }
                        const headerBytes = this.readBytes(adts_reader/* MAX_ADTS_FRAME_HEADER_SIZE */.Y$);
                        const header = (0,adts_reader/* readAdtsFrameHeader */.lh)(src_reader/* FileSlice */.x$.tempFromBytes(headerBytes));
                        if (header) {
                            this.seekTo(possibleHeaderStartPos);
                            let remaining = this.ensureBuffered(header.frameLength);
                            if (remaining instanceof Promise)
                                remaining = await remaining;
                            return this.supplyPacket(remaining, Math.round(SAMPLES_PER_AAC_FRAME * mpeg_ts_misc/* TIMESCALE */.cS / elementaryStream.info.sampleRate));
                        }
                        else {
                            this.seekTo(possibleHeaderStartPos + 1);
                        }
                    }
                    else if (codec === 'mp3') {
                        if (byte !== 0xff) {
                            continue;
                        }
                        this.skip(-1);
                        const possibleHeaderStartPos = this.currentPos;
                        let remaining = this.ensureBuffered(mp3_misc/* FRAME_HEADER_SIZE */.Yq);
                        if (remaining instanceof Promise)
                            remaining = await remaining;
                        if (remaining < mp3_misc/* FRAME_HEADER_SIZE */.Yq) {
                            return;
                        }
                        const headerBytes = this.readBytes(mp3_misc/* FRAME_HEADER_SIZE */.Yq);
                        const word = (0,misc/* toDataView */.Zc)(headerBytes).getUint32(0);
                        const result = (0,mp3_misc/* readMp3FrameHeader */.P8)(word, null);
                        if (result.header) {
                            this.seekTo(possibleHeaderStartPos);
                            let remaining = this.ensureBuffered(result.header.totalSize);
                            if (remaining instanceof Promise)
                                remaining = await remaining;
                            const duration = result.header.audioSamplesInFrame * mpeg_ts_misc/* TIMESCALE */.cS
                                / elementaryStream.info.sampleRate;
                            return this.supplyPacket(remaining, Math.round(duration));
                        }
                        else {
                            this.seekTo(possibleHeaderStartPos + 1);
                        }
                    }
                    else if (codec === 'ac3') {
                        if (byte !== 0x0b) {
                            continue;
                        }
                        this.skip(-1);
                        const possibleSyncPos = this.currentPos;
                        // Need at least 5 bytes for sync word + CRC + fscod/frmsizecod
                        let remaining = this.ensureBuffered(5);
                        if (remaining instanceof Promise)
                            remaining = await remaining;
                        if (remaining < 5) {
                            return;
                        }
                        const headerBytes = this.readBytes(5);
                        // Verify sync word (0x0B77)
                        if (headerBytes[0] !== 0x0b || headerBytes[1] !== 0x77) {
                            this.seekTo(possibleSyncPos + 1);
                            continue;
                        }
                        const fscod = headerBytes[4] >> 6;
                        const frmsizecod = headerBytes[4] & 0x3f;
                        if (fscod === 3 || frmsizecod > 37) {
                            // Invalid
                            this.seekTo(possibleSyncPos + 1);
                            continue;
                        }
                        const frameSize = codec_data/* AC3_FRAME_SIZES */.Pl[3 * frmsizecod + fscod];
                        (0,misc/* assert */.vA)(frameSize !== undefined);
                        this.seekTo(possibleSyncPos);
                        remaining = this.ensureBuffered(frameSize);
                        if (remaining instanceof Promise)
                            remaining = await remaining;
                        const duration = Math.round(codec_data/* AC3_SAMPLES_PER_FRAME */.Ir * mpeg_ts_misc/* TIMESCALE */.cS / elementaryStream.info.sampleRate);
                        return this.supplyPacket(remaining, duration);
                    }
                    else if (codec === 'eac3') {
                        if (byte !== 0x0b) {
                            continue;
                        }
                        this.skip(-1);
                        const possibleSyncPos = this.currentPos;
                        // Need at least 5 bytes for E-AC-3 header parsing (sync word + frmsiz + fscod/numblkscod)
                        let remaining = this.ensureBuffered(5);
                        if (remaining instanceof Promise)
                            remaining = await remaining;
                        if (remaining < 5) {
                            return;
                        }
                        const headerBytes = this.readBytes(5);
                        if (headerBytes[0] !== 0x0b || headerBytes[1] !== 0x77) {
                            this.seekTo(possibleSyncPos + 1);
                            continue;
                        }
                        const frmsiz = ((headerBytes[2] & 0x07) << 8) | headerBytes[3];
                        const frameSize = (frmsiz + 1) * 2;
                        const fscod = headerBytes[4] >> 6;
                        const numblkscod = fscod === 3 ? 3 : (headerBytes[4] >> 4) & 0x03;
                        const numblks = codec_data/* EAC3_NUMBLKS_TABLE */.FY[numblkscod];
                        this.seekTo(possibleSyncPos);
                        remaining = this.ensureBuffered(frameSize);
                        if (remaining instanceof Promise)
                            remaining = await remaining;
                        // Duration = numblks * 256 samples per block
                        const samplesPerFrame = numblks * 256;
                        const duration = Math.round(samplesPerFrame * mpeg_ts_misc/* TIMESCALE */.cS / elementaryStream.info.sampleRate);
                        return this.supplyPacket(remaining, duration);
                    }
                    else {
                        throw new Error('Unhandled.');
                    }
                }
                if (remaining < CHUNK_SIZE) {
                    break;
                }
            }
        }
    }
    /** Supplies the context with a new encoded packet, beginning at the current position. */
    supplyPacket(packetLength, intrinsicDuration) {
        const currentPesPacket = this.getCurrentPesPacket();
        let pts;
        if (this.lastSuppliedPesPacket === currentPesPacket) {
            (0,misc/* assert */.vA)(this.nextPts !== null);
            pts = this.nextPts;
        }
        else {
            if (currentPesPacket.pts === null) {
                throw new Error(MISSING_PTS_ERROR_MESSAGE);
            }
            pts = currentPesPacket.pts;
            maybeInsertReferencePacket(this.elementaryStream, currentPesPacket);
        }
        this.lastSuppliedPesPacket = currentPesPacket;
        this.nextPts = pts + intrinsicDuration;
        const sectionStartPos = currentPesPacket.sectionStartPos;
        // The sequence number is the starting position of the section the PES packet is in, PLUS the offset within the
        // PES packet where the packet starts.
        const sequenceNumber = sectionStartPos + (this.currentPos - this.currentPesPacketPos);
        const data = this.readBytes(packetLength);
        let randomAccessIndicator = currentPesPacket.randomAccessIndicator;
        if (randomAccessIndicator === 0 && !this.elementaryStream.canBeTrustedWithKeyPackets) {
            if (this.elementaryStream.info.type === 'audio') {
                randomAccessIndicator = 1;
            }
            else {
                if (this.elementaryStream.info.decoderConfig) {
                    const isKey = (0,codec_data/* determineVideoPacketType */.PR)(this.elementaryStream.info.codec, this.elementaryStream.info.decoderConfig, data) === 'key';
                    randomAccessIndicator = Number(isKey);
                }
                else {
                    // We're reading packets before the decoder config is determined
                }
            }
        }
        this.suppliedPacket = {
            pts,
            data,
            sequenceNumber,
            sectionStartPos,
            randomAccessIndicator,
        };
        this.pesPackets.splice(0, this.currentPesPacketIndex);
        this.currentPesPacketIndex = 0;
    }
}
/**
 * A buffer that simulates decoder frame reordering to compute packet durations. Packets arrive in decode order but
 * durations are based on presentation order.
 */
class PacketBuffer {
    constructor(backing, context) {
        this.decodeOrderPackets = [];
        this.reorderBuffer = [];
        this.presentationOrderPackets = [];
        this.reachedEnd = false;
        this.lastDuration = 0;
        this.backing = backing;
        this.context = context;
        this.reorderSize = backing.getReorderSize();
        (0,misc/* assert */.vA)(this.reorderSize >= 0);
    }
    async readNext() {
        if (this.decodeOrderPackets.length === 0) {
            // We need the next packet
            const didRead = await this.readNextPacket();
            if (!didRead) {
                return null;
            }
        }
        // Ensure we know the next packet in presentation order so we can compute the current packet's duration
        await this.ensureCurrentPacketHasNext();
        const packet = this.decodeOrderPackets[0];
        // Let's compute the duration
        const presentationIndex = this.presentationOrderPackets.indexOf(packet);
        (0,misc/* assert */.vA)(presentationIndex !== -1);
        let duration;
        if (presentationIndex === this.presentationOrderPackets.length - 1) {
            duration = this.lastDuration; // Reasonable heuristic
        }
        else {
            const nextPacket = this.presentationOrderPackets[presentationIndex + 1];
            duration = nextPacket.pts - packet.pts;
            this.lastDuration = duration;
        }
        this.decodeOrderPackets.shift();
        // Shrink the presentation array as much as possible
        while (this.presentationOrderPackets.length > 0) {
            const first = this.presentationOrderPackets[0];
            if (this.decodeOrderPackets.includes(first)) {
                break;
            }
            this.presentationOrderPackets.shift();
        }
        return { packet, duration };
    }
    async readNextPacket() {
        if (this.reachedEnd) {
            return false;
        }
        let suppliedPacket;
        if (this.context.suppliedPacket) {
            // Small optimization: there was already a supplied packet in the context, so let's first use that one
            suppliedPacket = this.context.suppliedPacket;
        }
        else {
            await this.context.markNextPacket();
            suppliedPacket = this.context.suppliedPacket;
        }
        this.context.suppliedPacket = null;
        if (!suppliedPacket) {
            this.reachedEnd = true;
            this.flushReorderBuffer();
            return false;
        }
        this.decodeOrderPackets.push(suppliedPacket);
        this.processPacketThroughReorderBuffer(suppliedPacket);
        return true;
    }
    async ensureCurrentPacketHasNext() {
        const current = this.decodeOrderPackets[0];
        (0,misc/* assert */.vA)(current);
        while (true) {
            const presentationIndex = this.presentationOrderPackets.indexOf(current);
            // Check if current packet has a next packet
            if (presentationIndex !== -1 && presentationIndex <= this.presentationOrderPackets.length - 2) {
                break;
            }
            const didRead = await this.readNextPacket();
            if (!didRead) {
                break;
            }
        }
    }
    processPacketThroughReorderBuffer(packet) {
        this.reorderBuffer.push(packet);
        // If buffer is now overfull, output the packet with smallest PTS
        if (this.reorderBuffer.length > this.reorderSize) {
            let minIndex = 0;
            for (let i = 1; i < this.reorderBuffer.length; i++) {
                if (this.reorderBuffer[i].pts < this.reorderBuffer[minIndex].pts) {
                    minIndex = i;
                }
            }
            const packet = this.reorderBuffer[minIndex];
            this.presentationOrderPackets.push(packet);
            this.reorderBuffer.splice(minIndex, 1);
        }
    }
    flushReorderBuffer() {
        this.reorderBuffer.sort((a, b) => a.pts - b.pts);
        this.presentationOrderPackets.push(...this.reorderBuffer);
        this.reorderBuffer.length = 0;
    }
}

// EXTERNAL MODULE: ./node_modules/mediabunny/dist/modules/src/hls/hls-misc.js
var hls_misc = __webpack_require__(3622);
// EXTERNAL MODULE: ./node_modules/mediabunny/dist/modules/src/input.js
var src_input = __webpack_require__(2030);
;// ./node_modules/mediabunny/dist/modules/src/segmented-input.js
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

class SegmentedInput {
    constructor(input, path, trackDeclarations) {
        this.nextInputCacheAge = 0;
        this.inputCache = [];
        this.trackBackingsPromise = null;
        this.firstSegment = null;
        this.firstSegmentFirstTimestamps = new WeakMap();
        this.firstTimestampCache = new WeakMap();
        this.input = input;
        this.path = path;
        this.trackDeclarations = trackDeclarations;
    }
    async getDurationFromMetadata(options) {
        const lastSegment = await this.getSegmentAt(Infinity, {
            skipLiveWait: options.skipLiveWait,
        });
        if (!lastSegment) {
            return null;
        }
        return lastSegment.timestamp + lastSegment.duration;
    }
    async getTrackBackings() {
        return this.trackBackingsPromise ??= (async () => {
            const backings = [];
            if (this.trackDeclarations) {
                for (const decl of this.trackDeclarations) {
                    if (decl.type === 'video') {
                        const number = (0,misc/* arrayCount */.v$)(backings, x => x.getType() === 'video') + 1;
                        backings.push(new SegmentedInputInputVideoTrackBacking(this, decl, number));
                    }
                    else if (decl.type === 'audio') {
                        const number = (0,misc/* arrayCount */.v$)(backings, x => x.getType() === 'audio') + 1;
                        backings.push(new SegmentedInputInputAudioTrackBacking(this, decl, number));
                    }
                }
            }
            else {
                // There are no declarations, we must determine the tracks from the first segment
                this.firstSegment = await this.getFirstSegment({});
                if (!this.firstSegment) {
                    return [];
                }
                const input = this.getInputForSegment(this.firstSegment);
                const inputTracks = await input.getTracks();
                for (const track of inputTracks) {
                    if (track.type === 'video') {
                        const number = (0,misc/* arrayCount */.v$)(backings, x => x.getType() === 'video') + 1;
                        backings.push(new SegmentedInputInputVideoTrackBacking(this, {
                            id: backings.length + 1,
                            type: 'video',
                        }, number));
                    }
                    else if (track.type === 'audio') {
                        const number = (0,misc/* arrayCount */.v$)(backings, x => x.getType() === 'audio') + 1;
                        backings.push(new SegmentedInputInputAudioTrackBacking(this, {
                            id: backings.length + 1,
                            type: 'audio',
                        }, number));
                    }
                }
            }
            return backings;
        })();
    }
    // This operation is done a lot and can be semi-expensive, so it's good to have a cache for it
    async getFirstTimestampForInput(input) {
        const existing = this.firstTimestampCache.get(input);
        if (existing !== undefined) {
            return existing;
        }
        const firstTimestamp = await input.getFirstTimestamp();
        this.firstTimestampCache.set(input, firstTimestamp);
        return firstTimestamp;
    }
    async getMediaOffset(segment, input) {
        const firstSegment = segment.firstSegment ?? segment;
        let firstSegmentFirstTimestamp;
        if (this.firstSegmentFirstTimestamps.has(firstSegment)) {
            firstSegmentFirstTimestamp = this.firstSegmentFirstTimestamps.get(firstSegment);
        }
        else {
            const firstInput = this.getInputForSegment(firstSegment);
            firstSegmentFirstTimestamp = await this.getFirstTimestampForInput(firstInput);
            this.firstSegmentFirstTimestamps.set(firstSegment, firstSegmentFirstTimestamp);
        }
        if (firstSegment === segment) {
            return firstSegment.timestamp - firstSegmentFirstTimestamp;
        }
        const segmentFirstTimestamp = await this.getFirstTimestampForInput(input);
        const segmentElapsed = segment.timestamp - firstSegment.timestamp;
        const inputElapsed = segmentFirstTimestamp - firstSegmentFirstTimestamp;
        const difference = inputElapsed - segmentElapsed;
        if (Math.abs(difference) <= Math.min(0.25, segmentElapsed)) { // Heuristic
            // We're close enough
            return firstSegment.timestamp - firstSegmentFirstTimestamp;
        }
        else {
            // Ideally, each segment has absolute timestamps that are relative to some outside clock which is
            // consistent across segments. This is often the case, but not always. Either the container format used is
            // not timestamped at all (like ADTS), or the segments are just fucky. In this case, use the segment's
            // relative timestamp to determine where we are, and completely offset out the segment's input start
            // timestamp.
            return segment.timestamp - segmentFirstTimestamp;
        }
    }
    dispose() {
        for (const entry of this.inputCache) {
            entry.input.dispose();
        }
        this.inputCache.length = 0;
    }
}
class SegmentedInputInputTrackBacking {
    constructor(segmentedInput, decl, number) {
        this.packetInfos = new WeakMap();
        this.hydrationPromise = null;
        this.firstInputTrack = null;
        this.segmentedInput = segmentedInput;
        this.decl = decl;
        this.number = number;
    }
    hydrate() {
        return this.hydrationPromise ??= (async () => {
            this.segmentedInput.firstSegment ??= await this.segmentedInput.getFirstSegment({});
            if (!this.segmentedInput.firstSegment) {
                throw new Error('Missing first segment, can\'t retrieve track.');
            }
            const input = this.segmentedInput.getInputForSegment(this.segmentedInput.firstSegment);
            const inputTracks = await input.getTracks();
            const track = inputTracks.find(x => x.type === this.decl.type && x.number === this.number);
            if (!track) {
                throw new Error('No matching track found in underlying media data.');
            }
            this.firstInputTrack = track;
        })();
    }
    getId() {
        return this.decl.id;
    }
    getType() {
        return this.decl.type;
    }
    getNumber() {
        return this.number;
    }
    /** If the backing track is already present, delegate synchronously; otherwise, hydrate first. */
    delegate(fn) {
        if (this.firstInputTrack) {
            return fn();
        }
        return this.hydrate().then(fn);
    }
    async getDecoderConfig() {
        return this.delegate(() => this.firstInputTrack._backing.getDecoderConfig());
    }
    getHasOnlyKeyPackets() {
        return this.delegate(() => this.firstInputTrack._backing.getHasOnlyKeyPackets?.() ?? null);
    }
    getPairingMask() {
        return 1n;
    }
    getCodec() {
        return this.delegate(() => this.firstInputTrack._backing.getCodec());
    }
    getInternalCodecId() {
        return this.delegate(() => this.firstInputTrack._backing.getInternalCodecId());
    }
    getDisposition() {
        return this.delegate(() => this.firstInputTrack._backing.getDisposition());
    }
    getLanguageCode() {
        return this.delegate(() => this.firstInputTrack._backing.getLanguageCode());
    }
    getName() {
        return this.delegate(() => this.firstInputTrack._backing.getName());
    }
    getTimeResolution() {
        return this.delegate(() => this.firstInputTrack._backing.getTimeResolution());
    }
    async isRelativeToUnixEpoch() {
        await this.hydrate();
        (0,misc/* assert */.vA)(this.segmentedInput.firstSegment);
        return this.segmentedInput.firstSegment.relativeToUnixEpoch;
    }
    getBitrate() {
        return this.delegate(() => this.firstInputTrack._backing.getBitrate());
    }
    getAverageBitrate() {
        return this.delegate(() => this.firstInputTrack._backing.getAverageBitrate());
    }
    getDurationFromMetadata(options) {
        return this.segmentedInput.getDurationFromMetadata(options);
    }
    getLiveRefreshInterval() {
        return this.segmentedInput.getLiveRefreshInterval();
    }
    async createAdjustedPacket(packet, segment, track) {
        (0,misc/* assert */.vA)(packet.sequenceNumber >= 0);
        (0,misc/* assert */.vA)(this.segmentedInput.firstSegment);
        const mediaOffset = await this.segmentedInput.getMediaOffset(segment, track.input);
        // If we didn't do this then sequence numbers would exceed Number.MAX_SAFE_INTEGER for Unix-timestamped segments
        const segmentTimestampRelativeToFirst = segment.timestamp - this.segmentedInput.firstSegment.timestamp;
        const modified = packet.clone({
            timestamp: (0,misc/* roundToDivisor */.gl)(packet.timestamp + mediaOffset, await track.getTimeResolution()),
            // The 1e8 assumes a max of 100 MB per second, highly unlikely to be hit, so this should guarantee
            // monotonically increasing sequence numbers across segments.
            sequenceNumber: Math.floor(1e8 * segmentTimestampRelativeToFirst) + packet.sequenceNumber,
        });
        this.packetInfos.set(modified, {
            segment,
            track,
            sourcePacket: packet,
        });
        return modified;
    }
    async getFirstPacket(options) {
        await this.hydrate();
        (0,misc/* assert */.vA)(this.segmentedInput.firstSegment);
        (0,misc/* assert */.vA)(this.firstInputTrack);
        const packet = await this.firstInputTrack._backing.getFirstPacket(options);
        if (!packet) {
            return null;
        }
        return this.createAdjustedPacket(packet, this.segmentedInput.firstSegment, this.firstInputTrack);
    }
    getNextPacket(packet, options) {
        return this._getNextInternal(packet, options, false);
    }
    getNextKeyPacket(packet, options) {
        return this._getNextInternal(packet, options, true);
    }
    async _getNextInternal(packet, options, keyframesOnly) {
        const info = this.packetInfos.get(packet);
        if (!info) {
            throw new Error('Packet was not created from this track.');
        }
        const nextPacket = keyframesOnly
            ? await info.track._backing.getNextKeyPacket(info.sourcePacket, options)
            : await info.track._backing.getNextPacket(info.sourcePacket, options);
        if (nextPacket) {
            return this.createAdjustedPacket(nextPacket, info.segment, info.track);
        }
        let currentSegment = info.segment;
        while (true) {
            const nextSegment = await this.segmentedInput.getNextSegment(currentSegment, {
                skipLiveWait: options.skipLiveWait,
            });
            if (!nextSegment) {
                return null;
            }
            const nextInput = this.segmentedInput.getInputForSegment(nextSegment);
            const nextTracks = await nextInput.getTracks();
            const nextTrack = nextTracks.find(t => t.type === info.track.type && t.number === info.track.number);
            if (!nextTrack) {
                currentSegment = nextSegment;
                continue;
            }
            const firstPacket = await nextTrack._backing.getFirstPacket(options);
            if (!firstPacket) {
                return null;
            }
            return this.createAdjustedPacket(firstPacket, nextSegment, nextTrack);
        }
    }
    getPacket(timestamp, options) {
        return this._getPacketInternal(timestamp, options, false);
    }
    getKeyPacket(timestamp, options) {
        return this._getPacketInternal(timestamp, options, true);
    }
    async _getPacketInternal(timestamp, options, keyframesOnly) {
        let currentSegment = await this.segmentedInput.getSegmentAt(timestamp, {
            skipLiveWait: options.skipLiveWait,
        });
        if (!currentSegment) {
            return null;
        }
        await this.hydrate();
        while (currentSegment) {
            const input = this.segmentedInput.getInputForSegment(currentSegment);
            const tracks = await input.getTracks();
            const track = tracks.find(t => (t.type === this.firstInputTrack.type && t.number === this.firstInputTrack.number));
            if (!track) {
                // Search the previous segment
                currentSegment = await this.segmentedInput.getPreviousSegment(currentSegment, {
                    skipLiveWait: options.skipLiveWait,
                });
                continue;
            }
            const mediaOffset = await this.segmentedInput.getMediaOffset(currentSegment, input);
            const offsetTimestamp = timestamp - mediaOffset;
            const packet = keyframesOnly
                ? await track._backing.getKeyPacket(offsetTimestamp, options)
                : await track._backing.getPacket(offsetTimestamp, options);
            if (!packet) {
                // Search the previous segment
                currentSegment = await this.segmentedInput.getPreviousSegment(currentSegment, {
                    skipLiveWait: options.skipLiveWait,
                });
                continue;
            }
            return this.createAdjustedPacket(packet, currentSegment, track);
        }
        return null;
    }
}
class SegmentedInputInputVideoTrackBacking extends SegmentedInputInputTrackBacking {
    getType() {
        return 'video';
    }
    getCodec() {
        return this.delegate(() => this.firstInputTrack._backing.getCodec());
    }
    getCodedWidth() {
        return this.delegate(() => this.firstInputTrack._backing.getCodedWidth());
    }
    getCodedHeight() {
        return this.delegate(() => this.firstInputTrack._backing.getCodedHeight());
    }
    getSquarePixelWidth() {
        return this.delegate(() => this.firstInputTrack._backing.getSquarePixelWidth());
    }
    getSquarePixelHeight() {
        return this.delegate(() => this.firstInputTrack._backing.getSquarePixelHeight());
    }
    getRotation() {
        return this.delegate(() => this.firstInputTrack._backing.getRotation());
    }
    async getColorSpace() {
        return this.delegate(() => this.firstInputTrack._backing.getColorSpace());
    }
    async canBeTransparent() {
        return this.delegate(() => this.firstInputTrack._backing.canBeTransparent());
    }
    async getDecoderConfig() {
        return this.delegate(() => this.firstInputTrack._backing.getDecoderConfig());
    }
}
class SegmentedInputInputAudioTrackBacking extends SegmentedInputInputTrackBacking {
    getType() {
        return 'audio';
    }
    getCodec() {
        return this.delegate(() => this.firstInputTrack._backing.getCodec());
    }
    getNumberOfChannels() {
        return this.delegate(() => this.firstInputTrack._backing.getNumberOfChannels());
    }
    getSampleRate() {
        return this.delegate(() => this.firstInputTrack._backing.getSampleRate());
    }
    async getDecoderConfig() {
        return this.delegate(() => this.firstInputTrack._backing.getDecoderConfig());
    }
}

// EXTERNAL MODULE: ./node_modules/mediabunny/dist/modules/src/source.js
var source = __webpack_require__(4709);
;// ./node_modules/mediabunny/dist/modules/src/hls/hls-segmented-input.js
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
var __addDisposableResource = (undefined && undefined.__addDisposableResource) || function (env, value, async) {
    if (value !== null && value !== void 0) {
        if (typeof value !== "object" && typeof value !== "function") throw new TypeError("Object expected.");
        var dispose, inner;
        if (async) {
            if (!Symbol.asyncDispose) throw new TypeError("Symbol.asyncDispose is not defined.");
            dispose = value[Symbol.asyncDispose];
        }
        if (dispose === void 0) {
            if (!Symbol.dispose) throw new TypeError("Symbol.dispose is not defined.");
            dispose = value[Symbol.dispose];
            if (async) inner = dispose;
        }
        if (typeof dispose !== "function") throw new TypeError("Object not disposable.");
        if (inner) dispose = function() { try { inner.call(this); } catch (e) { return Promise.reject(e); } };
        env.stack.push({ value: value, dispose: dispose, async: async });
    }
    else if (async) {
        env.stack.push({ async: true });
    }
    return value;
};
var __disposeResources = (undefined && undefined.__disposeResources) || (function (SuppressedError) {
    return function (env) {
        function fail(e) {
            env.error = env.hasError ? new SuppressedError(e, env.error, "An error was suppressed during disposal.") : e;
            env.hasError = true;
        }
        var r, s = 0;
        function next() {
            while (r = env.stack.pop()) {
                try {
                    if (!r.async && s === 1) return s = 0, env.stack.push(r), Promise.resolve().then(next);
                    if (r.dispose) {
                        var result = r.dispose.call(r.value);
                        if (r.async) return s |= 2, Promise.resolve(result).then(next, function(e) { fail(e); return next(); });
                    }
                    else s |= 1;
                }
                catch (e) {
                    fail(e);
                }
            }
            if (s === 1) return env.hasError ? Promise.reject(env.error) : Promise.resolve();
            if (env.hasError) throw env.error;
        }
        return next();
    };
})(typeof SuppressedError === "function" ? SuppressedError : function (error, suppressed, message) {
    var e = new Error(message);
    return e.name = "SuppressedError", e.error = error, e.suppressed = suppressed, e;
});









const IV_STRING_REGEX = /^0[xX][0-9a-fA-F]+$/;
const BASE64_DATA_URI_REGEX = /^data:.*;base64,/i;
class HlsSegmentedInput extends SegmentedInput {
    constructor(demuxer, path, trackDeclarations, lines) {
        super(demuxer.input, path, trackDeclarations);
        this.segments = [];
        this.nextLines = null;
        this.currentUpdateSegmentsPromise = null;
        this.streamHasEnded = false;
        this.lastSegmentUpdateTime = -Infinity;
        this.refreshInterval = 5; // Reasonable default in case the playlist doesn't specify it
        this.demuxer = demuxer;
        this.nextLines = lines;
    }
    runUpdateSegments() {
        return this.currentUpdateSegmentsPromise ??= (async () => {
            try {
                const remainingWaitTimeMs = this.getRemainingWaitTimeMs();
                if (remainingWaitTimeMs > 0) {
                    await (0,misc/* wait */.uk)(remainingWaitTimeMs);
                }
                this.lastSegmentUpdateTime = performance.now();
                await this.updateSegments();
            }
            finally {
                this.currentUpdateSegmentsPromise = null;
            }
        })();
    }
    getRemainingWaitTimeMs() {
        const elapsed = performance.now() - this.lastSegmentUpdateTime;
        const result = Math.max(0, 1000 * this.refreshInterval - elapsed);
        if (result <= 50) {
            // If only a little bit of time is left, don't wait at all; this removes the chance for timing race
            // conditions when running a task every `refreshInterval` seconds
            return 0;
        }
        return result;
    }
    /**
     * Reads and parses the segment info from the playlist file. When called more than one, it updates the existing
     * segments by appending the new ones. Existing segments are never removed.
     */
    async updateSegments() {
        let lines = this.nextLines;
        this.nextLines = null;
        if (!lines) {
            const env_1 = { stack: [], error: void 0, hasError: false };
            try {
                const ref = __addDisposableResource(env_1, await this.demuxer.input._getSourceUncached({ path: this.path, isRoot: false }), false);
                const reader = new src_reader/* Reader */.mP(ref.source);
                const slice = await reader.requestEntireFile();
                (0,misc/* assert */.vA)(slice);
                lines = (0,src_reader/* readAllLines */.jo)(slice, slice.length, { ignore: hls_misc/* canIgnoreLine */.nf });
            }
            catch (e_1) {
                env_1.error = e_1;
                env_1.hasError = true;
            }
            finally {
                __disposeResources(env_1);
            }
        }
        let headerRead = false;
        let accumulatedTime = 0;
        let nextSegmentDuration = null;
        let currentKey = null;
        let nextSequenceNumber = 0;
        let currentFirstSegment = null;
        let currentInitSegment = null;
        let lastByteRangeEnd = null;
        let nextByteRange = null;
        let lastProgramDateTimeSeconds = null;
        let targetDuration = null;
        let segmentSeen = false;
        // Used for repeated parses where our job it is to only add the new segments
        let prevLastSegment = (0,misc/* last */._g)(this.segments) ?? null;
        const parseByteRange = (content) => {
            const atIndex = content.indexOf('@');
            const length = Number(atIndex === -1 ? content : content.slice(0, atIndex));
            if (!Number.isInteger(length) || length < 0) {
                throw new Error(`Invalid #EXT-X-BYTERANGE length '${content}'.`);
            }
            let offset = null;
            if (atIndex !== -1) {
                offset = Number(content.slice(atIndex + 1));
                if (!Number.isInteger(offset) || offset < 0) {
                    throw new Error(`Invalid #EXT-X-BYTERANGE offset '${content}'.`);
                }
            }
            return { length, offset };
        };
        const setNextSequenceNumber = (number) => {
            nextSequenceNumber = number;
            if (prevLastSegment) {
                (0,misc/* assert */.vA)(prevLastSegment.sequenceNumber !== null);
                if (prevLastSegment.sequenceNumber < number) {
                    // The sequence number has finally exceeded the last sequence number we knew, meaning we can now
                    // continue the segment list from there. Set some data to continue where we left off.
                    accumulatedTime = prevLastSegment.timestamp + prevLastSegment.duration;
                    currentFirstSegment = prevLastSegment.firstSegment;
                    currentInitSegment = prevLastSegment.initSegment;
                    lastProgramDateTimeSeconds = prevLastSegment.lastProgramDateTimeSeconds;
                    prevLastSegment = null;
                }
            }
        };
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            if (!headerRead) {
                if (line !== '#EXTM3U') {
                    throw new Error('Invalid M3U8 file; expected first line to be #EXTM3U.');
                }
                headerRead = true;
                continue;
            }
            if (!line.startsWith('#')) {
                if (!prevLastSegment) {
                    if (nextSegmentDuration === null) {
                        throw new Error('Invalid M3U8 file; a segment must be preceded by an #EXTINF tag.');
                    }
                    let key = currentKey;
                    if (key && key.method === 'AES-128' && !key.iv) {
                        // "the Media Sequence Number is to be used as the IV when decrypting a Media Segment, by
                        // putting its big-endian binary representation into a 16-octet (128-bit) buffer and padding
                        // (on the left) with zeros"
                        const iv = new Uint8Array(AES_128_BLOCK_SIZE);
                        const view = (0,misc/* toDataView */.Zc)(iv);
                        view.setUint32(8, Math.floor(nextSequenceNumber / (2 ** 32)));
                        view.setUint32(12, nextSequenceNumber);
                        key = { ...key, iv };
                    }
                    const fullPath = (0,misc/* joinPaths */.HS)(this.path, line);
                    const location = {
                        path: fullPath,
                        offset: nextByteRange?.offset ?? 0,
                        length: nextByteRange?.length ?? null,
                    };
                    const segment = {
                        timestamp: accumulatedTime,
                        relativeToUnixEpoch: lastProgramDateTimeSeconds !== null,
                        firstSegment: currentFirstSegment,
                        sequenceNumber: nextSequenceNumber,
                        location,
                        duration: nextSegmentDuration,
                        encryption: key,
                        initSegment: currentInitSegment,
                        lastProgramDateTimeSeconds,
                    };
                    currentFirstSegment ??= segment;
                    accumulatedTime += nextSegmentDuration;
                    this.segments.push(segment);
                }
                else {
                    // We're still seeing segments we already know about
                }
                nextSegmentDuration = null;
                if (nextByteRange === null) {
                    lastByteRangeEnd = null;
                }
                else {
                    nextByteRange = null;
                }
                setNextSequenceNumber(nextSequenceNumber + 1);
            }
            if (line.startsWith(hls_misc/* TAG_EXTINF */.e9)) {
                if (prevLastSegment) {
                    segmentSeen = true;
                    continue;
                }
                if (!segmentSeen) {
                    if (lastProgramDateTimeSeconds === null && nextSequenceNumber > 0 && targetDuration !== null) {
                        // Offset the first segment's start timestamp by the following:
                        accumulatedTime = nextSequenceNumber * targetDuration;
                    }
                    segmentSeen = true;
                }
                const extinfContent = line.slice(hls_misc/* TAG_EXTINF */.e9.length);
                const commaIndex = extinfContent.indexOf(',');
                const durationStr = commaIndex === -1 ? extinfContent : extinfContent.slice(0, commaIndex);
                const duration = Number(durationStr);
                if (!Number.isFinite(duration) || duration < 0) {
                    throw new Error(`Invalid #EXTINF tag duration '${durationStr}'.`);
                }
                nextSegmentDuration = duration;
            }
            else if (line.startsWith(hls_misc/* TAG_MAP */.sA)) {
                const attributes = new hls_misc/* AttributeList */.Hw(line.slice(hls_misc/* TAG_MAP */.sA.length));
                const uri = attributes.get('uri');
                if (!uri) {
                    throw new Error('Invalid #EXT-X-MAP tag; missing URI attribute.');
                }
                const byteRange = attributes.get('byterange');
                let parsedByteRange = null;
                if (byteRange !== null) {
                    parsedByteRange = parseByteRange(byteRange);
                }
                if (parsedByteRange && parsedByteRange.offset === null) {
                    throw new Error('Invalid #EXT-X-MAP tag; BYTERANGE attribute must have a specified offset.');
                }
                if (!prevLastSegment) {
                    const fullPath = (0,misc/* joinPaths */.HS)(this.path, uri);
                    const location = {
                        path: fullPath,
                        offset: parsedByteRange?.offset ?? 0,
                        length: parsedByteRange?.length ?? null,
                    };
                    if (currentKey?.method === 'AES-128' && !currentKey.iv) {
                        // Required by the spec
                        throw new Error('IV attribute must be set on #EXT-X-KEY tag preceding the #EXT-X-MAP tag.');
                    }
                    const segment = {
                        timestamp: accumulatedTime,
                        relativeToUnixEpoch: lastProgramDateTimeSeconds !== null,
                        firstSegment: null,
                        sequenceNumber: null,
                        location,
                        duration: 0,
                        encryption: currentKey,
                        initSegment: null,
                        lastProgramDateTimeSeconds,
                    };
                    // Accumulated time and sequence number are not updated in this case
                    currentInitSegment = segment;
                }
                else {
                    // We're still seeing segments we already know about
                }
                nextSegmentDuration = null;
                if (nextByteRange === null) {
                    lastByteRangeEnd = null;
                }
                else {
                    nextByteRange = null;
                }
            }
            else if (line.startsWith(hls_misc/* TAG_KEY */.L2)) {
                const attributes = new hls_misc/* AttributeList */.Hw(line.slice(hls_misc/* TAG_KEY */.L2.length));
                const method = attributes.get('method');
                if (method === 'NONE') {
                    currentKey = null;
                }
                else if (method === 'AES-128') {
                    const uri = attributes.get('uri');
                    if (!uri) {
                        throw new Error('Invalid #EXT-X-KEY: AES-128 requires a URI attribute.');
                    }
                    let iv = null;
                    const ivString = attributes.get('iv');
                    if (ivString) {
                        if (!IV_STRING_REGEX.test(ivString)) {
                            throw new Error(`Unsupported IV format '${ivString}'.`);
                        }
                        let hex = ivString.slice(2);
                        hex = hex.padStart(AES_128_BLOCK_SIZE * 2, '0');
                        iv = new Uint8Array(AES_128_BLOCK_SIZE);
                        for (let i = 0; i < AES_128_BLOCK_SIZE; i++) {
                            const startIndex = -AES_128_BLOCK_SIZE * 2 + i;
                            iv[i] = parseInt(hex.slice(startIndex, startIndex + 2), 16);
                        }
                    }
                    const keyFormat = attributes.get('keyformat') ?? 'identity';
                    if (keyFormat !== 'identity') {
                        throw new Error('For AES-128 encryption, only the \'identity\' KEYFORMAT is currently supported. If you'
                            + ' think other formats should be supported, please raise an issue.');
                    }
                    currentKey = {
                        method: 'AES-128',
                        keyUri: (0,misc/* joinPaths */.HS)(this.path, uri),
                        iv,
                        keyFormat,
                    };
                }
                else if (method === 'SAMPLE-AES' || method === 'SAMPLE-AES-CTR') {
                    const uri = attributes.get('uri');
                    if (!uri) {
                        throw new Error(`Invalid #EXT-X-KEY: ${method} requires a URI attribute.`);
                    }
                    const keyFormat = attributes.get('keyformat') ?? 'identity';
                    if (keyFormat === 'identity') {
                        throw new Error('For SAMPLE-AES and SAMPLE-AES-CTR encryption, the \'identity\' KEYFORMAT is not'
                            + ' supported. If you think this format should be supported, please raise an issue.');
                    }
                    let psshBox = null;
                    if (BASE64_DATA_URI_REGEX.test(uri)) {
                        const commaIndex = uri.indexOf(',');
                        const bytes = (0,misc/* base64ToBytes */.Kp)(uri.slice(commaIndex + 1));
                        if (bytes.length >= 8
                            && bytes[4] === 0x70
                            && bytes[5] === 0x73
                            && bytes[6] === 0x73
                            && bytes[7] === 0x68) {
                            const size = (0,misc/* toDataView */.Zc)(bytes).getUint32(0);
                            psshBox = (0,isobmff_misc/* parsePsshBoxContents */.j1)(bytes.subarray(8, Math.min(size, bytes.length)));
                        }
                    }
                    currentKey = {
                        method,
                        psshBox,
                    };
                }
                else {
                    throw new Error(`Unsupported encryption method '${method}'. If you think this method should be supported,`
                        + ` please raise an issue.`);
                }
            }
            else if (line.startsWith(hls_misc/* TAG_MEDIA_SEQUENCE */._2)) {
                const value = line.slice(hls_misc/* TAG_MEDIA_SEQUENCE */._2.length);
                const number = Number(value);
                if (!Number.isInteger(number) || number < 0) {
                    throw new Error(`Invalid EXT-X-MEDIA-SEQUENCE value '${value}'.`);
                }
                setNextSequenceNumber(number);
            }
            else if (line.startsWith(hls_misc/* TAG_BYTERANGE */.v6)) {
                const parsed = parseByteRange(line.slice(hls_misc/* TAG_BYTERANGE */.v6.length));
                if (parsed.offset === null) {
                    if (lastByteRangeEnd === null) {
                        throw new Error('Invalid M3U8 file; #EXT-X-BYTERANGE without offset requires a previous byte range.');
                    }
                    parsed.offset = lastByteRangeEnd;
                }
                nextByteRange = parsed;
                lastByteRangeEnd = parsed.offset + parsed.length;
            }
            else if (line.startsWith(hls_misc/* TAG_PROGRAM_DATE_TIME */.bW)) {
                if (prevLastSegment) {
                    // No need to spend effort parsing dates if we're gonna discard it anyway. Also would be wrong to do
                    // the segment shifting!
                    continue;
                }
                const dateTime = line.slice(hls_misc/* TAG_PROGRAM_DATE_TIME */.bW.length);
                const dateTimeMs = Date.parse(dateTime);
                if (!Number.isFinite(dateTimeMs)) {
                    continue;
                }
                const dateTimeSeconds = dateTimeMs / 1000;
                if (lastProgramDateTimeSeconds === dateTimeSeconds) {
                    continue;
                }
                if (lastProgramDateTimeSeconds === null && this.segments.length > 0) {
                    // "If the first EXT-X-PROGRAM-DATE-TIME tag in a Playlist appears after
                    // one or more Media Segment URIs, the client SHOULD extrapolate
                    // backward from that tag (using EXTINF durations and/or media
                    // timestamps) to associate dates with those segments."
                    const lastSegment = (0,misc/* last */._g)(this.segments);
                    const lastSegmentEnd = lastSegment.timestamp + lastSegment.duration;
                    const offset = dateTimeSeconds - lastSegmentEnd;
                    for (const segment of this.segments) {
                        segment.timestamp += offset;
                        segment.relativeToUnixEpoch = true;
                    }
                    accumulatedTime += offset;
                }
                lastProgramDateTimeSeconds = dateTimeSeconds;
                accumulatedTime = dateTimeSeconds; // Snap the accumulated time to the datetime
            }
            else if (line === hls_misc/* TAG_DISCONTINUITY */.i$) {
                currentFirstSegment = null;
                // Note: the init segment is not reset; the #EXT-X-MAP statement simply lasts until the next
                // #EXT-X-MAP statement.
            }
            else if (line.startsWith(hls_misc/* TAG_TARGETDURATION */.xe)) {
                const value = line.slice(hls_misc/* TAG_TARGETDURATION */.xe.length);
                const duration = Number(value);
                if (!Number.isFinite(duration) || duration < 0) {
                    throw new Error(`Invalid EXT-X-TARGETDURATION value '${value}'.`);
                }
                this.refreshInterval = duration;
                targetDuration = duration;
            }
            else if (line === hls_misc/* TAG_ENDLIST */.dY) {
                this.streamHasEnded = true;
                break; // No need to keep reading after this
            }
            else if (line.startsWith(hls_misc/* TAG_PLAYLIST_TYPE */.zA)) {
                const type = line.slice(hls_misc/* TAG_PLAYLIST_TYPE */.zA.length);
                if (type.toLowerCase() === 'vod') {
                    // A VOD playlist cannot be updated per spec so we can be sure the stream has ended
                    this.streamHasEnded = true;
                }
            }
        }
        if (!headerRead) {
            throw new Error('Invalid M3U8 file; no #EXTM3U header.');
        }
    }
    async getFirstSegment() {
        if (this.segments.length === 0) {
            await this.runUpdateSegments();
        }
        return this.segments[0] ?? null;
    }
    async getSegmentAt(timestamp, options) {
        if (this.segments.length === 0) {
            await this.runUpdateSegments();
        }
        // If we're skipping the live wait BUT there's no wait time, we're actually not lazy for the first iteration
        let isLazy = !!options.skipLiveWait && this.getRemainingWaitTimeMs() > 0;
        while (true) {
            const index = (0,misc/* binarySearchLessOrEqual */.eE)(this.segments, timestamp, x => x.timestamp);
            if (index === -1) {
                return null;
            }
            if (index < this.segments.length - 1 || this.streamHasEnded || isLazy) {
                return this.segments[index];
            }
            const segment = this.segments[index];
            if (timestamp < segment.timestamp + segment.duration) {
                return segment;
            }
            await this.runUpdateSegments();
            if (options.skipLiveWait) {
                isLazy = true; // Definitely lazy in the next iteration
            }
        }
    }
    async getNextSegment(segment, options) {
        const index = this.segments.indexOf(segment);
        (0,misc/* assert */.vA)(index !== -1);
        const nextIndex = index + 1;
        // If we're skipping the live wait BUT there's no wait time, we're actually not lazy for the first iteration
        let isLazy = !!options.skipLiveWait && this.getRemainingWaitTimeMs() > 0;
        while (true) {
            if (nextIndex < this.segments.length) {
                return this.segments[nextIndex];
            }
            if (this.streamHasEnded || isLazy) {
                return null;
            }
            await this.runUpdateSegments();
            if (options.skipLiveWait) {
                isLazy = true; // Definitely lazy in the next iteration
            }
        }
    }
    async getPreviousSegment(segment) {
        const index = this.segments.indexOf(segment);
        (0,misc/* assert */.vA)(index !== -1);
        return this.segments[index - 1] ?? null;
    }
    getInputForSegment(segment) {
        const hlsSegment = segment;
        const cacheEntry = this.inputCache.find(x => x.segment === hlsSegment);
        if (cacheEntry) {
            cacheEntry.age = this.nextInputCacheAge++;
            return cacheEntry.input;
        }
        let initInput = null;
        if (hlsSegment.initSegment || hlsSegment.firstSegment) {
            initInput = this.getInputForSegment((hlsSegment.initSegment ?? hlsSegment.firstSegment));
        }
        const formatOptions = {
            ...this.input._formatOptions,
            isobmff: {
                ...this.input._formatOptions.isobmff,
                // Intercept calls to resolveKeyId to inject our psshBox knowledge into it
                resolveKeyId: this.input._formatOptions.isobmff?.resolveKeyId && ((options) => {
                    if (!hlsSegment.encryption
                        || !(hlsSegment.encryption.method === 'SAMPLE-AES'
                            || hlsSegment.encryption.method === 'SAMPLE-AES-CTR')
                        || !hlsSegment.encryption.psshBox) {
                        return this.input._formatOptions.isobmff.resolveKeyId(options);
                    }
                    let psshBoxes = options.psshBoxes;
                    const { psshBox } = hlsSegment.encryption;
                    if ((psshBox.keyIds === null || psshBox.keyIds.includes(options.keyId))
                        && !psshBoxes.some(x => (0,isobmff_misc/* psshBoxesAreEqual */.MG)(x, psshBox))) {
                        psshBoxes = [...psshBoxes, psshBox];
                    }
                    return this.input._formatOptions.isobmff.resolveKeyId({ ...options, psshBoxes });
                }),
            },
        };
        const input = new src_input/* Input */.pd({
            source: new source/* CustomPathedSource */.r3(hlsSegment.location.path, async (request) => {
                (0,misc/* assert */.vA)(request.isRoot); // Shouldn't fail since we don't allow recursive HLS
                const proxiedRequest = {
                    ...request,
                    isRoot: false,
                };
                let ref;
                const needsSlice = hlsSegment.location.offset > 0 || hlsSegment.location.length !== null;
                if (!hlsSegment.encryption
                    || hlsSegment.encryption.method === 'SAMPLE-AES'
                    || hlsSegment.encryption.method === 'SAMPLE-AES-CTR') {
                    ref = await this.input._getSourceCached(proxiedRequest);
                    if (needsSlice) {
                        const slice = ref.source.slice(hlsSegment.location.offset, hlsSegment.location.length ?? undefined);
                        const sliceRef = slice.ref();
                        ref.free();
                        ref = sliceRef;
                    }
                }
                else if (hlsSegment.encryption.method === 'AES-128') {
                    const encryption = hlsSegment.encryption;
                    (0,misc/* assert */.vA)(encryption.iv);
                    let ciphertextRef = await this.input._getSourceCached(proxiedRequest);
                    if (needsSlice) {
                        // Slice before decrypting
                        const slice = ciphertextRef.source.slice(hlsSegment.location.offset, hlsSegment.location.length ?? undefined);
                        const sliceRef = slice.ref();
                        ciphertextRef.free();
                        ciphertextRef = sliceRef;
                    }
                    const ciphertextReader = new src_reader/* Reader */.mP(ciphertextRef.source);
                    const stream = createAes128CbcDecryptStream(ciphertextReader, async () => {
                        const env_2 = { stack: [], error: void 0, hasError: false };
                        try {
                            const keyRef = __addDisposableResource(env_2, await this.input._getSourceCached({ path: encryption.keyUri, isRoot: false }, src_input/* ENCRYPTION_KEY_CACHE_GROUP */.Ng), false);
                            const keyReader = new src_reader/* Reader */.mP(keyRef.source);
                            const keySlice = await keyReader.requestSlice(0, AES_128_BLOCK_SIZE);
                            if (!keySlice) {
                                throw new Error('Invalid AES-128 key; expected at least 16 bytes of data.');
                            }
                            const key = (0,src_reader/* readBytes */.io)(keySlice, AES_128_BLOCK_SIZE);
                            return { key, iv: encryption.iv };
                        }
                        catch (e_2) {
                            env_2.error = e_2;
                            env_2.hasError = true;
                        }
                        finally {
                            __disposeResources(env_2);
                        }
                    }, () => {
                        ciphertextRef.free();
                    });
                    ref = new source/* ReadableStreamSource */.m6(stream).ref();
                }
                else {
                    (0,misc/* assert */.vA)(false);
                }
                return ref;
            }),
            // Do not allow recursive HLS. Cool on paper, but allows for nasty infinite-depth request trees.
            formats: this.input._formats.filter(x => !(x instanceof HlsInputFormat)),
            initInput: initInput ?? undefined,
            formatOptions,
        });
        input._onFormatDetermined = (format) => {
            if ((hlsSegment.encryption?.method === 'SAMPLE-AES' || hlsSegment.encryption?.method === 'SAMPLE-AES-CTR')
                && !format._isIsobmff) {
                // These methods can also be used for formats such as MPEG-TS
                // eslint-disable-next-line @stylistic/max-len
                // (see https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/HLS_Sample_Encryption/Encryption/Encryption.html)
                // but we don't support them there yet, so instead of silently decrypting nothing, we throw an error.
                throw new Error('The SAMPLE-AES and SAMPLE-AES-CTR encryption methods are currently only supported for'
                    + ' ISOBMFF files.');
            }
        };
        this.inputCache.push({
            segment: hlsSegment,
            input,
            age: this.nextInputCacheAge++,
        });
        const MAX_INPUT_CACHE_SIZE = 4;
        if (this.inputCache.length > MAX_INPUT_CACHE_SIZE) {
            const minAgeIndex = (0,misc/* arrayArgmin */.Yg)(this.inputCache, x => x.age);
            (0,misc/* assert */.vA)(minAgeIndex !== -1);
            this.inputCache.splice(minAgeIndex, 1);
            // DON'T dispose here; the Input might still be used! The source disposal will happen with GC logic
        }
        return input;
    }
    async getLiveRefreshInterval() {
        if (this.getRemainingWaitTimeMs() === 0) {
            await this.runUpdateSegments();
        }
        return this.streamHasEnded ? null : this.refreshInterval;
    }
}

;// ./node_modules/mediabunny/dist/modules/src/hls/hls-demuxer.js
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */








class HlsDemuxer extends demuxer/* Demuxer */.B {
    constructor(input) {
        super(input);
        this.metadataPromise = null;
        this.trackBackings = null;
        this.internalTracks = null;
        this.segmentedInputs = [];
        this.hasMasterPlaylist = true;
    }
    readMetadata() {
        return this.metadataPromise ??= (async () => {
            (0,misc/* assert */.vA)(this.input._rootSource instanceof source/* PathedSource */.QI);
            const { rootPath } = this.input._rootSource;
            const slice = await this.input._reader.requestEntireFile();
            (0,misc/* assert */.vA)(slice);
            const lines = (0,src_reader/* readAllLines */.jo)(slice, slice.length, { ignore: hls_misc/* canIgnoreLine */.nf });
            const variantStreams = [];
            const mediaTags = [];
            // Let's first iterate through the entire file, collecting all variant streams and media tags
            for (let i = 1; i < lines.length; i++) {
                const line = lines[i];
                if (line.startsWith(hls_misc/* TAG_STREAM_INF */.c$)) {
                    const streamInfLineNumber = i;
                    const playlistPath = lines[++i];
                    if (playlistPath === undefined) {
                        throw new Error('Incorrect M3U8 file; a line must follow the #EXT-X-STREAM-INF tag.');
                    }
                    const fullPath = (0,misc/* joinPaths */.HS)(rootPath, playlistPath);
                    const attributes = new hls_misc/* AttributeList */.Hw(line.slice(hls_misc/* TAG_STREAM_INF */.c$.length));
                    const bandwidth = attributes.getAsNumber('bandwidth');
                    if (bandwidth === null) {
                        throw new Error('Invalid M3U8 file; #EXT-X-STREAM-INF tag requires a BANDWIDTH attribute with a valid'
                            + ' numerical value.');
                    }
                    variantStreams.push({
                        fullPath,
                        attributes,
                        lineNumber: streamInfLineNumber,
                        hasOnlyKeyPackets: false,
                    });
                }
                else if (line.startsWith(hls_misc/* TAG_I_FRAME_STREAM_INF */.g4)) {
                    const attributes = new hls_misc/* AttributeList */.Hw(line.slice(hls_misc/* TAG_I_FRAME_STREAM_INF */.g4.length));
                    const playlistPath = attributes.get('uri');
                    if (playlistPath === null) {
                        throw new Error('Invalid M3U8 file; #EXT-X-I-FRAME-STREAM-INF tag requires a URI attribute.');
                    }
                    const bandwidth = attributes.getAsNumber('bandwidth');
                    if (bandwidth === null) {
                        throw new Error('Invalid M3U8 file; #EXT-X-I-FRAME-STREAM-INF tag requires a BANDWIDTH attribute with a'
                            + ' valid numerical value.');
                    }
                    const fullPath = (0,misc/* joinPaths */.HS)(rootPath, playlistPath);
                    variantStreams.push({
                        fullPath,
                        attributes,
                        lineNumber: i,
                        hasOnlyKeyPackets: true,
                    });
                }
                else if (line.startsWith(hls_misc/* TAG_MEDIA */.EF)) {
                    const attributes = new hls_misc/* AttributeList */.Hw(line.slice(hls_misc/* TAG_MEDIA */.EF.length));
                    const type = attributes.get('type');
                    if (type === null) {
                        throw new Error('Invalid M3U8 file; #EXT-X-MEDIA tag requires a TYPE attribute.');
                    }
                    const groupId = attributes.get('group-id');
                    if (groupId === null) {
                        throw new Error('Invalid M3U8 file; #EXT-X-MEDIA tag requires a GROUP-ID attribute.');
                    }
                    let fullPath = null;
                    const uri = attributes.get('uri');
                    if (uri !== null) {
                        fullPath = (0,misc/* joinPaths */.HS)(rootPath, uri);
                    }
                    mediaTags.push({ fullPath, attributes, lineNumber: i });
                }
                else if (line === hls_misc/* TAG_I_FRAMES_ONLY */.DT) {
                    // iFramesOnlyTagFound = true;
                }
                else if (line.startsWith(hls_misc/* TAG_EXTINF */.e9)) {
                    // This is a media playlist, not a master playlist
                    const segmentedInput = new HlsSegmentedInput(this, rootPath, null, lines);
                    this.segmentedInputs = [segmentedInput];
                    this.hasMasterPlaylist = false;
                    this.trackBackings = await segmentedInput.getTrackBackings();
                    return;
                }
            }
            const videoGroupIds = [...new Set(mediaTags
                    .filter(tag => tag.attributes.get('type').toLowerCase() === 'video')
                    .map(tag => tag.attributes.get('group-id'))),
            ];
            const audioGroupIds = [...new Set(mediaTags
                    .filter(tag => tag.attributes.get('type').toLowerCase() === 'audio')
                    .map(tag => tag.attributes.get('group-id'))),
            ];
            // Now, let's process & resolve all variant streams in parallel, mapping each of them to tracks.
            const internalTracksByVariant = await Promise.all(variantStreams.map(async (variantStream, i) => {
                const result = [];
                const codecsList = variantStream.attributes.get('codecs');
                let codecStrings;
                if (codecsList) {
                    codecStrings = codecsList.split(',').map(x => x.trim());
                }
                else {
                    // No codecs were specified, we need to read the underlying media data
                    const segmentedInput = this.getSegmentedInputForPath(variantStream.fullPath);
                    const trackBackings = await segmentedInput.getTrackBackings();
                    const tracksWithCodec = await Promise.all(trackBackings.map(async (t) => ({ track: t, codec: await t.getCodec() })));
                    codecStrings = await Promise.all(tracksWithCodec
                        .filter(x => x.codec !== null)
                        .map(x => x.track.getDecoderConfig().then(x => x.codec)));
                }
                const videoGroupId = variantStream.attributes.get('video');
                const audioGroupId = variantStream.attributes.get('audio');
                const containsVideoCodecs = codecStrings.some(x => codec/* VIDEO_CODECS */.WN.includes((0,codec/* inferCodecFromCodecString */.oU)(x)));
                const containsAudioCodecs = codecStrings.some(x => codec/* AUDIO_CODECS */.PP.includes((0,codec/* inferCodecFromCodecString */.oU)(x)));
                if (videoGroupId !== null && !containsVideoCodecs) {
                    // A video group is linked but no video codec is listed, sigh. Let's resolve the video codec.
                    if (!videoGroupIds.includes(videoGroupId)) {
                        throw new Error(`Invalid M3U8 file; variant stream references video group "${videoGroupId}" which`
                            + ` is not defined in any #EXT-X-MEDIA tags.`);
                    }
                    // We only need to look at the first matching tag, since all tags are required to have the same
                    // codec anyway
                    const matchingVideoMediaTag = mediaTags.find((mediaTag) => {
                        const groupId = mediaTag.attributes.get('group-id');
                        const type = mediaTag.attributes.get('type');
                        return groupId === videoGroupId && type.toLowerCase() === 'video';
                    });
                    outer: if (matchingVideoMediaTag) {
                        const uri = matchingVideoMediaTag.attributes.get('uri');
                        if (uri === null) {
                            break outer;
                        }
                        const fullPath = (0,misc/* joinPaths */.HS)(rootPath, uri);
                        const segmentedInput = this.getSegmentedInputForPath(fullPath);
                        const trackBackings = await segmentedInput.getTrackBackings();
                        const videoTrack = trackBackings.find(x => x.getType() === 'video');
                        if (!videoTrack || (await videoTrack.getCodec()) === null) {
                            break outer;
                        }
                        const additionalCodecString = await videoTrack.getDecoderConfig().then(x => x?.codec ?? null);
                        (0,misc/* assert */.vA)(additionalCodecString !== null);
                        codecStrings.push(additionalCodecString);
                    }
                }
                if (audioGroupId !== null && !containsAudioCodecs) {
                    // An audio group is linked but no audio codec is listed, sigh. Let's resolve the audio codec.
                    if (!audioGroupIds.includes(audioGroupId)) {
                        throw new Error(`Invalid M3U8 file; variant stream references audio group "${audioGroupId}" which`
                            + ` is not defined in any #EXT-X-MEDIA tags.`);
                    }
                    // We only need to look at the first matching tag, since all tags are required to have the same
                    // codec anyway
                    const matchingAudioMediaTag = mediaTags.find((tag) => {
                        const groupId = tag.attributes.get('group-id');
                        const type = tag.attributes.get('type');
                        return groupId === audioGroupId && type.toLowerCase() === 'audio';
                    });
                    outer: if (matchingAudioMediaTag) {
                        const uri = matchingAudioMediaTag.attributes.get('uri');
                        if (uri === null) {
                            break outer;
                        }
                        const fullPath = (0,misc/* joinPaths */.HS)(rootPath, uri);
                        const segmentedInput = this.getSegmentedInputForPath(fullPath);
                        const trackBackings = await segmentedInput.getTrackBackings();
                        const audioTrack = trackBackings.find(x => x.getType() === 'audio');
                        if (!audioTrack || (await audioTrack.getCodec()) === null) {
                            break outer;
                        }
                        const additionalCodecString = await audioTrack.getDecoderConfig().then(x => x?.codec ?? null);
                        (0,misc/* assert */.vA)(additionalCodecString !== null);
                        codecStrings.push(additionalCodecString);
                    }
                }
                // Unique that shit
                codecStrings = [...new Set(codecStrings)];
                let videoCodecString = null;
                let audioCodecString = null;
                const bandwidth = variantStream.attributes.getAsNumber('bandwidth');
                (0,misc/* assert */.vA)(bandwidth !== null);
                const averageBandwidth = variantStream.attributes.getAsNumber('average-bandwidth');
                const name = variantStream.attributes.get('name');
                // Now, finally, loop over each codec string for the variant and resolve each one to one or more tracks.
                for (const codecString of codecStrings) {
                    const inferredCodec = (0,codec/* inferCodecFromCodecString */.oU)(codecString);
                    if (inferredCodec === null) {
                        continue;
                    }
                    if (codec/* VIDEO_CODECS */.WN.includes(inferredCodec)) {
                        if (videoCodecString !== null) {
                            throw new Error('Unsupported M3U8 file; multiple video codecs found in the CODECS attribute of a'
                                + ' variant stream.');
                        }
                        videoCodecString = codecString;
                        const videoGroupId = variantStream.attributes.get('video');
                        if (videoGroupId === null) {
                            const resolution = variantStream.attributes.get('resolution');
                            let width = null;
                            let height = null;
                            if (resolution) {
                                const match = resolution.match(/^(\d+)x(\d+)$/);
                                if (match) {
                                    width = Number(match[1]);
                                    height = Number(match[2]);
                                }
                            }
                            result.push({
                                id: -1,
                                demuxer: this,
                                backingTrack: null,
                                default: true,
                                autoselect: true,
                                languageCode: misc/* UNDETERMINED_LANGUAGE */.IR,
                                lineNumber: variantStream.lineNumber,
                                fullPath: variantStream.fullPath,
                                fullCodecString: videoCodecString,
                                pairingMask: 1n << BigInt(i),
                                peakBitrate: bandwidth,
                                averageBitrate: averageBandwidth,
                                name,
                                hasOnlyKeyPackets: variantStream.hasOnlyKeyPackets,
                                info: {
                                    type: 'video',
                                    width,
                                    height,
                                },
                            });
                        }
                        else {
                            if (!videoGroupIds.includes(videoGroupId)) {
                                throw new Error(`Invalid M3U8 file; variant stream references video group "${videoGroupId}"`
                                    + ` which is not defined in any #EXT-X-MEDIA tags.`);
                            }
                            for (const mediaTag of mediaTags) {
                                const groupId = mediaTag.attributes.get('group-id');
                                const type = mediaTag.attributes.get('type');
                                if (groupId !== videoGroupId || type.toLowerCase() !== 'video') {
                                    continue;
                                }
                                const resolution = mediaTag.attributes.get('resolution')
                                    ?? variantStream.attributes.get('resolution');
                                let width = null;
                                let height = null;
                                if (resolution) {
                                    const match = resolution.match(/^(\d+)x(\d+)$/);
                                    if (match) {
                                        width = Number(match[1]);
                                        height = Number(match[2]);
                                    }
                                }
                                result.push({
                                    id: -1,
                                    demuxer: this,
                                    backingTrack: null,
                                    default: getMediaTagDefault(mediaTag.attributes),
                                    // Autoselect is inferred to be true if the default is true
                                    autoselect: getMediaTagDefault(mediaTag.attributes)
                                        || getMediaTagAutoselect(mediaTag.attributes),
                                    languageCode: preprocessLanguageCode(mediaTag.attributes.get('language')),
                                    lineNumber: mediaTag.lineNumber,
                                    fullPath: mediaTag.fullPath ?? variantStream.fullPath,
                                    fullCodecString: videoCodecString,
                                    pairingMask: 1n << BigInt(i),
                                    peakBitrate: null,
                                    averageBitrate: null,
                                    name: mediaTag.attributes.get('name'),
                                    hasOnlyKeyPackets: variantStream.hasOnlyKeyPackets,
                                    info: {
                                        type: 'video',
                                        width,
                                        height,
                                    },
                                });
                            }
                        }
                    }
                    else if (codec/* AUDIO_CODECS */.PP.includes(inferredCodec)) {
                        if (audioCodecString !== null) {
                            throw new Error('Unsupported M3U8 file; multiple audio codecs found in the CODECS attribute of a'
                                + ' variant stream.');
                        }
                        audioCodecString = codecString;
                        const audioGroupId = variantStream.attributes.get('audio');
                        if (audioGroupId === null) {
                            const channels = variantStream.attributes.get('channels');
                            const parsedChannels = channels !== null
                                ? Number(channels.split('/')[0])
                                : null;
                            result.push({
                                id: -1,
                                demuxer: this,
                                backingTrack: null,
                                default: true,
                                autoselect: true,
                                languageCode: misc/* UNDETERMINED_LANGUAGE */.IR,
                                lineNumber: variantStream.lineNumber,
                                fullPath: variantStream.fullPath,
                                fullCodecString: audioCodecString,
                                pairingMask: 1n << BigInt(i),
                                peakBitrate: bandwidth,
                                averageBitrate: averageBandwidth,
                                name,
                                hasOnlyKeyPackets: variantStream.hasOnlyKeyPackets,
                                info: {
                                    type: 'audio',
                                    numberOfChannels: parsedChannels !== null
                                        && Number.isInteger(parsedChannels)
                                        && parsedChannels > 0
                                        ? parsedChannels
                                        : null,
                                },
                            });
                        }
                        else {
                            if (!audioGroupIds.includes(audioGroupId)) {
                                throw new Error(`Invalid M3U8 file; variant stream references audio group "${audioGroupId}"`
                                    + ` which is not defined in any #EXT-X-MEDIA tags.`);
                            }
                            for (const mediaTag of mediaTags) {
                                const groupId = mediaTag.attributes.get('group-id');
                                const type = mediaTag.attributes.get('type');
                                if (groupId !== audioGroupId || type.toLowerCase() !== 'audio') {
                                    continue;
                                }
                                const channels = mediaTag.attributes.get('channels')
                                    ?? variantStream.attributes.get('channels');
                                const parsedChannels = channels !== null
                                    ? Number(channels.split('/')[0])
                                    : null;
                                result.push({
                                    id: -1,
                                    demuxer: this,
                                    backingTrack: null,
                                    default: getMediaTagDefault(mediaTag.attributes),
                                    // Autoselect is inferred to be true if the default is true
                                    autoselect: getMediaTagDefault(mediaTag.attributes)
                                        || getMediaTagAutoselect(mediaTag.attributes),
                                    languageCode: preprocessLanguageCode(mediaTag.attributes.get('language')),
                                    lineNumber: mediaTag.lineNumber,
                                    fullPath: mediaTag.fullPath ?? variantStream.fullPath,
                                    fullCodecString: audioCodecString,
                                    pairingMask: 1n << BigInt(i),
                                    peakBitrate: null,
                                    averageBitrate: null,
                                    name: mediaTag.attributes.get('name'),
                                    hasOnlyKeyPackets: variantStream.hasOnlyKeyPackets,
                                    info: {
                                        type: 'audio',
                                        numberOfChannels: parsedChannels !== null
                                            && Number.isInteger(parsedChannels)
                                            && parsedChannels > 0
                                            ? parsedChannels
                                            : null,
                                    },
                                });
                            }
                        }
                    }
                }
                return result;
            }));
            const internalTracks = [];
            const addInternalTrack = (track) => {
                const existingTrack = internalTracks.find(x => x.fullPath === track.fullPath && x.info.type === track.info.type);
                if (existingTrack) {
                    existingTrack.pairingMask |= track.pairingMask;
                    existingTrack.default ||= track.default;
                    existingTrack.autoselect ||= track.autoselect;
                    existingTrack.lineNumber = Math.min(existingTrack.lineNumber, track.lineNumber);
                    if (track.peakBitrate !== null) {
                        existingTrack.peakBitrate = Math.max(existingTrack.peakBitrate ?? -Infinity, track.peakBitrate);
                    }
                    if (track.averageBitrate !== null) {
                        existingTrack.averageBitrate = Math.max(existingTrack.averageBitrate ?? -Infinity, track.averageBitrate);
                    }
                    if (existingTrack.languageCode === misc/* UNDETERMINED_LANGUAGE */.IR) {
                        existingTrack.languageCode = track.languageCode;
                    }
                }
                else {
                    track.id = internalTracks.length + 1;
                    internalTracks.push(track);
                }
            };
            for (const variantInternalTracks of internalTracksByVariant) {
                for (const trackEntry of variantInternalTracks) {
                    addInternalTrack(trackEntry);
                }
            }
            // Order tracks by how they appear in the file
            internalTracks.sort((a, b) => a.lineNumber - b.lineNumber);
            this.trackBackings = [];
            for (const internalTrack of internalTracks) {
                if (internalTrack.info.type === 'video') {
                    this.trackBackings.push(new HlsInputVideoTrackBacking(internalTrack));
                }
                else {
                    this.trackBackings.push(new HlsInputAudioTrackBacking(internalTrack));
                }
            }
            this.internalTracks = internalTracks;
        })();
    }
    async getTrackBackings() {
        await this.readMetadata();
        (0,misc/* assert */.vA)(this.trackBackings);
        return this.trackBackings;
    }
    getSegmentedInputForPath(path) {
        let segmentedInput = this.segmentedInputs.find(x => x.path === path);
        if (segmentedInput) {
            return segmentedInput;
        }
        let decls = null;
        if (this.internalTracks) {
            const tracks = this.internalTracks.filter(x => x.fullPath === path);
            decls = tracks.map(x => ({
                id: x.id,
                type: x.info.type,
            }));
        }
        segmentedInput = new HlsSegmentedInput(this, path, decls, null);
        this.segmentedInputs.push(segmentedInput);
        return segmentedInput;
    }
    async getMetadataTags() {
        return {};
    }
    async getMimeType() {
        return hls_misc/* HLS_MIME_TYPE */.is;
    }
    dispose() {
        if (this.segmentedInputs) {
            for (const segInput of this.segmentedInputs) {
                segInput.dispose();
            }
            this.segmentedInputs.length = 0;
        }
    }
}
class HlsInputTrackBacking {
    constructor(internalTrack) {
        this.internalTrack = internalTrack;
        this.hydrationPromise = null;
    }
    hydrate() {
        return this.hydrationPromise ??= (async () => {
            const segmentedInput = this.internalTrack.demuxer.getSegmentedInputForPath(this.internalTrack.fullPath);
            let trackBacking = null;
            const trackBackings = await segmentedInput.getTrackBackings();
            const matchingType = trackBackings.filter(x => x.getType() === this.getType());
            if (matchingType.length === 1) {
                // Avoids reading fields on the track
                trackBacking = matchingType[0];
            }
            else {
                if (this instanceof HlsInputVideoTrackBacking) {
                    for (const backing of matchingType) {
                        if ((await backing.getCodec()) === this.getCodec()) {
                            trackBacking = backing;
                            break;
                        }
                    }
                }
                else {
                    (0,misc/* assert */.vA)(this instanceof HlsInputAudioTrackBacking);
                    for (const backing of matchingType) {
                        if ((await backing.getCodec()) === this.getCodec()) {
                            trackBacking = backing;
                            break;
                        }
                    }
                }
            }
            if (!trackBacking) {
                throw new Error('Could not find matching track in underlying media data.');
            }
            this.internalTrack.backingTrack = trackBacking;
        })();
    }
    /** If the backing track is already present, delegate synchronously; otherwise, hydrate first. */
    delegate(fn) {
        if (this.internalTrack.backingTrack) {
            return fn();
        }
        return this.hydrate().then(fn);
    }
    getCodec() {
        throw new Error('Not implemented on base class.');
    }
    getDisposition() {
        return {
            ...metadata/* DEFAULT_TRACK_DISPOSITION */.gM,
            // Meanings are swapped in HLS: "Default" means that a track is the primary track.
            default: this.internalTrack.autoselect,
            primary: this.internalTrack.default,
        };
    }
    getId() {
        return this.internalTrack.id;
    }
    getPairingMask() {
        return this.internalTrack.pairingMask;
    }
    getInternalCodecId() {
        return null;
    }
    getLanguageCode() {
        return this.internalTrack.languageCode;
    }
    getName() {
        return this.internalTrack.name;
    }
    getNumber() {
        (0,misc/* assert */.vA)(this.internalTrack.demuxer.internalTracks);
        const trackType = this.internalTrack.info.type;
        let number = 0;
        for (const track of this.internalTrack.demuxer.internalTracks) {
            if (track.info.type === trackType) {
                number++;
            }
            if (track === this.internalTrack) {
                break;
            }
        }
        return number;
    }
    getTimeResolution() {
        return this.delegate(() => this.internalTrack.backingTrack.getTimeResolution());
    }
    isRelativeToUnixEpoch() {
        return this.delegate(() => this.internalTrack.backingTrack.isRelativeToUnixEpoch());
    }
    getBitrate() {
        return this.internalTrack.peakBitrate;
    }
    getAverageBitrate() {
        return this.internalTrack.averageBitrate;
    }
    async getDurationFromMetadata(options) {
        await this.hydrate();
        return this.internalTrack.backingTrack.getDurationFromMetadata(options);
    }
    async getLiveRefreshInterval() {
        await this.hydrate();
        return this.internalTrack.backingTrack.getLiveRefreshInterval();
    }
    getHasOnlyKeyPackets() {
        return this.internalTrack.hasOnlyKeyPackets || null;
    }
    async getFirstPacket(options) {
        await this.hydrate();
        return this.internalTrack.backingTrack.getFirstPacket(options);
    }
    async getPacket(timestamp, options) {
        await this.hydrate();
        return this.internalTrack.backingTrack.getPacket(timestamp, options);
    }
    async getKeyPacket(timestamp, options) {
        await this.hydrate();
        return this.internalTrack.backingTrack.getKeyPacket(timestamp, options);
    }
    async getNextPacket(packet, options) {
        await this.hydrate();
        return this.internalTrack.backingTrack.getNextPacket(packet, options);
    }
    async getNextKeyPacket(packet, options) {
        await this.hydrate();
        return this.internalTrack.backingTrack.getNextKeyPacket(packet, options);
    }
}
class HlsInputVideoTrackBacking extends HlsInputTrackBacking {
    constructor(internalTrack) {
        super(internalTrack);
    }
    get backingVideoTrack() {
        return this.internalTrack.backingTrack;
    }
    getType() {
        return 'video';
    }
    getCodec() {
        const inferredCodec = (0,codec/* inferCodecFromCodecString */.oU)(this.internalTrack.fullCodecString);
        return inferredCodec;
    }
    getCodedWidth() {
        return this.delegate(() => this.backingVideoTrack.getCodedWidth());
    }
    getCodedHeight() {
        return this.delegate(() => this.backingVideoTrack.getCodedHeight());
    }
    getSquarePixelWidth() {
        return this.delegate(() => this.backingVideoTrack.getSquarePixelWidth());
    }
    getSquarePixelHeight() {
        return this.delegate(() => this.backingVideoTrack.getSquarePixelHeight());
    }
    getMetadataDisplayWidth() {
        if (this.backingVideoTrack) {
            return null;
        }
        return this.internalTrack.info.width;
    }
    getMetadataDisplayHeight() {
        if (this.backingVideoTrack) {
            return null;
        }
        return this.internalTrack.info.height;
    }
    getRotation() {
        return this.delegate(() => this.backingVideoTrack.getRotation());
    }
    async getColorSpace() {
        await this.hydrate();
        return this.backingVideoTrack.getColorSpace();
    }
    async canBeTransparent() {
        await this.hydrate();
        return this.backingVideoTrack.canBeTransparent();
    }
    getMetadataCodecParameterString() {
        if (this.backingVideoTrack) {
            return null;
        }
        return this.internalTrack.fullCodecString;
    }
    async getDecoderConfig() {
        await this.hydrate();
        return this.backingVideoTrack.getDecoderConfig();
    }
}
class HlsInputAudioTrackBacking extends HlsInputTrackBacking {
    constructor(internalTrack) {
        super(internalTrack);
    }
    get backingAudioTrack() {
        return this.internalTrack.backingTrack;
    }
    getType() {
        return 'audio';
    }
    getCodec() {
        const inferredCodec = (0,codec/* inferCodecFromCodecString */.oU)(this.internalTrack.fullCodecString);
        return inferredCodec;
    }
    getNumberOfChannels() {
        if (this.internalTrack.info.numberOfChannels !== null) {
            return this.internalTrack.info.numberOfChannels;
        }
        return this.delegate(() => this.backingAudioTrack.getNumberOfChannels());
    }
    getSampleRate() {
        return this.delegate(() => this.backingAudioTrack.getSampleRate());
    }
    getMetadataCodecParameterString() {
        if (this.backingAudioTrack) {
            return null;
        }
        return this.internalTrack.fullCodecString;
    }
    async getDecoderConfig() {
        await this.hydrate();
        return this.backingAudioTrack.getDecoderConfig();
    }
}
const getMediaTagDefault = (attributes) => {
    const value = attributes.get('default');
    if (value === null) {
        return false;
    }
    const normalized = value.toUpperCase();
    if (normalized === 'YES') {
        return true;
    }
    if (normalized === 'NO') {
        return false;
    }
    throw new Error(`Invalid M3U8 file; #EXT-X-MEDIA DEFAULT attribute must be YES or NO, got "${value}".`);
};
const getMediaTagAutoselect = (attributes) => {
    const value = attributes.get('autoselect');
    if (value === null) {
        return false;
    }
    const normalized = value.toUpperCase();
    if (normalized === 'YES') {
        return true;
    }
    if (normalized === 'NO') {
        return false;
    }
    throw new Error(`Invalid M3U8 file; #EXT-X-MEDIA AUTOSELECT attribute must be YES or NO, got "${value}".`);
};
const preprocessLanguageCode = (code) => {
    if (code === null) {
        return misc/* UNDETERMINED_LANGUAGE */.IR;
    }
    const languageSubtag = code.split('-')[0];
    if (!languageSubtag) {
        return misc/* UNDETERMINED_LANGUAGE */.IR;
    }
    // Technically invalid, for now: The language subtag might be a language code from ISO 639-1,
    // ISO 639-2, ISO 639-3, ISO 639-5 or some other thing (source: Wikipedia). But, `languageCode` is
    // documented as ISO 639-2. Changing the definition would be a breaking change. This will get
    // cleaned up in the future by defining languageCode to be BCP 47 instead.
    return languageSubtag;
};

;// ./node_modules/mediabunny/dist/modules/src/input-format.js
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


















/**
 * Base class representing an input media file format.
 * @group Input formats
 * @public
 */
class InputFormat {
    constructor() {
        /**
         * Provided for tree-shakable checking.
         * @internal
         */
        this._isIsobmff = false;
    }
}
/**
 * Format representing files compatible with the ISO base media file format (ISOBMFF), like MP4 or MOV files.
 *
 * This format can make use of {@link InputOptions.initInput}. When the file contents are fragmented but no track
 * initialization info is provided (no `moov` atom), then it must be provided via `initInput`.
 *
 * @group Input formats
 * @public
 */
class IsobmffInputFormat extends InputFormat {
    constructor() {
        super(...arguments);
        /** @internal */
        this._isIsobmff = true;
    }
    /** @internal */
    async _getMajorBrand(input) {
        let slice = input._reader.requestSlice(0, 12);
        if (slice instanceof Promise)
            slice = await slice;
        if (!slice)
            return null;
        slice.skip(4);
        const fourCc = (0,src_reader/* readAscii */.IT)(slice, 4);
        if (fourCc !== 'ftyp'
            && fourCc !== 'styp' // Segment
        ) {
            return null;
        }
        return (0,src_reader/* readAscii */.IT)(slice, 4);
    }
    /** @internal */
    _createDemuxer(input) {
        return new IsobmffDemuxer(input);
    }
}
/**
 * MPEG-4 Part 14 (MP4) file format.
 *
 * Do not instantiate this class; use the {@link MP4} singleton instead.
 *
 * @group Input formats
 * @public
 */
class Mp4InputFormat extends IsobmffInputFormat {
    /** @internal */
    async _canReadInput(input) {
        const majorBrand = await this._getMajorBrand(input);
        if (majorBrand !== null) {
            return majorBrand !== 'qt  ';
        }
        let slice = input._reader.requestSlice(4, 4);
        if (slice instanceof Promise)
            slice = await slice;
        if (!slice)
            return false;
        return (0,src_reader/* readAscii */.IT)(slice, 4) === 'moof'; // Seen in HLS for example
    }
    get name() {
        return 'MP4';
    }
    get mimeType() {
        return 'video/mp4';
    }
}
/**
 * QuickTime File Format (QTFF), often called MOV.
 *
 * Do not instantiate this class; use the {@link QTFF} singleton instead.
 *
 * @group Input formats
 * @public
 */
class QuickTimeInputFormat extends IsobmffInputFormat {
    /** @internal */
    async _canReadInput(input) {
        const majorBrand = await this._getMajorBrand(input);
        return majorBrand === 'qt  ';
    }
    get name() {
        return 'QuickTime File Format';
    }
    get mimeType() {
        return 'video/quicktime';
    }
}
/**
 * Matroska file format.
 *
 * Do not instantiate this class; use the {@link MATROSKA} singleton instead.
 *
 * @group Input formats
 * @public
 */
class MatroskaInputFormat extends InputFormat {
    /** @internal */
    async isSupportedEBMLOfDocType(input, desiredDocType) {
        let headerSlice = input._reader.requestSlice(0, ebml/* MAX_HEADER_SIZE */.r1);
        if (headerSlice instanceof Promise)
            headerSlice = await headerSlice;
        if (!headerSlice)
            return false;
        const varIntSize = (0,ebml/* readVarIntSize */.YO)(headerSlice);
        if (varIntSize === null) {
            return false;
        }
        if (varIntSize < 1 || varIntSize > 8) {
            return false;
        }
        const id = (0,ebml/* readUnsignedInt */.dl)(headerSlice, varIntSize);
        if (id !== ebml/* EBMLId */.Cl.EBML) {
            return false;
        }
        const dataSize = (0,ebml/* readElementSize */.Kb)(headerSlice);
        if (typeof dataSize !== 'number') {
            return false; // Miss me with that shit
        }
        let dataSlice = input._reader.requestSlice(headerSlice.filePos, dataSize);
        if (dataSlice instanceof Promise)
            dataSlice = await dataSlice;
        if (!dataSlice)
            return false;
        const startPos = headerSlice.filePos;
        while (dataSlice.filePos <= startPos + dataSize - ebml/* MIN_HEADER_SIZE */.De) {
            const header = (0,ebml/* readElementHeader */.ur)(dataSlice);
            if (!header)
                break;
            const { id, size } = header;
            const dataStartPos = dataSlice.filePos;
            if (size === undefined)
                return false;
            switch (id) {
                case ebml/* EBMLId */.Cl.EBMLVersion:
                    {
                        const ebmlVersion = (0,ebml/* readUnsignedInt */.dl)(dataSlice, size);
                        if (ebmlVersion !== 1) {
                            return false;
                        }
                    }
                    ;
                    break;
                case ebml/* EBMLId */.Cl.EBMLReadVersion:
                    {
                        const ebmlReadVersion = (0,ebml/* readUnsignedInt */.dl)(dataSlice, size);
                        if (ebmlReadVersion !== 1) {
                            return false;
                        }
                    }
                    ;
                    break;
                case ebml/* EBMLId */.Cl.DocType:
                    {
                        const docType = (0,ebml/* readAsciiString */.IX)(dataSlice, size);
                        if (docType !== desiredDocType) {
                            return false;
                        }
                    }
                    ;
                    break;
                case ebml/* EBMLId */.Cl.DocTypeVersion:
                    {
                        const docTypeVersion = (0,ebml/* readUnsignedInt */.dl)(dataSlice, size);
                        if (docTypeVersion > 4) { // Support up to Matroska v4
                            return false;
                        }
                    }
                    ;
                    break;
            }
            dataSlice.filePos = dataStartPos + size;
        }
        return true;
    }
    /** @internal */
    _canReadInput(input) {
        return this.isSupportedEBMLOfDocType(input, 'matroska');
    }
    /** @internal */
    _createDemuxer(input) {
        return new MatroskaDemuxer(input);
    }
    get name() {
        return 'Matroska';
    }
    get mimeType() {
        return 'video/x-matroska';
    }
}
/**
 * WebM file format, based on Matroska.
 *
 * Do not instantiate this class; use the {@link WEBM} singleton instead.
 *
 * @group Input formats
 * @public
 */
class WebMInputFormat extends MatroskaInputFormat {
    /** @internal */
    _canReadInput(input) {
        return this.isSupportedEBMLOfDocType(input, 'webm');
    }
    get name() {
        return 'WebM';
    }
    get mimeType() {
        return 'video/webm';
    }
}
/**
 * MP3 file format.
 *
 * Do not instantiate this class; use the {@link MP3} singleton instead.
 *
 * @group Input formats
 * @public
 */
class Mp3InputFormat extends InputFormat {
    /** @internal */
    async _canReadInput(input) {
        let currentPos = 0;
        while (true) {
            let slice = input._reader.requestSlice(currentPos, id3/* ID3_V2_HEADER_SIZE */.sY);
            if (slice instanceof Promise)
                slice = await slice;
            if (!slice)
                break;
            const id3V2Header = (0,id3/* readId3V2Header */.IX)(slice);
            if (!id3V2Header) {
                break;
            }
            currentPos = slice.filePos + id3V2Header.size;
        }
        const firstResult = await readNextMp3FrameHeader(input._reader, currentPos, currentPos + 4096);
        if (!firstResult) {
            return false;
        }
        const firstHeader = firstResult.header;
        const xingOffset = (0,mp3_misc/* getXingOffset */.EZ)(firstHeader.mpegVersionId, firstHeader.channel);
        let slice = input._reader.requestSlice(firstResult.startPos + xingOffset, 4);
        if (slice instanceof Promise)
            slice = await slice;
        if (!slice)
            return false;
        const word = (0,src_reader/* readU32Be */.cN)(slice);
        const isXing = word === mp3_misc/* XING */.hY || word === mp3_misc/* INFO */.rD;
        if (isXing) {
            // Gotta be MP3
            return true;
        }
        currentPos = firstResult.startPos + firstResult.header.totalSize;
        // Fine, we found one frame header, but we're still not entirely sure this is MP3. Let's check if we can find
        // another header right after it:
        const secondResult = await readNextMp3FrameHeader(input._reader, currentPos, currentPos + mp3_misc/* FRAME_HEADER_SIZE */.Yq);
        if (!secondResult) {
            return false;
        }
        const secondHeader = secondResult.header;
        // In a well-formed MP3 file, we'd expect these two frames to share some similarities:
        if (firstHeader.channel !== secondHeader.channel || firstHeader.sampleRate !== secondHeader.sampleRate) {
            return false;
        }
        // We have found two matching consecutive MP3 frames, a strong indicator that this is an MP3 file
        return true;
    }
    /** @internal */
    _createDemuxer(input) {
        return new Mp3Demuxer(input);
    }
    get name() {
        return 'MP3';
    }
    get mimeType() {
        return 'audio/mpeg';
    }
}
/**
 * WAVE file format, based on RIFF.
 *
 * Do not instantiate this class; use the {@link WAVE} singleton instead.
 *
 * @group Input formats
 * @public
 */
class WaveInputFormat extends InputFormat {
    /** @internal */
    async _canReadInput(input) {
        let slice = input._reader.requestSlice(0, 12);
        if (slice instanceof Promise)
            slice = await slice;
        if (!slice)
            return false;
        const riffType = (0,src_reader/* readAscii */.IT)(slice, 4);
        if (riffType !== 'RIFF' && riffType !== 'RIFX' && riffType !== 'RF64') {
            return false;
        }
        slice.skip(4);
        const format = (0,src_reader/* readAscii */.IT)(slice, 4);
        return format === 'WAVE';
    }
    /** @internal */
    _createDemuxer(input) {
        return new wave_demuxer/* WaveDemuxer */.E(input);
    }
    get name() {
        return 'WAVE';
    }
    get mimeType() {
        return 'audio/wav';
    }
}
/**
 * Ogg file format.
 *
 * Do not instantiate this class; use the {@link OGG} singleton instead.
 *
 * @group Input formats
 * @public
 */
class OggInputFormat extends InputFormat {
    /** @internal */
    async _canReadInput(input) {
        let slice = input._reader.requestSlice(0, 4);
        if (slice instanceof Promise)
            slice = await slice;
        if (!slice)
            return false;
        return (0,src_reader/* readAscii */.IT)(slice, 4) === 'OggS';
    }
    /** @internal */
    _createDemuxer(input) {
        return new OggDemuxer(input);
    }
    get name() {
        return 'Ogg';
    }
    get mimeType() {
        return 'application/ogg';
    }
}
/**
 * FLAC file format.
 *
 * Do not instantiate this class; use the {@link FLAC} singleton instead.
 *
 * @group Input formats
 * @public
 */
class FlacInputFormat extends InputFormat {
    /** @internal */
    async _canReadInput(input) {
        let slice = input._reader.requestSlice(0, 4);
        if (slice instanceof Promise)
            slice = await slice;
        if (!slice)
            return false;
        return (0,src_reader/* readAscii */.IT)(slice, 4) === 'fLaC';
    }
    get name() {
        return 'FLAC';
    }
    get mimeType() {
        return 'audio/flac';
    }
    /** @internal */
    _createDemuxer(input) {
        return new FlacDemuxer(input);
    }
}
/**
 * ADTS file format.
 *
 * Do not instantiate this class; use the {@link ADTS} singleton instead.
 *
 * @group Input formats
 * @public
 */
class AdtsInputFormat extends InputFormat {
    /** @internal */
    async _canReadInput(input) {
        let currentPos = 0;
        while (true) {
            let slice = input._reader.requestSlice(currentPos, id3/* ID3_V2_HEADER_SIZE */.sY);
            if (slice instanceof Promise)
                slice = await slice;
            if (!slice)
                break;
            const id3V2Header = (0,id3/* readId3V2Header */.IX)(slice);
            if (!id3V2Header) {
                break;
            }
            currentPos = slice.filePos + id3V2Header.size;
        }
        let slice = input._reader.requestSliceRange(currentPos, adts_reader/* MIN_ADTS_FRAME_HEADER_SIZE */.gc, adts_reader/* MAX_ADTS_FRAME_HEADER_SIZE */.Y$);
        if (slice instanceof Promise)
            slice = await slice;
        if (!slice)
            return false;
        const firstHeader = (0,adts_reader/* readAdtsFrameHeader */.lh)(slice);
        if (!firstHeader) {
            return false;
        }
        currentPos += firstHeader.frameLength;
        slice = input._reader.requestSliceRange(currentPos, adts_reader/* MIN_ADTS_FRAME_HEADER_SIZE */.gc, adts_reader/* MAX_ADTS_FRAME_HEADER_SIZE */.Y$);
        if (slice instanceof Promise)
            slice = await slice;
        if (!slice)
            return false;
        const secondHeader = (0,adts_reader/* readAdtsFrameHeader */.lh)(slice);
        if (!secondHeader) {
            return false;
        }
        return firstHeader.objectType === secondHeader.objectType
            && firstHeader.samplingFrequencyIndex === secondHeader.samplingFrequencyIndex
            && firstHeader.channelConfiguration === secondHeader.channelConfiguration;
    }
    /** @internal */
    _createDemuxer(input) {
        return new AdtsDemuxer(input);
    }
    get name() {
        return 'ADTS';
    }
    get mimeType() {
        return 'audio/aac';
    }
}
/**
 * MPEG Transport Stream (MPEG-TS) file format.
 *
 * This format can make use of {@link InputOptions.initInput} to initialize track information even when no
 * initialization information is provided for the track, for example because it has no key frames. In this case, tracks
 * are matched to each other based on their PID.
 *
 * Do not instantiate this class; use the {@link MPEG_TS} singleton instead.
 *
 * @group Input formats
 * @public
 */
class MpegTsInputFormat extends InputFormat {
    /** @internal */
    async _canReadInput(input) {
        const lengthToCheck = mpeg_ts_misc/* TS_PACKET_SIZE */.ZT + 16 + 1;
        let slice = input._reader.requestSlice(0, lengthToCheck);
        if (slice instanceof Promise)
            slice = await slice;
        if (!slice)
            return false;
        const bytes = (0,src_reader/* readBytes */.io)(slice, lengthToCheck);
        if (bytes[0] === 0x47 && bytes[mpeg_ts_misc/* TS_PACKET_SIZE */.ZT] === 0x47) {
            // Regular MPEG-TS
            return true;
        }
        else if (bytes[0] === 0x47 && bytes[mpeg_ts_misc/* TS_PACKET_SIZE */.ZT + 16] === 0x47) {
            // MPEG-TS with Forward Error Correction
            return true;
        }
        else if (bytes[4] === 0x47 && bytes[4 + mpeg_ts_misc/* TS_PACKET_SIZE */.ZT + 4] === 0x47) {
            // MPEG-2-TS (DVHS)
            return true;
        }
        return false;
    }
    /** @internal */
    _createDemuxer(input) {
        return new MpegTsDemuxer(input);
    }
    get name() {
        return 'MPEG Transport Stream';
    }
    get mimeType() {
        return 'video/MP2T';
    }
}
/**
 * Media described using the HTTP Live Streaming (HLS) protocol, with playlists in the M3U8 format.
 *
 * Do not instantiate this class; use the {@link HLS} singleton instead.
 *
 * @group Input formats
 * @public
 */
class HlsInputFormat extends InputFormat {
    /** @internal */
    async _canReadInput(input) {
        let slice = input._reader.requestSlice(0, 7);
        if (slice instanceof Promise)
            slice = await slice;
        if (!slice)
            return false;
        const isM3u8 = (0,src_reader/* readAscii */.IT)(slice, 7) === '#EXTM3U';
        if (!isM3u8) {
            return false;
        }
        if (!(input._rootSource instanceof source/* PathedSource */.QI)) {
            throw new TypeError('HLS inputs require `InputOptions.source` to be a PathedSource or a ref to one.');
        }
        input._rootSource._usedForHls = true;
        return true;
    }
    /** @internal */
    _createDemuxer(input) {
        return new HlsDemuxer(input);
    }
    get name() {
        return 'HTTP Live Streaming (HLS)';
    }
    get mimeType() {
        return hls_misc/* HLS_MIME_TYPE */.is;
    }
}
/**
 * MP4 input format singleton.
 * @group Input formats
 * @public
 */
const MP4 = /* #__PURE__ */ new Mp4InputFormat();
/**
 * QuickTime File Format input format singleton.
 * @group Input formats
 * @public
 */
const QTFF = /* #__PURE__ */ new QuickTimeInputFormat();
/**
 * Matroska input format singleton.
 * @group Input formats
 * @public
 */
const MATROSKA = /* #__PURE__ */ new MatroskaInputFormat();
/**
 * WebM input format singleton.
 * @group Input formats
 * @public
 */
const WEBM = /* #__PURE__ */ new WebMInputFormat();
/**
 * MP3 input format singleton.
 * @group Input formats
 * @public
 */
const MP3 = /* #__PURE__ */ new Mp3InputFormat();
/**
 * WAVE input format singleton.
 * @group Input formats
 * @public
 */
const WAVE = /* #__PURE__ */ new WaveInputFormat();
/**
 * Ogg input format singleton.
 * @group Input formats
 * @public
 */
const OGG = /* #__PURE__ */ new OggInputFormat();
/**
 * ADTS input format singleton.
 * @group Input formats
 * @public
 */
const ADTS = /* #__PURE__ */ new AdtsInputFormat();
/**
 * FLAC input format singleton.
 * @group Input formats
 * @public
 */
const FLAC = /* #__PURE__ */ new FlacInputFormat();
/**
 * MPEG-TS input format singleton.
 * @group Input formats
 * @public
 */
const MPEG_TS = /* #__PURE__ */ new MpegTsInputFormat();
/**
 * HLS input format singleton.
 * @group Input formats
 * @public
 */
const HLS = /* #__PURE__ */ new HlsInputFormat();
/**
 * List of all input format singletons. If you don't need to support all input formats, you should specify the
 * formats individually for better tree shaking.
 * @group Input formats
 * @public
 */
const ALL_FORMATS = [HLS, MP4, QTFF, MATROSKA, WEBM, WAVE, OGG, FLAC, MP3, ADTS, MPEG_TS];
/**
 * List of input formats required for playback of typical HLS manifests. Includes HLS itself as well as the typical
 * segment formats: MPEG Transport Stream (.ts), MP4 (CMAF), ADTS (.aac) and MP3.
 * @group Input formats
 * @public
 */
const HLS_FORMATS = [HLS, MP4, QTFF, MP3, ADTS, MPEG_TS];
const validateInputFormatOptions = (options, prefix) => {
    if (!options || typeof options !== 'object') {
        throw new TypeError(`${prefix}, when provided, must be an object.`);
    }
    if (options.isobmff !== undefined) {
        if (!options.isobmff || typeof options.isobmff !== 'object') {
            throw new TypeError(`${prefix}.isobmff, when provided, must be an object.`);
        }
        if (options.isobmff.resolveKeyId !== undefined && typeof options.isobmff.resolveKeyId !== 'function') {
            throw new TypeError(`${prefix}.isobmff.resolveKeyId, when provided, must be a function.`);
        }
    }
};


/***/ },

/***/ 6244
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   D8: () => (/* binding */ prefer),
/* harmony export */   Kh: () => (/* binding */ InputTrack),
/* harmony export */   N0: () => (/* binding */ InputVideoTrack),
/* harmony export */   NY: () => (/* binding */ queryInputTracks),
/* harmony export */   Uj: () => (/* binding */ mergeInputTrackQueries),
/* harmony export */   Yi: () => (/* binding */ InputAudioTrack),
/* harmony export */   i8: () => (/* binding */ desc),
/* harmony export */   vo: () => (/* binding */ toValidatedInputTrackQuery)
/* harmony export */ });
/* unused harmony export asc */
/* harmony import */ var _codec_data_js__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(6297);
/* harmony import */ var _custom_coder_js__WEBPACK_IMPORTED_MODULE_1__ = __webpack_require__(8647);
/* harmony import */ var _media_sink_js__WEBPACK_IMPORTED_MODULE_2__ = __webpack_require__(388);
/* harmony import */ var _misc_js__WEBPACK_IMPORTED_MODULE_3__ = __webpack_require__(3912);
/* harmony import */ var _packet_js__WEBPACK_IMPORTED_MODULE_4__ = __webpack_require__(3936);
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */





/**
 * Represents a media track in an input file.
 * @group Input files & tracks
 * @public
 */
class InputTrack {
    /** @internal */
    constructor(input, backing) {
        this.input = input;
        this._backing = backing;
    }
    /** Returns true if and only if this track is a video track. */
    isVideoTrack() {
        return this instanceof InputVideoTrack;
    }
    /** Returns true if and only if this track is an audio track. */
    isAudioTrack() {
        return this instanceof InputAudioTrack;
    }
    /** The unique ID of this track in the input file. */
    get id() {
        return this._backing.getId();
    }
    /**
     * The 1-based index of this track among all tracks of the same type in the input file. For example, the first
     * video track has number 1, the second video track has number 2, and so on. The index refers to the order in
     * which the tracks are returned by {@link Input.getTracks}.
     */
    get number() {
        return this._backing.getNumber();
    }
    /**
     * Returns the identifier of the codec used internally by the container. It is not homogenized by Mediabunny
     * and depends entirely on the container format.
     *
     * This method can be used to determine the codec of a track in case Mediabunny doesn't know that codec.
     *
     * - For ISOBMFF files, this resolves to the name of the Sample Description Box (e.g. `'avc1'`).
     * - For Matroska files, this resolves to the value of the `CodecID` element.
     * - For WAVE files, this resolves to the value of the format tag in the `'fmt '` chunk.
     * - For ADTS files, this resolves to the `MPEG-4 Audio Object Type`.
     * - For MPEG-TS files, this resolves to the `streamType` value from the Program Map Table.
     * - In all other cases, this resolves to `null`.
     */
    async getInternalCodecId() {
        return this._backing.getInternalCodecId();
    }
    /**
     * See {@link InputTrack.getInternalCodecId}.
     * @deprecated Use {@link InputTrack.getInternalCodecId} instead.
     */
    get internalCodecId() {
        return requireSync(this._backing.getInternalCodecId(), 'internalCodecId', 'getInternalCodecId');
    }
    /**
     * Returns the ISO 639-2/T language code for this track. If the language is unknown, this resolves to `'und'`
     * (undetermined).
     */
    async getLanguageCode() {
        return this._backing.getLanguageCode();
    }
    /**
     * The ISO 639-2/T language code for this track. If the language is unknown, this field is `'und'` (undetermined).
     * @deprecated Use {@link InputTrack.getLanguageCode} instead.
     */
    get languageCode() {
        return requireSync(this._backing.getLanguageCode(), 'languageCode', 'getLanguageCode');
    }
    /** Returns the user-defined name for this track. */
    async getName() {
        return this._backing.getName();
    }
    /**
     * A user-defined name for this track.
     * @deprecated Use {@link InputTrack.getName} instead.
     */
    get name() {
        return requireSync(this._backing.getName(), 'name', 'getName');
    }
    /**
     * Returns a positive number x such that all timestamps and durations of all packets of this track are
     * integer multiples of 1/x.
     */
    async getTimeResolution() {
        return this._backing.getTimeResolution();
    }
    /**
     * A positive number x such that all timestamps and durations of all packets of this track are
     * integer multiples of 1/x.
     * @deprecated Use {@link InputTrack.getTimeResolution} instead.
     */
    get timeResolution() {
        return requireSync(this._backing.getTimeResolution(), 'timeResolution', 'getTimeResolution');
    }
    /**
     * Returns whether the timestamps of this track are relative to the Unix epoch (January 1, 1970 00:00:00 UTC).
     * When `true`, each timestamp maps to a definitive point in time.
     */
    async isRelativeToUnixEpoch() {
        return this._backing.isRelativeToUnixEpoch();
    }
    /** Returns the track's disposition, i.e. information about its intended usage. */
    async getDisposition() {
        return this._backing.getDisposition();
    }
    /**
     * The track's disposition, i.e. information about its intended usage.
     * @deprecated Use {@link InputTrack.getDisposition} instead.
     */
    get disposition() {
        return requireSync(this._backing.getDisposition(), 'disposition', 'getDisposition');
    }
    /**
     * Returns the peak bitrate of the track in bits per second, as specified in the track's metadata. This might not
     * match the actual media data's bitrate.
     */
    async getBitrate() {
        return this._backing.getBitrate();
    }
    /**
     * Returns the average bitrate of the track in bits per second, as specified in the track's metadata. This might
     * not match the actual media data's bitrate.
     */
    async getAverageBitrate() {
        return this._backing.getAverageBitrate();
    }
    /**
     * Returns the start timestamp of the first packet of this track, in seconds. While often near zero, this value
     * may be positive or even negative. A negative starting timestamp means the track's timing has been offset. Samples
     * with a negative timestamp should not be presented.
     */
    async getFirstTimestamp() {
        const firstPacket = await this._backing.getFirstPacket({ metadataOnly: true });
        return firstPacket?.timestamp ?? 0;
    }
    /**
     * Returns the end timestamp of the last packet of this track, in seconds.
     *
     * By default, when the underlying media is live, this method will only resolve once the live stream ends. If you
     * want to query the current end timestamp of the stream, set {@link PacketRetrievalOptions.skipLiveWait} to `true`
     * in the options.
     */
    async computeDuration(options) {
        const lastPacket = await this._backing.getPacket(Infinity, { metadataOnly: true, ...options });
        const result = (lastPacket?.timestamp ?? 0) + (lastPacket?.duration ?? 0);
        return (0,_misc_js__WEBPACK_IMPORTED_MODULE_3__/* .roundToDivisor */ .gl)(result, await this.getTimeResolution());
    }
    /**
     * Gets the duration (end timestamp) in seconds of this track from metadata stored in the file. This value may be
     * approximate or diverge from the actual, precise duration returned by `.computeDuration()`, but compared to that
     * method, this method is cheaper. When the duration cannot be determined from the file metadata, `null`
     * is returned.
     *
     * By default, when the underlying media is live, this method will only resolve once the live stream
     * ends. If you want to query the current duration of the media, set
     * {@link DurationMetadataRequestOptions.skipLiveWait} to `true` in the options.
     */
    async getDurationFromMetadata(options = {}) {
        return this._backing.getDurationFromMetadata(options);
    }
    /**
     * Computes aggregate packet statistics for this track, such as average packet rate or bitrate.
     *
     * @param targetPacketCount - This optional parameter sets a target for how many packets this method must have
     * looked at before it can return early; this means, you can use it to aggregate only a subset (prefix) of all
     * packets. This is very useful for getting a great estimate of video frame rate without having to scan through the
     * entire file.
     *
     * By default, when the underlying media is live and `targetPacketCount` is not set, this method will only resolve
     * once the live stream ends. If you want to query the current packet statistics of the stream, set
     * {@link PacketRetrievalOptions.skipLiveWait} to `true` in the options.
     */
    async computePacketStats(targetPacketCount = Infinity, options) {
        const sink = new _media_sink_js__WEBPACK_IMPORTED_MODULE_2__/* .EncodedPacketSink */ .kQ(this);
        let startTimestamp = Infinity;
        let endTimestamp = -Infinity;
        let packetCount = 0;
        let totalPacketBytes = 0;
        for await (const packet of sink.packets(undefined, undefined, { metadataOnly: true, ...options })) {
            if (packetCount >= targetPacketCount
                // This additional condition is needed to produce correct results with out-of-presentation-order packets
                && packet.timestamp >= endTimestamp) {
                break;
            }
            startTimestamp = Math.min(startTimestamp, packet.timestamp);
            endTimestamp = Math.max(endTimestamp, packet.timestamp + packet.duration);
            packetCount++;
            totalPacketBytes += packet.byteLength;
        }
        return {
            packetCount,
            averagePacketRate: packetCount
                ? Number((packetCount / (endTimestamp - startTimestamp)).toPrecision(16))
                : 0,
            averageBitrate: packetCount
                ? Number((8 * totalPacketBytes / (endTimestamp - startTimestamp)).toPrecision(16))
                : 0,
        };
    }
    /**
     * Whether or not this track is currently live, meaning the media's end is still unknown.
     *
     * The value returned by this method may change over time as the track stops being live. To keep track of the
     * track's live status, poll this method at the track's refresh interval
     * via {@link InputTrack.getLiveRefreshInterval}.
     */
    async isLive() {
        return (await this._backing.getLiveRefreshInterval()) !== null;
    }
    /**
     * Returns the track's live refresh interval in seconds, or `null` if the track is not live. This interval describes
     * the time it takes, on average, for new live media data to become available.
     */
    async getLiveRefreshInterval() {
        return this._backing.getLiveRefreshInterval();
    }
    /**
     * Returns `true` if this track can be paired with the given track. Two tracks being pairable means they can be
     * presented (displayed) together.
     *
     * Returns `false` if `other` equals `this`.
     */
    canBePairedWith(other) {
        if (!(other instanceof InputTrack)) {
            throw new TypeError('other must be an InputTrack.');
        }
        if (this.input !== other.input || this === other) {
            return false;
        }
        return (this._backing.getPairingMask() & other._backing.getPairingMask()) !== 0n;
    }
    /**
     * Gets the list of other tracks that can be paired with this track. An optional query can be provided to narrow
     * down the results.
     */
    async getPairableTracks(query) {
        return this.input.getTracks(mergeInputTrackQueries({
            filter: t => t.canBePairedWith(this),
        }, query));
    }
    /**
     * Gets the list of other video tracks that can be paired with this track. An optional query can be provided to
     * narrow down the results.
     */
    async getPairableVideoTracks(query) {
        return this.input.getVideoTracks(mergeInputTrackQueries({
            filter: t => t.canBePairedWith(this),
        }, query));
    }
    /**
     * Gets the list of other audio tracks that can be paired with this track. An optional query can be provided to
     * narrow down the results.
     */
    async getPairableAudioTracks(query) {
        return this.input.getAudioTracks(mergeInputTrackQueries({
            filter: t => t.canBePairedWith(this),
        }, query));
    }
    /** Returns the primary track that can be paired with this track, optionally steered by the provided query. */
    async getPrimaryPairableVideoTrack(query) {
        return this.input.getPrimaryVideoTrack(mergeInputTrackQueries({
            filter: t => t.canBePairedWith(this),
        }, query));
    }
    /** Returns the primary track that can be paired with this track, optionally steered by the provided query. */
    async getPrimaryPairableAudioTrack(query) {
        return this.input.getPrimaryAudioTrack(mergeInputTrackQueries({
            filter: t => t.canBePairedWith(this),
        }, query));
    }
    /** Returns `true` if there is another track that can be paired with this track. */
    async hasPairableTrack(predicate) {
        predicate &&= toValidatedPredicate(predicate);
        const tracks = await this.input.getTracks();
        for (const track of tracks) {
            if (!this.canBePairedWith(track)) {
                continue;
            }
            if (!predicate || await predicate(track)) {
                return true;
            }
        }
        return false;
    }
    /** Returns `true` if there is a video track that can be paired with this track. */
    hasPairableVideoTrack(predicate) {
        predicate &&= toValidatedPredicate(predicate);
        return this.hasPairableTrack(async (x) => x.isVideoTrack() && (!predicate || await predicate(x)));
    }
    /** Returns `true` if there is an audio track that can be paired with this track. */
    hasPairableAudioTrack(predicate) {
        predicate &&= toValidatedPredicate(predicate);
        return this.hasPairableTrack(async (x) => x.isAudioTrack() && (!predicate || await predicate(x)));
    }
}
const requireSync = (value, getterName, asyncName) => {
    if (value instanceof Promise) {
        throw new Error(`'${getterName}' is deprecated and not available synchronously for this track. Use the preferred`
            + ` '${asyncName}()' instead.`);
    }
    return value;
};
const toValidatedPredicate = (predicate) => {
    if (predicate !== undefined && typeof predicate !== 'function') {
        throw new TypeError('predicate, when provided, must be a function.');
    }
    return predicate
        ? (track) => {
            const handle = (result) => {
                if (typeof result !== 'boolean') {
                    throw new TypeError('predicate must return or resolve to a boolean value.');
                }
                return result;
            };
            const result = predicate(track);
            if (result instanceof Promise) {
                return result.then(handle);
            }
            return handle(result);
        }
        : undefined;
};
/**
 * Represents a video track in an input file.
 * @group Input files & tracks
 * @public
 */
class InputVideoTrack extends InputTrack {
    /** @internal */
    constructor(input, backing) {
        super(input, backing);
        /** @internal */
        this._pixelAspectRatioCache = null;
        this._backing = backing;
    }
    get type() {
        return 'video';
    }
    /** The codec of the track's packets. */
    async getCodec() {
        return this._backing.getCodec();
    }
    /**
     * The codec of the track's packets.
     * @deprecated Use {@link InputVideoTrack.getCodec} instead.
     */
    get codec() {
        return requireSync(this._backing.getCodec(), 'codec', 'getCodec');
    }
    async hasOnlyKeyPackets() {
        return (await this._backing.getHasOnlyKeyPackets?.()) ?? false;
    }
    /** Returns the width in pixels of the track's coded samples, before any transformations or rotations. */
    async getCodedWidth() {
        return this._backing.getCodedWidth();
    }
    /**
     * The width in pixels of the track's coded samples, before any transformations or rotations.
     * @deprecated Use {@link InputVideoTrack.getCodedWidth} instead.
     */
    get codedWidth() {
        return requireSync(this._backing.getCodedWidth(), 'codedWidth', 'getCodedWidth');
    }
    /** Returns the height in pixels of the track's coded samples, before any transformations or rotations. */
    async getCodedHeight() {
        return this._backing.getCodedHeight();
    }
    /**
     * The height in pixels of the track's coded samples, before any transformations or rotations.
     * @deprecated Use {@link InputVideoTrack.getCodedHeight} instead.
     */
    get codedHeight() {
        return requireSync(this._backing.getCodedHeight(), 'codedHeight', 'getCodedHeight');
    }
    /** Returns the angle in degrees by which the track's frames should be rotated (clockwise). */
    async getRotation() {
        return this._backing.getRotation();
    }
    /**
     * The angle in degrees by which the track's frames should be rotated (clockwise).
     * @deprecated Use {@link InputVideoTrack.getRotation} instead.
     */
    get rotation() {
        return requireSync(this._backing.getRotation(), 'rotation', 'getRotation');
    }
    /**
     * Returns the width of the track's frames in square pixels, adjusted for pixel aspect ratio but before rotation.
     */
    async getSquarePixelWidth() {
        return this._backing.getSquarePixelWidth();
    }
    /**
     * The width of the track's frames in square pixels, adjusted for pixel aspect ratio but before rotation.
     * @deprecated Use {@link InputVideoTrack.getSquarePixelWidth} instead.
     */
    get squarePixelWidth() {
        return requireSync(this._backing.getSquarePixelWidth(), 'squarePixelWidth', 'getSquarePixelWidth');
    }
    /**
     * Returns the height of the track's frames in square pixels, adjusted for pixel aspect ratio but before rotation.
     */
    async getSquarePixelHeight() {
        return this._backing.getSquarePixelHeight();
    }
    /**
     * The height of the track's frames in square pixels, adjusted for pixel aspect ratio but before rotation.
     * @deprecated Use {@link InputVideoTrack.getSquarePixelHeight} instead.
     */
    get squarePixelHeight() {
        return requireSync(this._backing.getSquarePixelHeight(), 'squarePixelHeight', 'getSquarePixelHeight');
    }
    /**
     * Returns the pixel aspect ratio of the track's frames as a rational number in its reduced form. Most videos use
     * square pixels (1:1).
     */
    async getPixelAspectRatio() {
        // Potential minor async race condition here if called twice, but doesn't matter since the computation is
        // so cheap
        return this._pixelAspectRatioCache ??= (0,_misc_js__WEBPACK_IMPORTED_MODULE_3__/* .simplifyRational */ .Yf)({
            num: (await this.getSquarePixelWidth()) * (await this.getCodedHeight()),
            den: (await this.getSquarePixelHeight()) * (await this.getCodedWidth()),
        });
    }
    /**
     * The pixel aspect ratio of the track's frames, as a rational number in its reduced form. Most videos use
     * square pixels (1:1).
     * @deprecated Use {@link InputVideoTrack.getPixelAspectRatio} instead.
     */
    get pixelAspectRatio() {
        return this._pixelAspectRatioCache ??= (0,_misc_js__WEBPACK_IMPORTED_MODULE_3__/* .simplifyRational */ .Yf)({
            num: requireSync(this._backing.getSquarePixelWidth(), 'pixelAspectRatio', 'getPixelAspectRatio')
                * requireSync(this._backing.getCodedHeight(), 'pixelAspectRatio', 'getPixelAspectRatio'),
            den: requireSync(this._backing.getSquarePixelHeight(), 'pixelAspectRatio', 'getPixelAspectRatio')
                * requireSync(this._backing.getCodedWidth(), 'pixelAspectRatio', 'getPixelAspectRatio'),
        });
    }
    /** Returns the display width of the track's frames in pixels, after aspect ratio adjustment and rotation. */
    async getDisplayWidth() {
        const metadata = await this._backing.getMetadataDisplayWidth?.();
        if (metadata != null) {
            return metadata;
        }
        const rotation = await this.getRotation();
        return rotation % 180 === 0 ? this.getSquarePixelWidth() : this.getSquarePixelHeight();
    }
    /**
     * The display width of the track's frames in pixels, after aspect ratio adjustment and rotation.
     * @deprecated Use {@link InputVideoTrack.getDisplayWidth} instead.
     */
    get displayWidth() {
        const metadataRaw = this._backing.getMetadataDisplayWidth?.();
        if (metadataRaw !== undefined) {
            const metadata = requireSync(metadataRaw, 'displayWidth', 'getDisplayWidth');
            if (metadata !== null) {
                return metadata;
            }
        }
        const rotation = requireSync(this._backing.getRotation(), 'displayWidth', 'getDisplayWidth');
        const value = rotation % 180 === 0
            ? this._backing.getSquarePixelWidth()
            : this._backing.getSquarePixelHeight();
        return requireSync(value, 'displayWidth', 'getDisplayWidth');
    }
    /** Returns the display height of the track's frames in pixels, after aspect ratio adjustment and rotation. */
    async getDisplayHeight() {
        const metadata = await this._backing.getMetadataDisplayHeight?.();
        if (metadata != null) {
            return metadata;
        }
        const rotation = await this.getRotation();
        return rotation % 180 === 0 ? this.getSquarePixelHeight() : this.getSquarePixelWidth();
    }
    /**
     * The display height of the track's frames in pixels, after aspect ratio adjustment and rotation.
     * @deprecated Use {@link InputVideoTrack.getDisplayHeight} instead.
     */
    get displayHeight() {
        const metadataRaw = this._backing.getMetadataDisplayHeight?.();
        if (metadataRaw !== undefined) {
            const metadata = requireSync(metadataRaw, 'displayHeight', 'getDisplayHeight');
            if (metadata !== null) {
                return metadata;
            }
        }
        const rotation = requireSync(this._backing.getRotation(), 'displayHeight', 'getDisplayHeight');
        const value = rotation % 180 === 0
            ? this._backing.getSquarePixelHeight()
            : this._backing.getSquarePixelWidth();
        return requireSync(value, 'displayHeight', 'getDisplayHeight');
    }
    /** Returns the color space of the track's samples. */
    async getColorSpace() {
        return this._backing.getColorSpace();
    }
    /** If this method returns true, the track's samples use a high dynamic range (HDR). */
    async hasHighDynamicRange() {
        const colorSpace = await this._backing.getColorSpace();
        return colorSpace.primaries === 'bt2020' || colorSpace.primaries === 'smpte432'
            || colorSpace.transfer === 'pg' || colorSpace.transfer === 'hlg'
            || colorSpace.matrix === 'bt2020-ncl';
    }
    /** Checks if this track may contain transparent samples with alpha data. */
    async canBeTransparent() {
        return this._backing.canBeTransparent();
    }
    /**
     * Returns the [decoder configuration](https://www.w3.org/TR/webcodecs/#video-decoder-config) for decoding the
     * track's packets using a [`VideoDecoder`](https://developer.mozilla.org/en-US/docs/Web/API/VideoDecoder). Returns
     * null if the track's codec is unknown.
     */
    async getDecoderConfig() {
        return this._backing.getDecoderConfig();
    }
    async getCodecParameterString() {
        const fromMetadata = await this._backing.getMetadataCodecParameterString?.();
        if (fromMetadata != null) {
            return fromMetadata;
        }
        const decoderConfig = await this._backing.getDecoderConfig();
        return decoderConfig?.codec ?? null;
    }
    async canDecode() {
        try {
            const decoderConfig = await this._backing.getDecoderConfig();
            if (!decoderConfig) {
                return false;
            }
            const codec = await this._backing.getCodec();
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_3__/* .assert */ .vA)(codec !== null);
            if (_custom_coder_js__WEBPACK_IMPORTED_MODULE_1__/* .customVideoDecoders */ .wb.some(x => x.supports(codec, decoderConfig))) {
                return true;
            }
            if (typeof VideoDecoder === 'undefined') {
                return false;
            }
            const support = await VideoDecoder.isConfigSupported(decoderConfig);
            return support.supported === true;
        }
        catch (error) {
            console.error('Error during decodability check:', error);
            return false;
        }
    }
    async determinePacketType(packet) {
        if (!(packet instanceof _packet_js__WEBPACK_IMPORTED_MODULE_4__/* .EncodedPacket */ .Z)) {
            throw new TypeError('packet must be an EncodedPacket.');
        }
        if (packet.isMetadataOnly) {
            throw new TypeError('packet must not be metadata-only to determine its type.');
        }
        const codec = await this.getCodec();
        if (codec === null) {
            return null;
        }
        const decoderConfig = await this.getDecoderConfig();
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_3__/* .assert */ .vA)(decoderConfig);
        return (0,_codec_data_js__WEBPACK_IMPORTED_MODULE_0__/* .determineVideoPacketType */ .PR)(codec, decoderConfig, packet.data);
    }
}
/**
 * Represents an audio track in an input file.
 * @group Input files & tracks
 * @public
 */
class InputAudioTrack extends InputTrack {
    /** @internal */
    constructor(input, backing) {
        super(input, backing);
        this._backing = backing;
    }
    get type() {
        return 'audio';
    }
    /** The codec of the track's packets. */
    async getCodec() {
        return this._backing.getCodec();
    }
    /**
     * The codec of the track's packets.
     * @deprecated Use {@link InputAudioTrack.getCodec} instead.
     */
    get codec() {
        return requireSync(this._backing.getCodec(), 'codec', 'getCodec');
    }
    async hasOnlyKeyPackets() {
        return (await this._backing.getHasOnlyKeyPackets?.()) ?? true;
    }
    /** Returns the number of audio channels in the track. */
    async getNumberOfChannels() {
        return this._backing.getNumberOfChannels();
    }
    /**
     * The number of audio channels in the track.
     * @deprecated Use {@link InputAudioTrack.getNumberOfChannels} instead.
     */
    get numberOfChannels() {
        return requireSync(this._backing.getNumberOfChannels(), 'numberOfChannels', 'getNumberOfChannels');
    }
    /** Returns the track's audio sample rate in hertz. */
    async getSampleRate() {
        return this._backing.getSampleRate();
    }
    /**
     * The track's audio sample rate in hertz.
     * @deprecated Use {@link InputAudioTrack.getSampleRate} instead.
     */
    get sampleRate() {
        return requireSync(this._backing.getSampleRate(), 'sampleRate', 'getSampleRate');
    }
    /**
     * Returns the [decoder configuration](https://www.w3.org/TR/webcodecs/#audio-decoder-config) for decoding the
     * track's packets using an [`AudioDecoder`](https://developer.mozilla.org/en-US/docs/Web/API/AudioDecoder). Returns
     * null if the track's codec is unknown.
     */
    async getDecoderConfig() {
        return this._backing.getDecoderConfig();
    }
    async getCodecParameterString() {
        const fromMetadata = await this._backing.getMetadataCodecParameterString?.();
        if (fromMetadata != null) {
            return fromMetadata;
        }
        const decoderConfig = await this._backing.getDecoderConfig();
        return decoderConfig?.codec ?? null;
    }
    async canDecode() {
        try {
            const decoderConfig = await this._backing.getDecoderConfig();
            if (!decoderConfig) {
                return false;
            }
            const codec = await this._backing.getCodec();
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_3__/* .assert */ .vA)(codec !== null);
            if (_custom_coder_js__WEBPACK_IMPORTED_MODULE_1__/* .customAudioDecoders */ .zx.some(x => x.supports(codec, decoderConfig))) {
                return true;
            }
            if (decoderConfig.codec.startsWith('pcm-')) {
                return true; // Since we decode it ourselves
            }
            else {
                if (typeof AudioDecoder === 'undefined') {
                    return false;
                }
                const support = await AudioDecoder.isConfigSupported(decoderConfig);
                return support.supported === true;
            }
        }
        catch (error) {
            console.error('Error during decodability check:', error);
            return false;
        }
    }
    async determinePacketType(packet) {
        if (!(packet instanceof _packet_js__WEBPACK_IMPORTED_MODULE_4__/* .EncodedPacket */ .Z)) {
            throw new TypeError('packet must be an EncodedPacket.');
        }
        if ((await this.getCodec()) === null) {
            return null;
        }
        return 'key'; // No audio codec with delta packets
    }
}
/**
 * Helper function for use in {@link InputTrackQuery.sortBy}, used to describe sorting tracks by a numeric property in
 * ascending order. `null` and `undefined` are accepted too and are last in the order (sorted to the end).
 *
 * @group Input files & tracks
 * @public
 */
const asc = (value) => {
    return value ?? Infinity; // nulls and undefined last
};
/**
 * Helper function for use in {@link InputTrackQuery.sortBy}, used to describe sorting tracks by a numeric property in
 * descending order. `null` and `undefined` are accepted too and are last in the order (sorted to the end).
 *
 * @group Input files & tracks
 * @public
 */
const desc = (value) => {
    return -(value ?? -Infinity); // nulls and undefined last
};
/**
 * Helper function for use in {@link InputTrackQuery.sortBy}, used to sort tracks by boolean properties. `true` is
 * sorted to the start, `false` to the end. Useful for expressing soft preferences (e.g., "I'd prefer 1080p, but other
 * resolutions are fine too") as opposed to {@link InputTrackQuery.filter} which expresses hard requirements for
 * tracks.
 *
 * @group Input files & tracks
 * @public
 */
const prefer = (value) => {
    return -value;
};
const toValidatedInputTrackQuery = (query) => {
    if (typeof query !== 'object' || !query) {
        throw new TypeError('query must be an object.');
    }
    if (query.filter !== undefined && typeof query.filter !== 'function') {
        throw new TypeError('query.filter, when provided, must be a function.');
    }
    if (query.sortBy !== undefined && typeof query.sortBy !== 'function') {
        throw new TypeError('query.sortBy, when provided, must be a function.');
    }
    // Instead of validating the return types of the functions everywhere the query is used, simply return a new query
    // which wraps the old one while validating it.
    return {
        filter: query.filter
            ? (track) => {
                const handle = (bool) => {
                    if (typeof bool !== 'boolean') {
                        throw new TypeError('query.filter must return or resolve to a boolean.');
                    }
                    return bool;
                };
                const result = query.filter(track);
                if (result instanceof Promise) {
                    return result.then(handle);
                }
                else {
                    return handle(result);
                }
            }
            : undefined,
        sortBy: query.sortBy
            ? (track) => {
                const handle = (value) => {
                    if (typeof value !== 'number'
                        && (!Array.isArray(value) || !value.every(x => typeof x === 'number'))) {
                        throw new TypeError('query.sortBy must return or resolve to a number or an array of numbers.');
                    }
                    return value;
                };
                const result = query.sortBy(track);
                if (result instanceof Promise) {
                    return result.then(handle);
                }
                else {
                    return handle(result);
                }
            }
            : undefined,
    };
};
const mergeInputTrackQueries = (queryA, queryB) => {
    return {
        filter: queryA?.filter || queryB?.filter
            ? (track) => {
                const resultA = queryA?.filter?.(track) ?? true;
                const handleResultA = (resultA) => {
                    if (resultA === false) {
                        return false;
                    }
                    return queryB?.filter?.(track) ?? true;
                };
                if (resultA instanceof Promise) {
                    return resultA.then(handleResultA);
                }
                else {
                    return handleResultA(resultA);
                }
            }
            : undefined,
        sortBy: queryA?.sortBy || queryB?.sortBy
            ? (track) => {
                const resultA = queryA?.sortBy?.(track) ?? [];
                const resultB = queryB?.sortBy?.(track) ?? [];
                const join = (resultA, resultB) => {
                    return [
                        ...(Array.isArray(resultA) ? resultA : [resultA]),
                        ...(Array.isArray(resultB) ? resultB : [resultB]),
                    ];
                };
                if (resultA instanceof Promise || resultB instanceof Promise) {
                    return Promise.all([resultA, resultB]).then(([resultA, resultB]) => {
                        return join(resultA, resultB);
                    });
                }
                else {
                    return join(resultA, resultB);
                }
            }
            : undefined,
    };
};
const queryInputTracks = async (tracks, query) => {
    let matched = tracks;
    if (query?.filter) {
        const filterMatches = tracks.map(t => query.filter(t));
        const hasAsyncFilter = filterMatches.some(x => x instanceof Promise);
        if (hasAsyncFilter) {
            // eslint-disable-next-line @typescript-eslint/await-thenable
            const resolvedFilterMatches = await Promise.all(filterMatches);
            matched = tracks.filter((_, i) => resolvedFilterMatches[i]);
        }
        else {
            matched = tracks.filter((_, i) => filterMatches[i]);
        }
    }
    if (!query?.sortBy) {
        return matched;
    }
    const sortValues = matched.map(t => query.sortBy(t));
    const hasAsyncSort = sortValues.some(x => x instanceof Promise);
    const resolvedSortValues = hasAsyncSort
        // eslint-disable-next-line @typescript-eslint/await-thenable
        ? await Promise.all(sortValues)
        : sortValues;
    return matched
        .map((track, i) => ({ track, sortValue: resolvedSortValues[i] }))
        .sort((a, b) => {
        const aValues = Array.isArray(a.sortValue) ? a.sortValue : [a.sortValue];
        const bValues = Array.isArray(b.sortValue) ? b.sortValue : [b.sortValue];
        const maxLength = Math.max(aValues.length, bValues.length);
        for (let i = 0; i < maxLength; i++) {
            const aValue = aValues[i] ?? 0;
            const bValue = bValues[i] ?? 0;
            if (aValue === bValue) {
                continue;
            }
            return aValue - bValue;
        }
        return 0;
    })
        .map(x => x.track);
};


/***/ },

/***/ 2030
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   Ng: () => (/* binding */ ENCRYPTION_KEY_CACHE_GROUP),
/* harmony export */   QO: () => (/* binding */ InputDisposedError),
/* harmony export */   pd: () => (/* binding */ Input)
/* harmony export */ });
/* unused harmony exports DEFAULT_SOURCE_CACHE_GROUP, UnsupportedInputFormatError */
/* harmony import */ var _input_format_js__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(1290);
/* harmony import */ var _input_track_js__WEBPACK_IMPORTED_MODULE_1__ = __webpack_require__(6244);
/* harmony import */ var _misc_js__WEBPACK_IMPORTED_MODULE_2__ = __webpack_require__(3912);
/* harmony import */ var _reader_js__WEBPACK_IMPORTED_MODULE_3__ = __webpack_require__(7735);
/* harmony import */ var _source_js__WEBPACK_IMPORTED_MODULE_4__ = __webpack_require__(4709);
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */





(0,_misc_js__WEBPACK_IMPORTED_MODULE_2__/* .polyfillSymbolDispose */ .XQ)();
const DEFAULT_SOURCE_CACHE_GROUP = 1;
const ENCRYPTION_KEY_CACHE_GROUP = 2;
let inputFinalizationRegistry = null;
if (typeof FinalizationRegistry !== 'undefined') {
    inputFinalizationRegistry = new FinalizationRegistry((refs) => {
        for (const ref of refs) {
            if (!ref.freed) {
                ref.free();
            }
        }
    });
}
/**
 * Represents input media, backed by a single file or multiple files depending on the format.
 *
 * This is the root object from which all media read operations start.
 * @group Input files & tracks
 * @public
 */
class Input extends _misc_js__WEBPACK_IMPORTED_MODULE_2__/* .EventEmitter */ .bk {
    /** True if the input has been disposed. */
    get disposed() {
        return this._disposed;
    }
    /**
     * Creates a new input file from the specified options. No reading operations will be performed until methods are
     * called on this instance.
     */
    constructor(options) {
        super();
        /** @internal */
        this._demuxerPromise = null;
        /** @internal */
        this._format = null;
        /** @internal */
        this._trackBackingsCache = null;
        /** @internal */
        this._backingToTrack = new Map();
        /** @internal */
        this._disposed = false;
        /** @internal */
        this._nextSourceCacheAge = 0;
        /** @internal */
        this._sourceRefs = [];
        /** @internal */
        this._sourceCache = [];
        /** @internal */
        this._sourceCachePromises = [];
        /** @internal */
        this._onFormatDetermined = null;
        if (!options || typeof options !== 'object') {
            throw new TypeError('options must be an object.');
        }
        if (!Array.isArray(options.formats) || options.formats.some(x => !(x instanceof _input_format_js__WEBPACK_IMPORTED_MODULE_0__/* .InputFormat */ .CW))) {
            throw new TypeError('options.formats must be an array of InputFormat.');
        }
        if (!(options.source instanceof _source_js__WEBPACK_IMPORTED_MODULE_4__/* .Source */ .kL || options.source instanceof _source_js__WEBPACK_IMPORTED_MODULE_4__/* .SourceRef */ .Fy)) {
            throw new TypeError('options.source must be a Source or SourceRef.');
        }
        if (options.source instanceof _source_js__WEBPACK_IMPORTED_MODULE_4__/* .Source */ .kL && options.source._disposed) {
            throw new TypeError('options.source must not be a disposed Source.');
        }
        if (options.initInput !== undefined && !(options.initInput instanceof Input)) {
            throw new TypeError('options.initInput, when provided, must be an Input.');
        }
        if (options.formatOptions !== undefined) {
            (0,_input_format_js__WEBPACK_IMPORTED_MODULE_0__/* .validateInputFormatOptions */ .Gu)(options.formatOptions, 'formatOptions');
        }
        this._formats = options.formats;
        this._initInput = options.initInput ?? null;
        this._formatOptions = options.formatOptions ?? {};
        if (options.source instanceof _source_js__WEBPACK_IMPORTED_MODULE_4__/* .Source */ .kL) {
            this._rootRef = options.source.ref();
        }
        else {
            this._rootRef = options.source;
        }
        this._sourceRefs.push(this._rootRef);
        inputFinalizationRegistry?.register(this, this._sourceRefs, this);
    }
    /** @internal */
    get _rootSource() {
        return this._rootRef.source;
    }
    /** @internal */
    async _getSourceUncached(request) {
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_2__/* .assert */ .vA)(this._rootSource instanceof _source_js__WEBPACK_IMPORTED_MODULE_4__/* .PathedSource */ .QI);
        const ref = await this._rootSource._resolveRequest(request);
        this._emit('source', { source: ref.source, request, isRoot: request.isRoot });
        return ref;
    }
    /** @internal */
    _getSourceCached(request, cacheGroup = DEFAULT_SOURCE_CACHE_GROUP) {
        const cachedEntry = this._sourceCache.find(x => x.cacheGroup === cacheGroup && (0,_source_js__WEBPACK_IMPORTED_MODULE_4__/* .sourceRequestsAreEqual */ .SM)(x.request, request));
        if (cachedEntry) {
            cachedEntry.age++;
            return Promise.resolve(cachedEntry.sourceRef.source.ref());
        }
        const cachedPromiseEntry = this._sourceCachePromises.find(x => x.cacheGroup === cacheGroup && (0,_source_js__WEBPACK_IMPORTED_MODULE_4__/* .sourceRequestsAreEqual */ .SM)(x.request, request));
        if (cachedPromiseEntry) {
            return cachedPromiseEntry.promise.then(x => x.sourceRef.source.ref());
        }
        const promise = (async () => {
            const sourceRef = await this._getSourceUncached(request);
            const MAX_SOURCE_CACHE_SIZE = 4;
            const count = (0,_misc_js__WEBPACK_IMPORTED_MODULE_2__/* .arrayCount */ .v$)(this._sourceCache, x => x.cacheGroup === cacheGroup && x.sourceRef.source._refCount === 1);
            if (count >= MAX_SOURCE_CACHE_SIZE) {
                const minAgeIndex = (0,_misc_js__WEBPACK_IMPORTED_MODULE_2__/* .arrayArgmin */ .Yg)(this._sourceCache, x => x.cacheGroup === cacheGroup && x.sourceRef.source._refCount === 1 ? x.age : Infinity);
                (0,_misc_js__WEBPACK_IMPORTED_MODULE_2__/* .assert */ .vA)(minAgeIndex !== -1);
                const entry = this._sourceCache[minAgeIndex];
                this._sourceCache.splice(minAgeIndex, 1);
                entry.sourceRef.free();
                (0,_misc_js__WEBPACK_IMPORTED_MODULE_2__/* .removeItem */ .Ai)(this._sourceRefs, entry.sourceRef);
            }
            this._sourceRefs.push(sourceRef);
            const promiseIndex = this._sourceCachePromises.findIndex(x => x.request === request);
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_2__/* .assert */ .vA)(promiseIndex !== -1);
            this._sourceCachePromises.splice(promiseIndex, 1);
            const cacheEntry = {
                request,
                sourceRef,
                age: this._nextSourceCacheAge++,
                cacheGroup,
            };
            return cacheEntry;
        })();
        this._sourceCachePromises.push({
            request,
            cacheGroup,
            promise,
        });
        return promise.then((entry) => {
            const ref = entry.sourceRef.source.ref();
            // We need to add it to the cache this late to avoid the ref being freed prematurely due to race conditions
            this._sourceCache.push(entry);
            return ref;
        });
    }
    /** @internal */
    _getDemuxer() {
        return this._demuxerPromise ??= (async () => {
            this._reader = new _reader_js__WEBPACK_IMPORTED_MODULE_3__/* .Reader */ .mP(this._rootSource);
            this._emit('source', { source: this._rootSource, request: null, isRoot: true });
            for (const format of this._formats) {
                const canRead = await format._canReadInput(this);
                if (canRead) {
                    this._format = format;
                    this._onFormatDetermined?.(format);
                    return format._createDemuxer(this);
                }
            }
            throw new UnsupportedInputFormatError();
        })();
    }
    /**
     * Returns the source from which this input file reads data for the root path.
     */
    get source() {
        return this._rootSource;
    }
    /**
     * Returns the format of the input file. You can compare this result directly to the {@link InputFormat} singletons
     * or use `instanceof` checks for subset-aware logic (for example, `format instanceof MatroskaInputFormat` is true
     * for both MKV and WebM).
     */
    async getFormat() {
        await this._getDemuxer();
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_2__/* .assert */ .vA)(this._format);
        return this._format;
    }
    /** Returns `true` if the format of the input file is known and the file can be read, `false` otherwise. */
    async canRead() {
        try {
            await this._getDemuxer();
            return true;
        }
        catch (error) {
            if (error instanceof UnsupportedInputFormatError) {
                return false;
            }
            throw error;
        }
    }
    /**
     * Returns the timestamp at which the input file starts. More precisely, returns the smallest starting timestamp
     * among all tracks.
     *
     * Optionally, you can pass in the list of tracks for which you want to compute the starting timestamp.
     *
     * Note that this method is potentially expensive for inputs with many tracks (such as HLS manifests), since it
     * probes every track.
     */
    async getFirstTimestamp(tracks) {
        tracks ??= await this.getTracks();
        const filtered = tracks.filter(x => x !== null);
        if (filtered.length === 0) {
            return 0;
        }
        const firstTimestamps = await Promise.all(filtered.map(x => x.getFirstTimestamp()));
        return Math.min(...firstTimestamps);
    }
    /**
     * Computes the duration of the input file, in seconds. More precisely, returns the largest end timestamp among
     * all tracks.
     *
     * Optionally, you can pass in the list of tracks for which you want to compute the duration.
     *
     * This method can be potentially expensive depending on the underlying file format, because it returns the most
     * accurate duration possible and must check all tracks. Use {@link Input.getDurationFromMetadata} for a faster but
     * less accurate estimate of duration.
     *
     * By default, when any track in the underlying media is live, this method will only resolve once the live stream
     * ends. If you want to query the current duration of the media, set {@link PacketRetrievalOptions.skipLiveWait}
     * to `true` in the options.
     */
    async computeDuration(tracks, options) {
        tracks ??= await this.getTracks();
        const filtered = tracks.filter(x => x !== null);
        if (filtered.length === 0) {
            return 0;
        }
        const tracksDurations = await Promise.all(filtered.map(x => x.computeDuration(options)));
        return Math.max(...tracksDurations);
    }
    /**
     * Gets the duration (end timestamp) in seconds of the input file from metadata stored in the file. This value may
     * be approximate or diverge from the actual, precise duration returned by `.computeDuration()`, but compared to
     * that method, this method is cheaper. When the duration cannot be determined from the file metadata, `null`
     * is returned.
     *
     * Optionally, you can pass in the list of tracks for which you want to get the duration from metadata.
     *
     * By default, when the underlying media is live, this method will only resolve once the live stream
     * ends. If you want to query the current duration of the media, set
     * {@link DurationMetadataRequestOptions.skipLiveWait} to `true` in the options.
     */
    async getDurationFromMetadata(tracks, options) {
        tracks ??= await this.getTracks();
        const filtered = tracks.filter(x => x !== null);
        const tracksDurations = await Promise.all(filtered.map(x => x.getDurationFromMetadata(options)));
        const nonNullDurations = tracksDurations.filter(x => x !== null);
        if (nonNullDurations.length === 0) {
            return null;
        }
        return Math.max(...nonNullDurations);
    }
    /**
     * Returns the list of all tracks of this input file in the order in which they appear in the file. An optional
     * query can be provided.
     */
    async getTracks(query) {
        query &&= (0,_input_track_js__WEBPACK_IMPORTED_MODULE_1__/* .toValidatedInputTrackQuery */ .vo)(query);
        const backings = await this._getTrackBackings();
        const tracks = backings.map(backing => this._wrapBackingAsTrack(backing));
        return (0,_input_track_js__WEBPACK_IMPORTED_MODULE_1__/* .queryInputTracks */ .NY)(tracks, query);
    }
    /** Returns the list of all video tracks of this input file. An optional query can be provided. */
    async getVideoTracks(query) {
        query &&= (0,_input_track_js__WEBPACK_IMPORTED_MODULE_1__/* .toValidatedInputTrackQuery */ .vo)(query);
        const tracks = await this.getTracks();
        const videoTracks = tracks.filter((x) => x.isVideoTrack());
        return (0,_input_track_js__WEBPACK_IMPORTED_MODULE_1__/* .queryInputTracks */ .NY)(videoTracks, query);
    }
    /** Returns the list of all audio tracks of this input file. An optional query can be provided. */
    async getAudioTracks(query) {
        query &&= (0,_input_track_js__WEBPACK_IMPORTED_MODULE_1__/* .toValidatedInputTrackQuery */ .vo)(query);
        const tracks = await this.getTracks();
        const audioTracks = tracks.filter((x) => x.isAudioTrack());
        return (0,_input_track_js__WEBPACK_IMPORTED_MODULE_1__/* .queryInputTracks */ .NY)(audioTracks, query);
    }
    /**
     * Returns the primary video track of this input file, or null if there are no video tracks.
     *
     * Multiple factors determine which track is considered primary, including its position in the file, disposition,
     * bitrate (higher bitrate is preferred), and if it can be paired with an audio track.
     */
    async getPrimaryVideoTrack(query) {
        query &&= (0,_input_track_js__WEBPACK_IMPORTED_MODULE_1__/* .toValidatedInputTrackQuery */ .vo)(query);
        const merged = (0,_input_track_js__WEBPACK_IMPORTED_MODULE_1__/* .mergeInputTrackQueries */ .Uj)(query, {
            sortBy: async (t) => [
                (0,_input_track_js__WEBPACK_IMPORTED_MODULE_1__/* .prefer */ .D8)((await t.getDisposition()).default),
                (0,_input_track_js__WEBPACK_IMPORTED_MODULE_1__/* .prefer */ .D8)(await t.hasPairableAudioTrack()),
                (0,_input_track_js__WEBPACK_IMPORTED_MODULE_1__/* .prefer */ .D8)(!(await t.hasOnlyKeyPackets())),
                (0,_input_track_js__WEBPACK_IMPORTED_MODULE_1__/* .desc */ .i8)(await t.getBitrate()),
            ],
        });
        const sorted = await this.getVideoTracks(merged);
        return sorted[0] ?? null;
    }
    /**
     * Returns the primary audio track of this input file, or null if there are no audio tracks.
     *
     * Multiple factors determine which track is considered primary, including its position in the file, disposition,
     * bitrate (higher bitrate is preferred), and if it can be paired with the primary video track.
     */
    async getPrimaryAudioTrack(query) {
        query &&= (0,_input_track_js__WEBPACK_IMPORTED_MODULE_1__/* .toValidatedInputTrackQuery */ .vo)(query);
        const primaryVideoTrack = await this.getPrimaryVideoTrack();
        const merged = (0,_input_track_js__WEBPACK_IMPORTED_MODULE_1__/* .mergeInputTrackQueries */ .Uj)(query, {
            sortBy: async (t) => [
                (0,_input_track_js__WEBPACK_IMPORTED_MODULE_1__/* .prefer */ .D8)(!primaryVideoTrack || t.canBePairedWith(primaryVideoTrack)),
                (0,_input_track_js__WEBPACK_IMPORTED_MODULE_1__/* .prefer */ .D8)((await t.getDisposition()).default),
                (0,_input_track_js__WEBPACK_IMPORTED_MODULE_1__/* .desc */ .i8)(await t.getBitrate()),
            ],
        });
        const sorted = await this.getAudioTracks(merged);
        return sorted[0] ?? null;
    }
    /** @internal */
    async _getTrackBackings() {
        const demuxer = await this._getDemuxer();
        return this._trackBackingsCache ??= await demuxer.getTrackBackings();
    }
    /** @internal */
    _wrapBackingAsTrack(backing) {
        const existing = this._backingToTrack.get(backing);
        if (existing) {
            return existing;
        }
        const type = backing.getType();
        const track = type === 'video'
            ? new _input_track_js__WEBPACK_IMPORTED_MODULE_1__/* .InputVideoTrack */ .N0(this, backing)
            : new _input_track_js__WEBPACK_IMPORTED_MODULE_1__/* .InputAudioTrack */ .Yi(this, backing);
        this._backingToTrack.set(backing, track);
        return track;
    }
    /** Returns the full MIME type of this input file, including track codecs. */
    async getMimeType() {
        const demuxer = await this._getDemuxer();
        return demuxer.getMimeType();
    }
    /**
     * Returns descriptive metadata tags about the media file, such as title, author, date, cover art, or other
     * attached files.
     */
    async getMetadataTags() {
        const demuxer = await this._getDemuxer();
        return demuxer.getMetadataTags();
    }
    /**
     * Disposes this input and frees connected resources. When an input is disposed, ongoing read operations will be
     * canceled, all future read operations will fail, any open decoders will be closed, and all ongoing media sink
     * operations will be canceled. Disallowed and canceled operations will throw an {@link InputDisposedError}.
     *
     * You are expected not to use an input after disposing it. While some operations may still work, it is not
     * specified and may change in any future update.
     */
    dispose() {
        if (this._disposed) {
            return;
        }
        this._disposed = true;
        for (const ref of this._sourceRefs) {
            ref.free();
        }
        this._sourceRefs.length = 0;
        inputFinalizationRegistry?.unregister(this);
        void this._demuxerPromise
            ?.then(demuxer => demuxer.dispose());
    }
    /**
     * Calls `.dispose()` on the input, implementing the `Disposable` interface for use with
     * JavaScript Explicit Resource Management features.
     */
    [Symbol.dispose]() {
        this.dispose();
    }
}
/**
 * Thrown when trying to operate on an input that has an unsupported or unrecognizable format.
 * @group Input files & tracks
 * @public
 */
class UnsupportedInputFormatError extends Error {
    /** Creates a new {@link UnsupportedInputFormatError}. */
    constructor(message = 'Input has an unsupported or unrecognizable format.') {
        super(message);
        this.name = 'UnsupportedInputFormatError';
    }
}
/**
 * Thrown when an operation was prevented because the corresponding {@link Input} has been disposed.
 * @group Input files & tracks
 * @public
 */
class InputDisposedError extends Error {
    /** Creates a new {@link InputDisposedError}. */
    constructor(message = 'Input has been disposed.') {
        super(message);
        this.name = 'InputDisposedError';
    }
}


/***/ },

/***/ 1826
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   MG: () => (/* binding */ psshBoxesAreEqual),
/* harmony export */   Xh: () => (/* binding */ buildIsobmffMimeType),
/* harmony export */   j1: () => (/* binding */ parsePsshBoxContents)
/* harmony export */ });
/* harmony import */ var _misc_js__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(3912);
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

const buildIsobmffMimeType = (info) => {
    const base = info.hasVideo
        ? 'video/'
        : info.hasAudio
            ? 'audio/'
            : 'application/';
    let string = base + (info.isQuickTime ? 'quicktime' : 'mp4');
    if (info.codecStrings.length > 0) {
        const uniqueCodecMimeTypes = [...new Set(info.codecStrings)];
        string += `; codecs="${uniqueCodecMimeTypes.join(', ')}"`;
    }
    return string;
};
const parsePsshBoxContents = (contents) => {
    const view = (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .toDataView */ .Zc)(contents);
    let pos = 0;
    const version = view.getUint8(pos);
    pos += 1;
    pos += 3; // Flags
    const systemId = (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .bytesToHexString */ .Br)(contents.subarray(pos, pos + 16));
    pos += 16;
    let keyIds = null;
    if (version > 0) {
        const kidCount = view.getUint32(pos);
        pos += 4;
        if (kidCount > 0) {
            keyIds = [];
            for (let i = 0; i < kidCount; i++) {
                keyIds.push((0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .bytesToHexString */ .Br)(contents.subarray(pos, pos + 16)));
                pos += 16;
            }
        }
    }
    const dataSize = view.getUint32(pos);
    pos += 4;
    return {
        systemId,
        keyIds,
        data: contents.slice(pos, pos + dataSize),
    };
};
const psshBoxesAreEqual = (a, b) => (a.systemId === b.systemId
    && (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .uint8ArraysAreEqual */ .ju)(a.data, b.data));


/***/ },

/***/ 8561
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   $L: () => (/* binding */ readMetadataStringShort),
/* harmony export */   Cp: () => (/* binding */ readDataBox),
/* harmony export */   IS: () => (/* binding */ readFixed_2_30),
/* harmony export */   Vl: () => (/* binding */ readBoxHeader),
/* harmony export */   Xk: () => (/* binding */ MAX_BOX_HEADER_SIZE),
/* harmony export */   ZM: () => (/* binding */ MIN_BOX_HEADER_SIZE),
/* harmony export */   hs: () => (/* binding */ readIsomVariableInteger),
/* harmony export */   vX: () => (/* binding */ readFixed_16_16)
/* harmony export */ });
/* harmony import */ var _metadata_js__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(5165);
/* harmony import */ var _misc_js__WEBPACK_IMPORTED_MODULE_1__ = __webpack_require__(3912);
/* harmony import */ var _reader_js__WEBPACK_IMPORTED_MODULE_2__ = __webpack_require__(7735);
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */



const MIN_BOX_HEADER_SIZE = 8;
const MAX_BOX_HEADER_SIZE = 16;
const readBoxHeader = (slice) => {
    let totalSize = (0,_reader_js__WEBPACK_IMPORTED_MODULE_2__/* .readU32Be */ .cN)(slice);
    const name = (0,_reader_js__WEBPACK_IMPORTED_MODULE_2__/* .readAscii */ .IT)(slice, 4);
    let headerSize = 8;
    const hasLargeSize = totalSize === 1;
    if (hasLargeSize) {
        totalSize = (0,_reader_js__WEBPACK_IMPORTED_MODULE_2__/* .readU64Be */ .th)(slice);
        headerSize = 16;
    }
    const contentSize = totalSize - headerSize;
    if (contentSize < 0) {
        return null; // Hardly a box is it
    }
    return { name, totalSize, headerSize, contentSize };
};
const readFixed_16_16 = (slice) => {
    return (0,_reader_js__WEBPACK_IMPORTED_MODULE_2__/* .readI32Be */ .Ar)(slice) / 0x10000;
};
const readFixed_2_30 = (slice) => {
    return (0,_reader_js__WEBPACK_IMPORTED_MODULE_2__/* .readI32Be */ .Ar)(slice) / 0x40000000;
};
const readIsomVariableInteger = (slice) => {
    let result = 0;
    for (let i = 0; i < 4; i++) {
        result <<= 7;
        const nextByte = (0,_reader_js__WEBPACK_IMPORTED_MODULE_2__/* .readU8 */ .eo)(slice);
        result |= nextByte & 0x7f;
        if ((nextByte & 0x80) === 0) {
            break;
        }
    }
    return result;
};
const readMetadataStringShort = (slice) => {
    let stringLength = (0,_reader_js__WEBPACK_IMPORTED_MODULE_2__/* .readU16Be */ .mH)(slice);
    slice.skip(2); // Language
    stringLength = Math.min(stringLength, slice.remainingLength);
    return _misc_js__WEBPACK_IMPORTED_MODULE_1__/* .textDecoder */ .su.decode((0,_reader_js__WEBPACK_IMPORTED_MODULE_2__/* .readBytes */ .io)(slice, stringLength));
};
const readDataBox = (slice) => {
    const header = readBoxHeader(slice);
    if (!header || header.name !== 'data') {
        return null;
    }
    if (slice.remainingLength < 8) {
        // Box is too small
        return null;
    }
    const typeIndicator = (0,_reader_js__WEBPACK_IMPORTED_MODULE_2__/* .readU32Be */ .cN)(slice);
    slice.skip(4); // Locale indicator
    const data = (0,_reader_js__WEBPACK_IMPORTED_MODULE_2__/* .readBytes */ .io)(slice, header.contentSize - 8);
    switch (typeIndicator) {
        case 1: return _misc_js__WEBPACK_IMPORTED_MODULE_1__/* .textDecoder */ .su.decode(data); // UTF-8
        case 2: return new TextDecoder('utf-16be').decode(data); // UTF-16-BE
        case 13: return new _metadata_js__WEBPACK_IMPORTED_MODULE_0__/* .RichImageData */ .sF(data, 'image/jpeg');
        case 14: return new _metadata_js__WEBPACK_IMPORTED_MODULE_0__/* .RichImageData */ .sF(data, 'image/png');
        case 27: return new _metadata_js__WEBPACK_IMPORTED_MODULE_0__/* .RichImageData */ .sF(data, 'image/bmp');
        default: return data;
    }
};


/***/ },

/***/ 3616
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   V: () => (/* binding */ buildMatroskaMimeType)
/* harmony export */ });
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
const buildMatroskaMimeType = (info) => {
    const base = info.hasVideo
        ? 'video/'
        : info.hasAudio
            ? 'audio/'
            : 'application/';
    let string = base + (info.isWebM ? 'webm' : 'x-matroska');
    if (info.codecStrings.length > 0) {
        const uniqueCodecMimeTypes = [...new Set(info.codecStrings.filter(Boolean))];
        string += `; codecs="${uniqueCodecMimeTypes.join(', ')}"`;
    }
    return string;
};


/***/ },

/***/ 2490
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   Vx: () => (/* binding */ buildMpegTsMimeType),
/* harmony export */   ZT: () => (/* binding */ TS_PACKET_SIZE),
/* harmony export */   cS: () => (/* binding */ TIMESCALE)
/* harmony export */ });
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
const TIMESCALE = 90_000; // MPEG-TS timestamps run on a 90 kHz clock
const TS_PACKET_SIZE = 188;
const buildMpegTsMimeType = (codecStrings) => {
    let string = 'video/MP2T';
    const uniqueCodecStrings = [...new Set(codecStrings.filter(Boolean))];
    if (uniqueCodecStrings.length > 0) {
        string += `; codecs="${uniqueCodecStrings.join(', ')}"`;
    }
    return string;
};


/***/ },

/***/ 9730
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   Ob: () => (/* binding */ buildOggMimeType),
/* harmony export */   Zk: () => (/* binding */ OGGS),
/* harmony export */   _S: () => (/* binding */ computeOggPageCrc),
/* harmony export */   nL: () => (/* binding */ extractSampleMetadata)
/* harmony export */ });
/* harmony import */ var _codec_data_js__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(6297);
/* harmony import */ var _misc_js__WEBPACK_IMPORTED_MODULE_1__ = __webpack_require__(3912);
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


const OGGS = 0x5367674f; // 'OggS'
const OGG_CRC_POLYNOMIAL = 0x04c11db7;
const OGG_CRC_TABLE = new Uint32Array(256);
for (let n = 0; n < 256; n++) {
    let crc = n << 24;
    for (let k = 0; k < 8; k++) {
        crc = (crc & 0x80000000)
            ? ((crc << 1) ^ OGG_CRC_POLYNOMIAL)
            : (crc << 1);
    }
    OGG_CRC_TABLE[n] = (crc >>> 0) & 0xffffffff;
}
const computeOggPageCrc = (bytes) => {
    const view = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .toDataView */ .Zc)(bytes);
    const originalChecksum = view.getUint32(22, true);
    view.setUint32(22, 0, true); // Zero out checksum field
    let crc = 0;
    for (let i = 0; i < bytes.length; i++) {
        const byte = bytes[i];
        crc = ((crc << 8) ^ OGG_CRC_TABLE[(crc >>> 24) ^ byte]) >>> 0;
    }
    view.setUint32(22, originalChecksum, true); // Restore checksum field
    return crc;
};
const extractSampleMetadata = (data, codecInfo, vorbisLastBlocksize) => {
    let durationInSamples = 0;
    let currentBlocksize = null;
    if (data.length > 0) {
        // To know sample duration, we'll need to peak inside the packet
        if (codecInfo.codec === 'vorbis') {
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .assert */ .vA)(codecInfo.vorbisInfo);
            const vorbisModeCount = codecInfo.vorbisInfo.modeBlockflags.length;
            const bitCount = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .ilog */ .al)(vorbisModeCount - 1);
            const modeMask = ((1 << bitCount) - 1) << 1;
            const modeNumber = (data[0] & modeMask) >> 1;
            if (modeNumber >= codecInfo.vorbisInfo.modeBlockflags.length) {
                throw new Error('Invalid mode number.');
            }
            // In Vorbis, packet duration also depends on the blocksize of the previous packet
            let prevBlocksize = vorbisLastBlocksize;
            const blockflag = codecInfo.vorbisInfo.modeBlockflags[modeNumber];
            currentBlocksize = codecInfo.vorbisInfo.blocksizes[blockflag];
            if (blockflag === 1) {
                const prevMask = (modeMask | 0x1) + 1;
                const flag = data[0] & prevMask ? 1 : 0;
                prevBlocksize = codecInfo.vorbisInfo.blocksizes[flag];
            }
            durationInSamples = prevBlocksize !== null
                ? (prevBlocksize + currentBlocksize) >> 2
                : 0; // The first sample outputs no audio data and therefore has a duration of 0
        }
        else if (codecInfo.codec === 'opus') {
            const toc = (0,_codec_data_js__WEBPACK_IMPORTED_MODULE_0__/* .parseOpusTocByte */ .ls)(data);
            durationInSamples = toc.durationInSamples;
        }
    }
    return {
        durationInSamples,
        vorbisBlockSize: currentBlocksize,
    };
};
const buildOggMimeType = (info) => {
    let string = 'audio/ogg';
    if (info.codecStrings) {
        const uniqueCodecMimeTypes = [...new Set(info.codecStrings)];
        string += `; codecs="${uniqueCodecMimeTypes.join(', ')}"`;
    }
    return string;
};


/***/ },

/***/ 9841
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   BF: () => (/* binding */ readPageHeader),
/* harmony export */   H4: () => (/* binding */ MAX_PAGE_SIZE),
/* harmony export */   H9: () => (/* binding */ MAX_PAGE_HEADER_SIZE),
/* harmony export */   b0: () => (/* binding */ MIN_PAGE_HEADER_SIZE),
/* harmony export */   v5: () => (/* binding */ findNextPageHeader)
/* harmony export */ });
/* harmony import */ var _reader_js__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(7735);
/* harmony import */ var _ogg_misc_js__WEBPACK_IMPORTED_MODULE_1__ = __webpack_require__(9730);
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */


const MIN_PAGE_HEADER_SIZE = 27;
const MAX_PAGE_HEADER_SIZE = 27 + 255;
const MAX_PAGE_SIZE = MAX_PAGE_HEADER_SIZE + 255 * 255;
const readPageHeader = (slice) => {
    const startPos = slice.filePos;
    const capturePattern = (0,_reader_js__WEBPACK_IMPORTED_MODULE_0__/* .readU32Le */ .aJ)(slice);
    if (capturePattern !== _ogg_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .OGGS */ .Zk) {
        return null;
    }
    slice.skip(1); // Version
    const headerType = (0,_reader_js__WEBPACK_IMPORTED_MODULE_0__/* .readU8 */ .eo)(slice);
    const granulePosition = (0,_reader_js__WEBPACK_IMPORTED_MODULE_0__/* .readI64Le */ .TH)(slice);
    const serialNumber = (0,_reader_js__WEBPACK_IMPORTED_MODULE_0__/* .readU32Le */ .aJ)(slice);
    const sequenceNumber = (0,_reader_js__WEBPACK_IMPORTED_MODULE_0__/* .readU32Le */ .aJ)(slice);
    const checksum = (0,_reader_js__WEBPACK_IMPORTED_MODULE_0__/* .readU32Le */ .aJ)(slice);
    const numberPageSegments = (0,_reader_js__WEBPACK_IMPORTED_MODULE_0__/* .readU8 */ .eo)(slice);
    const lacingValues = new Uint8Array(numberPageSegments);
    for (let i = 0; i < numberPageSegments; i++) {
        lacingValues[i] = (0,_reader_js__WEBPACK_IMPORTED_MODULE_0__/* .readU8 */ .eo)(slice);
    }
    const headerSize = 27 + numberPageSegments;
    const dataSize = lacingValues.reduce((a, b) => a + b, 0);
    const totalSize = headerSize + dataSize;
    return {
        headerStartPos: startPos,
        totalSize,
        dataStartPos: startPos + headerSize,
        dataSize,
        headerType,
        granulePosition,
        serialNumber,
        sequenceNumber,
        checksum,
        lacingValues,
    };
};
const findNextPageHeader = (slice, until) => {
    while (slice.filePos < until - (4 - 1)) { // Size of word minus 1
        const word = (0,_reader_js__WEBPACK_IMPORTED_MODULE_0__/* .readU32Le */ .aJ)(slice);
        const firstByte = word & 0xff;
        const secondByte = (word >>> 8) & 0xff;
        const thirdByte = (word >>> 16) & 0xff;
        const fourthByte = (word >>> 24) & 0xff;
        const O = 0x4f; // 'O'
        if (firstByte !== O && secondByte !== O && thirdByte !== O && fourthByte !== O) {
            continue;
        }
        slice.skip(-4);
        if (word === _ogg_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .OGGS */ .Zk) {
            // We have found the capture pattern
            return true;
        }
        slice.skip(1);
    }
    return false;
};


/***/ },

/***/ 3936
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   T: () => (/* binding */ PLACEHOLDER_DATA),
/* harmony export */   Z: () => (/* binding */ EncodedPacket)
/* harmony export */ });
/* harmony import */ var _misc_js__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(3912);
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

const PLACEHOLDER_DATA = /* #__PURE__ */ new Uint8Array(0);
/**
 * Represents an encoded chunk of media. Mainly used as an expressive wrapper around WebCodecs API's
 * [`EncodedVideoChunk`](https://developer.mozilla.org/en-US/docs/Web/API/EncodedVideoChunk) and
 * [`EncodedAudioChunk`](https://developer.mozilla.org/en-US/docs/Web/API/EncodedAudioChunk), but can also be used
 * standalone.
 * @group Packets
 * @public
 */
class EncodedPacket {
    /** Creates a new {@link EncodedPacket} from raw bytes and timing information. */
    constructor(
    /**
     * The encoded data of this packet. For any given codec, this data must adhere to the format specified in the
     * Mediabunny Codec Registry.
     */
    data, 
    /** The type of this packet. */
    type, 
    /**
     * The presentation timestamp of this packet in seconds. May be negative. Samples with negative end timestamps
     * should not be presented.
     */
    timestamp, 
    /** The duration of this packet in seconds. */
    duration, 
    /**
     * The sequence number indicates the decode order of the packets. Packet A  must be decoded before packet B if A
     * has a lower sequence number than B. If two packets have the same sequence number, they are the same packet.
     * Otherwise, sequence numbers are arbitrary and are not guaranteed to have any meaning besides their relative
     * ordering. Negative sequence numbers mean the sequence number is undefined.
     */
    sequenceNumber = -1, byteLength, sideData) {
        this.data = data;
        this.type = type;
        this.timestamp = timestamp;
        this.duration = duration;
        this.sequenceNumber = sequenceNumber;
        if (data === PLACEHOLDER_DATA && byteLength === undefined) {
            throw new Error('Internal error: byteLength must be explicitly provided when constructing metadata-only packets.');
        }
        if (byteLength === undefined) {
            byteLength = data.byteLength;
        }
        if (!(data instanceof Uint8Array)) {
            throw new TypeError('data must be a Uint8Array.');
        }
        if (type !== 'key' && type !== 'delta') {
            throw new TypeError('type must be either "key" or "delta".');
        }
        if (!Number.isFinite(timestamp)) {
            throw new TypeError('timestamp must be a number.');
        }
        if (!Number.isFinite(duration) || duration < 0) {
            throw new TypeError('duration must be a non-negative number.');
        }
        if (!Number.isFinite(sequenceNumber)) {
            throw new TypeError('sequenceNumber must be a number.');
        }
        if (!Number.isInteger(byteLength) || byteLength < 0) {
            throw new TypeError('byteLength must be a non-negative integer.');
        }
        if (sideData !== undefined && (typeof sideData !== 'object' || !sideData)) {
            throw new TypeError('sideData, when provided, must be an object.');
        }
        if (sideData?.alpha !== undefined && !(sideData.alpha instanceof Uint8Array)) {
            throw new TypeError('sideData.alpha, when provided, must be a Uint8Array.');
        }
        if (sideData?.alphaByteLength !== undefined
            && (!Number.isInteger(sideData.alphaByteLength) || sideData.alphaByteLength < 0)) {
            throw new TypeError('sideData.alphaByteLength, when provided, must be a non-negative integer.');
        }
        this.byteLength = byteLength;
        this.sideData = sideData ?? {};
        if (this.sideData.alpha && this.sideData.alphaByteLength === undefined) {
            this.sideData.alphaByteLength = this.sideData.alpha.byteLength;
        }
    }
    /**
     * If this packet is a metadata-only packet. Metadata-only packets don't contain their packet data. They are the
     * result of retrieving packets with {@link PacketRetrievalOptions.metadataOnly} set to `true`.
     */
    get isMetadataOnly() {
        return this.data === PLACEHOLDER_DATA;
    }
    /** The timestamp of this packet in microseconds. */
    get microsecondTimestamp() {
        return Math.trunc(_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .SECOND_TO_MICROSECOND_FACTOR */ .MW * this.timestamp);
    }
    /** The duration of this packet in microseconds. */
    get microsecondDuration() {
        return Math.trunc(_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .SECOND_TO_MICROSECOND_FACTOR */ .MW * this.duration);
    }
    /** Converts this packet to an
     * [`EncodedVideoChunk`](https://developer.mozilla.org/en-US/docs/Web/API/EncodedVideoChunk) for use with the
     * WebCodecs API. */
    toEncodedVideoChunk() {
        if (this.isMetadataOnly) {
            throw new TypeError('Metadata-only packets cannot be converted to a video chunk.');
        }
        if (typeof EncodedVideoChunk === 'undefined') {
            throw new Error('Your browser does not support EncodedVideoChunk.');
        }
        return new EncodedVideoChunk({
            data: this.data,
            type: this.type,
            timestamp: this.microsecondTimestamp,
            duration: this.microsecondDuration,
        });
    }
    /**
     * Converts this packet to an
     * [`EncodedVideoChunk`](https://developer.mozilla.org/en-US/docs/Web/API/EncodedVideoChunk) for use with the
     * WebCodecs API, using the alpha side data instead of the color data. Throws if no alpha side data is defined.
     */
    alphaToEncodedVideoChunk(type = this.type) {
        if (!this.sideData.alpha) {
            throw new TypeError('This packet does not contain alpha side data.');
        }
        if (this.isMetadataOnly) {
            throw new TypeError('Metadata-only packets cannot be converted to a video chunk.');
        }
        if (typeof EncodedVideoChunk === 'undefined') {
            throw new Error('Your browser does not support EncodedVideoChunk.');
        }
        return new EncodedVideoChunk({
            data: this.sideData.alpha,
            type,
            timestamp: this.microsecondTimestamp,
            duration: this.microsecondDuration,
        });
    }
    /** Converts this packet to an
     * [`EncodedAudioChunk`](https://developer.mozilla.org/en-US/docs/Web/API/EncodedAudioChunk) for use with the
     * WebCodecs API. */
    toEncodedAudioChunk() {
        if (this.isMetadataOnly) {
            throw new TypeError('Metadata-only packets cannot be converted to an audio chunk.');
        }
        if (typeof EncodedAudioChunk === 'undefined') {
            throw new Error('Your browser does not support EncodedAudioChunk.');
        }
        return new EncodedAudioChunk({
            data: this.data,
            type: this.type,
            timestamp: this.microsecondTimestamp,
            duration: this.microsecondDuration,
        });
    }
    /**
     * Creates an {@link EncodedPacket} from an
     * [`EncodedVideoChunk`](https://developer.mozilla.org/en-US/docs/Web/API/EncodedVideoChunk) or
     * [`EncodedAudioChunk`](https://developer.mozilla.org/en-US/docs/Web/API/EncodedAudioChunk). This method is useful
     * for converting chunks from the WebCodecs API to `EncodedPacket` instances.
     */
    static fromEncodedChunk(chunk, sideData) {
        if (!(chunk instanceof EncodedVideoChunk || chunk instanceof EncodedAudioChunk)) {
            throw new TypeError('chunk must be an EncodedVideoChunk or EncodedAudioChunk.');
        }
        const data = new Uint8Array(chunk.byteLength);
        chunk.copyTo(data);
        return new EncodedPacket(data, chunk.type, chunk.timestamp / 1e6, (chunk.duration ?? 0) / 1e6, undefined, undefined, sideData);
    }
    /** Clones this packet while optionally modifying the new packet's data. */
    clone(options) {
        if (options !== undefined && (typeof options !== 'object' || options === null)) {
            throw new TypeError('options, when provided, must be an object.');
        }
        if (options?.data !== undefined && !(options.data instanceof Uint8Array)) {
            throw new TypeError('options.data, when provided, must be a Uint8Array.');
        }
        if (options?.type !== undefined && options.type !== 'key' && options.type !== 'delta') {
            throw new TypeError('options.type, when provided, must be either "key" or "delta".');
        }
        if (options?.timestamp !== undefined && !Number.isFinite(options.timestamp)) {
            throw new TypeError('options.timestamp, when provided, must be a number.');
        }
        if (options?.duration !== undefined && !Number.isFinite(options.duration)) {
            throw new TypeError('options.duration, when provided, must be a number.');
        }
        if (options?.sequenceNumber !== undefined && !Number.isFinite(options.sequenceNumber)) {
            throw new TypeError('options.sequenceNumber, when provided, must be a number.');
        }
        if (options?.sideData !== undefined && (typeof options.sideData !== 'object' || options.sideData === null)) {
            throw new TypeError('options.sideData, when provided, must be an object.');
        }
        return new EncodedPacket(options?.data ?? this.data, options?.type ?? this.type, options?.timestamp ?? this.timestamp, options?.duration ?? this.duration, options?.sequenceNumber ?? this.sequenceNumber, this.byteLength, options?.sideData ?? this.sideData);
    }
}


/***/ },

/***/ 7735
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   Ar: () => (/* binding */ readI32Be),
/* harmony export */   B5: () => (/* binding */ readI64Be),
/* harmony export */   IM: () => (/* binding */ readU64),
/* harmony export */   IT: () => (/* binding */ readAscii),
/* harmony export */   Jk: () => (/* binding */ readF32Be),
/* harmony export */   PF: () => (/* binding */ readU32),
/* harmony export */   TH: () => (/* binding */ readI64Le),
/* harmony export */   Vv: () => (/* binding */ readU16),
/* harmony export */   _3: () => (/* binding */ readF64Be),
/* harmony export */   aJ: () => (/* binding */ readU32Le),
/* harmony export */   cN: () => (/* binding */ readU32Be),
/* harmony export */   eo: () => (/* binding */ readU8),
/* harmony export */   iH: () => (/* binding */ readI16Be),
/* harmony export */   io: () => (/* binding */ readBytes),
/* harmony export */   jo: () => (/* binding */ readAllLines),
/* harmony export */   mH: () => (/* binding */ readU16Be),
/* harmony export */   mP: () => (/* binding */ Reader),
/* harmony export */   n2: () => (/* binding */ readU24Be),
/* harmony export */   th: () => (/* binding */ readU64Be),
/* harmony export */   x$: () => (/* binding */ FileSlice)
/* harmony export */ });
/* unused harmony export readI32Le */
/* harmony import */ var _input_js__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(2030);
/* harmony import */ var _misc_js__WEBPACK_IMPORTED_MODULE_1__ = __webpack_require__(3912);
/* harmony import */ var _source_js__WEBPACK_IMPORTED_MODULE_2__ = __webpack_require__(4709);
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */



class Reader {
    constructor(source) {
        this.source = source;
    }
    get fileSize() {
        const size = this.source._getFileSize();
        if (size === undefined) {
            throw new Error('Reading file size too early; read required first.');
        }
        return size;
    }
    get fileSizeNonStrict() {
        return this.source._getFileSize() ?? null;
    }
    requestSlice(start, length) {
        if (this.source._disposed) {
            throw new _input_js__WEBPACK_IMPORTED_MODULE_0__/* .InputDisposedError */ .QO();
        }
        if (start < 0) {
            return null;
        }
        if (this.fileSizeNonStrict !== null && start + length > this.fileSizeNonStrict) {
            return null;
        }
        if (length === 0) {
            const buffer = new Uint8Array(0);
            return new FileSlice(buffer, (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .toDataView */ .Zc)(buffer), 0, start, start);
        }
        const end = start + length;
        const result = this.source._read(start, end, _source_js__WEBPACK_IMPORTED_MODULE_2__/* .DEFAULT_MIN_READ_POSITION */ .oV, _source_js__WEBPACK_IMPORTED_MODULE_2__/* .DEFAULT_MAX_READ_POSITION */ .el);
        if (result instanceof Promise) {
            return result.then((x) => {
                if (!x) {
                    return null;
                }
                return new FileSlice(x.bytes, x.view, x.offset, start, end);
            });
        }
        else {
            if (!result) {
                return null;
            }
            return new FileSlice(result.bytes, result.view, result.offset, start, end);
        }
    }
    requestSliceRange(start, minLength, maxLength) {
        if (this.source._disposed) {
            throw new _input_js__WEBPACK_IMPORTED_MODULE_0__/* .InputDisposedError */ .QO();
        }
        if (start < 0) {
            return null;
        }
        if (this.fileSizeNonStrict !== null) {
            return this.requestSlice(start, (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .clamp */ .qE)(this.fileSizeNonStrict - start, minLength, maxLength));
        }
        else {
            const promisedAttempt = this.requestSlice(start, maxLength);
            const handleAttempt = (attempt) => {
                if (attempt) {
                    return attempt;
                }
                // The slice couldn't fit, meaning we must know the file size now
                (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .assert */ .vA)(this.fileSizeNonStrict !== null);
                return this.requestSlice(start, (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .clamp */ .qE)(this.fileSizeNonStrict - start, minLength, maxLength));
            };
            if (promisedAttempt instanceof Promise) {
                return promisedAttempt.then(handleAttempt);
            }
            else {
                return handleAttempt(promisedAttempt);
            }
        }
    }
    requestEntireFile() {
        if (this.fileSizeNonStrict !== null) {
            return this.requestSlice(0, this.fileSizeNonStrict);
        }
        const CHUNK_SIZE = 1024;
        return (async () => {
            const chunks = [];
            let currentSize = 0;
            while (true) {
                if (chunks.length === 1 && this.fileSizeNonStrict !== null) {
                    // It only took one read to get to know the whole file size
                    return this.requestSlice(0, this.fileSizeNonStrict);
                }
                const startOffset = chunks.length * CHUNK_SIZE;
                let slice = this.requestSliceRange(startOffset, 0, CHUNK_SIZE);
                if (slice instanceof Promise)
                    slice = await slice;
                if (!slice) {
                    break;
                }
                chunks.push(readBytes(slice, slice.length));
                currentSize += slice.length;
            }
            const joined = new Uint8Array(currentSize);
            let offset = 0;
            for (const chunk of chunks) {
                joined.set(chunk, offset);
                offset += chunk.length;
            }
            return new FileSlice(joined, (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .toDataView */ .Zc)(joined), 0, 0, currentSize);
        })();
    }
}
class FileSlice {
    constructor(
    /** The underlying bytes backing this slice. Avoid using this directly and prefer reader functions instead. */
    bytes, 
    /** A view into the bytes backing this slice. Avoid using this directly and prefer reader functions instead. */
    view, 
    /** The offset in "file bytes" at which `bytes` begins in the file. */
    offset, 
    /** The offset in "file bytes" where this slice begins. */
    start, 
    /** The offset in "file bytes" where this slice ends (exclusive). */
    end) {
        this.bytes = bytes;
        this.view = view;
        this.offset = offset;
        this.start = start;
        this.end = end;
        this.bufferPos = start - offset;
    }
    static tempFromBytes(bytes) {
        return new FileSlice(bytes, (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .toDataView */ .Zc)(bytes), 0, 0, bytes.length);
    }
    get length() {
        return this.end - this.start;
    }
    get filePos() {
        return this.offset + this.bufferPos;
    }
    set filePos(value) {
        this.bufferPos = value - this.offset;
    }
    /** The number of bytes left from the current pos to the end of the slice. */
    get remainingLength() {
        return Math.max(this.end - this.filePos, 0);
    }
    skip(byteCount) {
        this.bufferPos += byteCount;
    }
    /** Creates a new subslice of this slice whose byte range must be contained within this slice. */
    slice(filePos, length = this.end - filePos) {
        if (filePos < this.start || filePos + length > this.end) {
            throw new RangeError('Slicing outside of original slice.');
        }
        return new FileSlice(this.bytes, this.view, this.offset, filePos, filePos + length);
    }
}
const checkIsInRange = (slice, bytesToRead) => {
    if (slice.filePos < slice.start || slice.filePos + bytesToRead > slice.end) {
        throw new RangeError(`Tried reading [${slice.filePos}, ${slice.filePos + bytesToRead}), but slice is`
            + ` [${slice.start}, ${slice.end}). This is likely an internal error, please report it alongside the file`
            + ` that caused it.`);
    }
};
const readBytes = (slice, length) => {
    checkIsInRange(slice, length);
    const bytes = slice.bytes.subarray(slice.bufferPos, slice.bufferPos + length);
    slice.bufferPos += length;
    return bytes;
};
const readU8 = (slice) => {
    checkIsInRange(slice, 1);
    return slice.view.getUint8(slice.bufferPos++);
};
const readU16 = (slice, littleEndian) => {
    checkIsInRange(slice, 2);
    const value = slice.view.getUint16(slice.bufferPos, littleEndian);
    slice.bufferPos += 2;
    return value;
};
const readU16Be = (slice) => {
    checkIsInRange(slice, 2);
    const value = slice.view.getUint16(slice.bufferPos, false);
    slice.bufferPos += 2;
    return value;
};
const readU24Be = (slice) => {
    checkIsInRange(slice, 3);
    const value = (0,_misc_js__WEBPACK_IMPORTED_MODULE_1__/* .getUint24 */ .dq)(slice.view, slice.bufferPos, false);
    slice.bufferPos += 3;
    return value;
};
const readI16Be = (slice) => {
    checkIsInRange(slice, 2);
    const value = slice.view.getInt16(slice.bufferPos, false);
    slice.bufferPos += 2;
    return value;
};
const readU32 = (slice, littleEndian) => {
    checkIsInRange(slice, 4);
    const value = slice.view.getUint32(slice.bufferPos, littleEndian);
    slice.bufferPos += 4;
    return value;
};
const readU32Be = (slice) => {
    checkIsInRange(slice, 4);
    const value = slice.view.getUint32(slice.bufferPos, false);
    slice.bufferPos += 4;
    return value;
};
const readU32Le = (slice) => {
    checkIsInRange(slice, 4);
    const value = slice.view.getUint32(slice.bufferPos, true);
    slice.bufferPos += 4;
    return value;
};
const readI32Be = (slice) => {
    checkIsInRange(slice, 4);
    const value = slice.view.getInt32(slice.bufferPos, false);
    slice.bufferPos += 4;
    return value;
};
const readI32Le = (slice) => {
    checkIsInRange(slice, 4);
    const value = slice.view.getInt32(slice.bufferPos, true);
    slice.bufferPos += 4;
    return value;
};
const readU64 = (slice, littleEndian) => {
    let low;
    let high;
    if (littleEndian) {
        low = readU32(slice, true);
        high = readU32(slice, true);
    }
    else {
        high = readU32(slice, false);
        low = readU32(slice, false);
    }
    return high * 0x100000000 + low;
};
const readU64Be = (slice) => {
    const high = readU32Be(slice);
    const low = readU32Be(slice);
    return high * 0x100000000 + low;
};
const readI64Be = (slice) => {
    const high = readI32Be(slice);
    const low = readU32Be(slice);
    return high * 0x100000000 + low;
};
const readI64Le = (slice) => {
    const low = readU32Le(slice);
    const high = readI32Le(slice);
    return high * 0x100000000 + low;
};
const readF32Be = (slice) => {
    checkIsInRange(slice, 4);
    const value = slice.view.getFloat32(slice.bufferPos, false);
    slice.bufferPos += 4;
    return value;
};
const readF64Be = (slice) => {
    checkIsInRange(slice, 8);
    const value = slice.view.getFloat64(slice.bufferPos, false);
    slice.bufferPos += 8;
    return value;
};
const readAscii = (slice, length) => {
    checkIsInRange(slice, length);
    let str = '';
    for (let i = 0; i < length; i++) {
        str += String.fromCharCode(slice.bytes[slice.bufferPos++]);
    }
    return str;
};
const readAllLines = (slice, length, options) => {
    const text = _misc_js__WEBPACK_IMPORTED_MODULE_1__/* .textDecoder */ .su.decode(readBytes(slice, length));
    const lines = text.split('\n')
        .map(x => x.trim())
        .filter(x => x.length > 0 && !options?.ignore?.(x));
    return lines;
};


/***/ },

/***/ 4709
(__unused_webpack___webpack_module__, __webpack_exports__, __webpack_require__) {

var _node_js__WEBPACK_IMPORTED_MODULE_1___namespace_cache;
/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   Fy: () => (/* binding */ SourceRef),
/* harmony export */   QI: () => (/* binding */ PathedSource),
/* harmony export */   SM: () => (/* binding */ sourceRequestsAreEqual),
/* harmony export */   Ts: () => (/* binding */ UrlSource),
/* harmony export */   el: () => (/* binding */ DEFAULT_MAX_READ_POSITION),
/* harmony export */   kL: () => (/* binding */ Source),
/* harmony export */   m6: () => (/* binding */ ReadableStreamSource),
/* harmony export */   oV: () => (/* binding */ DEFAULT_MIN_READ_POSITION),
/* harmony export */   r3: () => (/* binding */ CustomPathedSource)
/* harmony export */ });
/* unused harmony exports BufferSource, BlobSource, FilePathSource, StreamSource, NullSource, RangedSource */
/* harmony import */ var _misc_js__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(3912);
/* harmony import */ var _node_js__WEBPACK_IMPORTED_MODULE_1__ = __webpack_require__(1845);
/* harmony import */ var _input_js__WEBPACK_IMPORTED_MODULE_2__ = __webpack_require__(2030);
/*!
 * Copyright (c) 2026-present, Vanilagy and contributors
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */



(0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .polyfillSymbolDispose */ .XQ)();
const node = typeof /*#__PURE__*/ (_node_js__WEBPACK_IMPORTED_MODULE_1___namespace_cache || (_node_js__WEBPACK_IMPORTED_MODULE_1___namespace_cache = __webpack_require__.t(_node_js__WEBPACK_IMPORTED_MODULE_1__, 2))) !== 'undefined'
    ? /*#__PURE__*/ (_node_js__WEBPACK_IMPORTED_MODULE_1___namespace_cache || (_node_js__WEBPACK_IMPORTED_MODULE_1___namespace_cache = __webpack_require__.t(_node_js__WEBPACK_IMPORTED_MODULE_1__, 2))) // Aliasing it prevents some bundler warnings
    : undefined;
const DEFAULT_MIN_READ_POSITION = 0;
const DEFAULT_MAX_READ_POSITION = Infinity;
/**
 * The source base class, representing a resource from which bytes can be read.
 * @group Input sources
 * @public
 */
class Source extends _misc_js__WEBPACK_IMPORTED_MODULE_0__/* .EventEmitter */ .bk {
    constructor() {
        super(...arguments);
        /** @internal */
        this._disposed = false;
        /** @internal */
        this._refCount = 0;
        /**
         * Used internally to mark if a source stems from an HLS reading operation. Used to suppress certain warnings.
         * @internal
         */
        this._usedForHls = false;
        /** @internal */
        this._sizePromise = null;
        /**
         * Called each time data is retrieved from the source. Will be called with the retrieved range (end exclusive).
         *
         * @deprecated Use `source.on('read', ({ start, end }) => ...)` instead.
         */
        this.onread = null;
    }
    /**
     * Resolves with the total size of the file in bytes. This function is memoized, meaning only the first call
     * will retrieve the size.
     *
     * Returns null if the source is unsized.
     */
    async getSizeOrNull() {
        if (this._disposed) {
            throw new _input_js__WEBPACK_IMPORTED_MODULE_2__/* .InputDisposedError */ .QO();
        }
        return this._sizePromise ??= (async () => {
            let size = this._getFileSize();
            if (size !== undefined) {
                return size;
            }
            await this._read(0, 1, DEFAULT_MIN_READ_POSITION, DEFAULT_MAX_READ_POSITION);
            size = this._getFileSize();
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(size !== undefined);
            return size;
        })();
    }
    /**
     * Resolves with the total size of the file in bytes. This function is memoized, meaning only the first call
     * will retrieve the size.
     *
     * Throws an error if the source is unsized.
     */
    async getSize() {
        if (this._disposed) {
            throw new _input_js__WEBPACK_IMPORTED_MODULE_2__/* .InputDisposedError */ .QO();
        }
        const result = await this.getSizeOrNull();
        if (result === null) {
            throw new Error('Cannot determine the size of an unsized source.');
        }
        return result;
    }
    /**
     * Returns a new {@link RangedSource} that maps data onto this source using the given offset and length. If a length
     * is not provided, the ranged source spans until the end of this source's data.
     *
     * Useful for reading files that are embedded within larger files.
     */
    slice(offset, length) {
        if (!Number.isInteger(offset) || offset < 0) {
            throw new TypeError('offset must be a non-negative integer.');
        }
        if (length !== undefined && (!Number.isInteger(length) || length < 0)) {
            throw new TypeError('length, when provided, must be a non-negative integer.');
        }
        return new RangedSource(this, offset, length);
    }
    /** @internal */
    _dispatchRead(start, end) {
        // eslint-disable-next-line @typescript-eslint/no-deprecated
        this.onread?.(start, end);
        this._emit('read', { start, end });
    }
    /**
     * Creates a new `SourceRef` pointing to this source. You are expected to call `.free()` on said `SourceRef` when
     * you're done with it.
     */
    ref() {
        return new SourceRef(this);
    }
}
/**
 * A reference to a {@link Source}, used to manage a source's lifecycle. Creating a `SourceRef` via {@link Source.ref}
 * increases that source's internal reference count. As long as a source has a non-zero reference count, it is assumed
 * to still be in use. Once all references are freed via {@link SourceRef.free}, the source gets disposed.
 *
 * @group Input sources
 * @public
 */
class SourceRef {
    /** @internal */
    constructor(source) {
        /** @internal */
        this._freed = false;
        if (source._disposed) {
            throw new Error('Cannot ref a disposed source.');
        }
        source._refCount++;
        this._source = source;
    }
    /** The {@link Source} this ref references. Accessing this field throws an error after having freed the ref. */
    get source() {
        if (!this._source) {
            throw new Error('Can\'t get source; ref has already been freed.');
        }
        return this._source;
    }
    /** Whether or not this reference has been freed via {@link SourceRef.free}. */
    get freed() {
        return this._freed;
    }
    /**
     * Frees the ref, decrementing the source's internal reference count. If the source's internal reference count
     * reaches zero, it gets disposed. To catch bugs, this method throws if the ref is already freed.
     */
    free() {
        if (this._freed) {
            throw new Error('Illegal operation: double free on SourceRef.');
        }
        const source = this.source;
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(source._refCount > 0);
        source._refCount--;
        if (source._refCount === 0) {
            source._dispose();
            source._disposed = true;
        }
        this._freed = true;
        this._source = null;
    }
    /**
     * Calls {@link SourceRef.free}.
     */
    [Symbol.dispose]() {
        if (!this.freed) {
            this.free();
        }
    }
}
/**
 * A source which can create new sources from file paths. Required for multi-file inputs such as HLS playlists.
 * @public
 * @group Input sources
 */
class PathedSource extends Source {
    constructor(
    /** The path that points to the root file; the entry file of the media. */
    rootPath, 
    /** The callback that is called for each requested file; must return a {@link Source} or {@link SourceRef}. */
    requestHandler) {
        if (typeof rootPath !== 'string') {
            throw new TypeError('rootPath must be a string.');
        }
        if (typeof requestHandler !== 'function') {
            throw new TypeError('requestHandler must be a function.');
        }
        super();
        this.rootPath = rootPath;
        this.requestHandler = requestHandler;
    }
    /** @internal */
    _resolveRequest(request) {
        const result = this.requestHandler(request);
        const handle = (result) => {
            if (!(result instanceof Source || result instanceof SourceRef)) {
                throw new TypeError('requestHandler must return or resolve to a Source or SourceRef.');
            }
            const ref = result instanceof Source
                ? result.ref()
                : result;
            ref.source._usedForHls ||= this._usedForHls;
            return ref;
        };
        if (result instanceof Promise) {
            return result.then(handle);
        }
        else {
            return handle(result);
        }
    }
}
const sourceRequestsAreEqual = (a, b) => {
    return a.path === b.path;
};
/**
 * A custom multi-file source where each file is uniquely identified by a {@link FilePath} and can be resolved to
 * an arbitrary {@link Source}.
 *
 * @public
 * @group Input sources
 */
class CustomPathedSource extends PathedSource {
    constructor() {
        super(...arguments);
        /** @internal */
        this._root = null;
        /** @internal */
        this._rootRequest = null;
    }
    /** @internal */
    _read(start, end, minReadPosition, maxReadPosition) {
        if (!this._root) {
            if (!this._rootRequest) {
                const result = this._resolveRequest({ path: this.rootPath, isRoot: true });
                const handle = (result) => {
                    const ref = result instanceof Source
                        ? result.ref()
                        : result;
                    this._root = ref;
                    this._rootRequest = null;
                    return ref;
                };
                if (result instanceof Promise) {
                    this._rootRequest = result.then(handle);
                }
                else {
                    handle(result);
                    (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(this._root);
                }
            }
            if (this._rootRequest) {
                return this._rootRequest.then(ref => ref.source._read(start, end, minReadPosition, maxReadPosition));
            }
        }
        return this._root.source._read(start, end, minReadPosition, maxReadPosition);
    }
    /** @internal */
    _getFileSize() {
        if (this._root) {
            return this._root.source._getFileSize();
        }
        return undefined;
    }
    /** @internal */
    _dispose() {
        if (this._root) {
            this._root.free();
        }
        else if (this._rootRequest) {
            void this._rootRequest
                .then(ref => ref.free());
        }
    }
}
/**
 * A source backed by an ArrayBuffer or ArrayBufferView, with the entire file held in memory.
 * @group Input sources
 * @public
 */
class BufferSource extends Source {
    /**
     * Creates a new {@link BufferSource} backed by the specified `ArrayBuffer`, `SharedArrayBuffer`,
     * or `ArrayBufferView`.
     */
    constructor(buffer) {
        if (!(buffer instanceof ArrayBuffer)
            && !(typeof SharedArrayBuffer !== 'undefined' && buffer instanceof SharedArrayBuffer)
            && !ArrayBuffer.isView(buffer)) {
            throw new TypeError('buffer must be an ArrayBuffer, SharedArrayBuffer, or ArrayBufferView.');
        }
        super();
        /** @internal */
        this._onreadCalled = false;
        this._bytes = (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .toUint8Array */ .Fo)(buffer);
        this._view = (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .toDataView */ .Zc)(buffer);
    }
    /** @internal */
    _getFileSize() {
        return this._bytes.byteLength;
    }
    /** @internal */
    _read() {
        if (!this._onreadCalled) {
            // We just say the first read retrieves all bytes from the source (which, I mean, it does)
            this._dispatchRead(0, this._bytes.byteLength);
            this._onreadCalled = true;
        }
        return {
            bytes: this._bytes,
            view: this._view,
            offset: 0,
        };
    }
    /** @internal */
    _dispose() { }
}
/**
 * A source backed by a [`Blob`](https://developer.mozilla.org/en-US/docs/Web/API/Blob). Since a
 * [`File`](https://developer.mozilla.org/en-US/docs/Web/API/File) is also a `Blob`, this is the source to use when
 * reading files off the disk.
 * @group Input sources
 * @public
 */
class BlobSource extends Source {
    /**
     * Creates a new {@link BlobSource} backed by the specified
     * [`Blob`](https://developer.mozilla.org/en-US/docs/Web/API/Blob).
     */
    constructor(blob, options = {}) {
        if (!(blob instanceof Blob)) {
            throw new TypeError('blob must be a Blob.');
        }
        if (!options || typeof options !== 'object') {
            throw new TypeError('options must be an object.');
        }
        if (options.maxCacheSize !== undefined
            && (!(0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .isNumber */ .Et)(options.maxCacheSize) || options.maxCacheSize < 0)) {
            throw new TypeError('options.maxCacheSize, when provided, must be a non-negative number.');
        }
        super();
        /** @internal */
        this._readers = new WeakMap();
        this._blob = blob;
        this._orchestrator = new ReadOrchestrator({
            maxCacheSize: options.maxCacheSize ?? (8 * 2 ** 20 /* 8 MiB */),
            maxWorkerCount: 4,
            runWorker: this._runWorker.bind(this),
            prefetchProfile: PREFETCH_PROFILES.fileSystem,
        });
        this._orchestrator.fileSize = blob.size;
    }
    /** @internal */
    _getFileSize() {
        return this._orchestrator.fileSize; // Faster than blob.size
    }
    /** @internal */
    _read(start, end, minReadPosition, maxReadPosition) {
        return this._orchestrator.read(start, end, minReadPosition, maxReadPosition);
    }
    /** @internal */
    async _runWorker(worker) {
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(worker.strictTarget);
        let reader = this._readers.get(worker);
        if (reader === undefined) {
            // https://github.com/Vanilagy/mediabunny/issues/184
            // WebKit has critical bugs with blob.stream():
            // - WebKitBlobResource error 1 when streaming large files
            // - Memory buildup and reload loops on iOS (network process crashes)
            // - ReadableStream stalls under backpressure (especially video)
            // Affects Safari and all iOS browsers (Chrome, Firefox, etc.).
            // Use arrayBuffer() fallback for WebKit browsers.
            if ('stream' in this._blob && !(0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .isWebKit */ .Tc)()) {
                // Get a reader of the blob starting at the required offset, and then keep it around
                const slice = this._blob.slice(worker.currentPos);
                reader = slice.stream().getReader();
            }
            else {
                // We'll need to use more primitive ways
                reader = null;
            }
            this._readers.set(worker, reader);
        }
        while (worker.currentPos < worker.targetPos && !worker.aborted) {
            if (reader) {
                const { done, value } = await reader.read();
                if (done) {
                    this._orchestrator.onWorkerFinished(worker);
                    throw new Error('Blob reader stopped unexpectedly before all requested data was read.');
                }
                if (worker.aborted) {
                    break;
                }
                this._dispatchRead(worker.currentPos, worker.currentPos + value.length);
                this._orchestrator.supplyWorkerData(worker, value);
            }
            else {
                const data = await this._blob.slice(worker.currentPos, worker.targetPos).arrayBuffer();
                if (worker.aborted) {
                    break;
                }
                this._dispatchRead(worker.currentPos, worker.currentPos + data.byteLength);
                this._orchestrator.supplyWorkerData(worker, new Uint8Array(data));
            }
        }
        this._orchestrator.signalWorkerStoppedRunning(worker);
        if (worker.aborted) {
            // MDN: "Calling this method signals a loss of interest in the stream by a consumer."
            await reader?.cancel();
        }
    }
    /** @internal */
    _dispose() {
        this._orchestrator.dispose();
    }
}
const URL_SOURCE_MIN_LOAD_AMOUNT = 0.5 * 2 ** 20; // 0.5 MiB
const DEFAULT_RETRY_DELAY = ((previousAttempts, error, src) => {
    // Check if this could be a CORS error. If so, we cannot recover from it and
    // should not attempt to retry.
    // CORS errors are intentionally not opaque, so we need to rely on heuristics.
    const couldBeCorsError = error instanceof Error && (error.message.includes('Failed to fetch') // Chrome
        || error.message.includes('Load failed') // Safari
        || error.message.includes('NetworkError when attempting to fetch resource') // Firefox
    );
    if (couldBeCorsError) {
        let originOfSrc = null;
        // Checking if the origin is different, because only then a CORS error could originate
        try {
            if (typeof window !== 'undefined' && typeof window.location !== 'undefined') {
                originOfSrc = new URL(src instanceof Request ? src.url : src, window.location.href).origin;
            }
        }
        catch {
            // URL parse failed
        }
        // If user is offline, it is probably not a CORS error.
        const isOnline = typeof navigator !== 'undefined' && typeof navigator.onLine === 'boolean' ? navigator.onLine : true;
        if (isOnline && originOfSrc !== null && originOfSrc !== window.location.origin) {
            console.warn(`Request will not be retried because a CORS error was suspected due to different origins. You can`
                + ` modify this behavior by providing your own function for the 'getRetryDelay' option.`);
            return null;
        }
    }
    return Math.min(2 ** (previousAttempts - 2), 16);
});
const warnedOrigins = new Set();
/**
 * A source backed by a URL. This is useful for reading data from the network. Requests will be made using an optimized
 * reading and prefetching pattern to minimize request count and latency.
 * @group Input sources
 * @public
 */
class UrlSource extends PathedSource {
    /**
     * Creates a new {@link UrlSource} backed by the resource at the specified URL.
     *
     * When passing a `Request` instance, note that the `signal` and `headers.Range` options will be overridden by
     * Mediabunny. If you want to cancel ongoing requests, use {@link Input.dispose}.
     */
    constructor(url, options = {}) {
        if (typeof url !== 'string'
            && !(url instanceof URL)
            && !(typeof Request !== 'undefined' && url instanceof Request)) {
            throw new TypeError('url must be a string, URL or Request.');
        }
        if (!options || typeof options !== 'object') {
            throw new TypeError('options must be an object.');
        }
        if (options.requestInit !== undefined && (!options.requestInit || typeof options.requestInit !== 'object')) {
            throw new TypeError('options.requestInit, when provided, must be an object.');
        }
        if (options.getRetryDelay !== undefined && typeof options.getRetryDelay !== 'function') {
            throw new TypeError('options.getRetryDelay, when provided, must be a function.');
        }
        if (options.maxCacheSize !== undefined
            && (!(0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .isNumber */ .Et)(options.maxCacheSize) || options.maxCacheSize < 0)) {
            throw new TypeError('options.maxCacheSize, when provided, must be a non-negative number.');
        }
        if (options.parallelism !== undefined && (!Number.isInteger(options.parallelism) || options.parallelism < 1)) {
            throw new TypeError('options.parallelism, when provided, must be a positive number.');
        }
        if (options.fetchFn !== undefined && typeof options.fetchFn !== 'function') {
            throw new TypeError('options.fetchFn, when provided, must be a function.');
            // Won't bother validating this function beyond this
        }
        const urlString = url instanceof Request
            ? url.url
            : url instanceof URL
                ? url.href
                : url;
        super(urlString, request => new UrlSource(request.path, this._options));
        /**
         * Note that this value being true does NOT mean the file size can't change anymore; it just signals that we have at
         * least checked if we know the file size or not.
         * @internal
         */
        this._fileSizeDetermined = false;
        this._url = url;
        this._options = options;
        this._getRetryDelay = options.getRetryDelay ?? DEFAULT_RETRY_DELAY;
        // Most files in the real-world have a single sequential access pattern, but having two in parallel can
        // also happen
        const DEFAULT_PARALLELISM = 2;
        this._orchestrator = new ReadOrchestrator({
            maxCacheSize: options.maxCacheSize ?? (64 * 2 ** 20 /* 64 MiB */),
            maxWorkerCount: options.parallelism ?? DEFAULT_PARALLELISM,
            runWorker: this._runWorker.bind(this),
            prefetchProfile: PREFETCH_PROFILES.network,
        });
    }
    /** @internal */
    _getFileSize() {
        return this._fileSizeDetermined
            ? this._orchestrator.fileSize
            : undefined;
    }
    /** @internal */
    _read(start, end, minReadPosition, maxReadPosition) {
        return this._orchestrator.read(start, end, minReadPosition, maxReadPosition);
    }
    /** @internal */
    async _runWorker(worker) {
        // The outer loop is for resuming a request if it dies mid-response
        while (true) {
            const abortController = new AbortController();
            const response = await (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .retriedFetch */ .G8)(this._options.fetchFn ?? fetch, this._url, (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .mergeRequestInit */ ._h)(this._options.requestInit ?? {}, {
                headers: {
                    // Always sending a range request is a good way to probe if the server supports them
                    Range: `bytes=${worker.currentPos}-`,
                },
                signal: abortController.signal,
            }), this._getRetryDelay, () => this._disposed);
            if (!response.ok) {
                // eslint-disable-next-line @typescript-eslint/no-base-to-string
                throw new Error(`Error fetching ${String(this._url)}: ${response.status} ${response.statusText}`);
            }
            outer: if (this._orchestrator.fileSize === null) {
                // See if we can deduce the file size from the response
                const contentRange = response.headers.get('Content-Range');
                if (contentRange) {
                    const match = /\/(\d+)/.exec(contentRange);
                    if (match) {
                        this._orchestrator.supplyFileSize(Number(match[1]));
                        break outer;
                    }
                }
                const contentLength = response.headers.get('Content-Length');
                if (contentLength) {
                    // Note: For range requests, this is _technically_ not correct, as the range response could contain
                    // less data than was requested. In practice, it seems most servers don't do this though, and the
                    // Content-Length header actually contains the length until the end of the file.
                    this._orchestrator.supplyFileSize(worker.currentPos + Number(contentLength));
                }
            }
            this._fileSizeDetermined = true; // Yes, this is correct even if file size is still null
            if (response.status !== 206) {
                if (!this._usedForHls) {
                    const url = new URL(this._url instanceof Request ? this._url.url : this._url, typeof window !== 'undefined' ? window.location.href : undefined);
                    if (url.origin !== 'null'
                        // Don't show the warning for M3U8 playlist files, it's irrelevant for those
                        && !(url.pathname.endsWith('.m3u8') || url.pathname.endsWith('.m3u'))) {
                        if (!warnedOrigins.has(url.origin)) {
                            console.log(this._usedForHls, this._url, url.pathname);
                            console.warn(`HTTP server (origin ${url.origin}) did not respond to a range request with 206 Partial`
                                + ' Content, meaning the entire resource will now be downloaded. To enable efficient'
                                + ' media file streaming across a network, please make sure your server supports'
                                + ' range requests.');
                            warnedOrigins.add(url.origin);
                        }
                    }
                }
                worker.currentPos = 0;
                this._orchestrator.options.maxCacheSize = Infinity; // 🤷
                if (this._orchestrator.fileSize !== null) {
                    worker.targetPos = this._orchestrator.fileSize;
                }
                else {
                    // The server is dumb, doesn't even surface the content length, but we'll work with it.
                    worker.targetPos = Infinity;
                    worker.strictTarget = false;
                }
                this._orchestrator.consolidateEverythingIntoOneWorker(worker);
            }
            if (!response.body) {
                throw new Error('Missing HTTP response body stream. The used fetch function must provide the response body as a'
                    + ' ReadableStream.');
            }
            const reader = response.body.getReader();
            while (true) {
                if (worker.currentPos >= worker.targetPos || worker.aborted) {
                    abortController.abort();
                    this._orchestrator.signalWorkerStoppedRunning(worker);
                    return;
                }
                let readResult;
                try {
                    readResult = await reader.read();
                }
                catch (error) {
                    if (this._disposed) {
                        // No need to try to retry
                        throw error;
                    }
                    const retryDelayInSeconds = this._getRetryDelay(1, error, this._url);
                    if (retryDelayInSeconds !== null) {
                        console.error('Error while reading response stream. Attempting to resume.', error);
                        await (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .wait */ .uk)(1000 * retryDelayInSeconds);
                        break;
                    }
                    else {
                        throw error;
                    }
                }
                if (worker.aborted) {
                    continue; // Cleanup happens in next iteration
                }
                const { done, value } = readResult;
                if (done) {
                    if (worker.currentPos >= worker.targetPos) {
                        // All data was delivered, we're good
                        this._orchestrator.onWorkerFinished(worker);
                        return;
                    }
                    if (worker.strictTarget) {
                        // The response stopped early, before the target. This can happen if server decides to cap range
                        // requests arbitrarily, even if the request had an uncapped end. In this case, let's fetch the
                        // rest of the data using a new request.
                        break;
                    }
                    else {
                        // Assume we have simply reached the end of the resource
                        this._orchestrator.onWorkerFinished(worker);
                        return;
                    }
                }
                this._dispatchRead(worker.currentPos, worker.currentPos + value.length);
                this._orchestrator.supplyWorkerData(worker, value);
            }
        }
        // The previous UrlSource had logic for circumventing https://issues.chromium.org/issues/436025873; I haven't
        // been able to observe this bug with the new UrlSource (maybe because we're using response streaming), so the
        // logic for that has vanished for now. Leaving a comment here if this becomes relevant again.
    }
    /** @internal */
    _dispose() {
        this._orchestrator.dispose();
    }
}
/**
 * A source backed by a path to a file. Intended for server-side usage in Node, Bun, or Deno.
 *
 * Make sure to call `.dispose()` on the corresponding {@link Input} when done to explicitly free the internal file
 * handle acquired by this source.
 * @group Input sources
 * @public
 */
class FilePathSource extends PathedSource {
    /** Creates a new {@link FilePathSource} backed by the file at the specified file path. */
    constructor(filePath, options = {}) {
        if (typeof filePath !== 'string') {
            throw new TypeError('filePath must be a string.');
        }
        if (!options || typeof options !== 'object') {
            throw new TypeError('options must be an object.');
        }
        if (options.maxCacheSize !== undefined
            && (!(0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .isNumber */ .Et)(options.maxCacheSize) || options.maxCacheSize < 0)) {
            throw new TypeError('options.maxCacheSize, when provided, must be a non-negative number.');
        }
        if (!node.fs) {
            throw new Error('FilePathSource is only available in server-side environments (Node.js, Bun, Deno).');
        }
        super(filePath, request => new FilePathSource(request.path, options));
        /** @internal */
        this._fileHandle = null;
        // Let's back this source with a StreamSource, makes the implementation very simple
        this._streamSource = new StreamSource({
            getSize: async () => {
                this._fileHandle = await node.fs.open(filePath, 'r');
                const stats = await this._fileHandle.stat();
                return stats.size;
            },
            read: async (start, end) => {
                (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(this._fileHandle);
                const buffer = new Uint8Array(end - start);
                await this._fileHandle.read(buffer, 0, end - start, start);
                return buffer;
            },
            maxCacheSize: options.maxCacheSize,
            prefetchProfile: 'fileSystem',
        });
    }
    /** @internal */
    _read(start, end, minReadPosition, maxReadPosition) {
        return this._streamSource._read(start, end, minReadPosition, maxReadPosition);
    }
    /** @internal */
    _getFileSize() {
        return this._streamSource._getFileSize();
    }
    /** @internal */
    _dispose() {
        this._streamSource._dispose();
        void this._fileHandle?.close();
        this._fileHandle = null;
    }
}
/**
 * A general-purpose, callback-driven source that can get its data from anywhere.
 * @group Input sources
 * @public
 */
class StreamSource extends Source {
    /** Creates a new {@link StreamSource} whose behavior is specified by `options`.  */
    constructor(options) {
        if (!options || typeof options !== 'object') {
            throw new TypeError('options must be an object.');
        }
        if (typeof options.getSize !== 'function') {
            throw new TypeError('options.getSize must be a function.');
        }
        if (typeof options.read !== 'function') {
            throw new TypeError('options.read must be a function.');
        }
        if (options.dispose !== undefined && typeof options.dispose !== 'function') {
            throw new TypeError('options.dispose, when provided, must be a function.');
        }
        if (options.maxCacheSize !== undefined
            && (!(0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .isNumber */ .Et)(options.maxCacheSize) || options.maxCacheSize < 0)) {
            throw new TypeError('options.maxCacheSize, when provided, must be a non-negative number.');
        }
        if (options.prefetchProfile && !['none', 'fileSystem', 'network'].includes(options.prefetchProfile)) {
            throw new TypeError('options.prefetchProfile, when provided, must be one of \'none\', \'fileSystem\' or \'network\'.');
        }
        super();
        this._options = options;
        this._orchestrator = new ReadOrchestrator({
            maxCacheSize: options.maxCacheSize ?? (8 * 2 ** 20 /* 8 MiB */),
            maxWorkerCount: 2, // Fixed for now, *should* be fine
            prefetchProfile: PREFETCH_PROFILES[options.prefetchProfile ?? 'none'],
            runWorker: this._runWorker.bind(this),
        });
    }
    /** @internal */
    _getFileSize() {
        return this._orchestrator.fileSize ?? undefined;
    }
    /** @internal */
    _read(start, end, minReadPosition, maxReadPosition) {
        if (this._orchestrator.fileSize !== null) {
            return this._orchestrator.read(start, end, minReadPosition, maxReadPosition);
        }
        const result = this._options.getSize();
        if (result instanceof Promise) {
            return result.then((size) => {
                if (!Number.isInteger(size) || size < 0) {
                    throw new TypeError('options.getSize must return or resolve to a non-negative integer.');
                }
                this._orchestrator.fileSize = size;
                return this._orchestrator.read(start, end, minReadPosition, maxReadPosition);
            });
        }
        else {
            if (!Number.isInteger(result) || result < 0) {
                throw new TypeError('options.getSize must return or resolve to a non-negative integer.');
            }
            this._orchestrator.fileSize = result;
            return this._orchestrator.read(start, end, minReadPosition, maxReadPosition);
        }
    }
    /** @internal */
    async _runWorker(worker) {
        while (worker.currentPos < worker.targetPos && !worker.aborted) {
            const originalCurrentPos = worker.currentPos;
            const originalTargetPos = worker.targetPos;
            let data = this._options.read(worker.currentPos, originalTargetPos);
            if (data instanceof Promise)
                data = await data;
            if (worker.aborted) {
                break;
            }
            if (data instanceof Uint8Array) {
                data = (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .toUint8Array */ .Fo)(data); // Normalize things like Node.js Buffer to Uint8Array
                if (data.length !== originalTargetPos - worker.currentPos) {
                    // Yes, we're that strict
                    throw new Error(`options.read returned a Uint8Array with unexpected length: Requested ${originalTargetPos - worker.currentPos} bytes, but got ${data.length}.`);
                }
                this._dispatchRead(worker.currentPos, worker.currentPos + data.length);
                this._orchestrator.supplyWorkerData(worker, data);
            }
            else if (data instanceof ReadableStream) {
                const reader = data.getReader();
                while (worker.currentPos < originalTargetPos && !worker.aborted) {
                    const { done, value } = await reader.read();
                    if (done) {
                        if (worker.currentPos < originalTargetPos) {
                            // Yes, we're *that* strict
                            throw new Error(`ReadableStream returned by options.read ended before supplying enough data.`
                                + ` Requested ${originalTargetPos - originalCurrentPos} bytes, but got ${worker.currentPos - originalCurrentPos}`);
                        }
                        break;
                    }
                    if (!(value instanceof Uint8Array)) {
                        throw new TypeError('ReadableStream returned by options.read must yield Uint8Array chunks.');
                    }
                    if (worker.aborted) {
                        break;
                    }
                    const data = (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .toUint8Array */ .Fo)(value); // Normalize things like Node.js Buffer to Uint8Array
                    this._dispatchRead(worker.currentPos, worker.currentPos + data.length);
                    this._orchestrator.supplyWorkerData(worker, data);
                }
            }
            else {
                throw new TypeError('options.read must return or resolve to a Uint8Array or a ReadableStream.');
            }
        }
        this._orchestrator.signalWorkerStoppedRunning(worker);
    }
    /** @internal */
    _dispose() {
        this._orchestrator.dispose();
        this._options.dispose?.();
    }
}
/**
 * A source backed by a [`ReadableStream`](https://developer.mozilla.org/en-US/docs/Web/API/ReadableStream) of
 * `Uint8Array`, representing an append-only byte stream of unknown length. This is the source to use for incrementally
 * streaming in input files that are still being constructed and whose size we don't yet know, like for example the
 * output chunks of [MediaRecorder](https://developer.mozilla.org/en-US/docs/Web/API/MediaRecorder).
 *
 * This source is *unsized*, meaning calls to `.getSize()` will throw and readers are more limited due to the
 * lack of random file access. You should only use this source with sequential access patterns, such as reading all
 * packets from start to end. This source does not work well with random access patterns unless you increase its
 * max cache size.
 *
 * @group Input sources
 * @public
 */
class ReadableStreamSource extends Source {
    /** Creates a new {@link ReadableStreamSource} backed by the specified `ReadableStream<Uint8Array>`. */
    constructor(stream, options = {}) {
        if (!(stream instanceof ReadableStream)) {
            throw new TypeError('stream must be a ReadableStream.');
        }
        if (!options || typeof options !== 'object') {
            throw new TypeError('options must be an object.');
        }
        if (options.maxCacheSize !== undefined
            && (!(0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .isNumber */ .Et)(options.maxCacheSize) || options.maxCacheSize < 0)) {
            throw new TypeError('options.maxCacheSize, when provided, must be a non-negative number.');
        }
        super();
        /** @internal */
        this._reader = null;
        /** @internal */
        this._cache = [];
        /** @internal */
        this._pendingSlices = [];
        /** @internal */
        this._currentIndex = 0;
        /** @internal */
        this._targetIndex = 0;
        /** @internal */
        this._maxRequestedIndex = 0;
        /** @internal */
        this._endIndex = null;
        /** @internal */
        this._pulling = false;
        this._stream = stream;
        this._maxCacheSize = options.maxCacheSize ?? (16 * 2 ** 20 /* 16 MiB */);
    }
    /** @internal */
    _getFileSize() {
        return this._endIndex; // Starts out as null, meaning this source is unsized
    }
    /** @internal */
    _read(start, end) {
        if (this._endIndex !== null && end > this._endIndex) {
            return null;
        }
        this._maxRequestedIndex = Math.max(this._maxRequestedIndex, end);
        const cacheStartIndex = (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .binarySearchLessOrEqual */ .eE)(this._cache, start, x => x.start);
        const cacheStartEntry = cacheStartIndex !== -1 ? this._cache[cacheStartIndex] : null;
        if (cacheStartEntry && cacheStartEntry.start <= start && end <= cacheStartEntry.end) {
            // The request can be satisfied with a single cache entry
            return {
                bytes: cacheStartEntry.bytes,
                view: cacheStartEntry.view,
                offset: cacheStartEntry.start,
            };
        }
        let lastEnd = start;
        const bytes = new Uint8Array(end - start);
        if (cacheStartIndex !== -1) {
            // Walk over the cache to see if we can satisfy the request using multiple cache entries
            for (let i = cacheStartIndex; i < this._cache.length; i++) {
                const cacheEntry = this._cache[i];
                if (cacheEntry.start >= end) {
                    break;
                }
                const cappedStart = Math.max(start, cacheEntry.start);
                if (cappedStart > lastEnd) {
                    // We're too far behind
                    this._throwDueToCacheMiss();
                }
                const cappedEnd = Math.min(end, cacheEntry.end);
                if (cappedStart < cappedEnd) {
                    bytes.set(cacheEntry.bytes.subarray(cappedStart - cacheEntry.start, cappedEnd - cacheEntry.start), cappedStart - start);
                    lastEnd = cappedEnd;
                }
            }
        }
        if (lastEnd === end) {
            return {
                bytes,
                view: (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .toDataView */ .Zc)(bytes),
                offset: start,
            };
        }
        // We need to pull more data
        if (this._currentIndex > lastEnd) {
            // We're too far behind
            this._throwDueToCacheMiss();
        }
        const { promise, resolve, reject } = (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .promiseWithResolvers */ .nJ)();
        this._pendingSlices.push({
            start,
            end,
            bytes,
            resolve,
            reject,
        });
        this._targetIndex = Math.max(this._targetIndex, end);
        // Start pulling from the stream if we're not already doing it
        if (!this._pulling) {
            this._pulling = true;
            void this._pull()
                .catch((error) => {
                this._pulling = false;
                if (this._pendingSlices.length > 0) {
                    this._pendingSlices.forEach(x => x.reject(error)); // Make sure to propagate any errors
                    this._pendingSlices.length = 0;
                }
                else {
                    throw error; // So it doesn't get swallowed
                }
            });
        }
        return promise;
    }
    /** @internal */
    _throwDueToCacheMiss() {
        throw new Error('Read is before the cached region. With ReadableStreamSource, you must access the data more'
            + ' sequentially or increase the size of its cache.');
    }
    /** @internal */
    async _pull() {
        this._reader ??= this._stream.getReader();
        // This is the loop that keeps pulling data from the stream until a target index is reached, filling requests
        // in the process
        while (this._currentIndex < this._targetIndex && !this._disposed) {
            const { done, value } = await this._reader.read();
            if (done) {
                for (const pendingSlice of this._pendingSlices) {
                    pendingSlice.resolve(null);
                }
                this._pendingSlices.length = 0;
                this._endIndex = this._currentIndex; // We know how long the file is now!
                break;
            }
            const startIndex = this._currentIndex;
            const endIndex = this._currentIndex + value.byteLength;
            // Fill the pending slices with the data
            for (let i = 0; i < this._pendingSlices.length; i++) {
                const pendingSlice = this._pendingSlices[i];
                const cappedStart = Math.max(startIndex, pendingSlice.start);
                const cappedEnd = Math.min(endIndex, pendingSlice.end);
                if (cappedStart < cappedEnd) {
                    pendingSlice.bytes.set(value.subarray(cappedStart - startIndex, cappedEnd - startIndex), cappedStart - pendingSlice.start);
                    if (cappedEnd === pendingSlice.end) {
                        // Pending slice fully filled
                        pendingSlice.resolve({
                            bytes: pendingSlice.bytes,
                            view: (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .toDataView */ .Zc)(pendingSlice.bytes),
                            offset: pendingSlice.start,
                        });
                        this._pendingSlices.splice(i, 1);
                        i--;
                    }
                }
            }
            this._cache.push({
                start: startIndex,
                end: endIndex,
                bytes: value,
                view: (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .toDataView */ .Zc)(value),
                age: 0, // Unused
            });
            // Do cache eviction, based on the distance from the last-requested index. It's important that we do it like
            // this and not based on where the reader is at, because if the reader is fast, we'll unnecessarily evict
            // data that we still might need.
            while (this._cache.length > 0) {
                const firstEntry = this._cache[0];
                const distance = this._maxRequestedIndex - firstEntry.end;
                if (distance <= this._maxCacheSize) {
                    break;
                }
                this._cache.shift();
            }
            this._currentIndex += value.byteLength;
        }
        this._pulling = false;
    }
    /** @internal */
    _dispose() {
        this._pendingSlices.length = 0;
        this._cache.length = 0;
        void this._reader?.cancel();
    }
}
const PREFETCH_PROFILES = {
    none: (start, end) => ({ start, end }),
    fileSystem: (start, end) => {
        const padding = 2 ** 16;
        start = Math.floor((start - padding) / padding) * padding;
        end = Math.ceil((end + padding) / padding) * padding;
        return { start, end };
    },
    network: (start, end, workers) => {
        // Add a slight bit of start padding because backwards reading is painful
        const paddingStart = 2 ** 16;
        start = Math.max(0, Math.floor((start - paddingStart) / paddingStart) * paddingStart);
        // Remote resources have extreme latency (relatively speaking), so the benefit from intelligent
        // prefetching is great. The network prefetch strategy is as follows: When we notice
        // successive reads to a worker's read region, we prefetch more data at the end of that region,
        // growing exponentially (up to a cap). This performs well for real-world use cases: Either we read a
        // small part of the file once and then never need it again, in which case the requested about of data
        // is small. Or, we're repeatedly doing a sequential access pattern (common in media files), in which
        // case we can become more and more confident to prefetch more and more data.
        for (const worker of workers) {
            const maxExtensionAmount = 8 * 2 ** 20; // 8 MiB
            // When the read region cross the threshold point, we trigger a prefetch. This point is typically
            // in the middle of the worker's read region, or a fixed offset from the end if the region has grown
            // really large.
            const thresholdPoint = Math.max((worker.startPos + worker.targetPos) / 2, worker.targetPos - maxExtensionAmount);
            if ((0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .closedIntervalsOverlap */ .oX)(start, end, thresholdPoint, worker.targetPos)) {
                const size = worker.targetPos - worker.startPos;
                // If we extend by maxExtensionAmount
                const a = Math.ceil((size + 1) / maxExtensionAmount) * maxExtensionAmount;
                // If we extend to the next power of 2
                const b = 2 ** Math.ceil(Math.log2(size + 1));
                const extent = Math.min(b, a);
                end = Math.max(end, worker.startPos + extent);
            }
        }
        end = Math.max(end, start + URL_SOURCE_MIN_LOAD_AMOUNT);
        return {
            start,
            end,
        };
    },
};
/**
 * Godclass for orchestrating complex, cached read operations. The reading model is as follows: Any reading task is
 * delegated to a *worker*, which is a sequential reader positioned somewhere along the file. All workers run in
 * parallel and can be stopped and resumed in their forward movement. When read requests come in, this orchestrator will
 * first try to satisfy the request with only the cached data. If this isn't possible, workers are spun up for all
 * missing parts (or existing workers are repurposed), and these workers will then fill the holes in the data as they
 * march along the file.
 */
class ReadOrchestrator {
    constructor(options) {
        this.options = options;
        this.fileSize = null;
        this.nextAge = 0; // Used for multiple things
        this.workers = [];
        this.cache = [];
        this.currentCacheSize = 0;
        this.disposed = false;
        this.queuedReads = [];
    }
    read(innerStart, innerEnd, minReadPosition, maxReadPosition) {
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(!this.disposed);
        const prefetchRange = this.options.prefetchProfile(innerStart, innerEnd, this.workers);
        const outerStart = Math.max(prefetchRange.start, minReadPosition);
        const outerEnd = Math.min(prefetchRange.end, this.fileSize ?? Infinity, maxReadPosition);
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(outerStart <= innerStart && innerEnd <= outerEnd);
        let result = null;
        const innerCacheStartIndex = (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .binarySearchLessOrEqual */ .eE)(this.cache, innerStart, x => x.start);
        const innerStartEntry = innerCacheStartIndex !== -1 ? this.cache[innerCacheStartIndex] : null;
        // See if the read request can be satisfied by a single cache entry
        if (innerStartEntry && innerStartEntry.start <= innerStart && innerEnd <= innerStartEntry.end) {
            innerStartEntry.age = this.nextAge++;
            result = {
                bytes: innerStartEntry.bytes,
                view: innerStartEntry.view,
                offset: innerStartEntry.start,
            };
            // Can't return yet though, still need to check if the prefetch range might lie outside the cached area
        }
        const outerCacheStartIndex = (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .binarySearchLessOrEqual */ .eE)(this.cache, outerStart, x => x.start);
        const bytes = result ? null : new Uint8Array(innerEnd - innerStart);
        let contiguousBytesWriteEnd = 0; // Used to track if the cache is able to completely cover the bytes
        let lastEnd = outerStart;
        // The "holes" in the cache (the parts we need to load)
        const outerHoles = [];
        // Loop over the cache and build up the list of holes
        if (outerCacheStartIndex !== -1) {
            for (let i = outerCacheStartIndex; i < this.cache.length; i++) {
                const entry = this.cache[i];
                if (entry.start >= outerEnd) {
                    break;
                }
                if (entry.end <= outerStart) {
                    continue;
                }
                const cappedOuterStart = Math.max(outerStart, entry.start);
                const cappedOuterEnd = Math.min(outerEnd, entry.end);
                (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(cappedOuterStart <= cappedOuterEnd);
                if (lastEnd < cappedOuterStart) {
                    outerHoles.push({ start: lastEnd, end: cappedOuterStart });
                }
                lastEnd = cappedOuterEnd;
                if (bytes) {
                    const cappedInnerStart = Math.max(innerStart, entry.start);
                    const cappedInnerEnd = Math.min(innerEnd, entry.end);
                    if (cappedInnerStart < cappedInnerEnd) {
                        const relativeOffset = cappedInnerStart - innerStart;
                        // Fill the relevant section of the bytes with the cached data
                        bytes.set(entry.bytes.subarray(cappedInnerStart - entry.start, cappedInnerEnd - entry.start), relativeOffset);
                        if (relativeOffset === contiguousBytesWriteEnd) {
                            contiguousBytesWriteEnd = cappedInnerEnd - innerStart;
                        }
                    }
                }
                entry.age = this.nextAge++;
            }
            if (lastEnd < outerEnd) {
                outerHoles.push({ start: lastEnd, end: outerEnd });
            }
        }
        else {
            outerHoles.push({ start: outerStart, end: outerEnd });
        }
        if (bytes && contiguousBytesWriteEnd >= bytes.length) {
            // Multiple cache entries were able to completely cover the requested bytes!
            result = {
                bytes,
                view: (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .toDataView */ .Zc)(bytes),
                offset: innerStart,
            };
        }
        if (outerHoles.length === 0) {
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(result);
            return result;
        }
        // We need to read more data, so now we're in async land
        const { promise, resolve, reject } = (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .promiseWithResolvers */ .nJ)();
        const innerHoles = [];
        for (const outerHole of outerHoles) {
            const cappedStart = Math.max(innerStart, outerHole.start);
            const cappedEnd = Math.min(innerEnd, outerHole.end);
            if (cappedStart === outerHole.start && cappedEnd === outerHole.end) {
                innerHoles.push(outerHole); // Can reuse without allocating a new object
            }
            else if (cappedStart < cappedEnd) {
                innerHoles.push({ start: cappedStart, end: cappedEnd });
            }
        }
        const pendingSlice = bytes && {
            start: innerStart,
            bytes,
            holes: innerHoles,
            resolve,
            reject,
        };
        // Fire off workers to take care of patching the holes
        outer: for (const outerHole of outerHoles) {
            for (const worker of this.workers) {
                const addedToWorker = this.checkHoleAgainstWorker(worker, outerHole, pendingSlice ? [pendingSlice] : []);
                if (addedToWorker) {
                    this.checkQueuedReadsAgainstWorker(worker);
                    continue outer;
                }
            }
            // We need to spawn a new worker
            const strictTarget = outerHole.end < outerEnd || this.fileSize !== null;
            const newWorker = this.createWorker(outerHole.start, outerHole.end, strictTarget);
            if (newWorker) {
                if (pendingSlice) {
                    newWorker.pendingSlices = [pendingSlice];
                }
                this.runWorker(newWorker);
            }
            else {
                // Max worker count has been reached, let's queue a read for later
                let index = (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .binarySearchLessOrEqual */ .eE)(this.queuedReads, outerHole.start, x => x.hole.start);
                let entry = index !== -1
                    ? this.queuedReads[index]
                    : null;
                if (entry && outerHole.start <= entry.hole.end) {
                    entry.hole.end = Math.max(entry.hole.end, outerHole.end);
                    entry.strictTarget &&= strictTarget;
                    if (pendingSlice) {
                        entry.pendingSlices.push(pendingSlice);
                    }
                }
                else {
                    index++;
                    entry = {
                        hole: {
                            // Clone the hole because it might be mutated later
                            start: outerHole.start,
                            end: outerHole.end,
                        },
                        strictTarget,
                        pendingSlices: pendingSlice ? [pendingSlice] : [],
                        age: this.nextAge++,
                    };
                    this.queuedReads.splice(index, 0, entry);
                }
                // Merge with any subsequent entries that overlap
                while (index + 1 < this.queuedReads.length) {
                    const nextEntry = this.queuedReads[index + 1];
                    if (nextEntry.hole.start > entry.hole.end) {
                        break;
                    }
                    entry.hole.end = Math.max(entry.hole.end, nextEntry.hole.end);
                    entry.pendingSlices.push(...nextEntry.pendingSlices);
                    entry.strictTarget &&= nextEntry.strictTarget;
                    entry.age = Math.min(entry.age, nextEntry.age);
                    this.queuedReads.splice(index + 1, 1);
                }
            }
        }
        if (!result) {
            (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(bytes);
            result = promise.then(bytes => bytes && {
                bytes,
                view: (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .toDataView */ .Zc)(bytes),
                offset: innerStart,
            });
        }
        else {
            // The requested region was satisfied by the cache, but the entire prefetch region was not
        }
        return result;
    }
    checkHoleAgainstWorker(worker, hole, pendingSlices) {
        // A small tolerance in the case that the requested region is *just* after the target position of an
        // existing worker. In that case, it's probably more efficient to repurpose that worker than to spawn
        // another one so close to it
        const gapTolerance = 2 ** 17;
        // This check also implies worker.currentPos <= hole.start, a critical condition
        if ((0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .closedIntervalsOverlap */ .oX)(hole.start - gapTolerance, hole.start, worker.currentPos, worker.targetPos)) {
            worker.targetPos = Math.max(worker.targetPos, hole.end); // Update the worker's target position
            for (let i = 0; i < pendingSlices.length; i++) {
                const pendingSlice = pendingSlices[i];
                if (!worker.pendingSlices.includes(pendingSlice)) {
                    worker.pendingSlices.push(pendingSlice);
                }
            }
            if (!worker.running) {
                // Kick it off if it's idle
                this.runWorker(worker);
            }
            return true;
        }
        return false;
    }
    checkQueuedReadsAgainstWorker(worker) {
        let wasTrueOnce = false;
        for (let i = 0; i < this.queuedReads.length; i++) {
            const queuedRead = this.queuedReads[i];
            const result = this.checkHoleAgainstWorker(worker, queuedRead.hole, queuedRead.pendingSlices);
            if (result) {
                this.queuedReads.splice(i, 1);
                i--;
                wasTrueOnce = true;
            }
            else if (wasTrueOnce) {
                // We can stop since the holes are sorted
                break;
            }
        }
    }
    createWorker(startPos, targetPos, strictTarget) {
        if (this.workers.length >= this.options.maxWorkerCount) {
            let oldestWorker = null;
            let oldestIndex = null;
            for (let i = 0; i < this.workers.length; i++) {
                const worker = this.workers[i];
                if (!worker.running
                    && worker.pendingSlices.length === 0
                    && (!oldestWorker || worker.age < oldestWorker.age)) {
                    oldestIndex = i;
                    oldestWorker = worker;
                }
            }
            if (oldestWorker) {
                // LRU eviction
                (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(oldestIndex !== null);
                (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(oldestWorker.pendingSlices.length === 0);
                this.workers.splice(oldestIndex, 1);
            }
            else {
                return null; // All workers are still running, we can't create a new one
            }
        }
        const worker = {
            startPos,
            currentPos: startPos,
            targetPos,
            strictTarget,
            running: false,
            // Due to async shenanigans, it can happen that workers are started after disposal. In this case, instead of
            // simply not creating the worker, we allow it to run but immediately label it as aborted, so it can then
            // shut itself down.
            aborted: this.disposed,
            pendingSlices: [],
            age: this.nextAge++,
        };
        this.workers.push(worker);
        return worker;
    }
    runWorker(worker) {
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(!worker.running);
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(worker.currentPos < worker.targetPos);
        worker.running = true;
        worker.age = this.nextAge++;
        void this.options.runWorker(worker)
            .catch((error) => {
            worker.running = false;
            if (worker.pendingSlices.length > 0) {
                worker.pendingSlices.forEach(x => x.reject(error)); // Make sure to propagate any errors
                worker.pendingSlices.length = 0;
            }
            else {
                throw error; // So it doesn't get swallowed
            }
        })
            .finally(() => {
            if (worker.running) {
                // Rare, but can happen with multiple concurrent reads. In this case, don't do anything.
                return;
            }
            if (this.queuedReads.length > 0) {
                let oldestIndex = 0;
                for (let i = 1; i < this.queuedReads.length; i++) {
                    const queuedRead = this.queuedReads[i];
                    if (queuedRead.age < this.queuedReads[oldestIndex].age) {
                        oldestIndex = i;
                    }
                }
                const queuedRead = this.queuedReads[oldestIndex];
                this.queuedReads.splice(oldestIndex, 1);
                const newWorker = this.createWorker(queuedRead.hole.start, queuedRead.hole.end, queuedRead.strictTarget);
                (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(newWorker); // We just freed up a worker, so this should never fail
                newWorker.pendingSlices = queuedRead.pendingSlices;
                this.runWorker(newWorker);
            }
        });
    }
    consolidateEverythingIntoOneWorker(worker) {
        // Here we merge everything into one "megaworker" that spans the entire file. We assume the passed-in worker
        // is already configured to be a megaworker.
        const uniqueSlices = new Set(worker.pendingSlices);
        for (let i = 0; i < this.workers.length; i++) {
            const otherWorker = this.workers[i];
            if (otherWorker === worker) {
                continue;
            }
            for (const slice of otherWorker.pendingSlices) {
                uniqueSlices.add(slice);
            }
            otherWorker.aborted = true;
            otherWorker.pendingSlices.length = 0;
            this.workers.splice(i, 1);
            i--;
        }
        for (let i = 0; i < this.queuedReads.length; i++) {
            const queuedRead = this.queuedReads[i];
            for (const slice of queuedRead.pendingSlices) {
                uniqueSlices.add(slice);
            }
        }
        worker.pendingSlices = [...uniqueSlices];
        this.queuedReads.length = 0;
    }
    /** Called by a worker when it has read some data. */
    supplyWorkerData(worker, bytes) {
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(!worker.aborted);
        const start = worker.currentPos;
        const end = start + bytes.length;
        this.insertIntoCache({
            start,
            end,
            bytes,
            view: (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .toDataView */ .Zc)(bytes),
            age: this.nextAge++,
        });
        worker.currentPos += bytes.length;
        if (worker.currentPos > worker.targetPos) {
            // In case it overshoots
            worker.targetPos = worker.currentPos;
            this.checkQueuedReadsAgainstWorker(worker);
        }
        // Now, let's see if we can use the read bytes to fill any pending slice
        for (let i = 0; i < worker.pendingSlices.length; i++) {
            const pendingSlice = worker.pendingSlices[i];
            const clampedStart = Math.max(start, pendingSlice.start);
            const clampedEnd = Math.min(end, pendingSlice.start + pendingSlice.bytes.length);
            if (clampedStart < clampedEnd) {
                pendingSlice.bytes.set(bytes.subarray(clampedStart - start, clampedEnd - start), clampedStart - pendingSlice.start);
            }
            for (let j = 0; j < pendingSlice.holes.length; j++) {
                // The hole is intentionally not modified here if the read section starts somewhere in the middle of
                // the hole. We don't need to do "hole splitting", since the workers are spawned *by* the holes,
                // meaning there's always a worker which will consume the hole left to right.
                const hole = pendingSlice.holes[j];
                if (start <= hole.start && end > hole.start) {
                    hole.start = end;
                }
                if (hole.end <= hole.start) {
                    pendingSlice.holes.splice(j, 1);
                    j--;
                }
            }
            if (pendingSlice.holes.length === 0) {
                // The slice has been fulfilled, everything has been read. Let's resolve the promise
                pendingSlice.resolve(pendingSlice.bytes);
                worker.pendingSlices.splice(i, 1);
                i--;
            }
        }
        // Remove other idle workers if we "ate" into their territory
        for (let i = 0; i < this.workers.length; i++) {
            const otherWorker = this.workers[i];
            if (worker === otherWorker || otherWorker.running) {
                continue;
            }
            if ((0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .closedIntervalsOverlap */ .oX)(start, end, otherWorker.currentPos, otherWorker.targetPos)) {
                this.workers.splice(i, 1);
                i--;
            }
        }
    }
    supplyFileSize(size) {
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(this.fileSize === null);
        this.fileSize = size;
        // Trim the workers with this new information
        for (const worker of this.workers) {
            worker.targetPos = Math.min(worker.targetPos, size);
            worker.strictTarget = true;
            for (let i = 0; i < worker.pendingSlices.length; i++) {
                const pendingSlice = worker.pendingSlices[i];
                for (const hole of pendingSlice.holes) {
                    if (hole.end > size) {
                        // Can't satisfy this slice anymore
                        pendingSlice.resolve(null);
                        worker.pendingSlices.splice(i, 1);
                        i--;
                        break;
                    }
                }
            }
        }
        // Trim the queued reads as well
        for (let i = 0; i < this.queuedReads.length; i++) {
            const queuedRead = this.queuedReads[i];
            if (queuedRead.hole.start >= size) {
                // Entirely out of bounds
                for (const slice of queuedRead.pendingSlices)
                    slice.resolve(null);
                this.queuedReads.splice(i, 1);
                i--;
            }
            else if (queuedRead.hole.end > size) {
                // Partially out of bounds
                queuedRead.hole.end = size;
                queuedRead.strictTarget = true;
                for (let j = 0; j < queuedRead.pendingSlices.length; j++) {
                    const slice = queuedRead.pendingSlices[j];
                    // If the slice itself is out of bounds, resolve it
                    if (slice.start >= size) {
                        slice.resolve(null);
                        queuedRead.pendingSlices.splice(j, 1);
                        j--;
                    }
                }
            }
        }
    }
    signalWorkerStoppedRunning(worker) {
        worker.running = false;
        // When a worker stops running, that means it has hit its targetPos. It might still have pendingSlices assigned,
        // but this is because those pending slices cover data that other workers are assigned to fill. Since targetPos
        // has been reached, we can confidently say that this worker has completed its share of work on the pending
        // slices and must no longer care about them.
        worker.pendingSlices.length = 0;
    }
    /** Called when a worker reaches the end of the underlying data and must be cleaned up. */
    onWorkerFinished(worker) {
        const index = this.workers.indexOf(worker);
        (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .assert */ .vA)(index !== -1);
        worker.running = false;
        this.workers.splice(index, 1);
        if (this.fileSize === null) {
            // We can now deduce the file size!
            this.supplyFileSize(worker.currentPos);
        }
        for (const pendingSlice of worker.pendingSlices) {
            pendingSlice.resolve(null);
        }
    }
    insertIntoCache(entry) {
        if (this.options.maxCacheSize === 0) {
            return; // No caching
        }
        let insertionIndex = (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .binarySearchLessOrEqual */ .eE)(this.cache, entry.start, x => x.start) + 1;
        if (insertionIndex > 0) {
            const previous = this.cache[insertionIndex - 1];
            if (previous.end >= entry.end) {
                // Previous entry swallows the one to be inserted; we don't need to do anything
                return;
            }
            if (previous.end > entry.start) {
                // Partial overlap with the previous entry, let's join
                const joined = new Uint8Array(entry.end - previous.start);
                joined.set(previous.bytes, 0);
                joined.set(entry.bytes, entry.start - previous.start);
                this.currentCacheSize += entry.end - previous.end;
                previous.bytes = joined;
                previous.view = (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .toDataView */ .Zc)(joined);
                previous.end = entry.end;
                // Do the rest of the logic with the previous entry instead
                insertionIndex--;
                entry = previous;
            }
            else {
                this.cache.splice(insertionIndex, 0, entry);
                this.currentCacheSize += entry.bytes.length;
            }
        }
        else {
            this.cache.splice(insertionIndex, 0, entry);
            this.currentCacheSize += entry.bytes.length;
        }
        for (let i = insertionIndex + 1; i < this.cache.length; i++) {
            const next = this.cache[i];
            if (entry.end <= next.start) {
                // Even if they touch, we don't wanna merge them, no need
                break;
            }
            if (entry.end >= next.end) {
                // The inserted entry completely swallows the next entry
                this.cache.splice(i, 1);
                this.currentCacheSize -= next.bytes.length;
                i--;
                continue;
            }
            // Partial overlap, let's join
            const joined = new Uint8Array(next.end - entry.start);
            joined.set(entry.bytes, 0);
            joined.set(next.bytes, next.start - entry.start);
            this.currentCacheSize -= entry.end - next.start; // Subtract the overlap
            entry.bytes = joined;
            entry.view = (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .toDataView */ .Zc)(joined);
            entry.end = next.end;
            this.cache.splice(i, 1);
            break; // After the join case, we're done: the next entry cannot possibly overlap with the inserted one.
        }
        // LRU eviction of cache entries
        while (this.currentCacheSize > this.options.maxCacheSize) {
            let oldestIndex = 0;
            let oldestEntry = this.cache[0];
            for (let i = 1; i < this.cache.length; i++) {
                const entry = this.cache[i];
                if (entry.age < oldestEntry.age) {
                    oldestIndex = i;
                    oldestEntry = entry;
                }
            }
            if (this.currentCacheSize - oldestEntry.bytes.length <= this.options.maxCacheSize) {
                // Don't evict if it would shrink the cache below the max size
                break;
            }
            this.cache.splice(oldestIndex, 1);
            this.currentCacheSize -= oldestEntry.bytes.length;
        }
    }
    dispose() {
        for (const worker of this.workers) {
            worker.aborted = true;
        }
        this.workers.length = 0;
        this.cache.length = 0;
        this.disposed = true;
    }
}
/**
 * A dummy source from which no data can be read. Can be used in conjunction with input formats that get their data
 * from another source.
 */
class NullSource extends (/* unused pure expression or super */ null && (Source)) {
    _getFileSize() {
        return null;
    }
    _read() {
        return null;
    }
    _dispose() {
        // Do nothing
    }
}
/**
 * A source that covers a range (offset + length) of another source. Useful for reading files that are embedded within
 * larger files.
 *
 * @group Input sources
 * @public
 */
class RangedSource extends Source {
    /** @internal */
    constructor(baseSource, offset, length) {
        super();
        /** @internal */
        this._ref = null;
        if (baseSource._disposed) {
            throw new Error('Cannot create a slice of a disposed source.');
        }
        this._baseSource = baseSource;
        this._offset = offset;
        this._length = length ?? null;
    }
    /** @internal */
    _getFileSize() {
        const baseSize = this._baseSource._getFileSize();
        if (baseSize === undefined) {
            return this._length !== null
                ? this._length
                : undefined;
        }
        if (baseSize === null) {
            if (this._length !== null) {
                return this._length;
            }
            else {
                return null;
            }
        }
        return (0,_misc_js__WEBPACK_IMPORTED_MODULE_0__/* .clamp */ .qE)(baseSize - this._offset, 0, this._length ?? Infinity);
    }
    /** @internal */
    _read(start, end, minReadPosition, maxReadPosition) {
        if (this._length !== null && end > this._length) {
            return null;
        }
        const result = this._baseSource._read(this._offset + start, this._offset + end, this._offset + minReadPosition, this._offset + maxReadPosition);
        if (result instanceof Promise) {
            return result.then((result) => {
                if (!result) {
                    return null;
                }
                result.offset -= this._offset;
                return result;
            });
        }
        else {
            if (!result) {
                return null;
            }
            result.offset -= this._offset;
            return result;
        }
    }
    /** @internal */
    _dispose() {
        this._ref?.free();
    }
    ref() {
        this._ref ??= this._baseSource.ref();
        return super.ref();
    }
}


/***/ }

}]);
//# sourceMappingURL=750.bundle.js.map