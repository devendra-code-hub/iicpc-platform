const express = require('express');
const multer  = require('multer');
const Docker  = require('dockerode');
const { v4: uuidv4 } = require('uuid');
const path = require('path');
const fs   = require('fs');

const app    = express();
const docker = new Docker({ socketPath: '/var/run/docker.sock' });
const upload = multer({ dest: '/tmp/uploads/' });
app.use(express.json());

const submissions = {};

app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'sandbox-api', total: Object.keys(submissions).length });
});

app.post('/submit', upload.single('code'), async (req, res) => {
  const submissionId = uuidv4();
  const language = req.body.language || 'cpp';
  if (!req.file) return res.status(400).json({ error: 'No file uploaded' });
  submissions[submissionId] = { status: 'received', language, createdAt: new Date() };
  console.log(`[${submissionId}] Received ${language} submission`);
  res.json({ submissionId, status: 'received', message: 'Queued for build' });
});

app.get('/submission/:id', (req, res) => {
  const sub = submissions[req.params.id];
  if (!sub) return res.status(404).json({ error: 'Not found' });
  res.json({ submissionId: req.params.id, ...sub });
});

app.get('/submissions', (req, res) => {
  res.json(Object.entries(submissions).map(([id, s]) => ({ id, ...s })));
});

app.delete('/submission/:id', async (req, res) => {
  const sub = submissions[req.params.id];
  if (!sub) return res.status(404).json({ error: 'Not found' });
  if (sub.containerId) {
    try {
      const c = docker.getContainer(sub.containerId);
      await c.stop();
      await c.remove();
    } catch (e) { console.error('Cleanup error:', e.message); }
  }
  delete submissions[req.params.id];
  res.json({ deleted: req.params.id });
});

app.listen(4000, () => console.log('Sandbox API running on :4000'));
