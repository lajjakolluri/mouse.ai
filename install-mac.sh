#!/bin/bash
# Monse.ai Mac Install Script v2.0
set -euo pipefail
PROXY_PORT="8765"
BACKEND_URL="http://129.159.45.114"
INSTALL_DIR="$HOME/.monse"
BIN_DIR="$HOME/.local/bin"
PROXY_DIR="$INSTALL_DIR/proxy-server"
LOG_FILE="$INSTALL_DIR/proxy.log"
PLIST="$HOME/Library/LaunchAgents/ai.monse.proxy.plist"
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'
RED='\033[0;31m'; BOLD='\033[1m'; RESET='\033[0m'
ok()   { echo -e "${GREEN}[OK]${RESET} $*"; }
fail() { echo -e "${RED}[FAIL]${RESET} $*"; exit 1; }
wrn()  { echo -e "${YELLOW}[WARN]${RESET} $*"; }
hdr()  { echo -e "\n${BOLD}${CYAN}=== $* ===${RESET}"; }
echo ""
echo -e "${BOLD}${CYAN}"
echo "  MONSE.AI  -  LLM Cost Optimization Infrastructure"
echo -e "${RESET}"
echo -e "  ${CYAN}$BACKEND_URL${RESET}"
echo ""
hdr "Step 1/7  Check Node.js"
if ! command -v node &>/dev/null; then
  wrn "Node.js not found. Installing via Homebrew..."
  command -v brew &>/dev/null || fail "Homebrew required"
  brew install node
fi
NODE_VER=$(node --version)
NODE_MAJOR=$(echo "$NODE_VER" | tr -d 'v' | cut -d. -f1)
[ "$NODE_MAJOR" -lt 16 ] && fail "Node $NODE_VER needs >= 16"
ok "Node.js $NODE_VER"
hdr "Step 2/7  Create directories"
mkdir -p "$INSTALL_DIR" "$PROXY_DIR" "$BIN_DIR"
ok "~/.monse  ~/.local/bin"
hdr "Step 3/7  Install proxy server"
python3 - "$PROXY_DIR/server.js" "$BACKEND_URL" "$PROXY_PORT" << 'PYEOF'
import sys, os
p, backend, port = sys.argv[1], sys.argv[2], sys.argv[3]
js = """
const http=require('http'),https=require('https');
const PORT=parseInt(process.env.MONSE_PROXY_PORT||'PORT_PLACEHOLDER',10);
const BACKEND=(process.env.MONSE_BACKEND_URL||'BACKEND_PLACEHOLDER').replace(/\/$/,'');
const stats={requests:0,cacheHits:0,savedUsd:0,costUsd:0,startedAt:Date.now()};
function readBody(req){return new Promise((res,rej)=>{let d='';req.on('data',c=>d+=c);req.on('end',()=>{try{res(d?JSON.parse(d):{});}catch{rej(new Error('bad json'));}});req.on('error',rej);});}
function callMonse(path,body,key){return new Promise((res,rej)=>{const u=new URL(BACKEND+path);const pl=JSON.stringify(body);const o={hostname:u.hostname,port:u.port||(u.protocol==='https:'?443:80),path:u.pathname,method:'POST',headers:{'Content-Type':'application/json','Content-Length':Buffer.byteLength(pl),'Authorization':'Bearer '+key}};const lib=u.protocol==='https:'?https:http;const r=lib.request(o,s=>{let d='';s.on('data',c=>d+=c);s.on('end',()=>{try{res({status:s.statusCode,body:JSON.parse(d)});}catch{res({status:s.statusCode,body:{}});}});});r.setTimeout(90000,()=>{r.destroy();rej(new Error('timeout'));});r.on('error',rej);r.write(pl);r.end();});}
function toOAI(m,rm){const t=(m.content||[]).filter(b=>b.type==='text').map(b=>b.text).join('');const i=(m.usage||{}).input||0,o=(m.usage||{}).output||0;return{id:'chatcmpl-'+Date.now(),object:'chat.completion',created:Math.floor(Date.now()/1000),model:m.model||rm||'claude-3-haiku-20240307',choices:[{index:0,message:{role:'assistant',content:t},finish_reason:'stop'}],usage:{prompt_tokens:i,completion_tokens:o,total_tokens:i+o},_monse:{cache_hit:m.cache_hit||false,cost:m.cost||{}}};}
function send(res,code,body){const s=JSON.stringify(body);res.writeHead(code,{'Content-Type':'application/json','Content-Length':Buffer.byteLength(s),'Access-Control-Allow-Origin':'*'});res.end(s);}
const srv=http.createServer(async(req,res)=>{
  const{method:M,url:U}=req;
  if(M==='OPTIONS'){res.writeHead(204,{'Access-Control-Allow-Origin':'*','Access-Control-Allow-Methods':'GET,POST,OPTIONS','Access-Control-Allow-Headers':'Authorization,Content-Type,x-api-key'});return res.end();}
  if(M==='GET'&&U==='/health')return send(res,200,{status:'healthy',backend:BACKEND,uptime:Math.floor((Date.now()-stats.startedAt)/1000)});
  if(M==='GET'&&U==='/savings')return send(res,200,{session_requests:stats.requests,session_cache_hits:stats.cacheHits,session_cache_hit_rate:stats.requests>0?(((stats.cacheHits/stats.requests)*100).toFixed(1)+'%'):'0%',session_saved_usd:stats.savedUsd.toFixed(6),session_cost_usd:stats.costUsd.toFixed(6),runtime_seconds:Math.floor((Date.now()-stats.startedAt)/1000)});
  if(M==='GET'&&(U==='/v1/models'||U==='/models'))return send(res,200,{object:'list',data:[{id:'monse-auto'},{id:'claude-3-haiku-20240307'},{id:'claude-sonnet-4-20250514'}]});
  if(M==='POST'&&(U==='/v1/chat/completions'||U==='/v1/messages')){
    const key=(req.headers['x-api-key']||'').trim()||(req.headers['authorization']||'').replace(/^Bearer\s+/i,'').trim();
    if(!key.startsWith('tok_monse_'))return send(res,401,{error:{message:'Use tok_monse_ key',type:'invalid_api_key'}});
    let body;try{body=await readBody(req);}catch{return send(res,400,{error:{message:'bad json'}});}
    const{messages,max_tokens,model:rm}=body;
    if(!Array.isArray(messages)||!messages.length)return send(res,400,{error:{message:'messages required'}});
    stats.requests++;
    let r;try{r=await callMonse('/api/v1/optimize',{messages,max_tokens},key);}catch(e){return send(res,502,{error:{message:e.message}});}
    if(r.status!==200)return send(res,r.status,{error:{message:'backend error'}});
    const mb=r.body;
    if(mb.cache_hit)stats.cacheHits++;
    if(mb.cost&&mb.cost.saved)stats.savedUsd+=parseFloat(mb.cost.saved)||0;
    if(mb.cost&&mb.cost.optimized)stats.costUsd+=parseFloat(mb.cost.optimized)||0;
    return send(res,200,toOAI(mb,rm));
  }
  send(res,404,{error:'not found'});
});
srv.listen(PORT,'127.0.0.1',()=>console.log('Monse proxy running on localhost:'+PORT));
srv.on('error',e=>{console.error(e.message);process.exit(1);});
process.on('SIGTERM',()=>{srv.close();process.exit(0);});
"""
js = js.replace("PORT_PLACEHOLDER", port).replace("BACKEND_PLACEHOLDER", backend)
open(p,"w").write(js)
os.chmod(p, 0o755)
print("written")
PYEOF
ok "Proxy server -> $PROXY_DIR/server.js"
hdr "Step 4/7  Install monse CLI"
python3 - "$BIN_DIR/monse" "$PROXY_PORT" "$BACKEND_URL" << 'PYEOF'
import sys, os
p, port, backend = sys.argv[1], sys.argv[2], sys.argv[3]
js = """
const http=require('http'),fs=require('fs'),path=require('path'),os=require('os');
const{spawn}=require('child_process');
const PORT=parseInt(process.env.MONSE_PROXY_PORT||'PORT_PLACEHOLDER',10);
const BACKEND='BACKEND_PLACEHOLDER';
const CFG=path.join(os.homedir(),'.monse','config.json');
const PID=path.join(os.homedir(),'.monse','proxy.pid');
const LOG=path.join(os.homedir(),'.monse','proxy.log');
const SRV=path.join(os.homedir(),'.monse','proxy-server','server.js');
const G='\x1b[32m',R='\x1b[31m',Y='\x1b[33m',B='\x1b[1m',X='\x1b[0m';
const ok=s=>G+'[OK] '+X+s, er=s=>R+'[ERR] '+X+s, wn=s=>Y+'[WARN] '+X+s;
function lcfg(){try{return JSON.parse(fs.readFileSync(CFG,'utf8'));}catch{return{};}}
function scfg(d){fs.mkdirSync(path.dirname(CFG),{recursive:true});fs.writeFileSync(CFG,JSON.stringify(Object.assign(lcfg(),d),null,2));}
function get(p,t){return new Promise((res,rej)=>{const r=http.get('http://localhost:'+PORT+p,{timeout:t||3000},s=>{let d='';s.on('data',c=>d+=c);s.on('end',()=>{try{res(JSON.parse(d));}catch{res({});}});});r.on('error',rej);r.on('timeout',()=>{r.destroy();rej(new Error('timeout'));});});}
async function up(){try{const r=await get('/health',1500);return r.status==='healthy';}catch{return false;}}
async function cmdStatus(){
  const running=await up();
  console.log(running?ok('Proxy running -> localhost:'+PORT):er('Proxy not running. Run: monse on'));
  if(!running)return;
  const[h,sv]=await Promise.all([get('/health'),get('/savings')]);
  console.log('Backend: '+h.backend+'  Uptime: '+h.uptime+'s');
  console.log('Requests: '+sv.session_requests+'  Cache hits: '+sv.session_cache_hits+' ('+sv.session_cache_hit_rate+')');
  console.log(G+'Saved: $'+parseFloat(sv.session_saved_usd||0).toFixed(4)+X);
}
async function cmdSavings(){
  if(!await up()){console.log(er('Not running'));return;}
  const sv=await get('/savings');
  const saved=parseFloat(sv.session_saved_usd||0);
  const cost=parseFloat(sv.session_cost_usd||0);
  const orig=saved+cost;
  const pct=orig>0?((saved/orig)*100).toFixed(1):'0.0';
  const ann=saved*(365*24*3600/Math.max(sv.runtime_seconds||1,1));
  console.log('Requests: '+sv.session_requests+'  Cache: '+sv.session_cache_hit_rate);
  console.log('Without Monse: $'+orig.toFixed(6)+'  With Monse: $'+cost.toFixed(6));
  console.log(G+B+'Saved: $'+saved.toFixed(6)+' ('+pct+'%)'+X);
  console.log(G+'Annualised: $'+ann.toFixed(2)+'/yr'+X);
}
async function cmdDoctor(){
  let pass=0,total=0;
  async function chk(label,fn){total++;try{const r=await fn();if(r.ok){console.log(ok(label+(r.note?' '+r.note:'')));pass++;}else{console.log(er(label+(r.note?' -> '+r.note:'')));}}catch(e){console.log(er(label+' -> '+e.message));}}
  await chk('Node.js>=16',async()=>({ok:parseInt(process.versions.node,10)>=16,note:'v'+process.versions.node}));
  await chk('Proxy installed',async()=>({ok:fs.existsSync(SRV)}));
  await chk('Proxy running',async()=>{const r=await up();return{ok:r,note:r?'ok':'run: monse on'};});
  try{const resp=await new Promise((res,rej)=>{const r=http.get(BACKEND+'/health',{timeout:5000},s=>{let d='';s.on('data',c=>d+=c);s.on('end',()=>res(s.statusCode));});r.on('error',rej);});await chk('Backend reachable',async()=>({ok:resp===200,note:BACKEND}));}catch(e){await chk('Backend reachable',async()=>({ok:false,note:e.message}));}
  const key=(lcfg().apiKey||process.env.ANTHROPIC_API_KEY||'');
  await chk('API key',async()=>({ok:key.startsWith('tok_monse_'),note:key.startsWith('tok_monse_')?'...'+key.slice(-6):'run: monse set-key tok_monse_xxx'}));
  await chk('ANTHROPIC_BASE_URL',async()=>({ok:(process.env.ANTHROPIC_BASE_URL||'').includes('localhost:'+PORT),note:process.env.ANTHROPIC_BASE_URL||'not set'}));
  await chk('OPENAI_BASE_URL',async()=>({ok:(process.env.OPENAI_BASE_URL||'').includes('localhost:'+PORT),note:process.env.OPENAI_BASE_URL||'not set'}));
  console.log(pass+'/'+total+' checks passed');
}
async function cmdOn(){
  if(await up()){console.log(wn('Already running'));return;}
  if(!fs.existsSync(SRV)){console.log(er('Not installed: '+SRV));process.exit(1);}
  fs.mkdirSync(path.dirname(LOG),{recursive:true});
  const c=spawn('node',[SRV],{detached:true,stdio:['ignore',fs.openSync(LOG,'a'),fs.openSync(LOG,'a')],env:Object.assign({},process.env,{MONSE_PROXY_PORT:String(PORT),MONSE_BACKEND_URL:BACKEND})});
  c.unref();fs.writeFileSync(PID,String(c.pid));
  for(let i=0;i<10;i++){await new Promise(r=>setTimeout(r,400));if(await up()){console.log(ok('Proxy started (PID '+c.pid+') -> localhost:'+PORT));return;}}
  console.log(wn('Proxy started, may take a moment'));
}
function cmdOff(){
  if(!fs.existsSync(PID)){console.log(wn('No PID file'));return;}
  const pid=parseInt(fs.readFileSync(PID,'utf8').trim(),10);
  try{process.kill(pid,'SIGTERM');fs.unlinkSync(PID);console.log(ok('Stopped (PID '+pid+')'));}catch(e){console.log(er(e.message));}
}
function cmdLogs(){if(!fs.existsSync(LOG)){console.log(wn('No logs yet'));return;}spawn('tail',['-f',LOG],{stdio:'inherit'}).on('exit',()=>process.exit(0));}
function cmdSetKey(key){
  if(!key||!key.startsWith('tok_monse_')){console.log(er('Usage: monse set-key tok_monse_xxx'));process.exit(1);}
  scfg({apiKey:key});
  console.log(ok('Key saved'));
  console.log('Add to ~/.zshrc:');
  console.log('  export ANTHROPIC_API_KEY='+key);
  console.log('  export ANTHROPIC_BASE_URL=http://localhost:'+PORT);
  console.log('  export OPENAI_API_KEY='+key);
  console.log('  export OPENAI_BASE_URL=http://localhost:'+PORT+'/v1');
}
function cmdConfig(){const c=lcfg();console.log('Key: '+(c.apiKey?'...'+c.apiKey.slice(-6):'not set'));console.log('Port: '+PORT);console.log('Backend: '+BACKEND);}
function cmdHelp(){console.log('monse -- Monse.ai CLI\nCommands: on off status savings doctor logs config set-key');}
(async()=>{
  const[,,cmd,...args]=process.argv;
  switch(cmd){
    case'status':await cmdStatus();break;case'savings':await cmdSavings();break;case'doctor':await cmdDoctor();break;
    case'on':case'start':await cmdOn();break;case'off':case'stop':cmdOff();break;
    case'logs':cmdLogs();break;case'config':cmdConfig();break;case'set-key':cmdSetKey(args[0]);break;
    case'help':case'--help':case undefined:cmdHelp();break;default:console.log('Unknown: '+cmd);process.exit(1);
  }
})();
"""
js = js.replace("PORT_PLACEHOLDER", port).replace("BACKEND_PLACEHOLDER", backend)
open(p,"w").write(js)
os.chmod(p, 0o755)
print("written")
PYEOF
ok "CLI -> $BIN_DIR/monse"
hdr "Step 5/7  Shell environment"
PROFILE="$HOME/.zshrc"
[ ! -f "$PROFILE" ] && PROFILE="$HOME/.bash_profile"
if grep -q "Monse.ai" "$PROFILE" 2>/dev/null; then
  wrn "Monse block already in $PROFILE -- skipping"
else
  printf '\n# -- Monse.ai --\n' >> "$PROFILE"
  printf 'export PATH="$HOME/.local/bin:$PATH"\n' >> "$PROFILE"
  printf 'export ANTHROPIC_BASE_URL="http://localhost:%s"\n' "$PROXY_PORT" >> "$PROFILE"
  printf 'export OPENAI_BASE_URL="http://localhost:%s/v1"\n' "$PROXY_PORT" >> "$PROFILE"
  printf '# Set key: monse set-key tok_monse_xxx\n' >> "$PROFILE"
  printf '# ---------------\n' >> "$PROFILE"
  ok "Added env vars to $PROFILE"
fi
hdr "Step 6/7  Auto-start on login"
NODE_PATH=$(command -v node)
mkdir -p "$HOME/Library/LaunchAgents"
python3 - "$PLIST" "$NODE_PATH" "$PROXY_DIR/server.js" "$PROXY_PORT" "$BACKEND_URL" "$LOG_FILE" << 'PYEOF'
import sys
plist, node, srv, port, backend, log = sys.argv[1:]
xml = (
  '<?xml version="1.0" encoding="UTF-8"?>\n'
  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
  '<plist version="1.0">\n<dict>\n'
  '  <key>Label</key><string>ai.monse.proxy</string>\n'
  '  <key>ProgramArguments</key><array><string>'+node+'</string><string>'+srv+'</string></array>\n'
  '  <key>EnvironmentVariables</key><dict>\n'
  '    <key>MONSE_PROXY_PORT</key><string>'+port+'</string>\n'
  '    <key>MONSE_BACKEND_URL</key><string>'+backend+'</string>\n'
  '  </dict>\n'
  '  <key>RunAtLoad</key><true/>\n'
  '  <key>KeepAlive</key><true/>\n'
  '  <key>StandardOutPath</key><string>'+log+'</string>\n'
  '  <key>StandardErrorPath</key><string>'+log+'</string>\n'
  '</dict>\n</plist>\n'
)
open(plist,"w").write(xml)
print("written")
PYEOF
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
ok "LaunchAgent registered -- proxy starts on every login"
sleep 2
if curl -s "http://localhost:$PROXY_PORT/health" 2>/dev/null | grep -q healthy; then
  ok "Proxy is running on localhost:$PROXY_PORT"
else
  wrn "Proxy not yet responding -- run: monse on"
fi
hdr "Step 7/7  VS Code + All AI Extensions"
python3 - "$PROXY_PORT" << 'PYEOF'
import json, os, re, sys, glob
port = sys.argv[1]
proxy = "http://localhost:" + port
proxy_v1 = "http://localhost:" + port + "/v1"
home = os.path.expanduser("~")

def parse_jsonc(text):
    text = re.sub(r'//[^\n]*', '', text)
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
    text = re.sub(r',\s*([}\]])', r'\1', text)
    text = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]', '', text)
    return json.loads(text)

def patch(f, label):
    if not os.path.exists(f): return False
    try: cfg = parse_jsonc(open(f).read())
    except Exception as e: print("  skip "+label+": "+str(e)); return False
    changed = []
    def chk(k, v):
        if cfg.get(k) != v: cfg[k] = v; changed.append(k)
    # METHOD 1: VS Code HTTP proxy (routes VS Code network stack)
    chk("http.proxy", proxy)
    chk("http.proxyStrictSSL", False)
    chk("http.proxySupport", "on")
    # METHOD 2: Terminal env injection (routes ALL CLI tools in VS Code terminals)
    env = dict(cfg.get("terminal.integrated.env.osx") or {})
    new_env = dict(env)
    new_env["ANTHROPIC_BASE_URL"] = proxy
    new_env["OPENAI_BASE_URL"] = proxy_v1
    if new_env != env: cfg["terminal.integrated.env.osx"] = new_env; changed.append("terminal.integrated.env.osx")
    # METHOD 3: Per-extension settings (covers extensions with own fetch logic)
    for k,v in {
        "cline.openAiBaseUrl": proxy_v1,
        "cline.apiProvider": "openai",
        "roo-cline.openAiBaseUrl": proxy_v1,
        "aider.openaiApiBase": proxy_v1,
        "coder-agent.serverUrl": proxy,
        "coder-agent.apiBase": proxy_v1,
        "coder-agent.openaiApiBase": proxy_v1,
        "coder-agent.baseUrl": proxy_v1,
        "coderAgent.apiUrl": proxy_v1,
        "coderAgent.apiKey": "tok_monse_YOUR_KEY",
        "coderAgent.model": "monse-auto",
    }.items(): chk(k, v)
    models = list(cfg.get("continue.models") or [])
    monse = {"title":"Monse","provider":"openai","model":"monse-auto","apiBase":proxy_v1}
    if not any(m.get("apiBase")==proxy_v1 for m in models):
        models.insert(0, monse); cfg["continue.models"] = models; changed.append("continue.models")
    # METHOD 4: Scan all installed extensions
    ext_dir = os.path.join(home, ".vscode", "extensions")
    if os.path.exists(ext_dir):
        for pkg in glob.glob(os.path.join(ext_dir, "*", "package.json")):
            try:
                d = json.loads(open(pkg).read())
                name = d.get("name","")
                contrib = d.get("contributes",{}).get("configuration",{})
                props = {}
                if isinstance(contrib, list):
                    for c in contrib: props.update(c.get("properties",{}))
                else: props = contrib.get("properties",{})
                for k in props:
                    if any(x in k.lower() for x in ["baseurl","base_url","apibase","api_base","endpoint","serverurl","openaibase"])  :
                        chk(k, proxy_v1)
            except: pass
    if changed:
        open(f,"w").write(json.dumps(cfg, indent=2))
        print("  patched "+label+": "+", ".join(changed[:5])+("..." if len(changed)>5 else ""))
    else: print("  "+label+" already configured")
    return True

variants = [
    (home+"/Library/Application Support/Code/User/settings.json", "VS Code"),
    (home+"/Library/Application Support/Code - Insiders/User/settings.json", "VS Code Insiders"),
    (home+"/Library/Application Support/Cursor/User/settings.json", "Cursor"),
    (home+"/Library/Application Support/Windsurf/User/settings.json", "Windsurf"),
    (home+"/Library/Application Support/Void/User/settings.json", "Void"),
]
found = sum(1 for f,l in variants if patch(f,l))
if found == 0: print("  No VS Code variants found")
else:
    print("\n  "+str(found)+" editor(s) configured -- all 4 methods applied:")
    print("    1. http.proxy              -> VS Code network stack")
    print("    2. terminal.integrated.env -> all CLI tools in terminals")
    print("    3. per-extension settings  -> Cline, Roo, coder-agent, aider")
    print("    4. extension scanner       -> any other AI extension")
    print("\n  Reload VS Code: Cmd+Shift+P -> Reload Window")
PYEOF
echo ""
echo "[OK] Monse.ai installed successfully v2.0"
echo ""
echo "  1. source ~/.zshrc"
echo "  2. monse set-key tok_monse_YOUR_KEY"
echo "  3. Reload VS Code: Cmd+Shift+P -> Reload Window"
echo "  4. monse doctor"
echo ""
