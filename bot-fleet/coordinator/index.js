const { Kafka } = require('kafkajs');
const { v4: uuidv4 } = require('uuid');

const kafka = new Kafka({
  clientId: 'bot-coordinator',
  brokers: [process.env.KAFKA_BROKER || 'redpanda:9092'],
  retry: { retries: 10, initialRetryTime: 3000 }
});

const producer = kafka.producer();
const consumer = kafka.consumer({ groupId: 'coordinator-group' });

async function dispatchBotFleet({ targetURL, botCount, submissionId, ordersPerBot = 500 }) {
  await producer.connect();
  const tasks = [];
  for (let i = 0; i < botCount; i++) {
    tasks.push(producer.send({
      topic: 'bot-tasks',
      messages: [{
        key: `bot-${i}`,
        value: JSON.stringify({ botId: i, targetURL, submissionId, ordersPerBot })
      }]
    }));
  }
  await Promise.all(tasks);
  console.log(`Dispatched ${botCount} bot tasks for submission ${submissionId}`);
  await producer.disconnect();
}

async function start() {
  console.log('Bot coordinator starting...');
  try {
    await consumer.connect();
    await consumer.subscribe({ topic: 'run-fleet', fromBeginning: false });
    await consumer.run({
      eachMessage: async ({ message }) => {
        const job = JSON.parse(message.value.toString());
        console.log('Received fleet job:', job);
        await dispatchBotFleet(job);
      }
    });
    console.log('Bot coordinator listening for fleet jobs...');
  } catch (err) {
    console.error('Coordinator error:', err.message);
    setTimeout(start, 5000);
  }
}

start();
module.exports = { dispatchBotFleet };
