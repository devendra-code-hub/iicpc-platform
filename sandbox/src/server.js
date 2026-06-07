const express = require('express');
const app = express();
app.use(express.json());
app.get('/health', (req, res) => res.json({ status: 'ok', service: 'sandbox-api' }));
app.listen(4000, () => console.log('Sandbox API running on :4000'));
