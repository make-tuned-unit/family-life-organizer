'use strict';

const fs = require('fs');

// Pulls <title>, <meta name="description">, and the first <h1> out of a
// hand-written HTML page so the build can check uniqueness against
// generated pages without maintaining that copy twice in the manifest.
function extractHeadMeta(html) {
  const titleMatch = html.match(/<title>([^<]*)<\/title>/i);
  const descMatch = html.match(
    /<meta\s+name=["']description["']\s+content=["']([^"']*)["'][^>]*>/i
  );
  const h1Match = html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i);
  const stripTags = (s) => (s || '').replace(/<[^>]*>/g, '').replace(/\s+/g, ' ').trim();
  return {
    title: stripTags(titleMatch ? titleMatch[1] : ''),
    description: stripTags(descMatch ? descMatch[1] : ''),
    h1: stripTags(h1Match ? h1Match[1] : ''),
  };
}

function readHeadMeta(absFilePath) {
  const html = fs.readFileSync(absFilePath, 'utf8');
  return extractHeadMeta(html);
}

module.exports = { extractHeadMeta, readHeadMeta };
