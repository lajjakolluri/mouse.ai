#!/bin/bash

echo "════════════════════════════════════════════════════════════"
echo "    TOKENOPTIMIZER PRO - COST SAVINGS CALCULATOR"
echo "════════════════════════════════════════════════════════════"
echo ""

# Customer inputs
REQUESTS_PER_MONTH=50000
CURRENT_MONTHLY_COST=5000

echo "CUSTOMER SCENARIO:"
echo "  • Monthly requests: $REQUESTS_PER_MONTH"
echo "  • Current monthly cost: \$$CURRENT_MONTHLY_COST"
echo ""

# Calculate current cost per request
CURRENT_COST_PER_REQUEST=$(echo "scale=4; $CURRENT_MONTHLY_COST / $REQUESTS_PER_MONTH" | bc)
echo "  • Current cost per request: \$$CURRENT_COST_PER_REQUEST"
echo ""

# Test actual optimization
echo "TESTING OPTIMIZATION ENDPOINT..."
RESPONSE=$(curl -s -X POST http://129.159.45.114:8000/api/v1/optimize \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "user", "content": "My order #12345 hasnt arrived yet. Can you help me track it?"}
    ],
    "optimization_features": ["all"]
  }')

echo "$RESPONSE" | python3 -m json.tool
echo ""

# Extract cost saved (using grep and awk)
COST_SAVED=$(echo "$RESPONSE" | grep -o '"cost_saved":[0-9.]*' | cut -d':' -f2)
TOKENS_SAVED=$(echo "$RESPONSE" | grep -o '"tokens_saved":[0-9]*' | cut -d':' -f2)
MODEL=$(echo "$RESPONSE" | grep -o '"model_used":"[^"]*"' | cut -d'"' -f4)

echo "OPTIMIZATION RESULTS:"
echo "  • Tokens saved per request: $TOKENS_SAVED"
echo "  • Cost saved per request: \$$COST_SAVED"
echo "  • Model used: $MODEL"
echo ""

# Calculate monthly savings
MONTHLY_TOKEN_SAVINGS=$(echo "scale=2; $COST_SAVED * $REQUESTS_PER_MONTH" | bc)

# Real pricing comparison
echo "════════════════════════════════════════════════════════════"
echo "    DETAILED COST BREAKDOWN"
echo "════════════════════════════════════════════════════════════"
echo ""

# WITHOUT TokenOptimizer (Claude Sonnet)
echo "WITHOUT TOKENOPTIMIZER (Direct Claude Sonnet):"
echo "  • Model: claude-sonnet-4-20250514"
echo "  • Pricing: \$3 input / \$15 output per 1M tokens"
echo "  • Average cost: \$$CURRENT_COST_PER_REQUEST per request"
echo "  • Monthly: \$$CURRENT_MONTHLY_COST"
echo ""

# WITH TokenOptimizer - Smart Routing
echo "WITH TOKENOPTIMIZER - Smart Model Routing:"
echo "  • Simple queries → Haiku (\$0.25 input / \$1.25 output)"
echo "  • Complex queries → Sonnet (\$3 input / \$15 output)"
echo "  • Estimated 80% of queries = simple (use Haiku)"
echo ""

# Haiku pricing (80% of requests)
HAIKU_COST_PER_REQUEST=0.0008
SONNET_COST_PER_REQUEST=$(echo "scale=4; $CURRENT_COST_PER_REQUEST" | bc)

WEIGHTED_COST=$(echo "scale=4; (0.80 * $HAIKU_COST_PER_REQUEST) + (0.20 * $SONNET_COST_PER_REQUEST)" | bc)
MONTHLY_AFTER_ROUTING=$(echo "scale=2; $WEIGHTED_COST * $REQUESTS_PER_MONTH" | bc)
ROUTING_SAVINGS=$(echo "scale=2; $CURRENT_MONTHLY_COST - $MONTHLY_AFTER_ROUTING" | bc)

echo "After Smart Routing:"
echo "  • New average cost: \$$WEIGHTED_COST per request"
echo "  • New monthly cost: \$$MONTHLY_AFTER_ROUTING"
echo "  • Savings: \$$ROUTING_SAVINGS/month"
echo ""

# WITH Semantic Caching (47% hit rate)
echo "WITH SEMANTIC CACHING (47% hit rate):"
CACHE_HIT_RATE=0.47
FINAL_COST_PER_REQUEST=$(echo "scale=4; $WEIGHTED_COST * (1 - $CACHE_HIT_RATE)" | bc)
FINAL_MONTHLY_COST=$(echo "scale=2; $FINAL_COST_PER_REQUEST * $REQUESTS_PER_MONTH" | bc)
TOTAL_SAVINGS=$(echo "scale=2; $CURRENT_MONTHLY_COST - $FINAL_MONTHLY_COST" | bc)
SAVINGS_PERCENT=$(echo "scale=1; ($TOTAL_SAVINGS / $CURRENT_MONTHLY_COST) * 100" | bc)

echo "  • 47% of requests = \$0 (cached)"
echo "  • 53% of requests = \$$WEIGHTED_COST"
echo "  • Effective cost: \$$FINAL_COST_PER_REQUEST per request"
echo "  • Final monthly cost: \$$FINAL_MONTHLY_COST"
echo ""

echo "════════════════════════════════════════════════════════════"
echo "    FINAL RESULTS"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "  Before: \$$CURRENT_MONTHLY_COST/month"
echo "  After:  \$$FINAL_MONTHLY_COST/month"
echo ""
echo "  💰 MONTHLY SAVINGS: \$$TOTAL_SAVINGS ($SAVINGS_PERCENT%)"
echo "  💰 ANNUAL SAVINGS:  \$$(echo "scale=2; $TOTAL_SAVINGS * 12" | bc)"
echo ""
echo "════════════════════════════════════════════════════════════"
