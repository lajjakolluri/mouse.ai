"""
Prompt Optimization for Monse.AI
Removes unnecessary words to reduce token usage
Saves 15-30% on input tokens!
"""

import re
from typing import List, Dict

class PromptOptimizer:
    def __init__(self):
        # Words to remove (filler words that don't change meaning)
        self.filler_words = [
            'please', 'could you', 'can you', 'would you',
            'i would like', 'i want to', 'i need to',
            'kindly', 'if possible', 'if you can',
            'thank you', 'thanks', 'appreciate it'
        ]
        
        # Phrases to simplify
        self.simplifications = {
            'could you please': '',
            'can you please': '',
            'would you mind': '',
            'i would like you to': '',
            'i want you to': '',
            'explain to me': 'explain',
            'tell me about': 'explain',
            'describe for me': 'describe',
            'give me information about': 'explain',
            'provide me with': 'provide',
            'help me understand': 'explain',
            'in simple terms': 'simply',
            'in a way that is easy to understand': 'simply'
        }
    
    def optimize(self, text: str) -> tuple[str, int, int]:
        """
        Optimize a prompt by removing unnecessary words
        
        Returns:
            (optimized_text, original_length, optimized_length)
        """
        original = text
        original_tokens = self._estimate_tokens(original)
        
        # Convert to lowercase for matching (preserve original case)
        text_lower = text.lower()
        optimized = text
        
        # Apply simplifications
        for phrase, replacement in self.simplifications.items():
            pattern = re.compile(re.escape(phrase), re.IGNORECASE)
            optimized = pattern.sub(replacement, optimized)
        
        # Remove filler words
        for filler in self.filler_words:
            pattern = re.compile(r'\b' + re.escape(filler) + r'\b', re.IGNORECASE)
            optimized = pattern.sub('', optimized)
        
        # Clean up extra spaces
        optimized = re.sub(r'\s+', ' ', optimized)
        optimized = optimized.strip()
        
        # Capitalize first letter
        if optimized:
            optimized = optimized[0].upper() + optimized[1:]
        
        optimized_tokens = self._estimate_tokens(optimized)
        
        return optimized, original_tokens, optimized_tokens
    
    def optimize_messages(self, messages: List[Dict]) -> tuple[List[Dict], int]:
        """
        Optimize all messages in a conversation
        
        Returns:
            (optimized_messages, total_tokens_saved)
        """
        optimized_messages = []
        total_saved = 0
        
        for msg in messages:
            if msg.get('role') == 'user' and 'content' in msg:
                optimized_content, orig_tokens, opt_tokens = self.optimize(msg['content'])
                
                optimized_messages.append({
                    'role': msg['role'],
                    'content': optimized_content
                })
                
                tokens_saved = orig_tokens - opt_tokens
                total_saved += tokens_saved
                
                if tokens_saved > 0:
                    print(f"  Optimized: '{msg['content'][:50]}...' → saved {tokens_saved} tokens")
            else:
                optimized_messages.append(msg)
        
        return optimized_messages, total_saved
    
    def _estimate_tokens(self, text: str) -> int:
        """
        Estimate token count (rough approximation)
        Real: ~4 chars per token for English
        """
        return len(text.split())  # Simple word count approximation
    
    def get_stats(self) -> Dict:
        """Get optimizer statistics"""
        return {
            'filler_words_count': len(self.filler_words),
            'simplifications_count': len(self.simplifications)
        }


# Example usage and testing
if __name__ == "__main__":
    optimizer = PromptOptimizer()
    
    test_prompts = [
        "Could you please explain to me what artificial intelligence is?",
        "I would like you to tell me about machine learning",
        "Can you help me understand deep learning in simple terms?",
        "Please provide me with information about neural networks"
    ]
    
    print("=== PROMPT OPTIMIZATION TEST ===\n")
    
    for prompt in test_prompts:
        optimized, orig, opt = optimizer.optimize(prompt)
        saved = orig - opt
        pct = (saved / orig * 100) if orig > 0 else 0
        
        print(f"Original:  {prompt}")
        print(f"Optimized: {optimized}")
        print(f"Tokens: {orig} → {opt} (saved {saved}, {pct:.1f}%)")
        print()
