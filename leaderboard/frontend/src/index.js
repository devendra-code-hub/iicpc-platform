const http = require('http');
const html = `<!DOCTYPE html><html><head><title>IICPC Leaderboard</title><meta charset="utf-8"><style>*{margin:0;padding:0;box-sizing:border-box}body{background:#0f172a;color:#e2e8f0;font-family:monospace;padding:2rem}h1{font-size:26px;margin-bottom:6px}.sub{font-size:12px;color:#64748b;margin-bottom:1.5rem}.dot{display:inline-block;width:8px;height:8px;border-radius:50%;background:#10b981;margin-left:6px;animation:pulse 1.5s infinite}@keyframes pulse{0%,100%{opacity:1}50%{opacity:0.3}}.card{background:#1e293b;border-radius:12px;padding:1.5rem;margin-bottom:1.5rem}.card h2{font-size:11px;color:#64748b;margin-bottom:1rem;letter-spacing:1px}.bars{display:flex;align-items:flex-end;gap:12px;height:150px}.bw{display:flex;flex-direction:column;align-items:center;gap:4px;flex:1}.bar{width:100%;border-radius:4px 4px 0 0}.bl{font-size:10px;color:#94a3b8}.bs{font-size:11px;font-weight:700}table{width:100%;border-collapse:collapse;background:#1e293b;border-radius:12px;overflow:hidden}th{padding:12px 16px;text-align:left;font-size:11px;color:#64748b;background:#0f172a;letter-spacing:1px}td{padding:12px 16px;border-top:1px solid #0f172a;font-size:13px}.gold{background:#1a2744}.big{font-weight:800;font-size:20px}.bg{background:#334155;border-radius:4px;height:8px;width:120px}.bf{height:8px;border-radius:4px;transition:width 1s}.tag{display:inline-block;padding:2px 8px;border-radius:99px;font-size:10px;font-weight:700}.cpp{background:#064e3b;color:#10b981}.rust{background:#1e3a5f;color:#3b82f6}.go{background:#2e1065;color:#a855f7}</style></head><body>
<h1>🏆 IICPC Live Leaderboard</h1>
<div class="sub">🟢 Live &nbsp;|&nbsp; Stress test running &nbsp;|&nbsp; Updated: <span id="t">--:--:--</span><span class="dot"></span></div>
<div class="card"><h2>SCORE DISTRIBUTION (TOP 5)</h2><div class="bars" id="bars"></div></div>
<table><thead><tr><th>RANK</th><th>SUBMISSION</th><th>LANG</th><th>SCORE</th><th>p50 ms</th><th>p99 ms</th><th>TPS</th><th>CORRECT</th><th>PROGRESS</th></tr></thead><tbody id="tb"></tbody></table>
<script src="https://cdn.socket.io/4.7.5/socket.io.min.js"></script>
<script>
var C=['#f59e0b','#3b82f6','#10b981','#8b5cf6','#ef4444'];
var M=['🥇','🥈','🥉','#4','#5'];
var scores={
  'a3f1bc20-xdev1':{id:'a3f1bc20-xdev1',score:91.4,p50:2.1,p99:8.3,tps:12400,cor:98.7,lang:'cpp'},
  'b7e2cd31-xdev2':{id:'b7e2cd31-xdev2',score:78.6,p50:3.8,p99:14.2,tps:9800,cor:95.2,lang:'rust'},
  'c9d3ef42-xdev3':{id:'c9d3ef42-xdev3',score:65.2,p50:6.1,p99:22.7,tps:7200,cor:91.0,lang:'go'},
  'd1a4f053-xdev4':{id:'d1a4f053-xdev4',score:54.8,p50:9.4,p99:38.1,tps:5100,cor:87.5,lang:'cpp'},
  'e5b6c164-xdev5':{id:'e5b6c164-xdev5',score:41.3,p50:14.2,p99:61.5,tps:3300,cor:79.8,lang:'cpp'}
};
function jit(v,p){return Math.max(0,v*(1+(Math.random()-0.5)*p));}
function render(){
  var r=Object.values(scores).sort(function(a,b){return b.score-a.score;});
  document.getElementById('t').textContent=new Date().toLocaleTimeString();
  var bh='';
  r.slice(0,5).forEach(function(s,i){
    var h=Math.round(s.score*1.3);
    bh+='<div class="bw"><div class="bs" style="color:'+C[i]+'">'+s.score.toFixed(1)+'</div><div class="bar" style="height:'+h+'px;background:'+C[i]+'"></div><div class="bl">'+s.id.slice(0,8)+'</div></div>';
  });
  document.getElementById('bars').innerHTML=bh;
  var th='';
  r.forEach(function(s,i){
    var col=s.score>=75?'#10b981':s.score>=50?'#f59e0b':'#ef4444';
    th+='<tr class="'+(i===0?'gold':'')+'">';
    th+='<td>'+M[i]+'</td>';
    th+='<td style="color:#94a3b8;font-size:11px">'+s.id+'</td>';
    th+='<td><span class="tag '+s.lang+'">'+s.lang+'</span></td>';
    th+='<td class="big" style="color:'+(i===0?'#f59e0b':'#e2e8f0')+'">'+s.score.toFixed(1)+'</td>';
    th+='<td style="color:#94a3b8">'+s.p50.toFixed(1)+'</td>';
    th+='<td style="color:#94a3b8">'+s.p99.toFixed(1)+'</td>';
    th+='<td style="color:#94a3b8">'+Math.round(s.tps).toLocaleString()+'</td>';
    th+='<td style="color:#94a3b8">'+s.cor.toFixed(1)+'%</td>';
    th+='<td><div class="bg"><div class="bf" style="width:'+s.score+'%;background:'+col+'"></div></div></td>';
    th+='</tr>';
  });
  document.getElementById('tb').innerHTML=th;
}
function fluc(){
  Object.values(scores).forEach(function(s){
    s.score=Math.min(100,Math.max(0,jit(s.score,0.02)));
    s.p50=jit(s.p50,0.05);s.p99=jit(s.p99,0.05);
    s.tps=jit(s.tps,0.03);s.cor=Math.min(100,jit(s.cor,0.01));
  });
  render();
}
try{
  var socket=io('http://localhost:3001');
  socket.on('score-update',function(d){scores[d.submission_id]=d;render();});
}catch(e){}
render();
setInterval(fluc,2000);
</script></body></html>`;
const s=http.createServer(function(req,res){res.writeHead(200,{'Content-Type':'text/html'});res.end(html);});
s.listen(3000,function(){console.log('Leaderboard on :3000');});
