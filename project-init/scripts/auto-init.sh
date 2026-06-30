#!/usr/bin/env bash
# Auto-initialization hook entry point.
# Called by Claude Code / Codex hooks on first interaction in a project.
# Fast-path: exits immediately if already initialized.
#
# Usage: auto-init.sh [directory]
# Exit codes:
#   0 - initialized or already done (pass through)
#   1 - not a code project (agent should warn user)
#   2 - setup failed

# set -euo pipefail

# TARGET="${1:-$PWD}"
# SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# # ── Fast path: already initialized ────────────────────────────────────
# if [[ -f "$TARGET/.claude/.init-done" ]]; then
#     exit 0
# fi

# # ── Detect project type ───────────────────────────────────────────────
# # Capture stdout AND exit code separately (detect script exits 1 for non-code)
# DETECT_OUTPUT="$("$SCRIPT_DIR/detect-code-project.sh" "$TARGET" 2>/dev/null)" && DETECT_EXIT=0 || DETECT_EXIT=$?
# DETECT_RESULT="${DETECT_OUTPUT:-DETECT_ERROR}"

# if [[ "$DETECT_RESULT" == "CODE_PROJECT" ]]; then
#     # ── Code project: run setup ───────────────────────────────────────
#     "$SCRIPT_DIR/setup-project.sh" "$TARGET"
#     exit 0
# elif [[ "$DETECT_RESULT" == "NOT_CODE_PROJECT" ]]; then
#     # ── Not a code project: create warning marker ─────────────────────
#     # Create a minimal CLAUDE.md that warns agents
#     if [[ ! -f "$TARGET/CLAUDE.md" ]]; then
#         mkdir -p "$TARGET/.claude"
#         cat > "$TARGET/CLAUDE.md" << 'NONCODE_EOF'
# # ⚠️ Non-Code Project

# This directory does not appear to be a programming/code project.

# If you are trying to work with code, please switch to a directory that contains source files (e.g., `.swift`, `.ts`, `.py`, `.go`, `.js`, etc.) or has a package manager file (e.g., `package.json`, `Podfile`, `Cargo.toml`, etc.).

# ## What to do:
# 1. `cd` into your actual code project directory
# 2. Restart your agent
# 3. The project will be auto-initialized on first use

# If you believe this IS a code project, create an empty `.claude/.init-done` file to skip this check:
# ```bash
# mkdir -p .claude && touch .claude/.init-done
# ```
# NONCODE_EOF
#     fi

#     if [[ ! -f "$TARGET/AGENTS.md" ]]; then
#         mkdir -p "$TARGET/.codex"
#         cat > "$TARGET/AGENTS.md" << 'NONCODEX_EOF'
# # ⚠️ Non-Code Project

# This directory does not appear to be a programming/code project.

# Please switch to a code project directory before using coding agents.
# NONCODEX_EOF
#     fi

#     # Emit a JSON result that hooks can parse
#     echo '{"status":"not_code_project","message":"This directory does not appear to be a programming project. Please switch to a code project directory."}'
#     exit 1
# else
#     # Detection error — pass through to avoid blocking legitimate work
#     echo "⚠️  Could not determine project type. Pass through." >&2
#     exit 0
# fi
