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

# 旧项目在 .init-done 之后才补上 Codex 技能。
# 有 .codex 时技能应在 .codex/skills；没有 .codex 时看低优先级的 .agents/skills。
# 标记在且对应位置的技能也在 → 跳过。缺了再跑 setup。补完以后这里会跳过。
codex_skills_missing=0
codex_skill_parent="$(codex_skill_parent_rel)"
if [[ -d "$SCRIPT_DIR/../assets/commands" ]]; then
    while IFS= read -r cmd_name; do
        [[ -n "$cmd_name" ]] || continue
        if [[ ! -e "$TARGET/${codex_skill_parent}/${cmd_name}/SKILL.md" ]]; then
            codex_skills_missing=1
            break
        fi
    done < <(find "$SCRIPT_DIR/../assets/commands" -maxdepth 1 -type f -name '*.md' -exec basename {} .md \;)
fi

if [[ -n "$(ci_resolve ".claude/.init-done" 2>/dev/null || true)" ]]; then
    if [[ "$codex_skills_missing" -eq 0 ]]; then
        exit 0
    fi
    # 已经初始化过，不必再 detect。只补缺失的 Codex 技能。
    if "$SCRIPT_DIR/setup-project.sh" "$TARGET"; then
        exit 0
    fi
    exit 2
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
