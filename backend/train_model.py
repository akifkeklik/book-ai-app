#!/usr/bin/env python3
"""
train_model.py — Standalone training & validation CLI for the Libris engine.

Usage:
    python train_model.py                        # train with defaults
    python train_model.py --csv data/books.csv   # custom CSV path
    python train_model.py --validate             # train + run quality checks
    python train_model.py --dry-run              # preview only, no save
    python train_model.py --force                # retrain even if pickle exists

This script delegates ALL ML logic to model/recommender.py so there is
exactly one source of truth for the recommendation engine.
"""

import argparse
import logging
import os
import sys
import time
from pathlib import Path

# ── Ensure the backend package is importable ──────────────────────────────────
# When run as `python train_model.py` from the backend/ directory, the parent
# package isn't on sys.path yet.
_BACKEND_DIR = Path(__file__).resolve().parent
if str(_BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(_BACKEND_DIR))

from config import Config
from model.recommender import BookRecommender

# ── Logging ───────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("train")

# ── ANSI colours for terminal output ─────────────────────────────────────────
_GREEN = "\033[92m"
_YELLOW = "\033[93m"
_RED = "\033[91m"
_CYAN = "\033[96m"
_BOLD = "\033[1m"
_RESET = "\033[0m"


def _banner(msg: str) -> None:
    width = max(len(msg) + 6, 50)
    logger.info("")
    logger.info(f"{_CYAN}{'═' * width}{_RESET}")
    logger.info(f"{_CYAN}║  {_BOLD}{msg}{_RESET}{_CYAN}{' ' * (width - len(msg) - 5)}║{_RESET}")
    logger.info(f"{_CYAN}{'═' * width}{_RESET}")


# ── Validation suite ─────────────────────────────────────────────────────────

_VALIDATION_QUERIES = [
    # (query_title, expected_genre_keywords, min_expected_results)
    ("Dune", ["science fiction", "sci-fi", "fiction"], 3),
    ("Harry Potter and the Sorcerer's Stone", ["fantasy", "young adult"], 3),
    ("The Great Gatsby", ["fiction", "classic"], 3),
    ("Atomic Habits", ["self-help", "self help"], 2),
    ("1984", ["dystopian", "fiction"], 3),
]


def _validate(engine: BookRecommender) -> bool:
    """
    Run a battery of sanity checks on the trained model.
    Returns True if all critical checks pass.
    """
    _banner("VALIDATION")
    passed = 0
    failed = 0
    warnings = 0

    # ── Check 1: Dataset integrity ────────────────────────────────────────────
    logger.info(f"\n{_BOLD}[Check 1] Dataset Integrity{_RESET}")
    n_books = len(engine.df)
    n_with_desc = (engine.df["description"].str.len() > 10).sum()
    n_with_cover = (engine.df["thumbnail"].str.len() > 5).sum()
    n_with_rating = (engine.df["average_rating"] > 0).sum()

    desc_pct = n_with_desc / n_books * 100
    cover_pct = n_with_cover / n_books * 100
    rating_pct = n_with_rating / n_books * 100

    logger.info(f"  Total books     : {_BOLD}{n_books}{_RESET}")
    logger.info(f"  With description: {n_with_desc} ({desc_pct:.0f}%)")
    logger.info(f"  With cover URL  : {n_with_cover} ({cover_pct:.0f}%)")
    logger.info(f"  With rating > 0 : {n_with_rating} ({rating_pct:.0f}%)")

    if n_books < 10:
        logger.warning(f"  {_RED}✗ Too few books ({n_books}). Need ≥10 for meaningful recs.{_RESET}")
        failed += 1
    else:
        logger.info(f"  {_GREEN}✓ Dataset size OK{_RESET}")
        passed += 1

    if desc_pct < 50:
        logger.warning(f"  {_YELLOW}⚠ Only {desc_pct:.0f}% have descriptions — recs quality may suffer{_RESET}")
        warnings += 1

    # ── Check 2: TF-IDF matrix ────────────────────────────────────────────────
    logger.info(f"\n{_BOLD}[Check 2] TF-IDF Matrix{_RESET}")
    n_features = engine.tfidf_matrix.shape[1]
    sparsity = 1.0 - (engine.tfidf_matrix.nnz / (engine.tfidf_matrix.shape[0] * engine.tfidf_matrix.shape[1]))

    logger.info(f"  Shape    : {engine.tfidf_matrix.shape}")
    logger.info(f"  Features : {n_features:,}")
    logger.info(f"  Sparsity : {sparsity:.2%}")
    logger.info(f"  {_GREEN}✓ Matrix built successfully{_RESET}")
    passed += 1

    # ── Check 3: Cosine similarity sanity ─────────────────────────────────────
    logger.info(f"\n{_BOLD}[Check 3] Cosine Similarity Matrix{_RESET}")
    diag = engine.cosine_sim.diagonal()
    diag_ok = all(abs(d - 1.0) < 1e-6 for d in diag)

    if diag_ok:
        logger.info(f"  {_GREEN}✓ Diagonal is all 1.0 (self-similarity correct){_RESET}")
        passed += 1
    else:
        logger.error(f"  {_RED}✗ Diagonal values are wrong — model may be corrupt{_RESET}")
        failed += 1

    avg_sim = engine.cosine_sim[engine.cosine_sim < 0.9999].mean()
    logger.info(f"  Avg pairwise similarity: {avg_sim:.4f}")

    if avg_sim > 0.8:
        logger.warning(f"  {_YELLOW}⚠ Avg similarity very high — features may lack diversity{_RESET}")
        warnings += 1

    # ── Check 4: Recommendation quality ───────────────────────────────────────
    logger.info(f"\n{_BOLD}[Check 4] Recommendation Quality{_RESET}")

    for title, expected_genres, min_results in _VALIDATION_QUERIES:
        recs = engine.recommend(title, top_n=5, use_hybrid=True)

        if not recs:
            # Book might not be in dataset — just warn
            logger.info(f"  '{title}': {_YELLOW}not in dataset — skipped{_RESET}")
            continue

        n_recs = len(recs)
        top_rec = recs[0]["title"]
        top_score = recs[0].get("similarity_score", 0)

        # Check genre relevance: do any rec categories match expected?
        genre_matches = 0
        for rec in recs:
            rec_cats = rec.get("categories", "").lower()
            if any(g in rec_cats for g in expected_genres):
                genre_matches += 1

        genre_pct = genre_matches / n_recs * 100 if n_recs else 0

        status = _GREEN + "✓" if genre_pct >= 40 else (_YELLOW + "⚠" if genre_pct >= 20 else _RED + "✗")

        logger.info(
            f"  '{title}' → {n_recs} recs, "
            f"top='{top_rec}' ({top_score:.2f}), "
            f"genre hit={genre_pct:.0f}% "
            f"{status}{_RESET}"
        )

        if n_recs >= min_results:
            passed += 1
        else:
            failed += 1

    # ── Check 5: Search functionality ─────────────────────────────────────────
    logger.info(f"\n{_BOLD}[Check 5] Search Engine{_RESET}")
    for query in ["tolkien", "science fiction", "harry"]:
        results = engine.search_books(query, limit=5)
        logger.info(f"  search('{query}') → {len(results)} results")
        if results:
            passed += 1
        else:
            logger.warning(f"  {_YELLOW}⚠ No results for '{query}'{_RESET}")
            warnings += 1

    # ── Check 6: Popular books ────────────────────────────────────────────────
    logger.info(f"\n{_BOLD}[Check 6] Popularity Ranking{_RESET}")
    popular = engine.get_popular_books(limit=5)
    if popular:
        top_popular = popular[0]
        logger.info(
            f"  #1 popular: '{top_popular['title']}' "
            f"(rating={top_popular['average_rating']}, "
            f"count={top_popular['ratings_count']:,})"
        )
        logger.info(f"  {_GREEN}✓ Popularity ranking working{_RESET}")
        passed += 1
    else:
        logger.error(f"  {_RED}✗ Popular books returned empty{_RESET}")
        failed += 1

    # ── Check 7: ISBN lookup ──────────────────────────────────────────────────
    logger.info(f"\n{_BOLD}[Check 7] ISBN Lookup{_RESET}")
    sample_isbn = str(engine.df.iloc[0]["isbn13"])
    result = engine.get_book_by_isbn(sample_isbn)
    if result:
        logger.info(f"  ISBN {sample_isbn} → '{result['title']}' {_GREEN}✓{_RESET}")
        passed += 1
    else:
        logger.error(f"  {_RED}✗ ISBN lookup failed for {sample_isbn}{_RESET}")
        failed += 1

    # ── Summary ───────────────────────────────────────────────────────────────
    total = passed + failed
    logger.info(f"\n{'─' * 50}")
    logger.info(
        f"  {_BOLD}Results: "
        f"{_GREEN}{passed} passed{_RESET}, "
        f"{_RED}{failed} failed{_RESET}, "
        f"{_YELLOW}{warnings} warnings{_RESET}"
    )

    if failed == 0:
        logger.info(f"  {_GREEN}{_BOLD}✓ ALL CHECKS PASSED{_RESET}")
    else:
        logger.info(f"  {_RED}{_BOLD}✗ {failed}/{total} CHECKS FAILED{_RESET}")

    logger.info(f"{'─' * 50}\n")
    return failed == 0


# ── Main entry ────────────────────────────────────────────────────────────────

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Train and validate the Libris recommendation model.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python train_model.py                       # train with defaults
  python train_model.py --validate            # train + run quality checks
  python train_model.py --csv my_books.csv    # custom dataset
  python train_model.py --dry-run             # preview data, don't save
  python train_model.py --force --validate    # retrain even if pickle exists
        """,
    )
    parser.add_argument(
        "--csv",
        default=Config.DATA_PATH,
        help=f"Path to books CSV (default: {Config.DATA_PATH})",
    )
    parser.add_argument(
        "--output",
        default=Config.MODEL_PATH,
        help=f"Output pickle path (default: {Config.MODEL_PATH})",
    )
    parser.add_argument(
        "--validate", "-v",
        action="store_true",
        help="Run validation checks after training",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Load and preprocess data but don't save the model",
    )
    parser.add_argument(
        "--force", "-f",
        action="store_true",
        help="Retrain even if a saved pickle already exists",
    )
    args = parser.parse_args()

    # ── Pre-flight checks ─────────────────────────────────────────────────────
    if not os.path.exists(args.csv):
        logger.error(f"{_RED}CSV not found: {args.csv}{_RESET}")
        logger.error("  Make sure data/books.csv exists or pass --csv <path>")
        return 1

    if os.path.exists(args.output) and not args.force and not args.dry_run:
        logger.info(f"{_YELLOW}Model already exists at {args.output}{_RESET}")
        logger.info("  Use --force to retrain, or delete the file manually.")
        logger.info("  Use --validate to run checks on the existing model.")

        if args.validate:
            engine = BookRecommender()
            if engine.load_model(args.output):
                ok = _validate(engine)
                return 0 if ok else 1
            else:
                logger.error("Failed to load existing model.")
                return 1
        return 0

    # ── Training ──────────────────────────────────────────────────────────────
    _banner("Libris Model Training")

    engine = BookRecommender()

    # Step 1: Load
    logger.info(f"\n{_BOLD}Step 1/3 — Loading dataset{_RESET}")
    t0 = time.perf_counter()
    engine.load_data(args.csv)
    t_load = time.perf_counter() - t0
    logger.info(f"  Loaded {len(engine.df)} books in {t_load:.2f}s")

    # Step 2: Fit
    logger.info(f"\n{_BOLD}Step 2/3 — Training TF-IDF + Cosine Similarity{_RESET}")
    t0 = time.perf_counter()
    save_path = None if args.dry_run else args.output
    engine.fit(save_path=save_path)
    t_train = time.perf_counter() - t0
    logger.info(f"  Training completed in {t_train:.2f}s")

    if args.dry_run:
        logger.info(f"\n{_YELLOW}Dry run — model NOT saved.{_RESET}")
    else:
        size_kb = os.path.getsize(args.output) / 1024
        logger.info(f"  Model saved → {args.output} ({size_kb:.0f} KB)")

    # Step 3: Summary
    logger.info(f"\n{_BOLD}Step 3/3 — Summary{_RESET}")
    logger.info(f"  Books         : {len(engine.df)}")
    logger.info(f"  TF-IDF shape  : {engine.tfidf_matrix.shape}")
    logger.info(f"  Vocab size    : {len(engine.vectorizer.vocabulary_):,}")
    logger.info(f"  Total time    : {t_load + t_train:.2f}s")

    # ── Validation (optional) ─────────────────────────────────────────────────
    if args.validate:
        ok = _validate(engine)
        return 0 if ok else 1

    logger.info(f"\n{_GREEN}{_BOLD}✓ Done!{_RESET} Run with --validate to check quality.\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())