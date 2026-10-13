#!/usr/bin/env python3
"""Build the app's compact course index and copy its state tee files.

Course identity is the synthetic `course_key` the scraper stores per row
(see golf_scraper/keys.py); this script does no hashing and carries the
column through. No external course IDs appear in the output.
"""

import argparse
import csv
from datetime import date
import json
import sys
from pathlib import Path

DATA_COLUMNS = [
    "course_key",
    "state",
    "tee_name",
    "gender",
    "par",
    "course_rating",
    "bogey_rating",
    "slope_rating",
    "rating_f9",
    "rating_b9",
    "front9_rating",
    "front9_slope",
    "back9_rating",
    "back9_slope",
    "bogey_f9",
    "bogey_b9",
    "front9_raw",
    "back9_raw",
]
INDEX_COLUMNS = {"facility_name", "course_name", "city"}


def display_name(facility: str, course: str) -> str:
    prefix = f"{facility} - "
    if course.casefold().startswith(prefix.casefold()):
        course = course[len(prefix) :].strip()
    return course or facility


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="Directory containing tees_STATE.csv files")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("assets/course_catalog"),
        help="App asset directory",
    )
    args = parser.parse_args()

    files = sorted(args.source.glob("tees_*.csv"))
    if not files:
        raise SystemExit(f"No tees_STATE.csv files found under {args.source}")

    state_files: dict[str, str] = {}
    courses: dict[tuple[str, str], tuple[str, str, str]] = {}
    total_rows = 0
    args.output.mkdir(parents=True, exist_ok=True)

    for source_file in files:
        with source_file.open(newline="", encoding="utf-8-sig") as handle:
            reader = csv.DictReader(handle)
            columns = set(reader.fieldnames or [])
            missing = set(DATA_COLUMNS) | INDEX_COLUMNS
            missing -= columns
            if missing:
                raise SystemExit(
                    f"{source_file.name} is missing columns: {', '.join(sorted(missing))}"
                )
            destination = args.output / source_file.name
            with destination.open("w", newline="", encoding="utf-8") as output:
                writer = csv.DictWriter(output, fieldnames=DATA_COLUMNS)
                writer.writeheader()
                skipped = 0
                for row in reader:
                    writer.writerow(
                        {name: row.get(name) or "" for name in DATA_COLUMNS}
                    )
                    state = (row.get("state") or "").strip().upper()
                    course_key = (row.get("course_key") or "").strip()
                    facility = (row.get("facility_name") or "").strip()
                    course = display_name(
                        facility, (row.get("course_name") or "").strip()
                    )
                    city = (row.get("city") or "").strip()
                    if not all((state, course_key, facility, course)):
                        skipped += 1
                        continue
                    previous_file = state_files.setdefault(state, source_file.name)
                    if previous_file != source_file.name:
                        raise SystemExit(
                            f"State {state} appears in both {previous_file} and "
                            f"{source_file.name}"
                        )
                    key = (state, course_key)
                    metadata = (facility, course, city)
                    previous = courses.setdefault(key, metadata)
                    if previous != metadata:
                        # Same key can only come from the same normalized
                        # names; raw text may differ in case/punctuation.
                        # First spelling wins so one odd row cannot fail
                        # a 14k-course build.
                        print(
                            f"WARNING: {source_file.name} repeats key "
                            f"{state}/{course_key} with different metadata; "
                            f"keeping the first spelling.",
                            file=sys.stderr,
                        )
                    total_rows += 1
                if skipped:
                    print(
                        f"WARNING: {source_file.name} skipped {skipped} rows "
                        f"missing state/key/facility/course.",
                        file=sys.stderr,
                    )

    payload = {
        "source": "Course Database",
        "generatedAt": date.today().isoformat(),
        "teeRecordCount": total_rows,
        "stateFiles": dict(sorted(state_files.items())),
        "courses": [
            [state, course_key, *metadata]
            for (state, course_key), metadata in sorted(
                courses.items(), key=lambda item: (item[0][0], item[1][1].casefold())
            )
        ],
    }
    index_path = args.output / "index.json"
    index_path.write_text(
        json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        f"Built {len(courses):,} course records and copied {len(files)} state files "
        f"({total_rows:,} tee rows) to {args.output}"
    )


if __name__ == "__main__":
    main()
