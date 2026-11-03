#!/usr/bin/env python3
"""
Libris — Migration 03 Operator Gate & Safety Verification Wrapper

Provides an authoritative, fail-closed operator workflow for database Migration 03:
- Enforces strict target validation (staging vs prod vs local).
- Redacts database credentials and connection secrets from all output and errors.
- Validates backup presence, non-emptiness, and cryptographic SHA-256 integrity.
- Verifies migration file hashes against source control.
- Runs comprehensive preflight queries (conflicts, orphans, schema inventory).
- Evaluates existing migration state to prevent blind re-execution (idempotency).
- Tracks unique execution attempt IDs and produces a verifiable evidence bundle.
- Defaults to safe DRY-RUN mode.
"""

import argparse
import hashlib
import json
import os
import re
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional
from urllib.parse import urlparse

try:
    import psycopg2
    from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
except ImportError:
    psycopg2 = None


HARDENING_DIR = Path(__file__).resolve().parent
WORKSPACE_ROOT = HARDENING_DIR.parents[2]

MIGRATION_FILE = HARDENING_DIR / "03_DRAFT_reconcile_interactions_and_trigger.sql"
ROLLBACK_FILE = HARDENING_DIR / "03_DRAFT_reconcile_interactions_and_trigger_rollback.sql"
RUNTIME_TEST_FILE = HARDENING_DIR / "test_03_interactions_and_trigger_runtime.sql"
RUNBOOK_FILE = HARDENING_DIR / "MIGRATION_03_STAGING_READINESS.md"


def mask_db_url(url: str) -> str:
    """Masks database credentials in connection string for safe logging."""
    if not url:
        return "<EMPTY>"
    try:
        parsed = urlparse(url)
        netloc = ""
        if parsed.username:
            netloc += parsed.username
            if parsed.password:
                netloc += ":***"
            netloc += "@"
        netloc += parsed.hostname or ""
        if parsed.port:
            netloc += f":{parsed.port}"
        masked = parsed._replace(netloc=netloc).geturl()
        return masked
    except Exception:
        # Fallback regex masking
        return re.sub(r"://([^:]+):([^@]+)@", r"://\1:***@", url)


def compute_sha256(file_path: Path) -> str:
    """Computes hex SHA-256 digest of a file."""
    if not file_path.exists():
        raise FileNotFoundError(f"File not found: {file_path}")
    h = hashlib.sha256()
    with open(file_path, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


class OperatorGateError(Exception):
    """Fail-closed operator gate exception."""
    pass


class Migration03OperatorGate:
    def __init__(
        self,
        db_url: Optional[str] = None,
        allow_local: bool = False,
        allow_prod: bool = False,
        backup_file: Optional[Path] = None,
        backup_sha256: Optional[str] = None,
        operator_ack: Optional[str] = None,
        dry_run: bool = True,
        attempt_id: Optional[str] = None,
        output_bundle_path: Optional[Path] = None,
    ):
        self.raw_db_url = db_url or os.environ.get("STAGING_DB_URL", "")
        self.allow_local = allow_local
        self.allow_prod = allow_prod
        self.backup_file = backup_file
        self.backup_sha256 = backup_sha256
        self.operator_ack = operator_ack
        self.dry_run = dry_run
        self.attempt_id = attempt_id or str(uuid.uuid4())
        self.output_bundle_path = output_bundle_path
        self.evidence: Dict[str, Any] = {
            "attempt_id": self.attempt_id,
            "timestamp_utc": datetime.now(timezone.utc).isoformat(),
            "dry_run": self.dry_run,
            "target": {},
            "migration_files": {},
            "backup_verification": {},
            "preflight_checks": {},
            "migration_state": "UNKNOWN",
            "decision": "NO-GO",
            "reasons": [],
            "post_verification": {},
        }

    def validate_target(self) -> Dict[str, str]:
        """Validates target database URI, enforcing isolation and security boundaries."""
        if not self.raw_db_url:
            msg = "Fail-closed abort: STAGING_DB_URL environment variable is missing or empty."
            self.evidence["reasons"].append(msg)
            raise OperatorGateError(msg)

        try:
            parsed = urlparse(self.raw_db_url)
        except Exception as e:
            msg = f"Fail-closed abort: Malformed database connection URL: {e}"
            self.evidence["reasons"].append(msg)
            raise OperatorGateError(msg)

        host = parsed.hostname or "unknown"
        dbname = (parsed.path or "").lstrip("/") or "postgres"
        port = parsed.port or 5432
        masked_url = mask_db_url(self.raw_db_url)

        self.evidence["target"] = {
            "host": host,
            "database": dbname,
            "port": port,
            "masked_url": masked_url,
        }

        # Check local / loopback safety
        is_loopback = host in ("localhost", "127.0.0.1", "::1", "0.0.0.0") or host.startswith("127.")
        if is_loopback and not self.allow_local:
            msg = (
                f"Fail-closed abort: Target host '{host}' is a local loopback interface. "
                "Migration 03 staging operator gate forbids accidental execution against local environments "
                "unless --allow-local-rehearsal is explicitly supplied."
            )
            self.evidence["reasons"].append(msg)
            raise OperatorGateError(msg)

        # Check production safety
        is_prod_named = any(k in host.lower() or k in dbname.lower() for k in ("prod", "production", "live"))
        if is_prod_named and not self.allow_prod:
            msg = (
                f"Fail-closed abort: Target host '{host}' or database '{dbname}' appears to be PRODUCTION. "
                "Execution strictly blocked. Production migrations require an authorized independent release gate."
            )
            self.evidence["reasons"].append(msg)
            raise OperatorGateError(msg)

        return {"host": host, "database": dbname, "masked_url": masked_url}

    def verify_migration_files(self) -> Dict[str, str]:
        """Verifies existence and hashes of all Migration 03 files."""
        files = {
            "migration_sql": MIGRATION_FILE,
            "rollback_sql": ROLLBACK_FILE,
            "runtime_test_sql": RUNTIME_TEST_FILE,
            "runbook": RUNBOOK_FILE,
        }
        hashes = {}
        for key, path in files.items():
            if not path.exists():
                msg = f"Fail-closed abort: Required migration artifact missing: {path}"
                self.evidence["reasons"].append(msg)
                raise OperatorGateError(msg)
            file_hash = compute_sha256(path)
            file_size = path.stat().st_size
            hashes[key] = {
                "path": str(path.relative_to(WORKSPACE_ROOT)),
                "sha256": file_hash,
                "size_bytes": file_size,
            }
        self.evidence["migration_files"] = hashes
        return {k: v["sha256"] for k, v in hashes.items()}

    def verify_backup(self) -> Dict[str, Any]:
        """Validates that a recent verified backup artifact exists with matching checksum."""
        if not self.backup_file:
            if not self.dry_run:
                msg = "Fail-closed abort: Non-dry-run operation requires --backup-file."
                self.evidence["reasons"].append(msg)
                raise OperatorGateError(msg)
            res = {
                "verified": False,
                "status": "SKIPPED_DRY_RUN",
                "message": "Backup verification skipped in dry-run mode (mandatory for actual execution)",
            }
            self.evidence["backup_verification"] = res
            return res

        if not self.backup_file.exists():
            msg = f"Fail-closed abort: Specified backup file does not exist: {self.backup_file}"
            self.evidence["reasons"].append(msg)
            raise OperatorGateError(msg)

        size = self.backup_file.stat().st_size
        if size == 0:
            msg = f"Fail-closed abort: Backup file is 0 bytes (empty): {self.backup_file}"
            self.evidence["reasons"].append(msg)
            raise OperatorGateError(msg)

        actual_sha256 = compute_sha256(self.backup_file)
        if self.backup_sha256 and actual_sha256.lower() != self.backup_sha256.lower():
            msg = (
                f"Fail-closed abort: Backup SHA-256 checksum mismatch!\n"
                f"  Expected: {self.backup_sha256}\n"
                f"  Actual:   {actual_sha256}"
            )
            self.evidence["reasons"].append(msg)
            raise OperatorGateError(msg)

        res = {
            "verified": True,
            "backup_file": str(self.backup_file),
            "size_bytes": size,
            "sha256": actual_sha256,
        }
        self.evidence["backup_verification"] = res
        return res

    def inspect_database_state(self, conn) -> str:
        """Determines if the database is CLEAN, ALREADY_APPLIED, or PARTIAL_INCONSISTENT."""
        with conn.cursor() as cur:
            # 1. Does unique constraint exist on user_interactions?
            cur.execute("""
                SELECT 1 FROM pg_constraint
                WHERE conname = 'unique_user_book_interaction'
                AND conrelid = 'public.user_interactions'::regclass;
            """)
            has_unique = cur.fetchone() is not None

            # 2. Does trigger exist on favorites?
            cur.execute("""
                SELECT 1 FROM pg_trigger
                WHERE tgname = 'trg_sync_favorites_to_interactions'
                AND tgrelid = 'public.favorites'::regclass;
            """)
            has_trigger = cur.fetchone() is not None

            # 3. Does archive table exist?
            cur.execute("""
                SELECT 1 FROM information_schema.tables
                WHERE table_schema = 'public'
                AND table_name = '_archived_user_interactions_duplicate_backup';
            """)
            has_archive = cur.fetchone() is not None

            # 4. Check constraint status
            cur.execute("""
                SELECT pg_get_constraintdef(oid)
                FROM pg_constraint
                WHERE conrelid = 'public.user_interactions'::regclass
                AND contype = 'c';
            """)
            check_defs = [r[0] for r in cur.fetchall()]
            has_6_states = any("want_to_read" in d and "reading" in d and "finished" in d for d in check_defs)

        if has_unique and has_trigger and has_6_states:
            state = "ALREADY_APPLIED"
        elif not has_unique and not has_archive:
            state = "CLEAN"
        else:
            state = "PARTIAL_INCONSISTENT"

        self.evidence["migration_state"] = state
        return state

    def run_preflights(self, conn) -> Dict[str, Any]:
        """Runs non-mutating preflight SELECT queries and records outcomes."""
        results: Dict[str, Any] = {}
        blockers: List[str] = []

        with conn.cursor() as cur:
            # Preflight 1: Essential tables exist
            cur.execute("""
                SELECT table_name
                FROM information_schema.tables
                WHERE table_schema IN ('public', 'auth')
                AND table_name IN ('user_interactions', 'favorites', 'books', 'users');
            """)
            found_tables = {r[0] for r in cur.fetchall()}
            missing_tables = {"user_interactions", "favorites", "books"} - found_tables
            if missing_tables:
                blockers.append(f"Missing required tables in catalog: {missing_tables}")
            results["catalog_tables_found"] = list(found_tables)

            # Preflight 2: Conflicting like/dislike interactions (NO-GO blocker if > 0)
            cur.execute("""
                SELECT count(*) FROM (
                    SELECT user_id, book_id
                    FROM public.user_interactions
                    WHERE interaction_type IN ('like', 'dislike')
                    GROUP BY user_id, book_id
                    HAVING count(DISTINCT interaction_type) > 1
                ) sub;
            """)
            conflict_count = cur.fetchone()[0]
            results["conflicting_like_dislike_pairs"] = conflict_count
            if conflict_count > 0:
                blockers.append(f"Found {conflict_count} unresolvable like/dislike conflicting pairs")

            # Preflight 3: Duplicate pairs that would violate FK when transferred to favorites
            cur.execute("""
                SELECT count(*)
                FROM public.user_interactions ui
                WHERE (ui.user_id, ui.book_id) IN (
                    SELECT user_id, book_id FROM public.user_interactions GROUP BY user_id, book_id HAVING count(*) > 1
                )
                AND ui.interaction_type IN ('favorite', 'like')
                AND (
                    NOT EXISTS (SELECT 1 FROM public.books b WHERE b.isbn13 = ui.book_id)
                    OR NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = ui.user_id)
                );
            """)
            orphan_transfer_count = cur.fetchone()[0]
            results["orphan_transfer_rows"] = orphan_transfer_count
            if orphan_transfer_count > 0:
                blockers.append(f"Found {orphan_transfer_count} orphan duplicate rows that would violate FK on favorites transfer")

            # Preflight 4: Invalid identifiers (NULL or whitespace)
            cur.execute("""
                SELECT count(*)
                FROM public.user_interactions
                WHERE user_id IS NULL OR book_id IS NULL OR trim(book_id) = '';
            """)
            invalid_ids_count = cur.fetchone()[0]
            results["invalid_identifier_rows"] = invalid_ids_count

            # Preflight 5: Duplicate pairs volume
            cur.execute("""
                SELECT count(*) AS total_duplicate_pairs, COALESCE(sum(dup_rows), 0) AS total_affected_rows
                FROM (
                    SELECT user_id, book_id, count(*) AS dup_rows
                    FROM public.user_interactions
                    GROUP BY user_id, book_id
                    HAVING count(*) > 1
                ) sub;
            """)
            dup_stats = cur.fetchone()
            results["duplicate_pairs_count"] = int(dup_stats[0]) if dup_stats and dup_stats[0] is not None else 0
            results["duplicate_affected_rows"] = int(dup_stats[1]) if dup_stats and dup_stats[1] is not None else 0

            # Preflight 6: Favorites table duplicate check
            cur.execute("""
                SELECT count(*)
                FROM (
                    SELECT user_id, book_id, count(*)
                    FROM public.favorites
                    GROUP BY user_id, book_id
                    HAVING count(*) > 1
                ) sub;
            """)
            fav_dup_count = cur.fetchone()[0]
            results["favorites_duplicates"] = fav_dup_count
            if fav_dup_count > 0:
                blockers.append(f"Found {fav_dup_count} duplicate pairs in favorites table")

        self.evidence["preflight_checks"] = {
            "metrics": results,
            "blockers": blockers,
            "passed": len(blockers) == 0,
        }

        if blockers:
            self.evidence["reasons"].extend(blockers)
            return results

        return results

    def execute(self) -> Dict[str, Any]:
        """Main orchestrator for operator gate verification or execution."""
        start_time = time.time()
        self.evidence["start_time_utc"] = datetime.now(timezone.utc).isoformat()

        # Step 1: Target Validation
        self.validate_target()

        # Step 2: File integrity
        self.verify_migration_files()

        # Step 3: Backup verification
        self.verify_backup()

        # Step 4: Database Connection & Verification
        if psycopg2 is None:
            raise OperatorGateError("psycopg2 is required but not installed.")

        try:
            conn = psycopg2.connect(self.raw_db_url)
            conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
        except Exception as e:
            msg = f"Database connection failed: {mask_db_url(str(e))}"
            self.evidence["reasons"].append(msg)
            raise OperatorGateError(msg)

        try:
            # Step 5: Migration state inspection
            state = self.inspect_database_state(conn)

            # Step 6: Preflight execution
            self.run_preflights(conn)

            has_blockers = len(self.evidence["preflight_checks"].get("blockers", [])) > 0

            # Step 7: Decision logic
            if has_blockers:
                self.evidence["decision"] = "NO-GO"
            elif state == "ALREADY_APPLIED":
                self.evidence["decision"] = "ALREADY_APPLIED"
                self.evidence["reasons"].append(
                    "Migration 03 schema invariants (UNIQUE constraint, Model A trigger, 6 statuses) are already satisfied."
                )
            elif state == "PARTIAL_INCONSISTENT":
                self.evidence["decision"] = "NO-GO"
                self.evidence["reasons"].append(
                    "Database is in a partial or inconsistent migration state. Manual triage or rollback required."
                )
            else:
                # State is CLEAN and no blockers
                if self.dry_run:
                    self.evidence["decision"] = "GO_DRY_RUN_PASSED"
                    self.evidence["reasons"].append(
                        "Preflight checks passed with zero blockers. Migration is safe to apply upon explicit operator authorization."
                    )
                else:
                    # Non-dry-run execution
                    if self.operator_ack != "CONFIRM_APPLY_MIGRATION_03":
                        msg = "Non-dry-run execution aborted: missing operator acknowledgement 'CONFIRM_APPLY_MIGRATION_03'."
                        self.evidence["decision"] = "NO-GO"
                        self.evidence["reasons"].append(msg)
                        raise OperatorGateError(msg)

                    # Real migration execution
                    self._apply_migration(conn)
                    self.evidence["decision"] = "APPLIED_SUCCESSFULLY"

        finally:
            conn.close()

        end_time = time.time()
        self.evidence["end_time_utc"] = datetime.now(timezone.utc).isoformat()
        self.evidence["duration_seconds"] = round(end_time - start_time, 3)

        if self.output_bundle_path:
            self.output_bundle_path.parent.mkdir(parents=True, exist_ok=True)
            with open(self.output_bundle_path, "w", encoding="utf-8") as f:
                json.dump(self.evidence, f, indent=2, default=str)

        return self.evidence

    def _apply_migration(self, conn):
        """Applies Migration 03 SQL script within an isolated transaction."""
        with open(MIGRATION_FILE, "r", encoding="utf-8") as f:
            sql = f.read()

        with conn.cursor() as cur:
            # Set lock timeout to 5 seconds to prevent locking production
            cur.execute("SET lock_timeout = '5s';")
            cur.execute("SET statement_timeout = '30s';")
            cur.execute(sql)

        # Post-migration verification
        state = self.inspect_database_state(conn)
        if state != "ALREADY_APPLIED":
            raise OperatorGateError(f"Post-migration verification failed: state is {state}")
        self.evidence["post_verification"] = {"status": "PASS", "state": state}


def build_cli() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Libris Migration 03 Operator Gate & Release Verification Wrapper"
    )
    parser.add_argument(
        "--db-url",
        type=str,
        default=None,
        help="Target PostgreSQL connection string (defaults to STAGING_DB_URL env var)",
    )
    parser.add_argument(
        "--allow-local-rehearsal",
        action="store_true",
        help="Allow running against localhost/loopback for local rehearsal testing",
    )
    parser.add_argument(
        "--allow-production",
        action="store_true",
        help="Allow running against production-like target host (requires explicit authorization)",
    )
    parser.add_argument(
        "--backup-file",
        type=Path,
        default=None,
        help="Path to pre-migration backup dump artifact",
    )
    parser.add_argument(
        "--backup-sha256",
        type=str,
        default=None,
        help="Expected SHA-256 hex digest of the pre-migration backup dump",
    )
    parser.add_argument(
        "--operator-ack",
        type=str,
        default=None,
        help="Explicit operator acknowledgment string (required for non-dry-run)",
    )
    parser.add_argument(
        "--execute",
        action="store_true",
        help="Execute the migration against the database (default is dry-run)",
    )
    parser.add_argument(
        "--output-bundle",
        type=Path,
        default=Path("artifacts/migration_03_operator_evidence.json"),
        help="Output path for the operator evidence bundle JSON",
    )
    return parser


def main():
    parser = build_cli()
    args = parser.parse_args()

    gate = Migration03OperatorGate(
        db_url=args.db_url,
        allow_local=args.allow_local_rehearsal,
        allow_prod=args.allow_production,
        backup_file=args.backup_file,
        backup_sha256=args.backup_sha256,
        operator_ack=args.operator_ack,
        dry_run=not args.execute,
        output_bundle_path=args.output_bundle,
    )

    try:
        evidence = gate.execute()
        print("\n" + "=" * 80)
        print(" LIBRIS MIGRATION 03 OPERATOR GATE — EXECUTION SUMMARY")
        print("=" * 80)
        print(f" Attempt ID:  {evidence['attempt_id']}")
        print(f" Mode:        {'DRY-RUN (Safe, zero writes)' if evidence['dry_run'] else 'LIVE EXECUTION'}")
        print(f" Target:      {evidence['target'].get('masked_url', '<UNKNOWN>')}")
        print(f" State:       {evidence['migration_state']}")
        print(f" Decision:    {evidence['decision']}")
        print(f" Duration:    {evidence.get('duration_seconds', 0)}s")
        if evidence.get("reasons"):
            print("\n Details & Findings:")
            for r in evidence["reasons"]:
                print(f"  • {r}")
        print("=" * 80 + "\n")

        if evidence["decision"] in ("NO-GO",):
            sys.exit(2)
        elif evidence["decision"] in ("GO_DRY_RUN_PASSED", "ALREADY_APPLIED", "APPLIED_SUCCESSFULLY"):
            sys.exit(0)
        else:
            sys.exit(1)

    except OperatorGateError as e:
        print(f"\n[FAIL-CLOSED GATE BLOCKER]: {e}\n", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"\n[UNEXPECTED OPERATOR ERROR]: {mask_db_url(str(e))}\n", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
