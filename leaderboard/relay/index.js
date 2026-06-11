const { Server } = require('socket.io');
const redis      = require('redis');

const io  = new Server(3001, { cors: { origin: '*' } });
const sub = redis.createClient({ url: process.env.REDIS_URL || 'redis://redis:6379' });

const latestScores = {};

async function start() {
  await sub.connect();
  await sub.subscribe('score-updates', (message) => {
    try {
      const data = JSON.parse(message);
      latestScores[data.submission_id] = data;
      io.emit('score-update', data);
      console.log(`Score update: ${data.submission_id} → ${data.score}`);
    } catch (e) {
      console.error('Parse error:', e.message);
    }
  });
  console.log('Leaderboard relay running on :3001');
}

io.on('connection', (socket) => {
  console.log('Dashboard connected:', socket.id);
  // Send all current scores to new client
  Object.values(latestScores).forEach(score => socket.emit('score-update', score));
  socket.on('disconnect', () => console.log('Dashboard disconnected:', socket.id));
});

start().catch(console.error);
