const grpc       = require('@grpc/grpc-js');
const protoLoader = require('@grpc/proto-loader');
const { Pool }   = require('pg');
const redis      = require('redis');
const path       = require('path');
const { computeScore } = require('./scorer');

const PROTO_PATH = path.join(__dirname, '../proto/metrics.proto');
const pkgDef = protoLoader.loadSync(PROTO_PATH, { keepCase: true, longs: String, enums: String, defaults: true, oneofs: true });
const proto  = grpc.loadPackageDefinition(pkgDef).metrics;

const db = new Pool({ connectionString: process.env.DB_URL || 'postgresql://iicpc:iicpc_secret@timescaledb:5432/telemetry' });
const redisClient = redis.createClient({ url: process.env.REDIS_URL || 'redis://redis:6379' });

async function init() {
  await redisClient.connect();
  console.log('Connected to Redis');
}

async function RecordEvent(call, callback) {
  const e = call.request;
  try {
    await db.query(
      `INSERT INTO order_events (submission_id, bot_id, order_id, latency_ms, status_code, order_type, side, price, quantity, accepted)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
      [e.submission_id, e.bot_id, e.order_id, e.latency_ms, e.status_code, e.order_type, e.side, e.price, e.quantity, e.accepted]
    );

    // Update Redis live stats
    await updateLiveStats(e.submission_id);
    callback(null, { success: true, message: 'recorded' });
  } catch (err) {
    console.error('RecordEvent error:', err.message);
    callback(null, { success: false, message: err.message });
  }
}

async function updateLiveStats(submissionId) {
  const res = await db.query('SELECT * FROM latency_stats WHERE submission_id = $1', [submissionId]);
  if (res.rows.length === 0) return;
  const stats = res.rows[0];
  const score = computeScore({
    p99: parseFloat(stats.p99_ms),
    tps: parseFloat(stats.tps),
    correctnessRate: parseFloat(stats.correctness_pct) / 100
  });
  const payload = JSON.stringify({ ...stats, score });
  await redisClient.publish('score-updates', payload);
}

async function GetStats(call, callback) {
  const res = await db.query('SELECT * FROM latency_stats WHERE submission_id = $1', [call.request.submission_id]);
  if (res.rows.length === 0) return callback(null, {});
  const s = res.rows[0];
  const score = computeScore({ p99: parseFloat(s.p99_ms), tps: parseFloat(s.tps), correctnessRate: parseFloat(s.correctness_pct) / 100 });
  callback(null, { ...s, score, total_orders: parseInt(s.total_orders) });
}

function StreamStats(call) {
  const subId = call.request.submission_id;
  const interval = setInterval(async () => {
    try {
      const res = await db.query('SELECT * FROM latency_stats WHERE submission_id = $1', [subId]);
      if (res.rows.length > 0) {
        const s = res.rows[0];
        const score = computeScore({ p99: parseFloat(s.p99_ms), tps: parseFloat(s.tps), correctnessRate: parseFloat(s.correctness_pct) / 100 });
        call.write({ ...s, score, total_orders: parseInt(s.total_orders) });
      }
    } catch (e) { call.end(); }
  }, 1000);
  call.on('cancelled', () => clearInterval(interval));
}

init().then(() => {
  const server = new grpc.Server();
  server.addService(proto.MetricsIngester.service, { RecordEvent, GetStats, StreamStats });
  server.bindAsync('0.0.0.0:50051', grpc.ServerCredentials.createInsecure(), () => {
    console.log('Telemetry gRPC server on :50051');
  });
}).catch(console.error);
