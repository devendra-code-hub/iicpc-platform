const http = require('http');
const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/html' });
  res.end('<h1>IICPC Leaderboard</h1><p>Frontend running!</p>');
});
server.listen(3000, () => console.log('Leaderboard frontend on :3000'));
