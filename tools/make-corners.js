// Writes the four corner pictures of the rounded boxes (Skin.lua) as 32 bit TGA files: fill4, ring4, fill8 and ring8.
// Each picture is the top-left corner of a box drawn at twice the size it is shown at (the other three corners are the same
// picture flipped by texture coordinates): a quarter disc for a fill, a quarter ring one shown pixel thick for an edge.
// White with an alpha channel, because the addon tints them. Usage: node make-corners.js <Media folder>
const fs = require('fs');
const path = require('path');

const out = process.argv[2];
if (!out) {
  console.error('usage: node make-corners.js <Media folder>');
  process.exit(2);
}
const SAMPLES = 8;

// How much of the pixel (x, y) lies inside the disc of radius `size` centred on the picture's bottom-right corner and, when
// `thickness` is given, outside the disc that much smaller.
function coverage(size, thickness, x, y) {
  let hit = 0;
  for (let i = 0; i < SAMPLES; i++) {
    for (let j = 0; j < SAMPLES; j++) {
      const px = x + (i + 0.5) / SAMPLES;
      const py = y + (j + 0.5) / SAMPLES;
      const d = Math.hypot(size - px, size - py);
      if (d <= size && (thickness === undefined || d >= size - thickness)) hit++;
    }
  }
  return hit / (SAMPLES * SAMPLES);
}

function tga(size, thickness) {
  const header = Buffer.alloc(18);
  header[2] = 2;                          // uncompressed true colour
  header.writeUInt16LE(size, 12);
  header.writeUInt16LE(size, 14);
  header[16] = 32;                        // bits per pixel
  header[17] = 8;                         // eight alpha bits, rows stored bottom to top
  const pixels = Buffer.alloc(size * size * 4);
  for (let row = 0; row < size; row++) {
    const y = size - 1 - row;
    for (let x = 0; x < size; x++) {
      const o = (row * size + x) * 4;
      pixels[o] = 255;
      pixels[o + 1] = 255;
      pixels[o + 2] = 255;
      pixels[o + 3] = Math.round(255 * coverage(size, thickness, x, y));
    }
  }
  return Buffer.concat([header, pixels]);
}

fs.mkdirSync(out, { recursive: true });
for (const radius of [4, 8]) {
  const size = radius * 2;
  fs.writeFileSync(path.join(out, 'fill' + radius + '.tga'), tga(size));
  fs.writeFileSync(path.join(out, 'ring' + radius + '.tga'), tga(size, size / radius));
}
console.log('wrote fill4, ring4, fill8 and ring8 to ' + out);
