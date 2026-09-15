'use strict';

const fs = require('fs');

// Reads just enough of a PNG file to pull width/height out of the IHDR chunk,
// per the PNG spec: 8-byte signature, then a 4-byte length + 4-byte type
// ("IHDR") + width (4 bytes BE) + height (4 bytes BE).
function readPngSize(absPath) {
  const fd = fs.openSync(absPath, 'r');
  try {
    const buf = Buffer.alloc(24);
    fs.readSync(fd, buf, 0, 24, 0);
    const sig = buf.subarray(0, 8).toString('hex');
    if (sig !== '89504e470d0a1a0a') {
      throw new Error(`not a PNG file: ${absPath}`);
    }
    const type = buf.subarray(12, 16).toString('ascii');
    if (type !== 'IHDR') {
      throw new Error(`PNG missing IHDR as first chunk: ${absPath}`);
    }
    const width = buf.readUInt32BE(16);
    const height = buf.readUInt32BE(20);
    return { width, height };
  } finally {
    fs.closeSync(fd);
  }
}

module.exports = { readPngSize };
