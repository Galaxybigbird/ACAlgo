#!/usr/bin/env python3
"""Initialise the AC pipeline SQLite database in the MT5 data directory."""

from __future__ import annotations

import argparse
import os
import sqlite3
from pathlib import Path


DEFAULT_SCHEMA = (
    r"C:/Users/marth/AppData/Roaming/MetaQuotes/Terminal"
    r"/E62C655ED163FFC555DD40DBEA67E6BB/MQL5/Include/ClusteringLib"
    r"/database.sqlite.schema.sql"
)
DEFAULT_DATABASE = (
    r"C:/Users/marth/AppData/Roaming/MetaQuotes/Terminal"
    r"/E62C655ED163FFC555DD40DBEA67E6BB/MQL5/Files/database.sqlite"
)


def parse_args() -> argparse.Namespace:
    """Parse optional overrides for schema/database paths."""
    parser = argparse.ArgumentParser(
        description=(
            "Initialise the AC pipeline SQLite database using the ClusteringLib schema."
        )
    )
    parser.add_argument(
        "--schema",
        type=str,
        default=DEFAULT_SCHEMA,
        help="Full path to database.sqlite.schema.sql "
        f"(default: {DEFAULT_SCHEMA})",
    )
    parser.add_argument(
        "--database",
        type=str,
        default=DEFAULT_DATABASE,
        help="Full path to the database.sqlite to create "
        f"(default: {DEFAULT_DATABASE})",
    )
    return parser.parse_args()


def normalise_path(raw_path: str) -> Path:
    """
    Convert Windows-style paths to the current platform representation.

    This supports running the script from WSL while referencing Windows paths.
    """
    candidate = Path(raw_path)

    # If the path already exists as provided, return immediately.
    if candidate.exists() or candidate.parent.exists():
        return candidate

    # On non-Windows systems, translate drive-letter paths to /mnt/<drive>/...
    if os.name != "nt" and len(raw_path) > 1 and raw_path[1] == ":":
        drive = raw_path[0].lower()
        remainder = raw_path[2:].lstrip("\\/").replace("\\", "/")
        return Path(f"/mnt/{drive}/{remainder}")

    return candidate


def read_schema(schema_path: Path) -> str:
    """Load SQL schema text from disk."""
    if not schema_path.is_file():
        raise FileNotFoundError(f"Schema file not found: {schema_path}")
    return schema_path.read_text(encoding="utf-8")


def ensure_database_directory(database_path: Path) -> None:
    """Ensure the destination directory exists before creating the database."""
    database_path.parent.mkdir(parents=True, exist_ok=True)


def initialise_database(database_path: Path, schema_sql: str) -> None:
    """Write schema to the SQLite database at the requested path."""
    # Remove any existing file to guarantee a clean initialisation.
    try:
        database_path.unlink()
    except FileNotFoundError:
        pass

    with sqlite3.connect(database_path) as conn:
        conn.executescript(schema_sql)
        conn.commit()


def main() -> None:
    args = parse_args()
    schema_path: Path = normalise_path(args.schema)
    database_path: Path = normalise_path(args.database)

    schema_sql = read_schema(schema_path)
    ensure_database_directory(database_path)
    initialise_database(database_path, schema_sql)

    print(f"Database initialised at: {database_path}")


if __name__ == "__main__":
    main()
