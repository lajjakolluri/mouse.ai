"""
Monse.AI - BYOK with 7-Day Trial → $19/month
"""
from fastapi import FastAPI, HTTPException, Depends, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr, validator
from typing import Optional, List, Dict
from datetime import datetime, timedelta
import os
import secrets
import psycopg2
from psycopg2.extras import RealDictCursor
import bcrypt
import jwt
import stripe
import requests
from cryptography.fernet import Fernet

app = FastAPI(title="Monse.AI", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Config
JWT_SECRET = os.getenv("JWT_SECRET", "default-secret")
JWT_ALGORITHM = "HS256"
ENCRYPTION_KEY = os.getenv("ENCRYPTION_KEY")
cipher = Fernet(ENCRYPTION_KEY.encode()) if ENCRYPTION_KEY else None
STRIPE_SECRET_KEY = os.getenv("STRIPE_SECRET_KEY", "")
if STRIPE_SECRET_KEY:
    stripe.api_key = STRIPE_SECRET_KEY

POSTGRES_DSN = f"postgresql://{os.getenv('DB_USER', 'admin')}:{os.getenv('POSTGRES_PASSWORD')}@{os.getenv('DB_HOST', 'postgres')}:5432/{os.getenv('DB_NAME', 'tokenoptimizer')}"

security = HTTPBearer()

def get_db():
    return psycopg2.connect(POSTGRES_DSN)

def encrypt_api_key(api_key: str) -> str:
    return cipher.encrypt(api_key.encode()).decode() if cipher else api_key

def decrypt_api_key(encrypted_key: str) -> str:
    try:
        return cipher.decrypt(encrypted_key.encode()).decode() if cipher else encrypted_key
    except:
        return None

def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')

def verify_password(plain_password: str, hashed_password: str) -> bool:
    return bcrypt.checkpw(plain_password.encode('utf-8'), hashed_password.encode('utf-8'))

def create_access_token(user_id: int, email: str) -> str:
    payload = {
        "user_id": user_id,
        "email": email,
        "exp": datetime.utcnow() + timedelta(hours=24)
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)

def decode_token(token: str) -> Dict:
    try:
        return jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
    except:
        raise HTTPException(status_code=401, detail="Invalid token")

def generate_api_key() -> str:
    return f"tok_monse_{secrets.token_urlsafe(32)}"

def get_user_by_email(email: str):
    conn = get_db()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute("SELECT * FROM users WHERE email = %s", (email,))
    user = cur.fetchone()
    cur.close()
    conn.close()
    return dict(user) if user else None

def get_user_by_id(user_id: int):
    conn = get_db()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute("SELECT * FROM users WHERE id = %s", (user_id,))
    user = cur.fetchone()
    cur.close()
    conn.close()
    return dict(user) if user else None

def get_user_by_api_key(api_key: str):
    conn = get_db()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute("SELECT * FROM users WHERE primary_api_key = %s", (api_key,))
    user = cur.fetchone()
    cur.close()
    conn.close()
    return dict(user) if user else None

async def get_current_user_from_token(credentials: HTTPAuthorizationCredentials = Depends(security)):
    token = credentials.credentials
    payload = decode_token(token)
    user = get_user_by_id(payload["user_id"])
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    return user

async def get_current_user_from_api_key(credentials: HTTPAuthorizationCredentials = Depends(security)):
    api_key = credentials.credentials
    user = get_user_by_api_key(api_key)
    if not user:
        raise HTTPException(status_code=401, detail="Invalid API key")
    return user

def can_use_platform(user: Dict):
    if user.get('is_admin'):
        return True, "admin"
    if not user.get('anthropic_api_key_encrypted'):
        return False, "no_api_key"
    if user['subscription_status'] == 'trial':
        if user.get('trial_ends_at') and datetime.fromisoformat(str(user['trial_ends_at'])) > datetime.utcnow():
            return True, "trial"
        return False, "trial_expired"
    if user['subscription_status'] == 'active':
        return True, "subscribed"
    return False, user['subscription_status']

class UserRegister(BaseModel):
    email: EmailStr
    password: str
    company_name: str
    full_name: Optional[str] = None

class UserLogin(BaseModel):
    email: EmailStr
    password: str

class AddAPIKey(BaseModel):
    api_key: str

class OptimizeRequest(BaseModel):
    messages: List[Dict[str, str]]
    max_tokens: Optional[int] = 1024
@app.get("/")
def root():
    return {"message": "Monse.AI - Save 97% on AI costs", "status": "operational"}

@app.get("/health")
def health():
    return {"status": "healthy"}

@app.post("/api/v1/auth/register")
async def register(user_data: UserRegister):
    if get_user_by_email(user_data.email):
        raise HTTPException(status_code=400, detail="Email already registered")
    
    password_hash = hash_password(user_data.password)
    api_key = generate_api_key()
    
    conn = get_db()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute("""
        INSERT INTO users (email, password_hash, company_name, full_name, primary_api_key, plan, subscription_status)
        VALUES (%s, %s, %s, %s, %s, %s, %s)
        RETURNING id, email, company_name, primary_api_key, plan, subscription_status
    """, (user_data.email, password_hash, user_data.company_name, user_data.full_name, api_key, 'trial', 'pending'))
    
    user = cur.fetchone()
    conn.commit()
    cur.close()
    conn.close()
    
    access_token = create_access_token(user['id'], user['email'])
    return {"access_token": access_token, "token_type": "bearer", "user": dict(user)}

@app.post("/api/v1/auth/login")
async def login(credentials: UserLogin):
    user = get_user_by_email(credentials.email)
    if not user or not verify_password(credentials.password, user['password_hash']):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    
    access_token = create_access_token(user['id'], user['email'])
    user_data = dict(user)
    user_data.pop('password_hash', None)
    user_data.pop('anthropic_api_key_encrypted', None)
    return {"access_token": access_token, "token_type": "bearer", "user": user_data}

@app.get("/api/v1/auth/me")
async def get_me(user: Dict = Depends(get_current_user_from_token)):
    user_data = dict(user)
    user_data.pop('password_hash', None)
    user_data.pop('anthropic_api_key_encrypted', None)
    can_access, reason = can_use_platform(user)
    user_data['has_platform_access'] = can_access
    user_data['access_reason'] = reason
    return user_data

@app.post("/api/v1/user/anthropic-key")
async def add_anthropic_key(key_data: AddAPIKey, user: Dict = Depends(get_current_user_from_token)):
    encrypted_key = encrypt_api_key(key_data.api_key)
    
    conn = get_db()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    
    if not user.get('anthropic_api_key_encrypted'):
        trial_ends = datetime.utcnow() + timedelta(days=7)
        cur.execute("""
            UPDATE users SET anthropic_api_key_encrypted = %s, anthropic_api_key_verified = TRUE,
            trial_started_at = CURRENT_TIMESTAMP, trial_ends_at = %s, subscription_status = 'trial'
            WHERE id = %s RETURNING trial_ends_at
        """, (encrypted_key, trial_ends, user['id']))
        result = cur.fetchone()
        conn.commit()
        cur.close()
        conn.close()
        return {"success": True, "message": "Trial started!", "trial_ends_at": result['trial_ends_at'].isoformat(), "trial_days": 7}
    else:
        cur.execute("UPDATE users SET anthropic_api_key_encrypted = %s WHERE id = %s", (encrypted_key, user['id']))
        conn.commit()

@app.post("/api/v1/optimize")
async def optimize(request: OptimizeRequest, user: Dict = Depends(get_current_user_from_api_key)):
    can_access, reason = can_use_platform(user)
    
    if not can_access:
        if reason == "no_api_key":
            raise HTTPException(status_code=402, detail={"error": "api_key_required", "message": "Please add your Anthropic API key to start FREE trial"})
        elif reason == "trial_expired":
            conn = get_db()
            cur = conn.cursor()
            cur.execute("SELECT COALESCE(SUM(cost_saved), 0) FROM api_usage WHERE user_id = %s", (user['id'],))
            savings = cur.fetchone()[0]
            cur.close()
            conn.close()
            raise HTTPException(status_code=402, detail={"error": "trial_expired", "message": f"Trial ended. You saved ${float(savings):.2f}! Continue for $19/month", "trial_savings": float(savings)})
        else:
            raise HTTPException(status_code=402, detail={"error": "subscription_required", "message": "Subscription required"})
    
    their_key = decrypt_api_key(user['anthropic_api_key_encrypted'])
    if not their_key:
        raise HTTPException(status_code=500, detail="Failed to decrypt API key")
    
    query_text = " ".join([msg.get('content', '') for msg in request.messages])
    word_count = len(query_text.split())
    
    if word_count > 50:
        model = "claude-sonnet-4-20250514"
    else:
        model = "claude-3-haiku-20240307"
    
    pricing = {
        "claude-3-haiku-20240307": {"input": 0.25, "output": 1.25},
        "claude-sonnet-4-20250514": {"input": 3.00, "output": 15.00}
    }
    
    start_time = datetime.utcnow()
    
    try:
        response = requests.post(
            'https://api.anthropic.com/v1/messages',
            headers={'x-api-key': their_key, 'anthropic-version': '2023-06-01', 'Content-Type': 'application/json'},
            json={'model': model, 'max_tokens': request.max_tokens, 'messages': request.messages},
            timeout=60
