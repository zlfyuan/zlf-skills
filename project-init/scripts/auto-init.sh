#!/usr/bin/env bash
# Auto-initialization hook entry point.
# Called by Claude Code / Codex hooks on first interaction in a project.
#
# Usage: auto-init.sh [directory]
# Exit codes:
#   0 - initialized or already done
#   1 - not a code project
#   2 - setup failed

set -euo pipefail

TARGET="${1:-$PWD}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ ! -d "$TARGET" ]]; then
    echo "Could not initialize missing directory: $TARGET" >&2
    exit 2
fi

TARGET="$(cd "$TARGET" && pwd)"

# Resolve the marker case-insensitively so .Claude/.init-done is reused.
source "$SCRIPT_DIR/ci-path.sh"
if [[ -n "$(ci_resolve ".claude/.init-done" 2>/dev/null || true)" ]]; then
    exit 0
fi

if DETECT_OUTPUT="$($SCRIPT_DIR/detect-code-project.sh "$TARGET" 2>/dev/null)"; then
    DETECT_EXIT=0
else
    DETECT_EXIT=$?
fi

case "$DETECT_OUTPUT" in
    CODE_PROJECT)
        if "$SCRIPT_DIR/setup-project.sh" "$TARGET"; then
            exit 0
        fi
        exit 2
        ;;
    NOT_CODE_PROJECT)
        # Keep the warning additive and do not overwrite user instruction files.
        CLAUDE_MD="$TARGET/CLAUDE.md"
        AGENTS_MD="$TARGET/AGENTS.md"
        if [[ ! -e "$CLAUDE_MD" && ! -L "$CLAUDE_MD" ]]; then
            cat > "$CLAUDE_MD" <<'NONCODE_EOF'
# Non-Code Project

This directory does not appear to be a programming project.

Switch to the code project directory before using coding agents.
NONCODE_EOF
        fi
        if [[ ! -e "$AGENTS_MD" && ! -L "$AGENTS_MD" ]]; then
            cat > "$AGENTS_MD" <<'NONCODEX_EOF'
# Non-Code Project

This directory does not appear to be a programming project.

Switch to the code project directory before using coding agents.
NONCODEX_EOF
        fi
        echo '{"status":"not_code_project","message":"This directory does not appear to be a programming project. Please switch to a code project directory."}'
        exit 1
        ;;
    *)
        echo "Could not determine project type (exit $DETECT_EXIT); passing through." >&2
        exit 0
        ;;
esac
