import { useEffect, useState } from 'react';
import { io } from 'socket.io-client';
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, Cell } from 'recharts';

const socket = io('http://localhost:3001');

const COLORS = ['#f59e0b','#3b82f6','#10b981','#8b5cf6','#ef4444','#06b6d4'];

function ScoreBar({ value }) {
  const color = value >= 75 ? '#10b981' : value >= 50 ? '#f59e0b' : '#ef4444';
  return (
    <div style={{ background: '#1e293b', borderRadius: 4, height: 8, width: '100%' }}>
      <div style={{ width: `${value}%`, background: color, height: '100%', borderRadius: 4, transition: 'width 0.5s' }} />
    </div>
  );
}

export default function Leaderboard() {
  const [scores, setScores] = useState({});
  const [lastUpdate, setLastUpdate] = useState(null);

  useEffect(() => {
    socket.on('score-update', (data) => {
      setScores(prev => ({ ...prev, [data.submission_id]: data }));
      setLastUpdate(new Date().toLocaleTimeString());
    });
    return () => socket.off('score-update');
  }, []);

  const ranked = Object.entries(scores)
    .map(([id, s]) => ({ id, ...s, score: parseFloat(s.score || 0) }))
    .sort((a, b) => b.score - a.score);

  const chartData = ranked.slice(0, 10).map(s => ({
    name: s.id.slice(0, 8),
    score: s.score
  }));

  return (
    <div style={{ minHeight: '100vh', background: '#0f172a', color: '#e2e8f0', fontFamily: 'monospace', padding: '2rem' }}>
      <div style={{ maxWidth: 1100, margin: '0 auto' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '2rem' }}>
          <h1 style={{ fontSize: 28, fontWeight: 800, color: '#f8fafc' }}>🏆 IICPC Live Leaderboard</h1>
          <div style={{ fontSize: 12, color: '#64748b' }}>
            {lastUpdate ? `Last update: ${lastUpdate}` : 'Waiting for data...'}
            <span style={{ marginLeft: 8, display: 'inline-block', width: 8, height: 8, borderRadius: '50%',
              background: lastUpdate ? '#10b981' : '#ef4444' }} />
          </div>
        </div>

        {ranked.length === 0 ? (
          <div style={{ textAlign: 'center', padding: '4rem', color: '#475569' }}>
            <div style={{ fontSize: 48, marginBottom: '1rem' }}>⏳</div>
            <p>Waiting for submissions to be tested...</p>
          </div>
        ) : (
          <>
            <div style={{ background: '#1e293b', borderRadius: 12, padding: '1.5rem', marginBottom: '2rem' }}>
              <h2 style={{ fontSize: 14, color: '#94a3b8', marginBottom: '1rem' }}>SCORE DISTRIBUTION (TOP 10)</h2>
              <ResponsiveContainer width="100%" height={200}>
                <BarChart data={chartData}>
                  <XAxis dataKey="name" tick={{ fill: '#94a3b8', fontSize: 11 }} />
                  <YAxis domain={[0, 100]} tick={{ fill: '#94a3b8', fontSize: 11 }} />
                  <Tooltip contentStyle={{ background: '#0f172a', border: '1px solid #334155', borderRadius: 8 }} />
                  <Bar dataKey="score" radius={[4, 4, 0, 0]}>
                    {chartData.map((_, i) => <Cell key={i} fill={COLORS[i % COLORS.length]} />)}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
            </div>

            <div style={{ background: '#1e293b', borderRadius: 12, overflow: 'hidden' }}>
              <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                <thead>
                  <tr style={{ background: '#0f172a' }}>
                    {['Rank','Submission ID','Score','p50 (ms)','p99 (ms)','TPS','Correctness','Progress'].map(h => (
                      <th key={h} style={{ padding: '12px 16px', textAlign: 'left', fontSize: 11, color: '#64748b', fontWeight: 700, letterSpacing: 1 }}>{h}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {ranked.map((s, i) => (
                    <tr key={s.id} style={{ borderTop: '1px solid #0f172a', background: i === 0 ? '#1a2744' : 'transparent' }}>
                      <td style={{ padding: '12px 16px' }}>
                        {i === 0 ? '🥇' : i === 1 ? '🥈' : i === 2 ? '🥉' : `#${i + 1}`}
                      </td>
                      <td style={{ padding: '12px 16px', fontFamily: 'monospace', fontSize: 12, color: '#94a3b8' }}>
                        {s.id.slice(0, 16)}...
                      </td>
                      <td style={{ padding: '12px 16px', fontWeight: 800, fontSize: 18, color: i === 0 ? '#f59e0b' : '#e2e8f0' }}>
                        {s.score.toFixed(1)}
                      </td>
                      <td style={{ padding: '12px 16px', color: '#94a3b8' }}>{s.p50_ms || '-'}</td>
                      <td style={{ padding: '12px 16px', color: '#94a3b8' }}>{s.p99_ms || '-'}</td>
                      <td style={{ padding: '12px 16px', color: '#94a3b8' }}>{s.tps || '-'}</td>
                      <td style={{ padding: '12px 16px', color: '#94a3b8' }}>{s.correctness_pct ? `${s.correctness_pct}%` : '-'}</td>
                      <td style={{ padding: '12px 16px', width: 120 }}><ScoreBar value={s.score} /></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
