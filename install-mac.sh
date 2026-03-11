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
curl -fsSL https://raw.githubusercontent.com/lajjakolluri/mouse.ai/main/monse-cli.js -o "$BIN_DIR/monse"
chmod +x "$BIN_DIR/monse"
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
    text = re.sub(r'(?<![:/])//[^\n]*', '', text)
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
    text = re.sub(r',\s*([}\]])', r'\1', text)
    text = ''.join(c for c in text if ord(c) >= 32 or c in '\t\n\r')
    return json.loads(text, strict=False)

def patch(f, label):
    if not os.path.exists(f): return False
    try: cfg = parse_jsonc(open(f, encoding="utf-8", errors="ignore").read())
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
