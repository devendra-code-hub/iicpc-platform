const { Server } = require('socket.io');
const io = new Server(3001, { cors: { origin: '*' } });
io.on('connection', socket => console.log('Client connected:', socket.id));
console.log('Leaderboard relay running on :3001');
