// Writes the minimap button's picture (UI.lua): the gauge of the Wago thumbnail drawn for a 20 pixel button, as a round 64 by 64
// 32 bit TGA. A dark blue to purple disc, an arc in the four profile colours (Original, Everyday, Crowded, Maximum), a needle on
// Everyday and a hub; no "fps" text and a thicker arc than the thumbnail's, so it still reads that small. Each pixel is the
// average of 8 by 8 samples. Usage: node make-icon.js <Media folder> [preview.png]
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const [out, preview] = process.argv.slice(2);
if (!out) {
  console.error('usage: node make-icon.js <Media folder> [preview.png]');
  process.exit(2);
}
const SIZE = 64;
const SAMPLES = 8;
const hex = (h) => [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)];
const FROM = [14, 20, 48];
const TO = [62, 32, 98];
const PROFILES = ['b4b2a9', '5dcaa5', 'ef9f27', 'f0997b'].map(hex);
const NEEDLE = hex('eef0f6');
const HUB = hex('9a9cff');

// The shape, in units of the picture's width (0 to 1, y down). Angles are in degrees, clockwise from pointing right.
const DISC = 0.49;
const CX = 0.5;
const CY = 0.56;
const ARC_IN = 0.27;
const ARC_OUT = 0.43;
const ARC_START = 150;                 // the arc runs 240 degrees, over the top, in four parts of 60
const GAP = 3.5;                       // half the gap between two parts
const NEEDLE_ANGLE = 255;              // on Everyday
const NEEDLE_LENGTH = 0.30;
const NEEDLE_HALF = 0.04;
const HUB_OUT = 0.085;
const HUB_IN = 0.042;

const tipX = CX + NEEDLE_LENGTH * Math.cos((NEEDLE_ANGLE * Math.PI) / 180);
const tipY = CY + NEEDLE_LENGTH * Math.sin((NEEDLE_ANGLE * Math.PI) / 180);

// The distance from (px, py) to the segment from the centre to the needle's tip.
function toNeedle(px, py) {
  const dx = tipX - CX;
  const dy = tipY - CY;
  const t = Math.max(0, Math.min(1, ((px - CX) * dx + (py - CY) * dy) / (dx * dx + dy * dy)));
  return Math.hypot(px - (CX + t * dx), py - (CY + t * dy));
}

// The colour at one sample point, or null outside the disc.
function colourAt(px, py) {
  if (Math.hypot(px - 0.5, py - 0.5) > DISC) return null;
  const r = Math.hypot(px - CX, py - CY);
  if (r <= HUB_IN) return HUB;
  if (r <= HUB_OUT) return NEEDLE;
  if (toNeedle(px, py) <= NEEDLE_HALF) return NEEDLE;
  if (r >= ARC_IN && r <= ARC_OUT) {
    let a = (Math.atan2(py - CY, px - CX) * 180) / Math.PI;
    if (a < 0) a += 360;
    if (a < ARC_START) a += 360;
    const along = a - ARC_START;
    if (along <= 240) {
      const part = Math.min(3, Math.floor(along / 60));
      const inPart = along - part * 60;
      if ((part === 0 || inPart >= GAP) && (part === 3 || inPart <= 60 - GAP)) return PROFILES[part];
    }
  }
  const t = Math.max(0, Math.min(1, (px + py) / 2));
  return FROM.map((c, i) => c + (TO[i] - c) * t);
}

// RGBA rows, top to bottom.
const rgba = Buffer.alloc(SIZE * SIZE * 4);
for (let y = 0; y < SIZE; y++) {
  for (let x = 0; x < SIZE; x++) {
    const sum = [0, 0, 0];
    let inside = 0;
    for (let i = 0; i < SAMPLES; i++) {
      for (let j = 0; j < SAMPLES; j++) {
        const c = colourAt((x + (i + 0.5) / SAMPLES) / SIZE, (y + (j + 0.5) / SAMPLES) / SIZE);
        if (!c) continue;
        inside++;
        for (let k = 0; k < 3; k++) sum[k] += c[k];
      }
    }
    const o = (y * SIZE + x) * 4;
    for (let k = 0; k < 3; k++) rgba[o + k] = inside ? Math.round(sum[k] / inside) : 0;
    rgba[o + 3] = Math.round((255 * inside) / (SAMPLES * SAMPLES));
  }
}

// The TGA: uncompressed true colour, 32 bits, eight alpha bits, rows bottom to top, pixels as blue, green, red, alpha.
const header = Buffer.alloc(18);
header[2] = 2;
header.writeUInt16LE(SIZE, 12);
header.writeUInt16LE(SIZE, 14);
header[16] = 32;
header[17] = 8;
const pixels = Buffer.alloc(SIZE * SIZE * 4);
for (let row = 0; row < SIZE; row++) {
  const y = SIZE - 1 - row;
  for (let x = 0; x < SIZE; x++) {
    const s = (y * SIZE + x) * 4;
    const d = (row * SIZE + x) * 4;
    pixels[d] = rgba[s + 2];
    pixels[d + 1] = rgba[s + 1];
    pixels[d + 2] = rgba[s];
    pixels[d + 3] = rgba[s + 3];
  }
}
fs.mkdirSync(out, { recursive: true });
fs.writeFileSync(path.join(out, 'icon.tga'), Buffer.concat([header, pixels]));
console.log('wrote ' + path.join(out, 'icon.tga'));

// An optional PNG of the same picture, to look at.
if (preview) {
  const table = [];
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  const crc = (buf) => {
    let c = 0xffffffff;
    for (const b of buf) c = table[(c ^ b) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  };
  const chunk = (type, data) => {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
    const sum = Buffer.alloc(4);
    sum.writeUInt32BE(crc(body));
    return Buffer.concat([len, body, sum]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(SIZE, 0);
  ihdr.writeUInt32BE(SIZE, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  const raw = Buffer.alloc(SIZE * (SIZE * 4 + 1));
  for (let y = 0; y < SIZE; y++) rgba.copy(raw, y * (SIZE * 4 + 1) + 1, y * SIZE * 4, (y + 1) * SIZE * 4);
  const png = Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
  fs.writeFileSync(preview, png);
  console.log('wrote ' + preview);
}
