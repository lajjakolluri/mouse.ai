#!/usr/bin/env bash
# Monse.ai — Mac Install Script
# Run: bash install-mac.sh

set -euo pipefail

PROXY_PORT="8765"
BACKEND_URL="http://129.159.45.114"
INSTALL_DIR="$HOME/.monse"
BIN_DIR="$HOME/.local/bin"
PROXY_DIR="$INSTALL_DIR/proxy-server"
PID_FILE="$INSTALL_DIR/proxy.pid"
LOG_FILE="$INSTALL_DIR/proxy.log"
PLIST="$HOME/Library/LaunchAgents/ai.monse.proxy.plist"

# ─── colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; BOLD='\033[1m'; RESET='\033[0m'
ok()  { echo -e "${GREEN}✓${RESET} $*"; }
err() { echo -e "${RED}✗${RESET} $*"; exit 1; }
wrn() { echo -e "${YELLOW}⚠${RESET} $*"; }
hdr() { echo -e "\n${BOLD}${CYAN}━━━ $* ━━━${RESET}"; }

echo ""
echo -e "${BOLD}${CYAN}"
echo "  ███╗   ███╗ ██████╗ ███╗   ██╗███████╗███████╗   █████╗ ██╗"
echo "  ████╗ ████║██╔═══██╗████╗  ██║██╔════╝██╔════╝  ██╔══██╗██║"
echo "  ██╔████╔██║██║   ██║██╔██╗ ██║███████╗█████╗    ███████║██║"
echo "  ██║╚██╔╝██║██║   ██║██║╚██╗██║╚════██║██╔══╝    ██╔══██║██║"
echo "  ██║ ╚═╝ ██║╚██████╔╝██║ ╚████║███████║███████╗  ██║  ██║██║"
echo "  ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝╚══════╝  ╚═╝  ╚═╝╚═╝"
echo -e "${RESET}"
echo -e "  ${BOLD}LLM Cost Optimization Infrastructure${RESET}"
echo -e "  ${CYAN}$BACKEND_URL${RESET}"
echo ""

# ─── 1. Node.js ───────────────────────────────────────────────────────────────
hdr "Step 1/6  Check Node.js"
if ! command -v node &>/dev/null; then
  wrn "Node.js not found. Installing via Homebrew..."
  command -v brew &>/dev/null || err "Homebrew required. Install from https://brew.sh"
  brew install node
fi
NODE_VER=$(node --version)
NODE_MAJOR=$(echo "$NODE_VER" | tr -d 'v' | cut -d. -f1)
[ "$NODE_MAJOR" -lt 16 ] && err "Node.js $NODE_VER found — needs ≥ 16"
ok "Node.js $NODE_VER"

# ─── 2. Directories ───────────────────────────────────────────────────────────
hdr "Step 2/6  Create directories"
mkdir -p "$INSTALL_DIR" "$PROXY_DIR" "$BIN_DIR"
ok "~/.monse  ~/.local/bin"

# ─── 3. Proxy server ──────────────────────────────────────────────────────────
hdr "Step 3/6  Install proxy server"
cat > "$PROXY_DIR/server.js" << 'PROXY_JS'
#!/usr/bin/env node
const http=require('http'),https=require('https'),fs=require('fs'),path=require('path'),os=require('os');
const PORT=parseInt(process.env.MONSE_PROXY_PORT||'8765',10);
const BACKEND=(process.env.MONSE_BACKEND_URL||'http://129.159.45.114').replace(/\/$/,'');
const LOG=process.env.MONSE_LOG_LEVEL||'info';
const stats={requests:0,cacheHits:0,savedUsd:0,costUsd:0,startedAt:Date.now()};
function log(l,...a){if(LOG==='silent')return;if(l==='debug'&&LOG!=='debug')return;console.log(`[${new Date().toISOString().slice(11,23)}] [${l.toUpperCase()}]`,...a);}
function readBody(req){return new Promise((res,rej)=>{let d='';req.on('data',c=>d+=c);req.on('end',()=>{try{res(d?JSON.parse(d):{});}catch{rej(new Error('Invalid JSON'));}});req.on('error',rej);});}
function callMonse(p,body,key){return new Promise((res,rej)=>{const u=new URL(BACKEND+p);const pl=JSON.stringify(body);const opts={hostname:u.hostname,port:u.port||(u.protocol==='https:'?443:80),path:u.pathname,method:'POST',headers:{'Content-Type':'application/json','Content-Length':Buffer.byteLength(pl),'Authorization':`Bearer ${key}`}};const lib=u.protocol==='https:'?https:http;const r=lib.request(opts,s=>{let d='';s.on('data',c=>d+=c);s.on('end',()=>{try{res({status:s.statusCode,body:JSON.parse(d)});}catch{res({status:s.statusCode,body:{raw:d}});}});});r.setTimeout(90000,()=>{r.destroy();rej(new Error('Timeout'));});r.on('error',rej);r.write(pl);r.end();});}
function toOpenAI(m,rm){const text=(m.content||[]).filter(b=>b.type==='text').map(b=>b.text).join('');const i=m.usage?.input||0,o=m.usage?.output||0;return{id:`chatcmpl-monse-${Date.now()}`,object:'chat.completion',created:Math.floor(Date.now()/1000),model:m.model||rm||'claude-3-haiku-20240307',choices:[{index:0,message:{role:'assistant',content:text},finish_reason:'stop'}],usage:{prompt_tokens:i,completion_tokens:o,total_tokens:i+o},_monse:{cache_hit:m.cache_hit||false,cost:m.cost||{}}};}
function send(res,status,body){const s=JSON.stringify(body);res.writeHead(status,{'Content-Type':'application/json','Content-Length':Buffer.byteLength(s),'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'Authorization,Content-Type,x-api-key'});res.end(s);}
const server=http.createServer(async(req,res)=>{
  const{method,url}=req;
  if(method==='OPTIONS'){res.writeHead(204,{'Access-Control-Allow-Origin':'*','Access-Control-Allow-Methods':'GET,POST,OPTIONS','Access-Control-Allow-Headers':'Authorization,Content-Type,x-api-key'});return res.end();}
  if(method==='GET'&&url==='/health')return send(res,200,{status:'healthy',proxy:'monse-local',backend:BACKEND,uptime_seconds:Math.floor((Date.now()-stats.startedAt)/1000)});
  if(method==='GET'&&url==='/savings')return send(res,200,{session_requests:stats.requests,session_cache_hits:stats.cacheHits,session_cache_hit_rate:stats.requests>0?`${((stats.cacheHits/stats.requests)*100).toFixed(1)}%`:'0.0%',session_saved_usd:stats.savedUsd.toFixed(6),session_cost_usd:stats.costUsd.toFixed(6),runtime_seconds:Math.floor((Date.now()-stats.startedAt)/1000),backend:BACKEND});
  if(method==='GET'&&(url==='/v1/models'||url==='/models'))return send(res,200,{object:'list',data:[{id:'monse-auto',object:'model',owned_by:'monse'},{id:'claude-3-haiku-20240307',object:'model',owned_by:'anthropic'},{id:'claude-sonnet-4-20250514',object:'model',owned_by:'anthropic'}]});
  if(method==='POST'&&url==='/cache/clear'){Object.assign(stats,{requests:0,cacheHits:0,savedUsd:0,costUsd:0,startedAt:Date.now()});return send(res,200,{success:true});}
  if(method==='POST'&&(url==='/v1/chat/completions'||url==='/v1/messages')){
    const xApiKey=(req.headers['x-api-key']||'').trim();
    const auth=(req.headers['authorization']||'').trim();
    const apiKey=xApiKey||auth.replace(/^Bearer\s+/i,'').trim();
    if(!apiKey||!apiKey.startsWith('tok_monse_'))return send(res,401,{error:{message:'Invalid API key. Use your tok_monse_ key from the Monse dashboard.',type:'invalid_api_key'}});
    let body;try{body=await readBody(req);}catch{return send(res,400,{error:{message:'Invalid JSON',type:'invalid_request_error'}});}
    const{messages,max_tokens,model:rm}=body;
    if(!Array.isArray(messages)||!messages.length)return send(res,400,{error:{message:'messages required',type:'invalid_request_error'}});
    stats.requests++;
    log('info',`→ /api/v1/optimize msgs=${messages.length} key=...${apiKey.slice(-6)}`);
    let r;try{r=await callMonse('/api/v1/optimize',{messages,max_tokens},apiKey);}catch(e){return send(res,502,{error:{message:`Backend unreachable: ${e.message}`,type:'api_error'}});}
    if(r.status!==200){const d=r.body?.detail;const m=typeof d==='object'?(d.message||JSON.stringify(d)):String(d||r.body?.error||'Error');return send(res,r.status,{error:{message:m,type:r.status===402?'billing_error':'api_error'}});}
    const mb=r.body;
    if(mb.cache_hit)stats.cacheHits++;
    if(mb.cost?.saved)stats.savedUsd+=parseFloat(mb.cost.saved)||0;
    if(mb.cost?.optimized)stats.costUsd+=parseFloat(mb.cost.optimized)||0;
    const resp=toOpenAI(mb,rm);
    log('info',`✓ ${mb.cache_hit?'CACHE HIT':resp.model} tokens=${resp.usage.total_tokens} saved=$${parseFloat(mb.cost?.saved||0).toFixed(6)}`);
    return send(res,200,resp);
  }
  return send(res,404,{error:`Unknown: ${method} ${url}`});
});
server.listen(PORT,'127.0.0.1',()=>{
  console.log(`\n╔══════════════════════════════════════════════════╗`);
  console.log(`║         Monse.ai Local Proxy v1.0                ║`);
  console.log(`╠══════════════════════════════════════════════════╣`);
  console.log(`║  Proxy  : http://localhost:${PORT}                  ║`);
  console.log(`║  Backend: ${BACKEND.padEnd(38)}║`);
  console.log(`╠══════════════════════════════════════════════════╣`);
  console.log(`║  ANTHROPIC_BASE_URL=http://localhost:${PORT}         ║`);
  console.log(`║  ANTHROPIC_API_KEY=tok_monse_<your-key>          ║`);
  console.log(`╚══════════════════════════════════════════════════╝\n`);
});
server.on('error',e=>{if(e.code==='EADDRINUSE'){console.error(`Port ${PORT} in use. Run: lsof -ti:${PORT} | xargs kill -9`);}else{console.error(e.message);}process.exit(1);});
process.on('SIGTERM',()=>{server.close();process.exit(0);});
process.on('SIGINT',()=>{server.close();process.exit(0);});
PROXY_JS
chmod +x "$PROXY_DIR/server.js"
ok "Proxy server → $PROXY_DIR/server.js"

# ─── 4. CLI ───────────────────────────────────────────────────────────────────
hdr "Step 4/6  Install monse CLI"
cat > "$BIN_DIR/monse" << 'CLI_JS'
#!/usr/bin/env node
const http=require('http'),fs=require('fs'),path=require('path'),os=require('os');
const{spawn,execSync}=require('child_process');
const PORT=parseInt(process.env.MONSE_PROXY_PORT||'8765',10);
const BACKEND='http://129.159.45.114';
const CONFIG_FILE=path.join(os.homedir(),'.monse','config.json');
const PID_FILE=path.join(os.homedir(),'.monse','proxy.pid');
const LOG_FILE=path.join(os.homedir(),'.monse','proxy.log');
const SERVER_PATH=path.join(os.homedir(),'.monse','proxy-server','server.js');
const G='\x1b[32m',R='\x1b[31m',Y='\x1b[1;33m',C='\x1b[36m',B='\x1b[1m',D='\x1b[2m',X='\x1b[0m';
const ok=s=>`${G}✓${X} ${s}`;
const er=s=>`${R}✗${X} ${s}`;
const wn=s=>`${Y}⚠${X} ${s}`;
const hd=s=>`\n${B}${C}━━━ ${s} ━━━${X}`;
function loadCfg(){try{return JSON.parse(fs.readFileSync(CONFIG_FILE,'utf8'));}catch{return{};}}
function saveCfg(d){fs.mkdirSync(path.dirname(CONFIG_FILE),{recursive:true});fs.writeFileSync(CONFIG_FILE,JSON.stringify({...loadCfg(),...d},null,2));}
function get(p,t=3000){return new Promise((res,rej)=>{const r=http.get(`http://localhost:${PORT}${p}`,{timeout:t},s=>{let d='';s.on('data',c=>d+=c);s.on('end',()=>{try{res(JSON.parse(d));}catch{res(d);}});});r.on('error',rej);r.on('timeout',()=>{r.destroy();rej(new Error('timeout'));});});}
async function running(){try{const r=await get('/health',1500);return r.status==='healthy';}catch{return false;}}

async function cmdStatus(){
  console.log(hd('Monse Status'));
  const up=await running();
  console.log(up?ok(`Proxy running  →  localhost:${PORT}`):er(`Proxy not running  (start with: monse on)`));
  if(!up)return;
  const[h,s]=await Promise.all([get('/health'),get('/savings')]);
  console.log(`\n  Backend : ${D}${h.backend}${X}`);
  console.log(`  Uptime  : ${D}${h.uptime_seconds}s${X}`);
  console.log(`\n${B}  Session${X}`);
  console.log(`  Requests  : ${B}${s.session_requests}${X}`);
  console.log(`  Cache hits: ${B}${s.session_cache_hits}${X}  (${s.session_cache_hit_rate})`);
  console.log(`  Saved     : ${G}$${parseFloat(s.session_saved_usd||0).toFixed(4)}${X}`);
}

async function cmdSavings(){
  console.log(hd('Savings Report'));
  if(!await running()){console.log(er('Proxy not running — start with: monse on'));return;}
  const s=await get('/savings');
  const saved=parseFloat(s.session_saved_usd||0);
  const cost=parseFloat(s.session_cost_usd||0);
  const orig=saved+cost;
  const pct=orig>0?((saved/orig)*100).toFixed(1):'0.0';
  const ann=saved*(365*24*3600/Math.max(s.runtime_seconds||1,1));
  console.log(`\n  ${B}Session${X}`);
  console.log(`  ─────────────────────────────────────`);
  console.log(`  Requests      : ${B}${s.session_requests}${X}`);
  console.log(`  Cache hits    : ${B}${s.session_cache_hits}${X}  (${s.session_cache_hit_rate})`);
  console.log(`  Without Monse : ${D}$${orig.toFixed(6)}${X}`);
  console.log(`  With Monse    : ${D}$${cost.toFixed(6)}${X}`);
  console.log(`  Saved         : ${G}${B}$${saved.toFixed(6)} (${pct}%)${X}`);
  console.log(`\n  ${B}Projected${X}`);
  console.log(`  ─────────────────────────────────────`);
  console.log(`  Annualised    : ${G}$${ann.toFixed(2)}/yr${X}  ${D}(at current rate)${X}\n`);
}

async function cmdDoctor(){
  console.log(hd('Doctor Check'));
  let pass=0,total=0;
  async function check(label,fn){
    total++;
    try{const r=await fn();if(r.ok){console.log(ok(label+(r.note?`  ${D}${r.note}${X}`:'')));pass++;}else{console.log(er(label+(r.note?`  ${D}→ ${r.note}${X}`:'')));}}
    catch(e){console.log(er(`${label}  ${D}→ ${e.message}${X}`));}
  }
  await check('Node.js ≥ 16',async()=>{const v=parseInt(process.versions.node.split('.')[0],10);return{ok:v>=16,note:`v${process.versions.node}`};});
  await check('Proxy server installed',async()=>({ok:fs.existsSync(SERVER_PATH),note:SERVER_PATH}));
  await check(`Proxy running on localhost:${PORT}`,async()=>{const up=await running();return{ok:up,note:up?'responding':'not running — run: monse on'};});
  try{const r=await new Promise((res,rej)=>{const req=http.get(`${BACKEND}/health`,{timeout:5000},s=>{let d='';s.on('data',c=>d+=c);s.on('end',()=>res({status:s.statusCode}));});req.on('error',rej);});await check(`Backend reachable`,async()=>({ok:r.status===200,note:r.status===200?BACKEND:`HTTP ${r.status}`}));}catch(e){await check('Backend reachable',async()=>({ok:false,note:e.message}));}
  const cfg=loadCfg();
  const key=cfg.apiKey||process.env.ANTHROPIC_API_KEY||'';
  await check('API key configured',async()=>({ok:key.startsWith('tok_monse_'),note:key.startsWith('tok_monse_')?`...${key.slice(-6)}`:'run: monse set-key tok_monse_xxx'}));
  await check('ANTHROPIC_BASE_URL set',async()=>{const v=process.env.ANTHROPIC_BASE_URL||'';return{ok:v.includes(`localhost:${PORT}`),note:v||`not set — open new terminal after install`};});
  await check('OPENAI_BASE_URL set',async()=>{const v=process.env.OPENAI_BASE_URL||'';return{ok:v.includes(`localhost:${PORT}`),note:v||`not set — open new terminal after install`};});
  console.log(`\n  ${pass}/${total} checks passed`);
  if(pass<total)console.log(`\n  ${D}Fix issues above, then re-run: monse doctor${X}`);
}

async function cmdOn(){
  if(await running()){console.log(wn(`Proxy already running on localhost:${PORT}`));return;}
  if(!fs.existsSync(SERVER_PATH)){console.log(er(`Proxy server not found at ${SERVER_PATH}`));process.exit(1);}
  fs.mkdirSync(path.dirname(LOG_FILE),{recursive:true});
  const child=spawn('node',[SERVER_PATH],{detached:true,stdio:['ignore',fs.openSync(LOG_FILE,'a'),fs.openSync(LOG_FILE,'a')],env:{...process.env,MONSE_PROXY_PORT:String(PORT),MONSE_BACKEND_URL:BACKEND}});
  child.unref();
  fs.writeFileSync(PID_FILE,String(child.pid));
  for(let i=0;i<10;i++){await new Promise(r=>setTimeout(r,400));if(await running()){console.log(ok(`Proxy started  (PID ${child.pid})  →  localhost:${PORT}`));console.log(`  Logs: ${LOG_FILE}`);return;}}
  console.log(wn('Proxy started — may take a moment to respond'));
}

function cmdOff(){
  if(!fs.existsSync(PID_FILE)){console.log(wn('No PID file — proxy may not be running'));return;}
  const pid=parseInt(fs.readFileSync(PID_FILE,'utf8').trim(),10);
  try{process.kill(pid,'SIGTERM');fs.unlinkSync(PID_FILE);console.log(ok(`Proxy stopped  (PID ${pid})`));}
  catch(e){console.log(er(`Could not stop PID ${pid}: ${e.message}`));}
}

function cmdLogs(){
  if(!fs.existsSync(LOG_FILE)){console.log(wn(`No log file yet — start proxy first: monse on`));return;}
  console.log(`${D}Tailing ${LOG_FILE} — Ctrl+C to stop${X}\n`);
  spawn('tail',['-f',LOG_FILE],{stdio:'inherit'}).on('exit',()=>process.exit(0));
}

function cmdSetKey(key){
  if(!key||!key.startsWith('tok_monse_')){console.log(er('Usage: monse set-key tok_monse_xxxxx'));process.exit(1);}
  saveCfg({apiKey:key});
  console.log(ok(`API key saved`));
  console.log(`\n  Add to your ~/.zshrc:\n`);
  console.log(`  ${C}export ANTHROPIC_API_KEY=${key}${X}`);
  console.log(`  ${C}export ANTHROPIC_BASE_URL=http://localhost:${PORT}${X}`);
  console.log(`  ${C}export OPENAI_API_KEY=${key}${X}`);
  console.log(`  ${C}export OPENAI_BASE_URL=http://localhost:${PORT}/v1${X}`);
  console.log(`\n  Then: source ~/.zshrc && monse doctor`);
}

function cmdConfig(){
  const cfg=loadCfg();
  console.log(hd('Configuration'));
  console.log(`  Config file : ${CONFIG_FILE}`);
  console.log(`  API key     : ${cfg.apiKey?`...${cfg.apiKey.slice(-6)}`:D+'not set'+X}`);
  console.log(`  Proxy port  : ${PORT}`);
  console.log(`  Backend     : ${BACKEND}`);
  console.log(`\n  Shell env`);
  console.log(`  ANTHROPIC_BASE_URL : ${process.env.ANTHROPIC_BASE_URL||D+'not set'+X}`);
  console.log(`  OPENAI_BASE_URL    : ${process.env.OPENAI_BASE_URL||D+'not set'+X}`);
}

function cmdHelp(){
  console.log(`
${B}${C}  monse${X} — Monse.ai CLI

${B}  Usage:${X}
    monse <command>

${B}  Commands:${X}
    ${C}on${X}              Start proxy in background
    ${C}off${X}             Stop proxy
    ${C}status${X}          Health + session stats
    ${C}savings${X}         Detailed cost breakdown
    ${C}doctor${X}          7-point environment check
    ${C}logs${X}            Tail proxy logs
    ${C}config${X}          Show configuration
    ${C}set-key <key>${X}   Save your Monse API key

${B}  Examples:${X}
    monse on
    monse set-key tok_monse_xxxxx
    monse doctor
    monse savings
  `);
}

(async()=>{
  const[,,cmd,...args]=process.argv;
  switch(cmd){
    case'status':          await cmdStatus();  break;
    case'savings':         await cmdSavings(); break;
    case'doctor':          await cmdDoctor();  break;
    case'on': case'start': await cmdOn();      break;
    case'off':case'stop':  cmdOff();           break;
    case'logs':            cmdLogs();          break;
    case'config':          cmdConfig();        break;
    case'set-key':         cmdSetKey(args[0]); break;
    case'help':case'--help':case'-h':case undefined: cmdHelp(); break;
    default: console.log(er(`Unknown command: ${cmd}`));console.log('  Run: monse help');process.exit(1);
  }
})();
CLI_JS
chmod +x "$BIN_DIR/monse"
ok "CLI → $BIN_DIR/monse"

# ─── 5. Shell profile ─────────────────────────────────────────────────────────
hdr "Step 5/6  Shell environment"
PROFILE="$HOME/.zshrc"
[ ! -f "$PROFILE" ] && PROFILE="$HOME/.bash_profile"

BLOCK='
# ── Monse.ai ──────────────────────────────────────────────────────
export PATH="$HOME/.local/bin:$PATH"
export ANTHROPIC_BASE_URL="http://localhost:8765"
export OPENAI_BASE_URL="http://localhost:8765/v1"
# Set your key with: monse set-key tok_monse_xxx
# ──────────────────────────────────────────────────────────────────'

if grep -q "Monse.ai" "$PROFILE" 2>/dev/null; then
  wrn "Monse block already in $PROFILE — skipping"
else
  echo "$BLOCK" >> "$PROFILE"
  ok "Added env vars to $PROFILE"
fi

# ─── 6. LaunchAgent (auto-start on login) ────────────────────────────────────
hdr "Step 6/6  Auto-start on login"
NODE_PATH=$(command -v node)
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>             <string>ai.monse.proxy</string>
  <key>ProgramArguments</key>  <array><string>$NODE_PATH</string><string>$PROXY_DIR/server.js</string></array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>MONSE_PROXY_PORT</key>   <string>$PROXY_PORT</string>
    <key>MONSE_BACKEND_URL</key>  <string>$BACKEND_URL</string>
  </dict>
  <key>RunAtLoad</key>   <true/>
  <key>KeepAlive</key>   <true/>
  <key>StandardOutPath</key>   <string>$LOG_FILE</string>
  <key>StandardErrorPath</key> <string>$LOG_FILE</string>
</dict>
</plist>
PLIST
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load   "$PLIST"
ok "LaunchAgent registered — proxy starts on every login"

# ─── start proxy now ──────────────────────────────────────────────────────────
sleep 2
if curl -s http://localhost:$PROXY_PORT/health | grep -q healthy; then
  ok "Proxy is running on localhost:$PROXY_PORT"
else
  wrn "Proxy not yet responding — run: monse on"
fi

# ─── done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║       Monse.ai installed successfully  ✓         ║${RESET}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════╝${RESET}"
echo ""
echo "  Next steps:"
echo ""
echo -e "  1. ${CYAN}Reload your shell${RESET}"
echo "     source $PROFILE"
echo ""
echo -e "  2. ${CYAN}Save your Monse API key${RESET}"
echo "     monse set-key tok_monse_sXNDWZWNFhr0PaOEhu001RuqTaxT1Cch_zfs2xLHHwI"
echo ""
echo -e "  3. ${CYAN}Verify everything works${RESET}"
echo "     monse doctor"
echo ""
echo -e "  4. ${CYAN}Check savings anytime${RESET}"
echo "     monse savings"
echo ""
