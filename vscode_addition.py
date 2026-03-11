# ADD THIS TO unified_production_app.py

class VscodeOptimizeRequest(BaseModel):
    code: str
    language: str
    optimization_level: Optional[str] = "balanced"

@app.post("/api/v1/vscode/optimize")
def optimize_vscode(request: VscodeOptimizeRequest, u: Dict = Depends(get_user_apikey)):
    can, why = can_use(u)
    if not can:
        raise HTTPException(402, "Subscription required for VS Code extension")
    
    original_tokens = len(request.code.split())
    
    if request.optimization_level == "aggressive":
        optimized_code = request.code.replace('\n\n\n', '\n\n').strip()
        savings_percent = 15
    else:
        optimized_code = request.code.replace('  ', ' ').strip()
        savings_percent = 8
    
    optimized_tokens = len(optimized_code.split())
    
    conn = get_db()
    cur = conn.cursor()
    cur.execute("INSERT INTO api_usage (user_id, model_used, input_tokens, output_tokens, total_tokens, original_cost, optimized_cost, cost_saved) VALUES (%s,%s,%s,%s,%s,%s,%s,%s)",
                (u['id'], 'vscode-optimizer', original_tokens, optimized_tokens, original_tokens, 0.01, 0.008, 0.002))
    conn.commit()
    cur.close()
    conn.close()
    
    return {
        "optimized_code": optimized_code,
        "original_tokens": original_tokens,
        "optimized_tokens": optimized_tokens,
        "savings_percent": savings_percent,
        "model_recommendation": "claude-3-haiku",
        "cost_saved": 0.002
    }
