const http = require('http');

const html = `<!DOCTYPE html>
<html>
<head>
  <title>IICPC Leaderboard</title>
  <meta charset="utf-8">
  <style>
    body { margin: 0; background: #0f172a; color: #e2e8f0; font-family: monospace; }
    .container { max-width: 1100px; margin: 0 auto; padding: 2rem; }
    h1 { font-size: 28px; }
    .waiting { text-align: center; padding: 4rem; color: #475569; }
    table { width: 100%; border-collapse: collapse; background: #1e293b; border-radius: 12px; overflow: hidden; }
    th { padding: 12px 16px; text-align: left; font-size: 11px; color: #64748b; background: #0f172a; }
    td { padding: 12px 16px; border-top: 1px solid #0f172a; }
    .score { font-weight: 800; font-size: 18px; }
    .bar-bg { background: #334155; border-radius: 4px; height: 8px; }
    .bar-fill { height: 8px; border-radius: 4px; transition: width 0.5s; }
  </style>
</head>
<body>
  <div class="container">
    <h1>🏆 IICPC Live Leaderboard</h1>
    <div id="status" style="color:#64748b;font-size:12px;margin-bottom:1rem">Connecting...</div>
    <div id="content" class="waiting"><div style="font-size:48px">⏳</div><p>Waiting for submissions...</p></div>
  </div>
  <script src="https://cdn.socket.io/4.7.5/socket.io.min.js"></script>
  <script>
    const socket = io('http://localhost:3001');
    const scores = {};

    socket.on('connect', () => document.getElementById('status').textContent = '🟢 Connected');
    socket.on('disconnect', () => document.getElementById('status').textContent = '🔴 Disconnected');

    socket.on('score-update', (data) => {
      scores[data.submission_id] = data;
      render();
    });

    function render() {
      const ranked = Object.values(scores).sort((a,b) => b.score - a.score);
      const medals = ['🥇','🥈','🥉'];
      const rows = ranked.map((s,i) => {
        const color = s.score >= 75 ? '#10b981' : s.score >= 50 ? '#f59e0b' : '#ef4444';
        return '<tr>' +
          '<td>' + (medals[i] || '#'+(i+1)) + '</td>' +
          '<td style="font-size:12px;color:#94a3b8">' + s.submission_id.slice(0,16) + '...</td>' +
          '<td class="score" style="color:' + (i===0?'#f59e0b':'#e2e8f0') + '">' + parseFloat(s.score).toFixed(1) + '</td>' +
          '<td style="color:#94a3b8">' + (s.p50_ms||'-') + '</td>' +
          '<td style="color:#94a3b8">' + (s.p99_ms||'-') + '</td>' +
          '<td style="color:#94a3b8">' + (s.tps||'-') + '</td>' +
          '<td style="color:#94a3b8">' + (s.correctness_pct ? s.correctness_pct+'%' : '-') + '</td>' +
          '<td><div class="bar-bg"><div class="bar-fill" style="width:'+s.score+'%;background:'+color+'"></div></div></td>' +
          '</tr>';
      }).join('');
      document.getElementById('content').innerHTML =
        '<table><thead><tr><th>Rank</th><th>Submission</th><th>Score</th><th>p50ms</th><th>p99ms</th><th>TPS</th><th>Correct</th><th>Progress</th></tr></thead><tbody>' + rows + '</tbody></table>';
    }
  </script>
</body>
</html>`;

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/html' });
  res.end(html);
});
server.listen(3000, () => console.log('Leaderboard frontend on :3000'));
