
import time
import numpy as np
import pandas as pd
from typing import List, Dict, Any
from sklearn.metrics.pairwise import cosine_similarity

# Backend imports
import sys
from pathlib import Path
_BACKEND_DIR = Path(__file__).resolve().parent.parent
if str(_BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(_BACKEND_DIR))

from backend.recommender import BookRecommender
from utils.preprocess import preprocess_dataframe

def calculate_jaccard(list1: List[str], list2: List[str]) -> float:
    s1, s2 = set(list1), set(list2)
    return len(s1 & s2) / len(s1 | s2) if len(s1 | s2) > 0 else 0.0

def calculate_diversity(books: List[Dict[str, Any]], recommender: BookRecommender) -> float:
    if len(books) < 2: return 0.0
    titles = [b["title"] for b in books]
    indices = [recommender.engine.find_index(t) for t in titles if recommender.engine.find_index(t) is not None]
    if not indices: return 0.0
    
    vectors = recommender.engine.tfidf_matrix[indices].toarray()
    sim_matrix = cosine_similarity(vectors)
    
    # Average of upper triangle (excluding diagonal)
    triu_indices = np.triu_indices(len(indices), k=1)
    if triu_indices[0].size == 0: return 0.0
    return np.mean(sim_matrix[triu_indices])

def run_audit():
    print("=== BookAI SYSTEM AUDIT DIAGNOSTICS ===")
    
    # 1. Setup Mock Data
    # Adding more diverse items for better failure analysis
    sample_data = [
        {"isbn13": "1", "title": "Dune", "authors": "Frank Herbert", "categories": "Sci-Fi", "description": "Desert planet", "ratings_count": 1000, "page_count": 500, "published_date": "1965", "average_rating": 4.5, "thumbnail": ""},
        {"isbn13": "2", "title": "1984", "authors": "George Orwell", "categories": "Sci-Fi|Dystopian", "description": "Big Brother", "ratings_count": 900, "page_count": 300, "published_date": "1949", "average_rating": 4.4, "thumbnail": ""},
        {"isbn13": "3", "title": "Harry Potter 1", "authors": "J.K. Rowling", "categories": "Fantasy", "description": "Wizard boy", "ratings_count": 2000, "page_count": 300, "published_date": "1997", "average_rating": 4.8, "thumbnail": ""},
        {"isbn13": "4", "title": "Harry Potter 2", "authors": "J.K. Rowling", "categories": "Fantasy", "description": "Chamber secrets", "ratings_count": 1800, "page_count": 350, "published_date": "1998", "average_rating": 4.7, "thumbnail": ""},
        {"isbn13": "5", "title": "Foundation", "authors": "Isaac Asimov", "categories": "Sci-Fi", "description": "Galactic empire", "ratings_count": 800, "page_count": 250, "published_date": "1951", "average_rating": 4.2, "thumbnail": ""},
        {"isbn13": "6", "title": "The Hobbit", "authors": "Tolkien", "categories": "Fantasy", "description": "Bilbo journey", "ratings_count": 1500, "page_count": 300, "published_date": "1937", "average_rating": 4.6, "thumbnail": ""},
        {"isbn13": "7", "title": "Neuromancer", "authors": "William Gibson", "categories": "Sci-Fi|Cyberpunk", "description": "Cyber hacker", "ratings_count": 600, "page_count": 270, "published_date": "1984", "average_rating": 4.0, "thumbnail": ""},
        {"isbn13": "8", "title": "Brave New World", "authors": "Aldous Huxley", "categories": "Sci-Fi|Dystopian", "description": "Future society", "ratings_count": 750, "page_count": 280, "published_date": "1932", "average_rating": 4.1, "thumbnail": ""},
        {"isbn13": "9", "title": "Pride and Prejudice", "authors": "Jane Austen", "categories": "Romance|Classic", "description": "Elizabeth Darcy", "ratings_count": 1200, "page_count": 400, "published_date": "1813", "average_rating": 4.5, "thumbnail": ""},
        {"isbn13": "10", "title": "Sense and Sensibility", "authors": "Jane Austen", "categories": "Romance|Classic", "description": "Dashwood sisters", "ratings_count": 1100, "page_count": 380, "published_date": "1811", "average_rating": 4.4, "thumbnail": ""},
        {"isbn13": "11", "title": "The Martian", "authors": "Andy Weir", "categories": "Sci-Fi", "description": "Survivor on Mars", "ratings_count": 1300, "page_count": 400, "published_date": "2011", "average_rating": 4.4, "thumbnail": ""},
        {"isbn13": "12", "title": "Project Hail Mary", "authors": "Andy Weir", "categories": "Sci-Fi", "description": "Space mission", "ratings_count": 1400, "page_count": 450, "published_date": "2021", "average_rating": 4.7, "thumbnail": ""},
        {"isbn13": "13", "title": "Cooking for Dummies", "authors": "Chef", "categories": "Cooking", "description": "How to cook", "ratings_count": 100, "page_count": 150, "published_date": "2005", "average_rating": 3.0, "thumbnail": ""},
    ]
    
    recommender = BookRecommender()
    df = pd.DataFrame(sample_data)
    recommender.engine.df = preprocess_dataframe(df)
    recommender.fit()
    
    # Check seed indices resolution
    print(f"Debug: 'Dune' index: {recommender.engine.find_index('Dune')}")
    print(f"Debug: 'Harry Potter 1' index: {recommender.engine.find_index('Harry Potter 1')}")

    # EDGE CASE A: Empty user profile
    print("\nCase A: Empty user profile")
    recs_a = recommender.recommend([], top_n=5)
    print(f"  Result count: {len(recs_a)}")
    print(f"  Fallback titles: {[r['title'] for r in recs_a]}")

    # EDGE CASE B: Single preference
    print("\nCase B: Single preference ('Dune')")
    recs_b = recommender.recommend(["Dune"], top_n=5)
    print(f"  Result titles: {[r['title'] for r in recs_b]}")
    # Verify 'Dune' is not in results
    assert "Dune" not in [r['title'] for r in recs_b], "CRITICAL: Seed book found in recommendations!"

    # EDGE CASE C: Large preference set
    print("\nCase C: Large preference set (6 books)")
    seeds_c = ["Dune", "1984", "Foundation", "Neuromancer", "Brave New World", "The Martian"]
    recs_c = recommender.recommend(seeds_c, top_n=5)
    print(f"  Result titles: {[r['title'] for r in recs_c]}")

    # EDGE CASE D: Same-genre bias (Fantasy)
    print("\nCase D: Same-genre bias (Fantasy)")
    seeds_d = ["Harry Potter 1", "Harry Potter 2", "The Hobbit"]
    recs_d = recommender.recommend(seeds_d, top_n=5, use_diversity=True)
    print(f"  Result titles: {[r['title'] for r in recs_d]}")
    non_fantasy = [r['title'] for r in recs_d if "Fantasy" not in r.get("categories", "")]
    print(f"  Non-fantasy included: {non_fantasy}")

    # PERSONALIZATION: User A vs User B
    print("\nPersonalization Audit")
    user_a_seeds = ["Dune", "1984"]
    user_b_seeds = ["Harry Potter 1", "The Hobbit"]
    recs_user_a = [r['title'] for r in recommender.recommend(user_a_seeds, top_n=5)]
    recs_user_b = [r['title'] for r in recommender.recommend(user_b_seeds, top_n=5)]
    jaccard = calculate_jaccard(recs_user_a, recs_user_b)
    print(f"  Jaccard Similarity: {jaccard:.4f} (Goal < 0.5)")

    # DIVERSITY: Average pairwise cosine similarity
    print("\nDiversity Audit")
    div_score = calculate_diversity(recs_d, recommender)
    print(f"  Average Pairwise Similarity: {div_score:.4f}")

    # FEEDBACK LOOP: Centroid Shift
    print("\nFeedback Loop Audit")
    # Before
    idx_dune = recommender.engine.find_index("Dune")
    vec1 = recommender.engine.tfidf_matrix[idx_dune].toarray()
    # After adding '1984'
    idx_1984 = recommender.engine.find_index("1984")
    vec2 = recommender.engine.tfidf_matrix[[idx_dune, idx_1984]].mean(axis=0)
    vec2_arr = np.asarray(vec2)
    shift = np.linalg.norm(vec1 - vec2_arr)
    print(f"  Centroid Euclidean Shift: {shift:.4f}")

    # PERFORMANCE: Benchmarking
    print("\nPerformance Audit")
    t0 = time.perf_counter()
    for _ in range(100):
        recommender.recommend(["Dune", "1984"], top_n=10)
    avg_time = (time.perf_counter() - t0) / 100 * 1000 # ms
    print(f"  Avg Recommendation Time: {avg_time:.2f}ms (Goal < 500ms)")

    # FAILURE ANALYSIS: Identification of 5 "bad" scores
    print("\nFailure Case Analysis (User A)")
    # We want to find cases where a completely unrelated book (e.g. Cooking) appears
    seeds_f = ["Dune", "1984"]
    all_recs = recommender.recommend(seeds_f, top_n=10)
    for i, r in enumerate(all_recs[:5]):
        print(f"  {i+1}. {r['title']} (Score: {r['final_score']}, Penalty: {r['diversity_penalty']})")
        print(f"     Explanation: {r['explanation']} (Source: {r['explanation_source_book']})")
        hallucinated = r['explanation_source_book'] not in seeds_f
        print(f"     Hallucination Detected: {hallucinated}")

run_audit()
