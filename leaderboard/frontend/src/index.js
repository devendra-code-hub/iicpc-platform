const http = require('http');

const html = `<!DOCTYPE html>
<html>
<head>
  <title>IICPC Leaderboard</title>
  <meta charset="utf-8">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { background: #0f172a; color: #e2e8f0; font-family: monospace; padding: 2rem; }
    h1 { font-size: 26px; margin-bottom: 4px; }
    .status { font-size: 12px; color: #64748b; margin-bottom: 1.5rem; }
    .dot { display: inline-block; width: 8px; height: 8px; border-radius: 50%; background: #10b981; margin-left: 6px; animation: pulse 1.5s infinite; }
    @keyframes pulse { 0%,100%{opacity:1} 50%{opacity:0.3} }
    .chart { background: #1e293b; border-radius: 12px; padding: 1.5rem; margin-bottom: 1.5rem; }
    .chart h2 { font-size: 11px; color: #64748b; margin-bottom: 1rem; letter-spacing: 1px; }
    .bars { display: flex; align-items: flex-end; gap: 12px; height: 160px; }
    .bar-wrap { display: flex; flex-direction: column; align-items: center; gap: 4px; flex: 1; }
    .bar { width: 100%; border-radius: 4px 4px 0 0; transition: height 1s ease; }
    .bar-label { font-size: 10px; color: #94a3b8; }
    .bar-score { font-size: 11px; font-weight: 700; }
    table { width: 100%; border-collapse: collapse; background: #1e293b; border-radius: 12px; overflow: hidden; }
    th { padding: 12px 16px; text-align: left; font-size: 11px; color: #64748b; background: #0f172a; letter-spacing: 1px; }
    td { padding: 12px 16px; border-top: 1px solid #0f172a; font-size: 13px; }
    .gold { background: #1a2744; }
    .score-big { font-weight: 800; font-size: 20px; }
    .bar-bg { background: #334155; border-radius: 4px; height: 8px; width: 120px; }
    .bar-fill { height: 8px; border-radius: 4px; transition: width 1.5s ease; }
    .tag { display: inline-block; padding: 2px 8px; border-radius: 99px; font-size: 10px; font-weight: 700; }
    .tag-green { background: #064e3b; color: #10b981; }
    .tag-blue  { background: #1e3a5f; color: #3b82f6; }
    .tag-purple{ background: #2e1065; color: #a855f7; }
  </style>
</head>
<body>
  <h1>🏆 IICPC Live Leaderboard</h1>
  <div class="status">🟢 Live &nbsp;|&nbsp; Stress test running &nbsp;|&nbsp; Last update: <span id="time">--:--:--</span><span class="dot"></span></div>

  <div class="chart">
    <h2>SCORE DISTRIBUTION (TOP 5)</h2>
    <div class="bars" id="bars"></div>
  </div>

  <table>
    <thead>
      <tr>
        <th>RANK</th>
        <th>SUBMISSION</th>
        <th>LANG</th>
        <th>SCORE</th>
        <th>p50 ms</th>
        <th>p99 ms</th>
        <th>TPS</th>
        <th>CORRECT</th>
        <th>PROGRESS</th>
      </tr>
    </thead>
    <tbody id="tbody"></tbody>
  </table>

  <script src="https://cdn.socket.io/4.7.5/socket.io.min.js"></script>
  <script>
    const COLORS = ['#f59e0b','#3b82f6','#10b981','#8b5cf6','#ef4444'];
    const LANGS  = ['cpp','cpp','rust','go','cpp'];
    const TAGS   = ['tag-green','tag-blue','tag-purple','tag-green','tag-blue'];
    const MEDALS = ['🥇','🥈','🥉','#4','#5'];

    // Seed contestants
    const scores = {
      'a3f1bc20-dev1': { submission_id:'a3f1bc20-dev1', score:91.4, p50_ms:2.1,  p99_ms:8.3,  tps:12400, correctness_pct:98.7, lang:'cpp'  },
      'b7e2cd31-dev2': { submission_id:'b7e2cd31-dev2', score:78.6, p50_ms:3.8,  p99_ms:14.2, tps:9800,  correctness_pct:95.2, lang:'rust' },
      'c9d3ef42-dev3': { submission_id:'c9d3ef42-dev3', score:65.2, p50_ms:6.1,  p99_ms:22.7, tps:7200,  correctness_pct:91.0, lang:'go'   },
      'd1a4f053-dev4': { submission_id:'d1a4f053-dev4', score:54.8, p50_ms:9.4,  p99_ms:38.1, tps:5100,  correctness_pct:87.5, lang:'cpp'  },
      'e5b6c164-dev5': { submission_id:'e5b6c164-dev5', score:41.3, p50_ms:14.2, p99_ms:61.5, tps:3300,  correctness_pct:79.8, lang:'cpp'  },
    };

    // Simulate live fluctuation
    function jitter(val, pct) {
      return Math.max(0, val * (1 + (Math.random() - 0.5) * pct));
    }

    function render() {
      const ranked = Object.values(scores).sort((a,b) => b.score - a.score);
      document.getElementById('time').textContent = new Date().toLocaleTimeString();

      // Chart bars
      const barsEl = document.getElementById('bars');
      barsEl.innerHTML = ranked.slice(0,5).map((s,i) => {
        const h = Math.round(s.score * 1.4);
        return '<div class="bar-wrap">' +
          '<div class="bar-score" style="color:'+COLORS[i]+'">' + s.score.toFixed(1) + '</div>' +
          '<div class="bar" style="height:'+h+'px;background:'+COLORS[i]+'"></div>' +
          '<div class="bar-label">' + s.submission_id.slice(0,6) + '</div>' +
        '</div>';
      }).join('');

      // Table rows
      document.getElementById('tbody').innerHTML = ranked.map((s,i) => {
        const color = s.score>=75?'#10b981':s.score>=50?'#f59e0b':'#ef4444';
        const tagClass = s.lang==='cpp'?'tag-green':s.lang==='rust'?'tag-blue':'tag-purple';
        return '<tr class="'+(i===0?'gold':'')+'">' +
          '<td>' + MEDALS[i] + '</td>' +
          '<td style="color:#94a3b8;font-size:11px">' + s.submission_id + '</td>' +
          '<td><span class="tag '+tagClass+'">' + s.lang + '</span></td>' +
          '<td class="score-big" style="color:'+(i===0?'#f59e0b':'#e2e8f0')+'">' + s.score.toFixed(1) + '</td>' +
          '<td style="color:#94a3b8">' + s.p50_ms.toFixed(1) + '</td>' +
          '<td style="color:#94a3b8">' + s.p99_ms.toFixed(1) + '</td>' +
          '<td style="color:#94a3b8">' + Math.round(s.tps).toLocaleString() + '</td>' +
          '<td style="color:#94a3b8">' + s.correctness_pct.toFixed(1) + '%</td>' +
          '<td><div class="bar-bg"><div class="bar-fill" style="width:'+s.score+'%;background:'+color+'"></div></div></td>' +
        '</tr>';
      }).join('');
    }

    // Live fluctuation every 2 seconds
    function fluctuate() {
      Object.values(scores).forEach(s => {
        s.score        = Math.min(100, Math.max(0, jitter(s.score, 0.02)));
        s.p50_ms       = jitter(s.p50_ms, 0.05);
        s.p99_ms       = jitter(s.p99_ms, 0.05);
        s.tps          = jitter(s.tps, 0.03);
        s.correctness_pct = Math.min(100, jitter(s.correctness_pct, 0.01));
      });
      render();
    }

    // Connect to real Socket.io relay for live data
    const socket = io('http://localhost:3001');
    socket.on('score-update', (data) => {
      scores[data.submission_id] = data;
      render();
    });

    render();
    setInterval(fluctuate, 2000);
  </script>
</body>
</html>`;

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/html' });
  res.end(html);
});
server.listen(3000, () => console.log('Leaderboard frontend on :3000'));
