"""
Regression tests for model artifact validation (audit H2).

The saved model must carry its own version and configuration, and loading must reject any
artifact that does not match the running code, for both the BookRecommender and the legacy
RecommenderEngine formats. A rejected artifact triggers retraining at startup.
"""

import pickle
from dataclasses import asdict, replace

import pandas as pd
from backend.infrastructure.ml import recommender as rec_module
from backend.infrastructure.ml.recommender import (
    MODEL_VERSION,
    BookRecommender,
    EngineConfig,
    RecommenderEngine,
    artifact_incompatibility,
)

BOOKS = [
    dict(isbn13=f"97800000003{i:02d}", title=f"Book {i}", authors=f"Author {i % 3}",
         categories="Fiction", description=f"story number {i} about ships and seas", average_rating=4.0,
         ratings_count=10 * i)
    for i in range(12)
]


def _fitted() -> BookRecommender:
    rec = BookRecommender()
    rec.load_from_dicts(BOOKS)
    rec.fit()
    assert rec.is_fitted
    return rec


def _dump(obj, path):
    with open(path, "wb") as f:
        pickle.dump(obj, f)
    return str(path)


def test_config_values_are_stored_in_the_artifact(tmp_path):
    path = tmp_path / "m.pkl"
    _fitted().save_model(str(path))
    with open(path, "rb") as f:
        loaded = pickle.load(f)
    assert vars(loaded.config) == asdict(EngineConfig())
    assert vars(loaded.config)["model_version"] == MODEL_VERSION
    assert BookRecommender().load_model(str(path)) is True


def test_default_configs_are_not_shared_between_instances():
    a, b = BookRecommender(), BookRecommender()
    assert a.config is not b.config
    a.config.diversity_lambda = 0.1
    assert b.config.diversity_lambda == EngineConfig().diversity_lambda
    assert RecommenderEngine().config is not RecommenderEngine().config


def test_old_model_version_is_rejected(tmp_path):
    rec = _fitted()
    rec.config = rec.engine.config = replace(rec.config, model_version="2.2.0")
    target = BookRecommender()
    assert target.load_model(_dump(rec, tmp_path / "old.pkl")) is False
    assert target.is_fitted is False and target.df.empty  # nothing from the old artifact leaked in


def test_artifact_from_before_configs_were_stored_is_rejected(tmp_path):
    """Pre-fix artifacts pickled an EngineConfig with an empty __dict__ (class attributes only)."""
    rec = _fitted()
    empty = EngineConfig.__new__(EngineConfig)
    assert vars(empty) == {}
    assert empty.model_version == MODEL_VERSION  # what the old check compared: always equal
    rec.config = rec.engine.config = empty
    assert BookRecommender().load_model(_dump(rec, tmp_path / "legacy.pkl")) is False
    assert "predates" in artifact_incompatibility(empty, EngineConfig())


def test_same_version_with_different_config_is_rejected(tmp_path):
    rec = _fitted()
    rec.config = rec.engine.config = replace(rec.config, tfidf_min_df=5)
    assert BookRecommender().load_model(_dump(rec, tmp_path / "drift.pkl")) is False
    assert "tfidf_min_df" in artifact_incompatibility(rec.config, EngineConfig())


def test_legacy_engine_artifact_is_validated_too(tmp_path):
    rec = _fitted()
    good = _dump(rec.engine, tmp_path / "engine.pkl")
    loaded = BookRecommender()
    assert loaded.load_model(good) is True and len(loaded.df) == len(BOOKS)

    rec.engine.config = replace(rec.engine.config, model_version="1.0.0")
    assert BookRecommender().load_model(_dump(rec.engine, tmp_path / "engine_old.pkl")) is False


def test_inconsistent_artifact_is_rejected(tmp_path):
    rec = _fitted()
    rec.engine.df = rec.engine.df.iloc[:-1]  # TF-IDF rows no longer align with catalog rows
    assert BookRecommender().load_model(_dump(rec, tmp_path / "broken.pkl")) is False


def test_unreadable_or_foreign_artifacts_are_rejected(tmp_path):
    (tmp_path / "junk.pkl").write_bytes(b"not a pickle")
    assert BookRecommender().load_model(str(tmp_path / "junk.pkl")) is False
    assert BookRecommender().load_model(_dump({"x": 1}, tmp_path / "dict.pkl")) is False
    assert BookRecommender().load_model(str(tmp_path / "missing.pkl")) is False


def test_rejected_artifact_triggers_retraining_at_startup(tmp_path, monkeypatch):
    """Controlled recovery: BookService retrains from the catalog and overwrites the bad artifact."""
    from backend.config import Config
    from backend.services.book_service import BookService

    stale = _fitted()
    stale.config = stale.engine.config = replace(stale.config, model_version="2.2.0")
    model_path = _dump(stale, tmp_path / "tfidf.pkl")
    csv_path = tmp_path / "books.csv"
    pd.DataFrame(BOOKS).to_csv(csv_path, index=False)
    monkeypatch.setattr(Config, "MODEL_PATH", model_path)
    monkeypatch.setattr(Config, "DATA_PATH", str(csv_path))

    service = BookService(recommender=BookRecommender())

    assert service.recommender.is_fitted
    assert service.recommender.config.model_version == MODEL_VERSION
    assert BookRecommender().load_model(model_path) is True  # the artifact on disk was replaced


def test_shipped_artifact_matches_the_running_code():
    """The committed saved_model/tfidf.pkl must load; a stale one would retrain on every boot."""
    from backend.config import Config

    rec = BookRecommender()
    assert rec.load_model(Config.MODEL_PATH) is True
    assert rec_module.artifact_incompatibility(rec.config, EngineConfig()) is None
