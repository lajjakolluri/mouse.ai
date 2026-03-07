"""
Semantic Caching for Monse.AI
Finds similar queries and returns cached responses
"""

import hashlib
import json
import numpy as np
from sentence_transformers import SentenceTransformer
from sklearn.metrics.pairwise import cosine_similarity
from datetime import datetime
from typing import Optional, Dict, List

class SemanticCache:
    def __init__(self, redis_client, similarity_threshold=0.85):
        self.redis = redis_client
        self.threshold = similarity_threshold
        
        print("Loading sentence transformer model...")
        self.model = SentenceTransformer('all-MiniLM-L6-v2')
        print("✓ Model loaded!")
        
        self.cache_ttl = 3600 * 24 * 7  # 7 days
        
    def _get_query_text(self, messages: List[Dict]) -> str:
        return " ".join([m.get('content', '') for m in messages])
    
    def _create_embedding(self, text: str) -> np.ndarray:
        return self.model.encode(text)
    
    def find_similar(self, messages: List[Dict]) -> Optional[Dict]:
        query_text = self._get_query_text(messages)
        query_embedding = self._create_embedding(query_text)
        
        num_cached = int(self.redis.get('semantic_cache:count') or 0)
        
        if num_cached == 0:
            return None
        
        best_similarity = 0
        best_match_hash = None
        
        search_limit = min(100, num_cached)
        start_idx = max(0, num_cached - search_limit)
        
        for idx in range(start_idx, num_cached):
            cached_data = self.redis.get(f'semantic_cache:embedding:{idx}')
            if not cached_data:
                continue
            
            cached = json.loads(cached_data)
            cached_embedding = np.array(cached['embedding'])
            
            similarity = cosine_similarity(
                query_embedding.reshape(1, -1),
                cached_embedding.reshape(1, -1)
            )[0][0]
            
            if similarity > best_similarity:
                best_similarity = similarity
                best_match_hash = cached['hash']
        
        if best_similarity >= self.threshold:
            cached_response = self.redis.get(f'semantic_cache:response:{best_match_hash}')
            
            if cached_response:
                response_data = json.loads(cached_response)
                response_data['cache_hit'] = True
                response_data['similarity'] = float(best_similarity)
                
                print(f"✓ Cache HIT! Similarity: {best_similarity:.2%}")
                return response_data
        
        print(f"✗ Cache MISS. Best: {best_similarity:.2%}")
        return None
    
    def store(self, messages: List[Dict], response: Dict):
        query_text = self._get_query_text(messages)
        embedding = self._create_embedding(query_text)
        
        query_hash = hashlib.md5(query_text.encode()).hexdigest()
        
        self.redis.setex(
            f'semantic_cache:response:{query_hash}',
            self.cache_ttl,
            json.dumps(response)
        )
        
        num_cached = int(self.redis.get('semantic_cache:count') or 0)
        
        embedding_data = {
            'embedding': embedding.tolist(),
            'hash': query_hash,
            'query': query_text[:200],
            'timestamp': datetime.utcnow().isoformat()
        }
        
        self.redis.setex(
            f'semantic_cache:embedding:{num_cached}',
            self.cache_ttl,
            json.dumps(embedding_data)
        )
        
        self.redis.set('semantic_cache:count', num_cached + 1)
        print(f"✓ Stored in cache. Total: {num_cached + 1}")
