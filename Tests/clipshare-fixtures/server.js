const http = require('node:http');
const fs = require('node:fs');
const videos = new Map();
const keys = new Map();
let sequence = 0;
function answer(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(body === undefined ? undefined : JSON.stringify(body));
}
const server = http.createServer(async (req, res) => {
  if (req.headers.authorization !== 'Bearer fixture-token') return answer(res, 401, { error: 'unauthorized' });
  const url = new URL(req.url, 'http://localhost');
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const data = Buffer.concat(chunks);
  if (url.pathname === '/api/videos' && req.method === 'POST') {
    const body = JSON.parse(data);
    let item = videos.get(keys.get(body.idempotencyKey));
    if (!item) {
      const id = String(++sequence);
      const video = { id, title: body.originalFilename, ...body, status: 'uploading', shareEnabled: true,
        shareUrl: null, createdAt: '2026-09-18T12:00:00.000Z', readyAt: null };
      item = { video, partSizeBytes: 4, partCount: Math.ceil(body.sizeBytes / 4), parts: new Map(), attempts: new Map() };
      videos.set(id, item); keys.set(body.idempotencyKey, id);
      if (body.originalFilename === 'lost-create.mp4') return req.socket.destroy();
    }
    return answer(res, 201, { video: item.video, partSizeBytes: 4, partCount: item.partCount });
  }
  if (url.pathname === '/api/videos' && req.method === 'GET') {
    if (url.searchParams.get('limit') !== '20') return answer(res, 400, {});
    return answer(res, 200, { videos: [...videos.values()].map(item => item.video), nextCursor: null });
  }
  const match = url.pathname.match(/^\/api\/videos\/([^/]+)(?:\/(.*))?$/);
  const item = match && videos.get(match[1]);
  if (!item) return answer(res, 404, { error: 'not_found' });
  const suffix = match[2];
  if (!suffix && req.method === 'GET') return answer(res, 200, {
    video: item.video, partSizeBytes: 4, partCount: item.partCount, uploadedParts: [...item.parts.keys()]
  });
  if (!suffix && req.method === 'DELETE') { videos.delete(match[1]); return answer(res, 204); }
  if (suffix?.startsWith('parts/') && req.method === 'PUT') {
    const number = Number(suffix.slice(6));
    const expected = Math.min(4, item.video.sizeBytes - (number - 1) * 4);
    if (Number(req.headers['content-length']) !== expected || data.length !== expected ||
        req.headers['content-type'] !== 'application/octet-stream') return answer(res, 400, {});
    if (item.parts.has(number)) return answer(res, 400, { error: 'part_repeated' });
    item.parts.set(number, data);
    if (number === 2 && item.video.originalFilename === 'resume.mp4') return req.socket.destroy();
    return answer(res, 200, { partNumber: number, sizeBytes: data.length, etag: 'fixture' });
  }
  if (suffix === 'complete' && req.method === 'POST') {
    if (item.parts.size !== item.partCount) return answer(res, 409, { error: 'parts_missing' });
    const contents = Buffer.concat([...item.parts.entries()].sort((a,b) => a[0]-b[0]).map(([,data]) => data));
    if (contents.toString() !== 'abcdefghij') return answer(res, 422, { error: 'bad_contents' });
    item.video.status = 'ready'; item.video.shareUrl = 'https://fixture.invalid/v/' + item.video.id;
    item.video.readyAt = '2026-09-18T12:01:00.000Z';
    return answer(res, 200, { video: item.video, shareUrl: item.video.shareUrl });
  }
  if (suffix === 'revoke' && req.method === 'POST') {
    item.video.shareUrl += '-new';
    return answer(res, 200, { video: item.video, shareUrl: item.video.shareUrl });
  }
  answer(res, 404, {});
});
server.listen(0, '127.0.0.1', () => fs.writeFileSync(process.argv[2], String(server.address().port)));
