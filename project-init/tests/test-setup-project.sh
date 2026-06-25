#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

bash "$ROOT_DIR/scripts/setup-project.sh" "$TMP_DIR" >/dev/null

for file in "$TMP_DIR/CLAUDE.md" "$TMP_DIR/AGENTS.md" "$TMP_DIR/.codex/AGENTS.md"; do
    if grep -q '<!-- TODO' "$file"; then
        echo "Found placeholder TODO in $file" >&2
        exit 1
    fi
done

if [[ ! -f "$TMP_DIR/.gitignore" ]]; then
    echo "Missing .gitignore" >&2
    exit 1
fi

for pattern in '.claude/' '.codex/' '.codegraph/' 'CLAUDE.md' 'AGENTS.md'; do
    if ! grep -Fq "$pattern" "$TMP_DIR/.gitignore"; then
        echo "Missing gitignore pattern: $pattern" >&2
        exit 1
    fi
done

echo "setup-project regression checks passed"
