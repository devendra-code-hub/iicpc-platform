import { useEffect, useState } from 'react';
import { io } from 'socket.io-client';
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer } from 'recharts';

const socket = io('http://localhost:3001');

export default function Leaderboard() {
  const [scores, setScores] = useState({});

  useEffect(() => {
    socket.on('score-update', ({ submissionId, score, p99, tps }) => {
      setScores(prev => ({
        ...prev,
        [submissionId]: { score: parseFloat(score), p99, tps }
      }));
    });
    return () => socket.off('score-update');
  }, []);

  const ranked = Object.entries(scores)
    .sort((a, b) => b[1].score - a[1].score);

  return (
    <div style={{ padding: '2rem', fontFamily: 'monospace' }}>
      <h1>🏆 IICPC Live Leaderboard</h1>

      {/* Bar chart */}
      <ResponsiveContainer width="100%" height={300}>
        <BarChart data={ranked.map(([id, s]) => ({ id: id.slice(0, 8), score: s.score }))}>
          <XAxis dataKey="id" />
          <YAxis domain={[0, 100]} />
          <Tooltip />
          <Bar dataKey="score" fill="#3B82F6" />
        </BarChart>
      </ResponsiveContainer>

      {/* Ranked table */}
      <table style={{ width: '100%', borderCollapse: 'collapse', marginTop: '2rem' }}>
        <thead>
          <tr style={{ borderBottom: '1px solid #333' }}>
            <th>#</th><th>Submission</th><th>Score</th><th>p99 (ms)</th><th>TPS</th>
          </tr>
        </thead>
        <tbody>
          {ranked.map(([id, s], i) => (
            <tr key={id} style={{ borderBottom: '1px solid #eee', padding: '8px' }}>
              <td>{i + 1}</td>
              <td>{id.slice(0, 12)}…</td>
              <td><strong>{s.score}</strong></td>
              <td>{s.p99}</td>
              <td>{s.tps}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}