"""
Tests for Migration 03 Operator Gate & Safety Verification Wrapper.
Covers all mandated fail-closed safety checks:
1. Missing target configuration
2. Production-like target rejected by default
3. Missing operator acknowledgement
4. Missing or incorrect backup checksum
5. Failed preflight (conflicts / orphan FK / missing tables)
6. Duplicate and inconsistent migration state (idempotency & partial detection)
7. Secret redaction from logs and error strings
8. Successful dry-run without database writes
"""

import hashlib
import os
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest
from backend.scripts.hardening.migration_03_operator_gate import (
    Migration03OperatorGate,
    OperatorGateError,
    mask_db_url,
)


class TestSecretRedaction:
    def test_masks_standard_postgres_password(self):
        url = "postgresql://postgres:SuperSecretP@ss123@db.staging.supabase.co:5432/postgres"
        masked = mask_db_url(url)
        assert "SuperSecretP@ss123" not in masked
        assert masked == "postgresql://postgres:***@db.staging.supabase.co:5432/postgres"

    def test_masks_special_chars_in_password(self):
        url = "postgres://admin:p%40ss%3Aw0rd@10.0.0.5:5432/libris_db"
        masked = mask_db_url(url)
        assert "p%40ss%3Aw0rd" not in masked
        assert "***@" in masked

    def test_handles_empty_or_none(self):
        assert mask_db_url("") == "<EMPTY>"


class TestTargetValidation:
    def test_missing_target_fails_closed(self):
        with patch.dict(os.environ, {}, clear=True):
            gate = Migration03OperatorGate(db_url="")
            with pytest.raises(OperatorGateError) as exc:
                gate.validate_target()
            assert "STAGING_DB_URL environment variable is missing" in str(exc.value)

    def test_localhost_rejected_without_allow_local(self):
        gate = Migration03OperatorGate(
            db_url="postgresql://postgres:secret@localhost:5432/postgres",
            allow_local=False,
        )
        with pytest.raises(OperatorGateError) as exc:
            gate.validate_target()
        assert "local loopback interface" in str(exc.value)

    def test_localhost_allowed_with_explicit_flag(self):
        gate = Migration03OperatorGate(
            db_url="postgresql://postgres:secret@127.0.0.1:5432/postgres",
            allow_local=True,
        )
        target = gate.validate_target()
        assert target["host"] == "127.0.0.1"

    def test_production_target_rejected_by_default(self):
        gate = Migration03OperatorGate(
            db_url="postgresql://postgres:secret@prod-db.supabase.co:5432/libris_production",
            allow_prod=False,
        )
        with pytest.raises(OperatorGateError) as exc:
            gate.validate_target()
        assert "appears to be PRODUCTION" in str(exc.value)

    def test_production_target_allowed_only_with_explicit_override(self):
        gate = Migration03OperatorGate(
            db_url="postgresql://postgres:secret@prod-db.supabase.co:5432/libris_production",
            allow_prod=True,
        )
        target = gate.validate_target()
        assert target["host"] == "prod-db.supabase.co"


class TestBackupVerification:
    def test_missing_backup_in_non_dry_run_fails_closed(self):
        gate = Migration03OperatorGate(
            db_url="postgresql://u:p@staging.host:5432/db",
            dry_run=False,
            backup_file=None,
        )
        with pytest.raises(OperatorGateError) as exc:
            gate.verify_backup()
        assert "Non-dry-run operation requires --backup-file" in str(exc.value)

    def test_empty_backup_file_fails_closed(self, tmp_path):
        empty_dump = tmp_path / "empty.dump"
        empty_dump.touch()
        gate = Migration03OperatorGate(
            db_url="postgresql://u:p@staging.host:5432/db",
            backup_file=empty_dump,
        )
        with pytest.raises(OperatorGateError) as exc:
            gate.verify_backup()
        assert "0 bytes (empty)" in str(exc.value)

    def test_backup_sha256_mismatch_fails_closed(self, tmp_path):
        dump_file = tmp_path / "real.dump"
        dump_file.write_bytes(b"dummy pg_dump binary content")
        gate = Migration03OperatorGate(
            db_url="postgresql://u:p@staging.host:5432/db",
            backup_file=dump_file,
            backup_sha256="ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        )
        with pytest.raises(OperatorGateError) as exc:
            gate.verify_backup()
        assert "checksum mismatch" in str(exc.value)

    def test_valid_backup_passes(self, tmp_path):
        dump_file = tmp_path / "real.dump"
        content = b"valid pg_dump binary stream with valid header"
        dump_file.write_bytes(content)
        expected_sha = hashlib.sha256(content).hexdigest()

        gate = Migration03OperatorGate(
            db_url="postgresql://u:p@staging.host:5432/db",
            backup_file=dump_file,
            backup_sha256=expected_sha,
        )
        res = gate.verify_backup()
        assert res["verified"] is True
        assert res["sha256"] == expected_sha


class TestMigrationFileIntegrity:
    def test_hashes_all_migration_artifacts(self):
        gate = Migration03OperatorGate(db_url="postgresql://u:p@staging.host:5432/db")
        hashes = gate.verify_migration_files()
        assert "migration_sql" in hashes
        assert "rollback_sql" in hashes
        assert "runtime_test_sql" in hashes
        assert len(hashes["migration_sql"]) == 64


class TestDatabaseStateAndPreflights:
    def test_identifies_already_applied_state(self):
        mock_conn = MagicMock()
        mock_cur = MagicMock()
        mock_conn.cursor.return_value.__enter__.return_value = mock_cur

        # unique constraint found, trigger found, archive found, 6 states found
        mock_cur.fetchone.side_effect = [
            (1,),  # unique
            (1,),  # trigger
            (1,),  # archive
        ]
        mock_cur.fetchall.return_value = [
            ("CHECK (interaction_type IN ('like', 'dislike', 'want_to_read', 'reading', 'finished', 'favorite'))",)
        ]

        gate = Migration03OperatorGate(db_url="postgresql://u:p@staging.host:5432/db")
        state = gate.inspect_database_state(mock_conn)
        assert state == "ALREADY_APPLIED"

    def test_identifies_partial_inconsistent_state(self):
        mock_conn = MagicMock()
        mock_cur = MagicMock()
        mock_conn.cursor.return_value.__enter__.return_value = mock_cur

        # unique constraint NOT found, trigger NOT found, but archive IS found
        mock_cur.fetchone.side_effect = [
            None,  # unique
            None,  # trigger
            (1,),  # archive exists (partial from interrupted run)
        ]
        mock_cur.fetchall.return_value = []

        gate = Migration03OperatorGate(db_url="postgresql://u:p@staging.host:5432/db")
        state = gate.inspect_database_state(mock_conn)
        assert state == "PARTIAL_INCONSISTENT"

    def test_preflight_blocks_on_like_dislike_conflicts(self):
        mock_conn = MagicMock()
        mock_cur = MagicMock()
        mock_conn.cursor.return_value.__enter__.return_value = mock_cur

        # Found tables: all 4 exist
        mock_cur.fetchall.side_effect = [
            [("user_interactions",), ("favorites",), ("books",), ("users",)],
        ]
        # Preflight counts:
        mock_cur.fetchone.side_effect = [
            (2,),  # conflicting pairs = 2 -> BLOCKER!
            (0,),  # orphan transfer
            (0,),  # invalid IDs
            (0, 0),  # duplicates volume
            (0,),  # favorites dups
        ]

        gate = Migration03OperatorGate(db_url="postgresql://u:p@staging.host:5432/db")
        _results = gate.run_preflights(mock_conn)
        assert gate.evidence["preflight_checks"]["passed"] is False
        assert any("conflicting pairs" in b for b in gate.evidence["preflight_checks"]["blockers"])

    def test_preflight_blocks_on_orphan_fk_transfer(self):
        mock_conn = MagicMock()
        mock_cur = MagicMock()
        mock_conn.cursor.return_value.__enter__.return_value = mock_cur

        mock_cur.fetchall.side_effect = [
            [("user_interactions",), ("favorites",), ("books",), ("users",)],
        ]
        mock_cur.fetchone.side_effect = [
            (0,),  # conflicts = 0
            (5,),  # orphan transfer = 5 -> BLOCKER!
            (0,),  # invalid IDs
            (0, 0),
            (0,),
        ]

        gate = Migration03OperatorGate(db_url="postgresql://u:p@staging.host:5432/db")
        gate.run_preflights(mock_conn)
        assert gate.evidence["preflight_checks"]["passed"] is False
        assert any("orphan duplicate rows" in b for b in gate.evidence["preflight_checks"]["blockers"])


class TestEndToEndDryRunAndOperatorAck:
    @patch("backend.scripts.hardening.migration_03_operator_gate.psycopg2.connect")
    def test_dry_run_completes_without_writes(self, mock_connect, tmp_path):
        mock_conn = MagicMock()
        mock_cur = MagicMock()
        mock_connect.return_value = mock_conn
        mock_conn.cursor.return_value.__enter__.return_value = mock_cur

        # State = CLEAN
        mock_cur.fetchone.side_effect = [
            None,  # unique
            None,  # trigger
            None,  # archive
            (0,),  # conflict count
            (0,),  # orphan count
            (0,),  # invalid IDs count
            (0, 0),  # dup volume
            (0,),  # fav dup count
        ]
        mock_cur.fetchall.side_effect = [
            [],  # check constraint definitions
            [("user_interactions",), ("favorites",), ("books",), ("users",)],  # tables
        ]

        bundle_path = tmp_path / "evidence.json"
        gate = Migration03OperatorGate(
            db_url="postgresql://app_staging:pw@staging.supabase.co:5432/postgres",
            dry_run=True,
            output_bundle_path=bundle_path,
        )

        evidence = gate.execute()
        assert evidence["decision"] == "GO_DRY_RUN_PASSED"
        assert evidence["dry_run"] is True
        assert bundle_path.exists()
        # Ensure no SQL execute calls performed dangerous mutations
        executed_sqls = [call[0][0] for call in mock_cur.execute.call_args_list]
        assert not any("DROP" in sql or "DELETE" in sql or "ALTER" in sql for sql in executed_sqls)

    def test_non_dry_run_requires_exact_operator_acknowledgement(self):
        with patch("backend.scripts.hardening.migration_03_operator_gate.psycopg2.connect") as mock_connect:
            mock_conn = MagicMock()
            mock_cur = MagicMock()
            mock_connect.return_value = mock_conn
            mock_conn.cursor.return_value.__enter__.return_value = mock_cur

            mock_cur.fetchone.side_effect = [
                None, None, None,
                (0,), (0,), (0,), (0, 0), (0,)
            ]
            mock_cur.fetchall.side_effect = [
                [],
                [("user_interactions",), ("favorites",), ("books",), ("users",)],
            ]

            gate = Migration03OperatorGate(
                db_url="postgresql://app_staging:pw@staging.supabase.co:5432/postgres",
                dry_run=False,
                operator_ack="wrong_ack_string",
                backup_file=Path(__file__),  # existing non-empty file
            )
            with pytest.raises(OperatorGateError) as exc:
                gate.execute()
            assert "missing operator acknowledgement" in str(exc.value)

    def test_real_pgserver_dry_run_generates_evidence_bundle(self, tmp_path):
        """Exercises the operator gate against an ephemeral local PostgreSQL database with baseline tables."""
        import pgserver
        import psycopg2

        pg_dir = tmp_path / "pgdata"
        pgserver._commands.initdb(
            ['--locale=C', '--auth=trust', '--auth-local=trust', '--encoding=utf8', '-U', 'postgres'],
            pgdata=pg_dir
        )
        srv = pgserver.PostgresServer(pg_dir)
        db_uri = srv.get_uri()

        # Seed baseline schema (books, auth.users, user_interactions, favorites)
        conn = psycopg2.connect(db_uri)
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute("CREATE SCHEMA IF NOT EXISTS auth;")
            cur.execute("CREATE TABLE IF NOT EXISTS auth.users (id UUID PRIMARY KEY);")
            cur.execute("CREATE TABLE IF NOT EXISTS public.books (isbn13 VARCHAR(13) PRIMARY KEY, title TEXT);")
            cur.execute("""
                CREATE TABLE IF NOT EXISTS public.user_interactions (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    user_id UUID NOT NULL REFERENCES auth.users(id),
                    book_id VARCHAR(13) NOT NULL REFERENCES public.books(isbn13),
                    interaction_type VARCHAR(20) NOT NULL,
                    created_at TIMESTAMPTZ DEFAULT NOW()
                );
            """)
            cur.execute("""
                CREATE TABLE IF NOT EXISTS public.favorites (
                    user_id UUID NOT NULL REFERENCES auth.users(id),
                    book_id VARCHAR(13) NOT NULL REFERENCES public.books(isbn13),
                    created_at TIMESTAMPTZ DEFAULT NOW(),
                    PRIMARY KEY (user_id, book_id)
                );
            """)
        conn.close()

        bundle_path = tmp_path / "operator_evidence.json"
        gate = Migration03OperatorGate(
            db_url=db_uri,
            allow_local=True,
            dry_run=True,
            output_bundle_path=bundle_path,
        )
        evidence = gate.execute()
        assert evidence["decision"] == "GO_DRY_RUN_PASSED"
        assert evidence["dry_run"] is True
        assert evidence["migration_state"] == "CLEAN"
        assert evidence["preflight_checks"]["passed"] is True
        assert bundle_path.exists()

        srv.cleanup()

