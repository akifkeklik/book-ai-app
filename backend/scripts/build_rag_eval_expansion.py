"""
Builds backend/evaluation/data/rag_eval_expansion.json: the expansion of the live RAG evaluation set
(data/rag_eval_tr_en.json, 44 queries) to cover every query category in English and Turkish.

    python -m backend.scripts.build_rag_eval_expansion          # (re)write the dataset
    python -m backend.scripts.build_rag_eval_expansion --check  # exit 1 if the file is out of date

Every expected set is computed from the catalog snapshot (backend/data/books.csv) by the machine
rule stored next to it, so the file is reproducible and every ISBN is a real catalog record.
None of these labels has been reviewed by a person: every query is `label_tier:
automatic_candidate`. Rules are deliberately simple (title / author / category / description /
page-count / year filters); they over- and under-include, which is why review is required before
any of these numbers is quoted as ground truth. Offline only: no network, no Gemini.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Dict, List

import pandas as pd

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))

from backend.evaluation.retrieval import CATALOG_CSV  # noqa: E402
from backend.utils.preprocess import normalize_isbn  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), "..", "evaluation", "data", "rag_eval_expansion.json")
DATASET_VERSION = "expansion-v1"
TIER = "automatic_candidate"

# Every category the combined dataset covers. Categories of the original 44 queries are derived
# from their `type` (see run_rag_quality_eval.TYPE_TO_CATEGORY).
CATEGORIES = {
    "exact_title": "The user names the book (known item); any edition is a hit.",
    "author": "Books by a named author.",
    "genre": "Discovery within a genre.",
    "topic": "Discovery by subject matter.",
    "semantic_description": "The plot or idea is described without the title (known item).",
    "multi_constraint": "Two or more constraints at once (author/genre plus length or period).",
    "mood": "A mood or reading preference instead of a subject.",
    "similar": "Books like a named book.",
    "ambiguous": "Under-specified taste request; no fixed relevant set.",
    "insufficient_info": "Not enough information to identify any book; the system should not invent one.",
    "no_relevant": "A real book/author/subject the catalog does not hold; the system must say so, not substitute.",
}

# Expected behaviour of the answer, checked after a live run (see run_rag_quality_eval).
BEHAVIOURS = {
    "retrieve_relevant": "Return catalog books from the expected set.",
    "open_judgment": "Return plausible catalog books; judged by hand, not scored.",
    "no_fabrication": "Do not invent a specific book; ask for detail or offer a broad, honest suggestion.",
    "abstain_not_in_catalog": "State that the requested work/author is not in the catalog; do not present another book as it.",
}

# (intent, category, difficulty, behaviour, en text, tr text, rule, single_work)
INTENTS: List[dict] = [
    # ── exact_title ──
    dict(intent="title_pride", category="exact_title", difficulty="easy",
         en="Pride and Prejudice by Jane Austen", tr="Jane Austen'ın Aşk ve Gurur romanı",
         rule={"title": r"^Pride and Prejudice$", "author": ["Austen"]}, single_work=True),
    dict(intent="title_fahrenheit", category="exact_title", difficulty="easy",
         en="Fahrenheit 451", tr="Ray Bradbury Fahrenheit 451",
         rule={"title": r"^Fahrenheit 451$"}, single_work=True),
    dict(intent="title_rose", category="exact_title", difficulty="easy",
         en="The Name of the Rose by Umberto Eco", tr="Umberto Eco'nun Gülün Adı kitabı",
         rule={"title": r"^The Name of the Rose$", "author": ["Umberto Eco"]}, single_work=True),
    dict(intent="title_kite", category="exact_title", difficulty="easy",
         en="The Kite Runner", tr="Uçurtma Avcısı romanı",
         rule={"title": r"^The Kite Runner$"}, single_work=True),
    dict(intent="title_handmaid", category="exact_title", difficulty="easy",
         en="The Handmaid's Tale", tr="Margaret Atwood Damızlık Kızın Öyküsü",
         rule={"title": r"^The Handmaid's Tale$"}, single_work=True),
    dict(intent="title_little_prince", category="exact_title", difficulty="medium",
         en="The Little Prince by Saint-Exupéry", tr="Küçük Prens kitabı",
         rule={"title": r"^The Little Prince$"}, single_work=True),
    # ── author ──
    dict(intent="author_king", category="author", difficulty="easy",
         en="Stephen King novels", tr="Stephen King romanları",
         rule={"author": ["Stephen King"]}),
    dict(intent="author_pratchett", category="author", difficulty="easy",
         en="Books by Terry Pratchett", tr="Terry Pratchett'ın kitapları",
         rule={"author": ["Terry Pratchett"]}),
    dict(intent="author_woolf", category="author", difficulty="medium",
         en="Something by Virginia Woolf", tr="Virginia Woolf'un eserleri",
         rule={"author": ["Virginia Woolf"]}),
    dict(intent="author_asimov", category="author", difficulty="easy",
         en="Isaac Asimov books", tr="Isaac Asimov kitapları",
         rule={"author": ["Isaac Asimov"]}),
    # ── genre ──
    dict(intent="genre_poetry", category="genre", difficulty="medium",
         en="Poetry collections", tr="Şiir kitapları",
         rule={"category": ["Poetry"]}),
    dict(intent="genre_comics", category="genre", difficulty="medium",
         en="Graphic novels and comics", tr="Çizgi roman ve grafik roman önerileri",
         rule={"category": ["Comics & Graphic Novels"]}),
    dict(intent="genre_cooking", category="genre", difficulty="easy",
         en="Cookbooks", tr="Yemek kitapları",
         rule={"category": ["Cooking"]}),
    dict(intent="genre_scifi", category="genre", difficulty="medium",
         en="Science fiction novels", tr="Bilim kurgu romanları",
         rule={"category": ["Science Fiction"]}),
    # ── topic ──
    dict(intent="topic_cosmology", category="topic", difficulty="medium",
         en="Books explaining the universe and the Big Bang", tr="Evreni ve Büyük Patlama'yı anlatan kitaplar",
         rule={"category": ["Cosmology", "Science"],
               "description": r"\b(?:big bang|cosmolog|origin of the universe|expanding universe|the universe)"}),
    dict(intent="topic_wwii", category="topic", difficulty="medium",
         en="History of the Second World War", tr="İkinci Dünya Savaşı tarihi",
         rule={"category": ["History"], "description": r"(?:world war ii|second world war|world war two)"}),
    dict(intent="topic_buddhism", category="topic", difficulty="hard",
         en="An introduction to Buddhism", tr="Budizme giriş kitabı",
         rule={"category": ["Religion", "Philosophy", "Body, Mind & Spirit"], "description": r"\bbuddhis"}),
    # ── semantic_description ──
    dict(intent="desc_moby", category="semantic_description", difficulty="medium",
         en="A sea captain obsessed with hunting a white whale",
         tr="Beyaz bir balinayı avlamaya takıntılı bir kaptan",
         rule={"title": r"^Moby[- ]Dick", "author": ["Melville"]}, single_work=True),
    dict(intent="desc_frankenstein", category="semantic_description", difficulty="medium",
         en="A scientist builds a living creature and is horrified by it",
         tr="Bir bilim insanının yarattığı canlı yaratıktan dehşete düşmesi",
         rule={"title": r"^Frankenstein(?:, Or|$)", "author": ["Shelley"]}, single_work=True),
    dict(intent="desc_road", category="semantic_description", difficulty="hard",
         en="A father and his son walk through a burned, post-apocalyptic America",
         tr="Kıyamet sonrası yanmış Amerika'da yürüyen bir baba ve oğlu",
         rule={"title": r"^The Road$", "author": ["Cormac McCarthy"]}, single_work=True),
    dict(intent="desc_dracula", category="semantic_description", difficulty="easy",
         en="The Transylvanian count who is a vampire",
         tr="Vampir olan Transilvanyalı kont",
         rule={"title": r"^Dracula$", "author": ["Bram Stoker"]}, single_work=True),
    dict(intent="desc_flies", category="semantic_description", difficulty="medium",
         en="Schoolboys stranded on an island turn savage",
         tr="Bir adada mahsur kalan okul çocuklarının vahşileşmesi",
         rule={"title": r"^Lord of the Flies$"}, single_work=True),
    # ── multi_constraint ──
    dict(intent="multi_king_short", category="multi_constraint", difficulty="hard",
         en="A Stephen King book under 300 pages", tr="300 sayfadan kısa bir Stephen King kitabı",
         rule={"author": ["Stephen King"], "max_pages": 299}),
    dict(intent="multi_poetry_short", category="multi_constraint", difficulty="hard",
         en="A short poetry collection, under 120 pages", tr="120 sayfadan kısa bir şiir kitabı",
         rule={"category": ["Poetry"], "max_pages": 119}),
    dict(intent="multi_history_recent", category="multi_constraint", difficulty="hard",
         en="A history book about Rome published after 2000",
         tr="2000'den sonra yayımlanmış Roma tarihi kitabı",
         rule={"category": ["History"], "title": r"\b(?:Rome|Roman|Caesar)\b", "min_year": 2001}),
    # ── mood ──
    dict(intent="mood_funny", category="mood", difficulty="hard",
         en="Something funny to cheer me up", tr="Beni neşelendirecek komik bir şey",
         rule={"category": ["Humor"], "or_author": ["Terry Pratchett", "Douglas Adams"]}),
    dict(intent="mood_scary", category="mood", difficulty="hard",
         en="A scary book for a stormy night", tr="Fırtınalı bir gece için korkutucu bir kitap",
         rule={"category": ["Horror", "Horror tales", "Horror tales, American", "Horror tales, English",
                            "Horror stories", "Horror stories."], "or_author": ["Stephen King"]}),
    # ── similar ──
    dict(intent="sim_hitchhiker", category="similar", difficulty="medium",
         en="Books like The Hitchhiker's Guide to the Galaxy",
         tr="Otostopçunun Galaksi Rehberi'ne benzer kitaplar",
         rule={"author": ["Douglas Adams", "Terry Pratchett"],
               "exclude_title": r"^The Hitchhiker's Guide to the Galaxy$"}),
    dict(intent="sim_sherlock", category="similar", difficulty="medium",
         en="Mysteries like Sherlock Holmes", tr="Sherlock Holmes gibi polisiye romanlar",
         rule={"category": ["Detective and mystery stories"], "or_author": ["Arthur Conan Doyle", "Agatha Christie"]}),
    dict(intent="sim_handmaid", category="similar", difficulty="medium",
         en="Dystopian novels like The Handmaid's Tale",
         tr="Damızlık Kızın Öyküsü gibi distopik romanlar",
         rule={"title": r"^(?:Brave New World|Fahrenheit 451|Nineteen Eighty-Four|1984|Never Let Me Go|We|The Road)$"}),
    # ── ambiguous (no fixed set) ──
    dict(intent="amb_good_book", category="ambiguous", difficulty="hard", behaviour="open_judgment",
         en="Recommend me a good book", tr="Bana güzel bir kitap öner", rule=None),
    dict(intent="amb_gift_mom", category="ambiguous", difficulty="hard", behaviour="open_judgment",
         en="A book to give my mother as a gift", tr="Anneme hediye edebileceğim bir kitap", rule=None),
    # ── insufficient_info ──
    dict(intent="insuff_blue_cover", category="insufficient_info", difficulty="hard", behaviour="no_fabrication",
         en="The book with the blue cover I saw last week", tr="Geçen hafta gördüğüm mavi kapaklı kitap", rule=None),
    dict(intent="insuff_that_one", category="insufficient_info", difficulty="hard", behaviour="no_fabrication",
         en="That novel everyone was talking about", tr="Herkesin konuştuğu o roman", rule=None),
    dict(intent="insuff_one_word", category="insufficient_info", difficulty="hard", behaviour="no_fabrication",
         en="book", tr="kitap", rule=None),
    # ── no_relevant (real works/authors absent from the catalog; asserted by the builder) ──
    dict(intent="none_shafak", category="no_relevant", difficulty="medium", behaviour="abstain_not_in_catalog",
         en="Novels by Elif Shafak", tr="Elif Şafak'ın romanları",
         rule=None, absent={"author": ["Shafak", "Şafak"]}),
    dict(intent="none_sapiens", category="no_relevant", difficulty="medium", behaviour="abstain_not_in_catalog",
         en="Sapiens by Yuval Noah Harari", tr="Yuval Noah Harari'nin Sapiens kitabı",
         rule=None, absent={"author": ["Harari"], "title": r"^Sapiens"}),
    dict(intent="none_mistborn", category="no_relevant", difficulty="medium", behaviour="abstain_not_in_catalog",
         en="Mistborn by Brandon Sanderson", tr="Brandon Sanderson'ın Mistborn serisi",
         rule=None, absent={"author": ["Brandon Sanderson"], "title": r"Mistborn"}),
]


def _load(csv_path: str) -> pd.DataFrame:
    df = pd.read_csv(csv_path, dtype=str).fillna("")
    df["isbn13"] = df["isbn13"].map(normalize_isbn)
    df["_pages"] = pd.to_numeric(df["page_count"], errors="coerce")
    df["_year"] = pd.to_numeric(df["published_date"].str[:4], errors="coerce")
    return df


def _any_author(df: pd.DataFrame, names: List[str]) -> pd.Series:
    mask = pd.Series(False, index=df.index)
    for n in names:
        mask |= df["authors"].str.contains(n, case=False, regex=False)
    return mask


def apply_rule(df: pd.DataFrame, rule: dict) -> List[str]:
    """ISBNs matching every constraint of `rule`; `or_author` widens the category constraint."""
    mask = pd.Series(True, index=df.index)
    if "title" in rule:
        mask &= df["title"].str.contains(rule["title"], case=False, regex=True)
    if "author" in rule:
        mask &= _any_author(df, rule["author"])
    if "category" in rule:
        cat = df["categories"].isin(rule["category"])
        if "or_author" in rule:
            cat |= _any_author(df, rule["or_author"])
        mask &= cat
    if "description" in rule:
        mask &= df["description"].str.contains(rule["description"], case=False, regex=True)
    if "max_pages" in rule:
        mask &= df["_pages"].le(rule["max_pages"])
    if "min_year" in rule:
        mask &= df["_year"].ge(rule["min_year"])
    if "exclude_title" in rule:
        mask &= ~df["title"].str.contains(rule["exclude_title"], case=False, regex=True)
    return sorted(df.loc[mask, "isbn13"].tolist())


def _absent_matches(df: pd.DataFrame, absent: dict) -> List[str]:
    hits = _any_author(df, absent.get("author", []))
    if "title" in absent:
        hits |= df["title"].str.contains(absent["title"], case=False, regex=True)
    return df.loc[hits, "isbn13"].tolist()


def _describe(rule: dict) -> str:
    return "; ".join(f"{k}={v}" for k, v in rule.items())


def build(csv_path: str = CATALOG_CSV) -> Dict:
    df = _load(csv_path)
    queries = []
    for spec in INTENTS:
        behaviour = spec.get("behaviour", "retrieve_relevant")
        if spec["rule"] is not None:
            expected = apply_rule(df, spec["rule"])
            if not expected:
                raise ValueError(f"{spec['intent']}: rule matches no catalog record")
            rule_text = "automatic rule over books.csv: " + _describe(spec["rule"])
        else:
            expected = []
            if "absent" in spec:
                leaked = _absent_matches(df, spec["absent"])
                if leaked:
                    raise ValueError(f"{spec['intent']}: catalog now holds {leaked}; not a no-relevant query")
                rule_text = "verified absent from books.csv: " + _describe(spec["absent"])
            else:
                rule_text = "no fixed relevant set; " + BEHAVIOURS[behaviour]
        for lang in ("en", "tr"):
            q = {
                "id": f"{spec['intent']}_{lang}",
                "intent": spec["intent"],
                "lang": lang,
                "category": spec["category"],
                "type": spec["category"],
                "difficulty": spec["difficulty"],
                "expected_behavior": behaviour,
                "text": spec[lang],
                "expected_isbns": expected,
                "label_tier": TIER,
                "label_rule": rule_text,
                "notes": "Automatically generated candidate labels; not reviewed by a person.",
            }
            if spec.get("single_work"):
                q["single_work"] = True
            queries.append(q)
    return {
        "dataset_version": DATASET_VERSION,
        "description": "Expansion of rag_eval_tr_en.json: every category in English and Turkish. "
                       "Expected sets are produced by the recorded rule over the catalog snapshot.",
        "human_verified": False,
        "label_tiers": {TIER: "Relevant set computed by a simple catalog rule (title, author, category, "
                              "description, length, year). Real ISBNs, but over- and under-inclusive and "
                              "NOT reviewed by a person. Not ground truth."},
        "categories": CATEGORIES,
        "expected_behaviors": BEHAVIOURS,
        "queries": queries,
    }


def _dump(doc: Dict) -> str:
    return json.dumps(doc, ensure_ascii=False, indent=1) + "\n"


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--check", action="store_true", help="fail if the committed file differs from a rebuild")
    args = p.parse_args()
    text = _dump(build())
    if args.check:
        current = open(OUT, encoding="utf-8").read() if os.path.exists(OUT) else ""
        if current != text:
            print("rag_eval_expansion.json is out of date; rebuild it", file=sys.stderr)
            return 1
        print("rag_eval_expansion.json is up to date")
        return 0
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    doc = json.loads(text)
    print(f"wrote {os.path.normpath(OUT)}: {len(doc['queries'])} queries")
    for q in doc["queries"][::2]:
        print(f"  {q['intent']:<22}{q['category']:<22}{len(q['expected_isbns']):>4} expected")
    return 0


if __name__ == "__main__":
    sys.exit(main())
