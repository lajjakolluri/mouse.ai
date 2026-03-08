
from fastapi import FastAPI, HTTPException, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr
from typing import Optional, List, Dict
from datetime import datetime, timedelta
import os, secrets, psycopg2, bcrypt, jwt, requests
from psycopg2.extras import RealDictCursor
from cryptography.fernet import Fernet

app = FastAPI(title="Monse.AI")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

JWT_SECRET = os.getenv("JWT_SECRET", "secret")
ENCRYPTION_KEY = os.getenv("ENCRYPTION_KEY")
cipher = Fernet(ENCRYPTION_KEY.encode()) if ENCRYPTION_KEY else None
POSTGRES_DSN = f"postgresql://{os.getenv('DB_USER', 'admin')}:{os.getenv('POSTGRES_PASSWORD')}@{os.getenv('DB_HOST', 'postgres')}:5432/{os.getenv('DB_NAME', 'tokenoptimizer')}"
security = HTTPBearer()

# Initialize Redis and Semantic Cache
try:
    import redis as redis_lib
    from semantic_cache import SemanticCache
    
    redis_client = redis_lib.Redis(
        host=os.getenv('REDIS_HOST', 'redis'),
        port=6379,
        db=0,
        decode_responses=True
    )
    semantic_cache = SemanticCache(redis_client, similarity_threshold=0.85)
    print("✓ Semantic cache initialized!")
except Exception as e:
    print(f"⚠ Semantic cache disabled: {e}")
    semantic_cache = None
try:
    from prompt_optimizer import PromptOptimizer
    prompt_optimizer = PromptOptimizer()
    print("✓ Prompt optimizer initialized!")
except Exception as e:
    print(f"⚠ Prompt optimizer disabled: {e}")
    prompt_optimizer = None

def get_db():
    return psycopg2.connect(POSTGRES_DSN)

def encrypt_api_key(k):
    return cipher.encrypt(k.encode()).decode() if cipher else k

def decrypt_api_key(k):
    try:
        return cipher.decrypt(k.encode()).decode() if cipher else k
    except:
        return None

def hash_password(p):
    return bcrypt.hashpw(p.encode(), bcrypt.gensalt()).decode()

def verify_password(p, h):
    return bcrypt.checkpw(p.encode(), h.encode())

def create_token(uid, email):
    return jwt.encode({"user_id": uid, "email": email, "exp": datetime.utcnow() + timedelta(hours=24)}, JWT_SECRET, algorithm="HS256")

def decode_token(t):
    try:
        return jwt.decode(t, JWT_SECRET, algorithms=["HS256"])
    except:
        raise HTTPException(401, "Invalid token")

def get_user_by_email(email):
    conn = get_db()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute("SELECT * FROM users WHERE email = %s", (email,))
    u = cur.fetchone()
    cur.close()
    conn.close()
    return dict(u) if u else None

def get_user_by_id(uid):
    conn = get_db()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute("SELECT * FROM users WHERE id = %s", (uid,))
    u = cur.fetchone()
    cur.close()
    conn.close()
    return dict(u) if u else None

def get_user_by_key(k):
    conn = get_db()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute("SELECT * FROM users WHERE primary_api_key = %s", (k,))
    u = cur.fetchone()
    cur.close()
    conn.close()
    return dict(u) if u else None

async def get_user_token(c: HTTPAuthorizationCredentials = Depends(security)):
    p = decode_token(c.credentials)
    u = get_user_by_id(p["user_id"])
    if not u:
        raise HTTPException(401, "Not found")
    return u

async def get_user_apikey(c: HTTPAuthorizationCredentials = Depends(security)):
    u = get_user_by_key(c.credentials)
    if not u:
        raise HTTPException(401, "Invalid key")
    return u

def can_use(u):
    if u.get('is_admin'):
        return True, "admin"
    if not u.get('anthropic_api_key_encrypted'):
        return False, "no_key"
    if u['subscription_status'] == 'trial' and u.get('trial_ends_at'):
        if datetime.fromisoformat(str(u['trial_ends_at'])) > datetime.utcnow():
            return True, "trial"
        return False, "expired"
    if u['subscription_status'] == 'active':
        return True, "active"
    return False, u['subscription_status']

class UserReg(BaseModel):
    email: EmailStr
    password: str
    company_name: str
    full_name: Optional[str] = None

class UserLogin(BaseModel):
    email: EmailStr
    password: str

class AddKey(BaseModel):
    api_key: str

class OptReq(BaseModel):
    messages: List[Dict]
    max_tokens: Optional[int] = 1024

class BatchOptReq(BaseModel):
    requests: List[OptReq]
    max_tokens: Optional[int] = 1024

class UserReg(BaseModel):
    email: EmailStr
    password: str
    company_name: str
    full_name: Optional[str] = None

class UserLogin(BaseModel):
    email: EmailStr
    password: str

class AddKey(BaseModel):
    api_key: str

class OptReq(BaseModel):
    messages: List[Dict]
    max_tokens: Optional[int] = 1024

@app.get("/")
def root():
    return {"message": "Monse.AI"}

@app.get("/health")
def health():
    return {"status": "healthy"}

@app.post("/api/v1/auth/register")
def register(d: UserReg):
    if get_user_by_email(d.email):
        raise HTTPException(400, "Email exists")
    h = hash_password(d.password)
    k = f"tok_monse_{secrets.token_urlsafe(32)}"
    conn = get_db()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute("INSERT INTO users (email, password_hash, company_name, full_name, primary_api_key, plan, subscription_status) VALUES (%s,%s,%s,%s,%s,%s,%s) RETURNING id, email, primary_api_key", 
                (d.email, h, d.company_name, d.full_name, k, 'trial', 'pending'))
    u = cur.fetchone()
    conn.commit()
    cur.close()
    conn.close()
    return {"access_token": create_token(u['id'], u['email']), "user": dict(u)}

@app.post("/api/v1/auth/login")
def login(d: UserLogin):
    u = get_user_by_email(d.email)
    if not u or not verify_password(d.password, u['password_hash']):
        raise HTTPException(401, "Invalid")
    return {"access_token": create_token(u['id'], u['email']), "user": {"email": u['email'], "id": u['id']}}

@app.get("/api/v1/auth/me")
def me(u: Dict = Depends(get_user_token)):
    can, why = can_use(u)

    return {"email": u['email'], "has_access": can, "reason": why, "trial_ends": str(u.get('trial_ends_at', ''))}


@app.post("/api/v1/optimize")
def optimize(r: OptReq, u: Dict = Depends(get_user_apikey)):
    can, why = can_use(u)
    if not can:
        if why == "no_key":
            raise HTTPException(402, "Add Anthropic key first")
        if why == "expired":
            raise HTTPException(402, "Trial expired - upgrade to continue")
        raise HTTPException(402, "Subscription required")

# 🔥 OPTIMIZE PROMPT FIRST (before cache check)
    if prompt_optimizer:
        try:
            optimized_messages, tokens_saved = prompt_optimizer.optimize_messages(r.messages)
            if tokens_saved > 0:
                print(f"✓ Prompt optimized: saved {tokens_saved} tokens")
                r.messages = optimized_messages
        except Exception as e:
            print(f"⚠ Prompt optimization failed: {e}")
    
    
    if semantic_cache:
        try:
            cached_response = semantic_cache.find_similar(r.messages)
            if cached_response:
                print(f"✓ Cache HIT for user {u['id']}")
                return cached_response
        except Exception as e:
            print(f"Cache check failed: {e}")
    
    k = decrypt_api_key(u['anthropic_api_key_encrypted'])
    if not k:
        raise HTTPException(500, "Key decrypt failed")
    
    wc = len(" ".join([m.get('content','') for m in r.messages]).split())
    model = "claude-sonnet-4-20250514" if wc > 50 else "claude-3-haiku-20240307"
    
    try:
        res = requests.post('https://api.anthropic.com/v1/messages',
                           headers={'x-api-key': k, 'anthropic-version': '2023-06-01', 'Content-Type': 'application/json'},
                           json={'model': model, 'max_tokens': r.max_tokens, 'messages': r.messages}, timeout=60)
        res.raise_for_status()
        d = res.json()
    except Exception as e:
        raise HTTPException(500, str(e))
    
    pricing = {"claude-3-haiku-20240307": {"input": 0.25, "output": 1.25}, "claude-sonnet-4-20250514": {"input": 3.00, "output": 15.00}}
    usage = d.get('usage', {})
    it = usage.get('input_tokens', 0)
    ot = usage.get('output_tokens', 0)
    oc = (it * pricing[model]['input'] + ot * pricing[model]['output']) / 1000000
    orig = (it * 3 + ot * 15) / 1000000
    saved = orig - oc
    
    conn = get_db()
    cur = conn.cursor()
    cur.execute("INSERT INTO api_usage (user_id, model_used, input_tokens, output_tokens, total_tokens, original_cost, optimized_cost, cost_saved) VALUES (%s,%s,%s,%s,%s,%s,%s,%s)",
                (u['id'], model, it, ot, it+ot, orig, oc, saved))
    cur.execute("UPDATE users SET total_savings_usd = COALESCE(total_savings_usd,0) + %s WHERE id=%s", (saved, u['id']))
    conn.commit()
    cur.close()
    conn.close()
    
    response = {"content": d.get('content'), "model": model, "usage": {"input": it, "output": ot}, "cost": {"optimized": round(oc,6), "original": round(orig,6), "saved": round(saved,6)}, "cache_hit": False}
    
    if semantic_cache:
        try:
            semantic_cache.store(r.messages, response)
        except:
            pass
    
    return response
@app.post("/api/v1/optimize/batch")
def optimize_batch(batch: BatchOptReq, u: Dict = Depends(get_user_apikey)):
    """Process multiple requests in a batch"""
    can, why = can_use(u)
    if not can:
        if why == "no_key":
            raise HTTPException(402, "Add Anthropic key first")
        if why == "expired":
            raise HTTPException(402, "Trial expired - upgrade to continue")
        raise HTTPException(402, "Subscription required")
    
    responses = []
    total_cost = 0
    total_saved = 0
    cache_hits = 0
    api_calls = 0
    
    print(f"Processing batch of {len(batch.requests)} requests...")
    
    for idx, req in enumerate(batch.requests):
        cache_hit = False
        if semantic_cache:
            try:
                cached = semantic_cache.find_similar(req.messages)
                if cached:
                    responses.append(cached)
                    cache_hits += 1
                    cache_hit = True
                    print(f"  Request {idx}: Cache HIT!")
            except:
                pass
        
        if not cache_hit:
            k = decrypt_api_key(u['anthropic_api_key_encrypted'])
            if not k:
                raise HTTPException(500, "Key decrypt failed")
            
            wc = len(" ".join([m.get('content','') for m in req.messages]).split())
            model = "claude-sonnet-4-20250514" if wc > 50 else "claude-3-haiku-20240307"
            
            try:
                res = requests.post('https://api.anthropic.com/v1/messages',
                    headers={'x-api-key': k, 'anthropic-version': '2023-06-01', 'Content-Type': 'application/json'},
                    json={'model': model, 'max_tokens': req.max_tokens or batch.max_tokens, 'messages': req.messages}, timeout=60)
                res.raise_for_status()
                d = res.json()
                
                pricing = {"claude-3-haiku-20240307": {"input": 0.25, "output": 1.25}, "claude-sonnet-4-20250514": {"input": 3.00, "output": 15.00}}
                usage = d.get('usage', {})
                it = usage.get('input_tokens', 0)
                ot = usage.get('output_tokens', 0)
                oc = (it * pricing[model]['input'] + ot * pricing[model]['output']) / 1000000
                orig = (it * 3 + ot * 15) / 1000000
                saved = orig - oc
                
                total_cost += oc
                total_saved += saved
                api_calls += 1
                
                response_data = {"content": d.get('content'), "model": model, "usage": {"input": it, "output": ot}, "cost": {"optimized": round(oc,6), "original": round(orig,6), "saved": round(saved,6)}, "cache_hit": False}
                responses.append(response_data)
                
                if semantic_cache:
                    try:
                        semantic_cache.store(req.messages, response_data)
                    except:
                        pass
                
                print(f"  Request {idx}: API call - {model}")
            except Exception as e:
                responses.append({"error": str(e)})
    
    return {"responses": responses, "summary": {"total_requests": len(batch.requests), "cache_hits": cache_hits, "api_calls": api_calls, "total_cost": round(total_cost, 6), "total_saved": round(total_saved, 6)}}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
