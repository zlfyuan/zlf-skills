#!/usr/bin/env bash
# Teardown / uninstall what setup-project.sh created in a code project.
# Symmetric counterpart to setup-project.sh:
#   - removes only files recorded by setup; shared directories are preserved
#     unless they become empty
#   - removes the .gitignore block we appended (or whole file if we created it)
#   - removes root-level CLAUDE.md / AGENTS.md ONLY when they match the
#     project-init template fingerprint (customized files are preserved)
#   - .claude/settings.local.json is preserved by default (may carry user
#     permissions); pass --purge-config to remove
#
# ⚠️  DESTRUCTIVE — this script DELETES files. By default it asks before
#   removing anything that could be user content. Pass --yes to skip prompts.
#   Use --dry-run to preview without touching disk.
#
# Usage:
#   teardown-project.sh [directory]                     # interactive
#   teardown-project.sh [directory] --yes               # skip confirmations
#   teardown-project.sh [directory] --dry-run           # audit only
#   teardown-project.sh [directory] --keep-config       # keep root CLAUDE.md/AGENTS.md + settings.local.json
#   teardown-project.sh [directory] --purge-config      # also remove settings.local.json (if it looks like ours)
#   teardown-project.sh [directory] --backup            # tar.gz a backup of what will be removed
#
# Exit codes:
#   0 - all targeted items cleaned
#   1 - directory not found or no project-init artifacts present
#   2 - user aborted or partial failure

set -euo pipefail

TARGET=""
YES=false
DRY_RUN=false
KEEP_CONFIG=false
PURGE_CONFIG=false
BACKUP=false

for arg in "$@"; do
    case "$arg" in
        --yes|-y)         YES=true ;;
        --dry-run|-n)     DRY_RUN=true ;;
        --keep-config|-k) KEEP_CONFIG=true ;;
        --purge-config)   PURGE_CONFIG=true ;;
        --backup|-b)      BACKUP=true ;;
        --help|-h)
            sed -n '2,30p' "$0"
            exit 0
            ;;
        -*)
            echo "❌ 未知选项: $arg" >&2
            exit 2
            ;;
        *)
            TARGET="$arg"
            ;;
    esac
done

TARGET="${TARGET:-$PWD}"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ ! -d "$TARGET" ]]; then
    echo "❌ Directory does not exist: $TARGET"
    exit 1
fi

cd "$TARGET"
TARGET_ABS="$PWD"

# ── Source case-insensitive path helpers ─────────────────────────────────
source "$SCRIPT_DIR/ci-path.sh"

# ── Resolve top-level entry names (复用用户在大小写敏感 FS 上已有的 .Claude/ 等变体） ──
# ci_canon 在命中时返回实际大小写；未命中时回退到原规范名（小写）
CLAUDE_DIR="$(ci_canon .claude)"
CODEX_DIR="$(ci_canon .codex)"
CODEGRAPH_DIR="$(ci_canon .codegraph)"
CLAUDE_MD_NAME="$(ci_canon CLAUDE.md)"
AGENTS_MD_NAME="$(ci_canon AGENTS.md)"
GITIGNORE_NAME="$(ci_canon .gitignore)"
SETTINGS_LOCAL="$CLAUDE_DIR/settings.local.json"
MANIFEST="$CLAUDE_DIR/.project-init-manifest"

echo "🧹 Teardown project: $TARGET_ABS"
[[ "$DRY_RUN" == true ]]   && echo "   Mode: DRY-RUN (no changes)"
[[ "$KEEP_CONFIG" == true ]] && echo "   Mode: keep-config (preserve CLAUDE.md / AGENTS.md / settings.local.json)"
[[ "$PURGE_CONFIG" == true ]] && echo "   Mode: purge-config (remove settings.local.json if it matches)"
[[ "$BACKUP" == true ]]    && echo "   Mode: backup (archive before removal)"
[[ "$YES" == true ]]       && echo "   Mode: assume-yes"

# ══════════════════════════════════════════════════════════════════════════
# PHASE 1: AUDIT
# ══════════════════════════════════════════════════════════════════════════
echo ""
echo "📋 Phase 1: Audit"

INIT_DONE=false
[[ -f "$CLAUDE_DIR/.init-done" ]] && INIT_DONE=true

if [[ "$INIT_DONE" == false && ! -d "$CLAUDE_DIR" && ! -d "$CODEX_DIR" && ! -d "$CODEGRAPH_DIR" && ! -f "$CLAUDE_MD_NAME" && ! -f "$AGENTS_MD_NAME" ]]; then
    echo "   (no project-init artifacts found — nothing to teardown)"
    exit 1
fi

REMOVE_DIRS=()        # empty directories listed in the setup manifest
REMOVE_FILES=()       # files/symlinks listed in the setup manifest
AMBIENT_DIRS=()       # removed unless --keep-config
AMBIENT_FILES=()      # removed unless --keep-config (fingerprint matched)
USER_FILES=()         # removed only with --yes (no fingerprint match — risky)
SKIP_NOTES=()         # informational, not removed

# Use the setup manifest when available. Directories are only removed with
# `rmdir` after their recorded children are gone, so user-added content wins.
if [[ -f "$MANIFEST" ]]; then
    while IFS= read -r entry; do
        [[ -z "$entry" || "${entry#\#}" != "$entry" ]] && continue
        # Root instructions and settings have their own fingerprint/config
        # policy below; never remove them solely because they are manifested.
        if [[ "$entry" == "$CLAUDE_MD_NAME" || "$entry" == "$AGENTS_MD_NAME" || "$entry" == "$SETTINGS_LOCAL" ]]; then
            continue
        fi
        if [[ -d "$entry" && ! -L "$entry" ]]; then
            REMOVE_DIRS+=("$entry")
        elif [[ -e "$entry" || -L "$entry" ]]; then
            REMOVE_FILES+=("$entry")
        fi
    done < "$MANIFEST"
    [[ "$KEEP_CONFIG" == true ]] || REMOVE_FILES+=("$MANIFEST")
else
    SKIP_NOTES+=("No setup manifest found; shared directories will be preserved")
fi

# Clean up known project-init symlinks/markers from older installations that
# predate the manifest, without recursively deleting their parent directories.
if [[ -L "$CLAUDE_DIR/CLAUDE.md" && "$(readlink "$CLAUDE_DIR/CLAUDE.md")" == "../$CLAUDE_MD_NAME" ]]; then
    REMOVE_FILES+=("$CLAUDE_DIR/CLAUDE.md")
fi
if [[ -L "$CODEX_DIR/AGENTS.md" && "$(readlink "$CODEX_DIR/AGENTS.md")" == "../$AGENTS_MD_NAME" ]]; then
    REMOVE_FILES+=("$CODEX_DIR/AGENTS.md")
fi
for sub in rules skills commands plans progress; do
    if [[ -L "$CODEX_DIR/$sub" && "$(readlink "$CODEX_DIR/$sub")" == "../$CLAUDE_DIR/$sub" ]]; then
        REMOVE_FILES+=("$CODEX_DIR/$sub")
    fi
done
[[ -f "$CLAUDE_DIR/.init-done" ]] && REMOVE_FILES+=("$CLAUDE_DIR/.init-done")
[[ -f "$CLAUDE_DIR/.init-stderr.log" ]] && REMOVE_FILES+=("$CLAUDE_DIR/.init-stderr.log")

# CLAUDE.md — fingerprint check
if [[ -f "$CLAUDE_MD_NAME" ]]; then
    if grep -qF "This file provides working guidance for Claude Code when contributing to this repository." "$CLAUDE_MD_NAME" \
       && grep -qF "## Plan 文件镜像（重要）" "$CLAUDE_MD_NAME"; then
        if [[ "$KEEP_CONFIG" == true ]]; then
            SKIP_NOTES+=("$CLAUDE_MD_NAME (--keep-config, matches project-init template)")
        else
            REMOVE_FILES+=("$CLAUDE_MD_NAME")
        fi
    else
        if [[ "$KEEP_CONFIG" == true ]]; then
            SKIP_NOTES+=("$CLAUDE_MD_NAME (--keep-config, user-customized)")
        else
            USER_FILES+=("$CLAUDE_MD_NAME (no project-init fingerprint — likely user content)")
        fi
    fi
fi

# AGENTS.md — fingerprint check
if [[ -f "$AGENTS_MD_NAME" ]]; then
    if grep -qF "This file provides guidance to Codex and other coding agents" "$AGENTS_MD_NAME" \
       && grep -qF "## Plan 文件镜像（重要）" "$AGENTS_MD_NAME"; then
        if [[ "$KEEP_CONFIG" == true ]]; then
            SKIP_NOTES+=("$AGENTS_MD_NAME (--keep-config, matches project-init template)")
        else
            REMOVE_FILES+=("$AGENTS_MD_NAME")
        fi
    else
        if [[ "$KEEP_CONFIG" == true ]]; then
            SKIP_NOTES+=("$AGENTS_MD_NAME (--keep-config, user-customized)")
        else
            USER_FILES+=("$AGENTS_MD_NAME (no project-init fingerprint — likely user content)")
        fi
    fi
fi

# .claude/settings.local.json — only remove with --purge-config, and only if it
# matches the project-init template shape (only "default" permissions)
if [[ -f "$SETTINGS_LOCAL" ]]; then
    if [[ "$PURGE_CONFIG" == true ]]; then
        # Check fingerprint: only contains the recommended permission set
        if CLAUDE_DIR="$CLAUDE_DIR" SETTINGS_LOCAL="$SETTINGS_LOCAL" python3 -c "
import json, sys, os
with open(os.environ['SETTINGS_LOCAL']) as f:
    data = json.load(f)
allow = set(data.get('permissions', {}).get('allow', []))
expected = {
    'Bash(npm:*)', 'Bash(npx:*)', 'Bash(yarn:*)', 'Bash(pnpm:*)', 'Bash(bun:*)',
    'Bash(pip:*)', 'Bash(pip3:*)', 'Bash(python:*)', 'Bash(python3:*)',
    'Bash(node:*)', 'Bash(go:*)', 'Bash(cargo:*)', 'Bash(rustc:*)',
    'Bash(javac:*)', 'Bash(mvn:*)', 'Bash(gradle:*)',
    'Bash(make:*)', 'Bash(cmake:*)', 'Bash(xcodebuild:*)', 'Bash(swift:*)',
    'Bash(codegraph:*)',
    'Bash(ls:*)', 'Bash(cat:*)', 'Bash(find:*)', 'Bash(grep:*)', 'Bash(wc:*)',
    'Bash(which:*)', 'Bash(echo:*)', 'Bash(mkdir:*)', 'Bash(cd:*)'
}
# settings.local.json 里的 plansDirectory 与 CLAUDE_DIR 必须匹配（一致大小写）
expected_plans = os.environ['CLAUDE_DIR'] + '/plans'
if data.get('plansDirectory') == expected_plans and allow == expected:
    sys.exit(0)
sys.exit(1)
" 2>/dev/null; then
            REMOVE_FILES+=("$SETTINGS_LOCAL")
        else
            USER_FILES+=("$SETTINGS_LOCAL (--purge-config requested, but file has user-customized permissions)")
        fi
    else
        SKIP_NOTES+=("$SETTINGS_LOCAL (pass --purge-config to remove)")
    fi
fi

# .gitignore — strip our block (or remove file if we created it whole)
GITIGNORE_HAS_BLOCK=false
GITIGNORE_WHOLE=false
if [[ -f "$GITIGNORE_NAME" ]]; then
    if grep -qF "# project-init generated local agent files" "$GITIGNORE_NAME"; then
        GITIGNORE_HAS_BLOCK=true
        # Was the file created entirely by us? Heuristic: file is small (≤ 7 lines)
        # and contains no content other than the header + 5 entries
        if [[ $(wc -l < "$GITIGNORE_NAME") -le 7 ]]; then
            GITIGNORE_WHOLE=true
        fi
    fi
fi

# ── Print audit ─────────────────────────────────────────────────────────
if [[ ${#REMOVE_DIRS[@]} -gt 0 ]]; then
    echo ""
    echo "   Directories to remove (created by setup):"
    for d in "${REMOVE_DIRS[@]}"; do
        echo "     - $d/"
    done
fi

if [[ ${#REMOVE_FILES[@]} -gt 0 ]]; then
    echo ""
    echo "   Files to remove (created by setup):"
    for f in "${REMOVE_FILES[@]}"; do
        echo "     - $f"
    done
fi

if [[ "$GITIGNORE_HAS_BLOCK" == true ]]; then
    echo ""
    if [[ "$GITIGNORE_WHOLE" == true ]]; then
        echo "   .gitignore to remove (entire file created by setup)"
    else
        echo "   .gitignore to modify (strip project-init block only)"
    fi
fi

if [[ ${#USER_FILES[@]} -gt 0 ]]; then
    echo ""
    echo "   ⚠ Files that look like USER content (not touched unless --yes):"
    for f in "${USER_FILES[@]}"; do
        echo "     - $f"
    done
fi

if [[ ${#SKIP_NOTES[@]} -gt 0 ]]; then
    echo ""
    echo "   Skipped (preserved):"
    for s in "${SKIP_NOTES[@]}"; do
        echo "     - $s"
    done
fi

if [[ ${#REMOVE_DIRS[@]} -eq 0 && ${#REMOVE_FILES[@]} -eq 0 && "$GITIGNORE_HAS_BLOCK" == false && ${#USER_FILES[@]} -eq 0 ]]; then
    echo ""
    echo "   (nothing to remove)"
    exit 0
fi

# ══════════════════════════════════════════════════════════════════════════
# PHASE 2: CONFIRM
# ══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Count actions
ACTION_COUNT=0
[[ ${#REMOVE_DIRS[@]}  -gt 0 ]] && ACTION_COUNT=$((ACTION_COUNT + ${#REMOVE_DIRS[@]}))
[[ ${#REMOVE_FILES[@]} -gt 0 ]] && ACTION_COUNT=$((ACTION_COUNT + ${#REMOVE_FILES[@]}))
[[ "$GITIGNORE_HAS_BLOCK" == true ]] && ACTION_COUNT=$((ACTION_COUNT + 1))
[[ ${#USER_FILES[@]} -gt 0 && "$YES" == true ]] && ACTION_COUNT=$((ACTION_COUNT + ${#USER_FILES[@]}))

echo "⚠  About to perform $ACTION_COUNT destructive action(s)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ "$DRY_RUN" == true ]]; then
    echo ""
    echo "🔍 DRY-RUN: no changes made. Re-run without --dry-run to apply."
    exit 0
fi

if [[ "$YES" != true ]]; then
    echo ""
    read -r -p "Continue? [y/N] " ans
    case "$ans" in
        y|Y|yes|YES) ;;
        *) echo "❌ Aborted."; exit 2 ;;
    esac
fi

# ══════════════════════════════════════════════════════════════════════════
# PHASE 3: BACKUP (optional)
# ══════════════════════════════════════════════════════════════════════════
if [[ "$BACKUP" == true ]]; then
    TS="$(date -u +%Y%m%dT%H%M%SZ)"
    ARCHIVE="$TARGET_ABS/.project-init-backup-$TS.tar.gz"
    echo ""
    echo "📦 Creating backup: $ARCHIVE"

    BACKUP_ARGS=()
    for d in "${REMOVE_DIRS[@]}"; do
        [[ -e "$d" ]] && BACKUP_ARGS+=("$d")
    done
    for f in "${REMOVE_FILES[@]}"; do
        [[ -e "$f" ]] && BACKUP_ARGS+=("$f")
    done
    [[ "$GITIGNORE_HAS_BLOCK" == true && -f "$GITIGNORE_NAME" ]] && BACKUP_ARGS+=("$GITIGNORE_NAME")
    [[ ${#USER_FILES[@]} -gt 0 && "$YES" == true ]] && for f in "${USER_FILES[@]}"; do
        path="${f%% *}"
        [[ -e "$path" ]] && BACKUP_ARGS+=("$path")
    done

    if [[ ${#BACKUP_ARGS[@]} -gt 0 ]]; then
        tar -czf "$ARCHIVE" "${BACKUP_ARGS[@]}" 2>/dev/null
        echo "   ✓ Archived ${#BACKUP_ARGS[@]} item(s)"
    fi
fi

# ══════════════════════════════════════════════════════════════════════════
# PHASE 4: REMOVE
# ══════════════════════════════════════════════════════════════════════════
echo ""
echo "🗑  Phase 4: Remove"

REMOVED=0
FAILED=0

remove_dir() {
    local d="$1"
    if [[ -d "$d" ]]; then
        if rmdir "$d" 2>/dev/null; then
            echo "   ✓ removed $d/"
            REMOVED=$((REMOVED + 1))
        else
            echo "   ↷ preserved non-empty $d/" >&2
        fi
    fi
}

remove_file() {
    local f="$1"
    if [[ -f "$f" || -L "$f" ]]; then
        if rm -f "$f" 2>/dev/null; then
            echo "   ✓ removed $f"
            REMOVED=$((REMOVED + 1))
        else
            echo "   ✗ failed to remove $f" >&2
            FAILED=$((FAILED + 1))
        fi
    fi
}

# Files first, then remove only empty manifest directories.
if [[ ${#REMOVE_FILES[@]} -gt 0 ]]; then
    for f in "${REMOVE_FILES[@]}"; do
        remove_file "$f"
    done
fi

if [[ ${#REMOVE_DIRS[@]} -gt 0 ]]; then
    for ((i=${#REMOVE_DIRS[@]} - 1; i>=0; i--)); do
        remove_dir "${REMOVE_DIRS[$i]}"
    done
fi

# .gitignore: strip block or remove whole file
if [[ "$GITIGNORE_HAS_BLOCK" == true ]]; then
    if [[ "$GITIGNORE_WHOLE" == true ]]; then
        remove_file "$GITIGNORE_NAME"
    else
        # Surgically strip the project-init block (header + 5 entries) from .gitignore.
        # sed range: from marker line through the next blank-line-just-before-EOF chunk.
        if sed -i.bak '/^# project-init generated local agent files$/,/^AGENTS\.md$/{/^AGENTS\.md$/d; /^# project-init generated local agent files$/d;}' "$GITIGNORE_NAME" 2>/dev/null \
            && sed -i.bak '/^$/N;/^\n$/d' "$GITIGNORE_NAME" 2>/dev/null \
            && rm -f "$GITIGNORE_NAME.bak"; then
            echo "   ✓ stripped project-init block from $GITIGNORE_NAME"
            REMOVED=$((REMOVED + 1))
        else
            echo "   ✗ failed to strip .gitignore block" >&2
            FAILED=$((FAILED + 1))
            rm -f "$GITIGNORE_NAME.bak"
        fi
    fi
fi

# User-flagged files (only with --yes)
if [[ "$YES" == true && ${#USER_FILES[@]} -gt 0 ]]; then
    for entry in "${USER_FILES[@]}"; do
        path="${entry%% *}"
        remove_file "$path"
    done
fi

# ══════════════════════════════════════════════════════════════════════════
# PHASE 5: CLEANUP / SUMMARY
# ══════════════════════════════════════════════════════════════════════════
# Best-effort codegraph index cleanup (no-op if CLI missing)
# 大小写不敏感：检查解析后的实际目录名，而不是硬编码 ".codegraph"
if command -v codegraph &> /dev/null && [[ ! -d "$CODEGRAPH_DIR" ]]; then
    codegraph clean "$TARGET_ABS" >/dev/null 2>&1 || true
fi

# Clean up empty parent dirs (使用解析后名) if anything was left
for d in "$CLAUDE_DIR" "$CODEX_DIR" "$CODEGRAPH_DIR"; do
    if [[ -d "$d" ]] && [[ -z "$(ls -A "$d" 2>/dev/null)" ]]; then
        rmdir "$d" 2>/dev/null || true
    fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ $FAILED -eq 0 ]]; then
    echo "✅ Teardown complete — $REMOVED item(s) removed"
else
    echo "⚠  Teardown finished with $FAILED error(s) — $REMOVED removed"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ ${#USER_FILES[@]} -gt 0 && "$YES" != true ]]; then
    echo ""
    echo "ℹ  Skipped (USER content, no fingerprint):"
    for f in "${USER_FILES[@]}"; do
        echo "   - $f"
    done
    echo "   Re-run with --yes to remove these too (destructive)."
fi

if [[ "$BACKUP" == true && -f .project-init-backup-*.tar.gz ]]; then
    echo ""
    echo "📦 Backup saved in project root: .project-init-backup-*.tar.gz"
fi

exit $((FAILED > 0 ? 1 : 0))
