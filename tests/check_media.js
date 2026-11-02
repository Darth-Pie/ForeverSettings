// Checks the corner pictures Skin.lua names (fill4, ring4, fill8, ring8 in the addon's Media folder): each must be a 32 bit
// uncompressed TGA of the right size, white, with the shape the rounded boxes expect (the top-left corner of a box, the circle
// centred on the picture's bottom-right corner). Prints what is wrong and exits 1, or exits 0.
// Usage: node check_media.js <Media folder>
const fs = require('fs');
const path = require('path');

const dir = process.argv[2];
if (!dir) {
  console.error('usage: node check_media.js <Media folder>');
  process.exit(2);
}
const problems = [];

for (const radius of [4, 8]) {
  const size = radius * 2;
  for (const kind of ['fill', 'ring']) {
    const name = kind + radius + '.tga';
    let buf;
    try {
      buf = fs.readFileSync(path.join(dir, name));
    } catch (e) {
      problems.push(name + ' is missing');
      continue;
    }
    if (buf.length !== 18 + size * size * 4 || buf[2] !== 2 || buf[16] !== 32 || buf.readUInt16LE(12) !== size || buf.readUInt16LE(14) !== size) {
      problems.push(name + ' is not an uncompressed 32 bit ' + size + 'x' + size + ' TGA');
      continue;
    }
    // Rows are stored bottom to top: alpha(x, y) with y counted from the top.
    const alpha = (x, y) => buf[18 + ((size - 1 - y) * size + x) * 4 + 3];
    let white = true;
    for (let i = 18; i < buf.length; i += 4) {
      if (buf[i] !== 255 || buf[i + 1] !== 255 || buf[i + 2] !== 255) white = false;
    }
    if (!white) problems.push(name + ' is not white (the addon tints it)');
    const last = size - 1;
    if (alpha(0, 0) !== 0) problems.push(name + ': the outer corner should be clear');
    if (kind === 'fill') {
      if (alpha(last, last) < 250) problems.push(name + ': the inside of the disc should be solid');
      if (alpha(last, 0) < 200 || alpha(0, last) < 200) problems.push(name + ': the straight sides should meet the strips');
    } else {
      if (alpha(last, last) !== 0) problems.push(name + ': the inside of the ring should be clear');
      if (alpha(last, 0) < 200 || alpha(0, last) < 200) problems.push(name + ': the ring should meet the straight edges');
    }
  }
}
for (const problem of problems) console.log('MEDIA FAIL: ' + problem);
process.exit(problems.length === 0 ? 0 : 1);
