// Dev server for the web prototype: serves this folder.
//
//   node web/server.js            -> http://localhost:5173
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

const DIR = __dirname;
const PORT = process.env.PORT || 5173;
const TYPES = { '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.js': 'text/javascript' };

function send(res, status, type, body) {
  res.writeHead(status, { 'Content-Type': type, 'Cache-Control': 'no-store' });
  res.end(body);
}

http
  .createServer((req, res) => {
    const urlPath = req.url.split('?')[0];
    const file = path.join(DIR, urlPath === '/' ? 'index.html' : path.normalize(urlPath));
    const type = TYPES[path.extname(file)];
    if (!type || !file.startsWith(DIR + path.sep)) return send(res, 404, 'text/plain', 'Not found');
    fs.readFile(file, (err, data) =>
      err ? send(res, 404, 'text/plain', 'Not found') : send(res, 200, type, data)
    );
  })
  .listen(PORT, () => console.log(`http://localhost:${PORT}`));
