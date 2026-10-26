#!/usr/bin/env bash
# Initialize a code project with Claude Code / Codex configuration.
# Creates .claude/ and .codex/ directory structures, runs codegraph init.
#
# ⚠️  ADDITIVE-ONLY PRINCIPLE:
#   - Existing files are NEVER overwritten or modified
#   - Existing directories are NEVER removed
#   - Only MISSING files and directories are created
#   - settings.local.json is MERGED (missing permissions added, existing kept)
#
# Usage: setup-project.sh [directory]
# Defaults to current working directory.

set -euo pipefail

TARGET="${1:-$PWD}"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Source shared Plan mirror rules + case-insensitive path lib ─────────
# plan-mirror-rules.sh: 让 setup 与 inject 复用同一份规则块与注入逻辑。
# ci-path.sh:           在大小写敏感 FS 上复用用户的 .Claude / .Codex 等变体。
# agents-mirror.sh:     把 CLAUDE.md 的项目约定镜像到 AGENTS.md（Codex 侧）。
source "$SCRIPT_DIR/plan-mirror-rules.sh"
source "$SCRIPT_DIR/ci-path.sh"
source "$SCRIPT_DIR/agents-mirror.sh"

# ── Resolve top-level entry names case-insensitively ──────────────────
# ci_canon returns the actual on-disk name if a case-variant already exists
# (e.g. ".Claude"), otherwise the canonical lowercase form (e.g. ".claude").
# All write targets below use these so we reuse user-existing dirs and never
# create parallel sibling copies like `.claude/` next to a pre-existing `.Claude/`.
CLAUDE_DIR="$(ci_canon .claude)"
CODEX_DIR="$(ci_canon .codex)"
CODEGRAPH_DIR="$(ci_canon .codegraph)"
CLAUDE_MD="$TARGET/$(ci_canon CLAUDE.md)"
AGENTS_MD="$TARGET/$(ci_canon AGENTS.md)"
SETTINGS_LOCAL="$TARGET/$CLAUDE_DIR/settings.local.json"
PROGRESS_README="$TARGET/$CLAUDE_DIR/progress/README.md"
PROBLEMS_MD="$TARGET/$CLAUDE_DIR/progress/problems.md"
MEMORY_INDEX="$TARGET/$CLAUDE_DIR/memory/MEMORY.md"
INIT_STDERR_LOG="$TARGET/$CLAUDE_DIR/.init-stderr.log"
GITIGNORE_FILE="$TARGET/$(ci_canon .gitignore)"
MANIFEST="$TARGET/$CLAUDE_DIR/.project-init-manifest"

# ── AGENTS.md 同步：模板没动过 + CLAUDE.md 已有真实约定 → 重新镜像 ────────
# 返回 0 = 已同步；返回 1 = 不满足同步条件（保持原样）
sync_agents_from_claude() {
    [[ -f "$AGENTS_MD" ]] || return 1
    agents_is_untouched_template "$AGENTS_MD" || return 1
    agents_claude_has_real_content "$CLAUDE_MD" || return 1
    echo "  [SYNC] AGENTS.md — still an untouched template, refreshing from CLAUDE.md..."
    agents_mirror "$CLAUDE_MD" "$AGENTS_MD"
    return 0
}

# ── Bundled git 命令：一份正文，两个发现入口 ──────────────────────────
# assets/commands/<name>.md 是唯一正文。
# Claude Code 读 .claude/commands/<name>.md，斜杠命令是 /<name>。
# Codex 不扫描 commands/，也不扫描 .codex/commands/。
# 技能目录：已有 .codex 时写到 .codex/skills/<name>/SKILL.md（高优先级，
# 通常是指到 .claude/skills 的软链）。没有 .codex 才写低优先级的 .agents/skills/。
# 正文仍是这一份命令模板，只包一层 skill frontmatter。

# 打印命令名（不含 .md），排序后逐行输出。没有模板目录时什么都不打印。
bundled_command_names() {
    [[ -d "$SKILL_DIR/assets/commands" ]] || return 0
    find "$SKILL_DIR/assets/commands" -maxdepth 1 -type f -name '*.md' -exec basename {} .md \; | sort
}

# Codex 靠 description 决定要不要选用该技能，所以每条命令要写清触发说法。
# 未知命令名走兜底，新增模板也不会从 Codex 的技能列表里消失。
bundled_skill_description() {
    case "$1" in
        z-commit)
            printf '%s' '把当前 working tree 的改动提交到本地 git，不 push。用户说 /z-commit、提交代码、只 commit 时使用。'
            ;;
        z-push)
            printf '%s' '把当前分支推送到 origin。没有上游时自动 set-upstream，绝不 force push。用户说 /z-push、推送、push 时使用。本地有未提交改动则先停下。'
            ;;
        z-commit-push)
            printf '%s' '先提交当前改动再推送到上游。用户说 /z-commit-push、提交并推送时使用。已有未推送 commit 时跳过 commit，只 push。'
            ;;
        *)
            printf '%s' "项目斜杠命令 /$1。用户显式调用 /$1 时使用。"
            ;;
    esac
}

# .gitignore 条目。命令在 .claude/commands/，有 .codex 时技能在 .codex/skills/，
# 这两处都已经被整目录忽略。低优先级的 .agents/skills/ 不在这里忽略，
# 避免把用户自己放在 .agents/skills/ 里的其他技能一并排除。
project_init_gitignore_entries() {
    printf '%s\n' '.claude/' '.codex/' '.codegraph/' 'CLAUDE.md' 'AGENTS.md'
}

# .agents 可能本来就有别的技能。只把本次新建的父目录记入 manifest，
# teardown 才只会在目录变空后删掉，不会拆用户已有的 .agents/。
ensure_agents_skills_dir() {
    if [[ -d "$TARGET/.agents/skills" ]]; then
        return 0
    fi
    if [[ -e "$TARGET/.agents" && ! -d "$TARGET/.agents" ]]; then
        echo "  [SKIP] .agents/skills — .agents exists but is not a directory" >&2
        return 1
    fi
    if [[ ! -e "$TARGET/.agents" ]]; then
        mkdir -p "$TARGET/.agents/skills"
        manifest_record ".agents"
        manifest_record ".agents/skills"
        return 0
    fi
    mkdir -p "$TARGET/.agents/skills"
    manifest_record ".agents/skills"
}

# ── Default permissions to ensure ───────────────────────────────────────
# These are the recommended permissions. If settings.local.json already
# exists, missing entries are added; existing entries are preserved.
DEFAULT_PERMISSIONS=(
    "Bash(npm:*)"
    "Bash(npx:*)"
    "Bash(yarn:*)"
    "Bash(pnpm:*)"
    "Bash(bun:*)"
    "Bash(pip:*)"
    "Bash(pip3:*)"
    "Bash(python:*)"
    "Bash(python3:*)"
    "Bash(node:*)"
    "Bash(go:*)"
    "Bash(cargo:*)"
    "Bash(rustc:*)"
    "Bash(javac:*)"
    "Bash(mvn:*)"
    "Bash(gradle:*)"
    "Bash(make:*)"
    "Bash(cmake:*)"
    "Bash(xcodebuild:*)"
    "Bash(swift:*)"
    # Git, network, and unrestricted file permissions remain prompt-gated.
    "Bash(codegraph:*)"
    "Bash(ls:*)"
    "Bash(cat:*)"
    "Bash(find:*)"
    "Bash(grep:*)"
    "Bash(wc:*)"
    "Bash(which:*)"
    "Bash(echo:*)"
    "Bash(mkdir:*)"
    "Bash(cd:*)"
)

echo "🔧 Setting up project: $TARGET"
echo "   Mode: additive-only (existing content preserved)"

# ── Check preconditions ─────────────────────────────────────────────────
if [[ ! -d "$TARGET" ]]; then
    echo "❌ Directory does not exist: $TARGET"
    exit 1
fi

# ══════════════════════════════════════════════════════════════════════════
# PHASE 1: AUDIT — Scan what exists and what's missing
# ══════════════════════════════════════════════════════════════════════════
echo ""
echo "📋 Phase 1: Audit"

AUDIT_NEW=()
AUDIT_EXISTING=()

check_file() {
    local path="$1"
    local label="$2"
    local resolved
    # ci_resolve 返回非 0 表示「大小写不敏感也都找不到」，用 || true 兜底 set -e
    if resolved="$(ci_resolve "$path" 2>/dev/null)" && [[ -n "$resolved" ]]; then
        AUDIT_EXISTING+=("  ✓ $label — already exists (at $resolved)")
        return 1
    else
        AUDIT_NEW+=("  + $label — will create")
        return 0
    fi
}

check_dir() {
    local path="$1"
    local label="$2"
    local resolved
    if resolved="$(ci_resolve "$path" 2>/dev/null)" && [[ -n "$resolved" ]]; then
        AUDIT_EXISTING+=("  ✓ $label/ — already exists (at $resolved/)")
        return 1
    else
        AUDIT_NEW+=("  + $label/ — will create")
        return 0
    fi
}

# Audit directories (|| true prevents set -e from tripping on return 1)
check_dir ".claude"              ".claude"              || true
check_dir ".claude/plans"        ".claude/plans"        || true
check_dir ".claude/rules"        ".claude/rules"        || true
check_dir ".claude/skills"       ".claude/skills"       || true
check_dir ".claude/commands"     ".claude/commands"     || true
check_dir ".claude/progress"     ".claude/progress"     || true
check_dir ".codex"               ".codex"               || true

# Audit progress files individually
if resolved="$(ci_resolve ".claude/progress/README.md" 2>/dev/null)" && [[ -n "$resolved" ]]; then
    AUDIT_EXISTING+=("  ✓ .claude/progress/README.md — already exists (at $resolved)")
else
    AUDIT_NEW+=("  + .claude/progress/README.md — will create")
fi
if resolved="$(ci_resolve ".claude/progress/problems.md" 2>/dev/null)" && [[ -n "$resolved" ]]; then
    AUDIT_EXISTING+=("  ✓ .claude/progress/problems.md — already exists (at $resolved)")
else
    AUDIT_NEW+=("  + .claude/progress/problems.md — will create")
fi

# Audit files
check_file "CLAUDE.md"                      "CLAUDE.md"                      || true
check_file "AGENTS.md"                      "AGENTS.md"                      || true
check_file ".codex/AGENTS.md"               ".codex/AGENTS.md"               || true
check_file ".gitignore"                     ".gitignore"                     || true
check_file ".claude/settings.local.json"    ".claude/settings.local.json"    || true
check_file ".claude/memory/MEMORY.md"       ".claude/memory/MEMORY.md"       || true

# Codex 技能缺失时必须进入 Phase 2。安装发生在 .codex 创建之后，
# 所以目标是 $CODEX_DIR/skills，不是低优先级的 .agents/skills。
# 用 -e 而不是 ci_resolve：.codex/skills 通常是软链，find 默认不追进去。
while IFS= read -r cmd_base; do
    [[ -n "$cmd_base" ]] || continue
    if [[ -e "$TARGET/$CODEX_DIR/skills/${cmd_base}/SKILL.md" || -L "$TARGET/$CODEX_DIR/skills/${cmd_base}/SKILL.md" ]]; then
        AUDIT_EXISTING+=("  ✓ $CODEX_DIR/skills/${cmd_base}/SKILL.md — already exists")
    else
        AUDIT_NEW+=("  + $CODEX_DIR/skills/${cmd_base}/SKILL.md — will create")
    fi
done < <(bundled_command_names)

# Audit codegraph
if resolved="$(ci_resolve ".codegraph" 2>/dev/null)" && [[ -n "$resolved" ]]; then
    AUDIT_EXISTING+=("  ✓ .codegraph/ — already initialized (at $resolved/)")
else
    AUDIT_NEW+=("  + .codegraph/ — will run codegraph init")
fi

# Print audit results
echo ""
echo "   Existing (will KEEP):"
if [[ ${#AUDIT_EXISTING[@]} -eq 0 ]]; then
    echo "     (none — fresh project)"
else
    for line in "${AUDIT_EXISTING[@]}"; do
        echo "$line"
    done
fi

echo ""
echo "   Missing (will CREATE):"
if [[ ${#AUDIT_NEW[@]} -eq 0 ]]; then
    # A project can already contain all generated artifacts without the
    # initialization marker (for example after a manual migration). Ensure the
    # marker is written so SessionStart hooks do not audit it every time.
    EXISTING_CLAUDE_DIR="$(ci_canon .claude)"
    if [[ ! -f "$TARGET/$EXISTING_CLAUDE_DIR/.init-done" ]]; then
        date -u +"%Y-%m-%dT%H:%M:%SZ" > "$TARGET/$EXISTING_CLAUDE_DIR/.init-done"
    fi
    # 没有新文件可建 ≠ 什么都不用做：AGENTS.md 可能还是没动过的模板，
    # 而 CLAUDE.md 早已有了真实项目约定 —— 这里补一次同步。
    if sync_agents_from_claude; then
        echo "     ✓ AGENTS.md synced from CLAUDE.md"
    fi
    echo "     (nothing — project already fully initialized)"
    echo ""
    echo "✅ Project already fully set up. Nothing to do."
    exit 0
else
    for line in "${AUDIT_NEW[@]}"; do
        echo "$line"
    done
fi

# ══════════════════════════════════════════════════════════════════════════
# PHASE 2: CREATE — Only add what's missing
# ══════════════════════════════════════════════════════════════════════════
echo ""
echo "🔨 Phase 2: Create missing items"

CREATED=0
SKIPPED=0
CREATED_PATHS=()

manifest_record() {
    CREATED_PATHS+=("$1")
}

manifest_record_tree() {
    local rel="$1"
    while IFS= read -r entry; do
        [[ -n "$entry" ]] && manifest_record "$entry"
    done < <(find "$TARGET/$rel" -mindepth 1 -print 2>/dev/null | sed "s#^$TARGET/##")
    manifest_record "$rel"
}

ensure_dir() {
    local full="$1"
    local rel="$2"
    if [[ ! -d "$full" ]]; then
        mkdir -p "$full"
        manifest_record "$rel"
    fi
}

# ── Create missing directories (mkdir -p is idempotent, safe) ───────────
echo "  → Ensuring directory structure..."
ensure_dir "$TARGET/$CLAUDE_DIR" "$CLAUDE_DIR"
ensure_dir "$TARGET/$CLAUDE_DIR/skills" "$CLAUDE_DIR/skills"
ensure_dir "$TARGET/$CLAUDE_DIR/rules" "$CLAUDE_DIR/rules"
ensure_dir "$TARGET/$CLAUDE_DIR/commands" "$CLAUDE_DIR/commands"
ensure_dir "$TARGET/$CLAUDE_DIR/plans" "$CLAUDE_DIR/plans"
ensure_dir "$TARGET/$CLAUDE_DIR/progress" "$CLAUDE_DIR/progress"
ensure_dir "$TARGET/$CLAUDE_DIR/memory" "$CLAUDE_DIR/memory"
ensure_dir "$TARGET/$CODEX_DIR" "$CODEX_DIR"

# ── .gitignore ─────────────────────────────────────────────────────────
GITIGNORE_ENTRIES=()
while IFS= read -r gitignore_entry; do
    [[ -n "$gitignore_entry" ]] && GITIGNORE_ENTRIES+=("$gitignore_entry")
done < <(project_init_gitignore_entries)

if [[ ! -f "$GITIGNORE_FILE" ]]; then
    echo "  [NEW] Creating .gitignore..."
    {
        printf '%s\n' '# project-init generated local agent files'
        printf '%s\n' "${GITIGNORE_ENTRIES[@]}"
    } > "$GITIGNORE_FILE"
    manifest_record "$(basename "$GITIGNORE_FILE")"
    CREATED=$((CREATED + 1))
else
    echo "  [MERGE] .gitignore — adding missing ignore rules..."
    touch "$GITIGNORE_FILE"
    MISSING=()
    for entry in "${GITIGNORE_ENTRIES[@]}"; do
        if ! grep -Fxq "$entry" "$GITIGNORE_FILE"; then
            MISSING+=("$entry")
        fi
    done
    if [[ ${#MISSING[@]} -gt 0 ]]; then
        if grep -qFxq '# project-init generated local agent files' "$GITIGNORE_FILE"; then
            # 已有 project-init 块 → 补进那一块，不新起一段
            # （新起一段会让 .gitignore 出现多个同名块，teardown 难以精确剥离）
            # 缺失项走 ENVIRON 传进 awk：awk -v 无法安全接收含换行的值
            AGENTS_GITIGNORE_MISSING="$(printf '%s\n' "${MISSING[@]}")" \
            awk '
                BEGIN { n = split(ENVIRON["AGENTS_GITIGNORE_MISSING"], arr, "\n"); done_add = 0 }
                # 块头 → 紧接着补齐缺失条目（只补第一段，重复块不再追加）
                /^# project-init generated local agent files$/ {
                    print
                    if (!done_add) {
                        for (i = 1; i <= n; i++) if (arr[i] != "") print arr[i]
                        done_add = 1
                    }
                    next
                }
                { print }
            ' "$GITIGNORE_FILE" > "$GITIGNORE_FILE.tmp" \
                && cat "$GITIGNORE_FILE.tmp" > "$GITIGNORE_FILE" \
                && rm -f "$GITIGNORE_FILE.tmp"
        else
            {
                printf '\n# project-init generated local agent files\n'
                printf '%s\n' "${MISSING[@]}"
            } >> "$GITIGNORE_FILE"
        fi
    fi
    SKIPPED=$((SKIPPED + 1))
fi

# ── CLAUDE.md ────────────────────────────────────────────────────────────
# 优先调用 `claude /init` 生成代码库感知的 CLAUDE.md，再追加 Plan 镜像规则。
# /init 用 --bare 跳过 SessionStart hooks（避免 auto-init 递归写入占位文件）。
# 失败时回退到带占位说明的 heredoc，并清楚提示用户。
# CLAUDE_MD / INIT_STDERR_LOG 已在 Phase 2 顶部用 ci_canon 解析（复用用户已有变体）
INIT_OK=false

if [[ ! -f "$CLAUDE_MD" ]]; then
    if command -v claude >/dev/null 2>&1; then
        echo "  [NEW] Generating CLAUDE.md via 'claude /init' (codebase-aware)..."
        # 两个必须的 trick：
        # 1. `< /dev/null` —— 后台 + 输出重定向时 stdin 不是 TTY，claude 会报
        #    "Warning: no stdin data received in 3s" 然后退出 0 不写文件
        # 2. `--permission-mode acceptEdits` —— 允许 /init 写入 CLAUDE.md，
        #    但不绕过其它工具的权限检查。
        (
            cd "$TARGET" && \
            claude --bare --permission-mode acceptEdits \
                --allowedTools "Write,Read,Glob,Grep,Bash(ls:*),Bash(find:*),Bash(cat:*),Bash(wc:*),Bash(head:*)" \
                -p "/init" < /dev/null
        ) > /dev/null 2> "$INIT_STDERR_LOG" &
        INIT_PID=$!

        # 限时 180s；/init 对小项目 < 30s，大仓库也很少超过 2 分钟
        WAITED=0
        MAX_WAIT=180
        while kill -0 "$INIT_PID" 2>/dev/null; do
            if [[ $WAITED -ge $MAX_WAIT ]]; then
                kill -TERM "$INIT_PID" 2>/dev/null
                sleep 1
                kill -KILL "$INIT_PID" 2>/dev/null
                wait "$INIT_PID" 2>/dev/null
                echo "      ⚠ /init timed out after ${MAX_WAIT}s"
                break
            fi
            sleep 1
            WAITED=$((WAITED + 1))
            if (( WAITED % 15 == 0 )); then
                echo "      ... still running (${WAITED}s)"
            fi
        done
        wait "$INIT_PID" 2>/dev/null

        # 校验产物：存在 + 体积合理 + 不像 fallback 占位
        if [[ -f "$CLAUDE_MD" ]]; then
            SIZE=$(wc -c < "$CLAUDE_MD" | tr -d ' ')
            if [[ $SIZE -ge 500 ]] && ! grep -q "Describe the repository purpose" "$CLAUDE_MD" 2>/dev/null; then
                echo "  ✓ CLAUDE.md generated by /init (${SIZE} bytes)"
                INIT_OK=true
                manifest_record "$(basename "$CLAUDE_MD")"
                CREATED=$((CREATED + 1))
            else
                echo "      ⚠ /init output too small or looks like placeholder (${SIZE} bytes); falling back"
                rm -f "$CLAUDE_MD"
            fi
        else
            echo "      ⚠ /init did not produce CLAUDE.md; falling back"
            [[ -s "$INIT_STDERR_LOG" ]] && echo "      (see .claude/.init-stderr.log for details)"
        fi
    else
        echo "  [SKIP] claude CLI not installed — falling back to placeholder"
        echo "      Install Claude Code to enable codebase-aware generation: https://claude.com/claude-code"
    fi

    if [[ "$INIT_OK" != "true" ]]; then
        # 回退：写带 Plan 镜像的占位模板（用户后续可手动 `claude /init` 覆盖）
        echo "  [NEW] Creating placeholder CLAUDE.md (will be overwritten by 'claude /init' if run later)..."
        cat > "$CLAUDE_MD" << 'CLAUDE_EOF'
# CLAUDE.md

<!-- project-init: placeholder -->

This file provides working guidance for Claude Code when contributing to this repository.

## Project Overview

- Describe the repository purpose and primary user workflow.
- Keep this file focused on project-specific context that helps future sessions.

## Working Rules

- Prefer small, verifiable changes over broad refactors.
- Run the relevant build, test, or lint commands before declaring work complete.
- Document non-obvious decisions in the repository when they matter for future maintenance.

## Build & Test Commands

- Add the repository-specific commands for install, build, test, and lint here.
- Use the project's existing scripts whenever possible.

## Notes

- This placeholder was created by project-init because `claude /init` was unavailable
  or failed. To regenerate with real codebase content, run:
      `claude --bare --allowedTools "Write,Read,Glob,Grep,Bash(ls:*),Bash(find:*),Bash(cat:*),Bash(wc:*)" -p "/init"`
- The Plan mirror instructions below are required for plan-mode workflows.

## Plan 文件镜像（重要）

harness 默认把 plan 写到 `~/.claude/plans/<session>.md`（系统路径，不在项目内），无法被 git 追踪。
为保证 `.claude/plans/` 里有项目级副本，**每次调用 `ExitPlanMode` 之前必须先执行以下步骤**：

1. 从 plan mode 的 system message 里拿到 plan 的 `file_path`（绝对路径，harness 会告知）
2. `mkdir -p .claude/plans`
3. `cp <file_path> .claude/plans/$(basename <file_path>)`
4. 用 Edit 在副本末尾追加一行：`<!-- mirror source: <file_path> -->`
5. **完成上述 4 步之后再调用 `ExitPlanMode`**

不执行镜像会让 plan 文件留在系统 `~/.claude/plans/` 里，项目级 `.claude/plans/` 始终为空。
注：`settings.local.json` 里的 `plansDirectory` 字段是预留配置，当前 harness 版本不读取，仍需通过本规则手动镜像。
CLAUDE_EOF
        manifest_record "$(basename "$CLAUDE_MD")"
        CREATED=$((CREATED + 1))
    else
        # /init 成功了：把 Plan 镜像规则追加到末尾（/init 不会写这个）
        if pmr_inject "$TARGET" "CLAUDE.md"; then
            CREATED=$((CREATED + 1))  # 注入计为一次写入
        fi
    fi
else
    echo "  [KEEP] CLAUDE.md — preserving existing content"
    SKIPPED=$((SKIPPED + 1))
    # 已存在但缺少 Plan 镜像规则 → 自动追加（覆盖 /init 创建的文件等场景）
    if pmr_inject "$TARGET" "CLAUDE.md"; then
        CREATED=$((CREATED + 1))  # 注入计为一次写入
    fi
fi

# ── settings.local.json (MERGE, not overwrite) ──────────────────────────
# SETTINGS_LOCAL 已在 Phase 2 顶部用 ci_canon 解析
if [[ ! -f "$SETTINGS_LOCAL" ]]; then
    echo "  [NEW] Creating .claude/settings.local.json..."
    # Build JSON with python3 for proper formatting
    CLAUDE_DIR="$CLAUDE_DIR" SETTINGS_LOCAL="$SETTINGS_LOCAL" python3 -c "
import json, os
# plansDirectory 必须匹配实际目录名（含用户的 case-variant）
data = {
    'plansDirectory': os.environ['CLAUDE_DIR'] + '/plans',
    'permissions': {
        'allow': [
            'Bash(npm:*)', 'Bash(npx:*)', 'Bash(yarn:*)', 'Bash(pnpm:*)', 'Bash(bun:*)',
            'Bash(pip:*)', 'Bash(pip3:*)', 'Bash(python:*)', 'Bash(python3:*)',
            'Bash(node:*)', 'Bash(go:*)', 'Bash(cargo:*)', 'Bash(rustc:*)',
            'Bash(javac:*)', 'Bash(mvn:*)', 'Bash(gradle:*)',
            'Bash(make:*)', 'Bash(cmake:*)', 'Bash(xcodebuild:*)', 'Bash(swift:*)',
            'Bash(codegraph:*)',
            'Bash(ls:*)', 'Bash(cat:*)', 'Bash(find:*)', 'Bash(grep:*)', 'Bash(wc:*)',
            'Bash(which:*)', 'Bash(echo:*)', 'Bash(mkdir:*)', 'Bash(cd:*)'
        ]
    }
}
with open(os.environ['SETTINGS_LOCAL'], 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"
    manifest_record "$CLAUDE_DIR/settings.local.json"
    CREATED=$((CREATED + 1))
else
    # Merge: add missing permissions + plansDirectory if absent
    echo "  [MERGE] .claude/settings.local.json — adding missing permissions..."
    CLAUDE_DIR="$CLAUDE_DIR" SETTINGS_LOCAL="$SETTINGS_LOCAL" python3 -c "
import json, os

with open(os.environ['SETTINGS_LOCAL'], 'r') as f:
    data = json.load(f)

# Track what we added
added = []

# Ensure plansDirectory matches the actual on-disk CLAUDE_DIR case
if 'plansDirectory' not in data:
    data['plansDirectory'] = os.environ['CLAUDE_DIR'] + '/plans'
    added.append('plansDirectory')

# Ensure permissions.allow exists
data.setdefault('permissions', {}).setdefault('allow', [])
existing = set(data['permissions']['allow'])

# Recommended permissions to check
recommended = [
    'Bash(npm:*)', 'Bash(npx:*)', 'Bash(yarn:*)', 'Bash(pnpm:*)', 'Bash(bun:*)',
    'Bash(pip:*)', 'Bash(pip3:*)', 'Bash(python:*)', 'Bash(python3:*)',
    'Bash(node:*)', 'Bash(go:*)', 'Bash(cargo:*)', 'Bash(rustc:*)',
    'Bash(javac:*)', 'Bash(mvn:*)', 'Bash(gradle:*)',
    'Bash(make:*)', 'Bash(cmake:*)', 'Bash(xcodebuild:*)', 'Bash(swift:*)',
    'Bash(codegraph:*)',
    'Bash(ls:*)', 'Bash(cat:*)', 'Bash(find:*)', 'Bash(grep:*)', 'Bash(wc:*)',
    'Bash(which:*)', 'Bash(echo:*)', 'Bash(mkdir:*)', 'Bash(cd:*)'
]

for perm in recommended:
    if perm not in existing:
        data['permissions']['allow'].append(perm)
        added.append(perm)

with open(os.environ['SETTINGS_LOCAL'], 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')

if added:
    print(f'    Added {len(added)} missing entries:')
    for a in added:
        print(f'      + {a}')
else:
    print('    All permissions already present, nothing to add')
"
    SKIPPED=$((SKIPPED + 1))
fi

# ── AGENTS.md (Codex instructions) ──────────────────────────────────────
# AGENTS_MD 已在 Phase 2 顶部用 ci_canon 解析。
# 会话开始检查必须写小写 `.codex/`：Codex 会把产品名幻觉成 `.Codex/`，
# 在大小写敏感 FS / 字面 glob 上把已初始化的项目当成缺失。
#
# 同步策略：CLAUDE.md 里已有真实项目约定时，AGENTS.md 由 CLAUDE.md 镜像生成
# （Codex 侧适配见 agents-mirror.sh）——两份文件各写一遍必然漂移。
# CLAUDE.md 缺失 / 仍是占位模板 → 退回 project-init 自带模板。
if [[ ! -f "$AGENTS_MD" ]]; then
    if agents_claude_has_real_content "$CLAUDE_MD"; then
        echo "  [NEW] Creating AGENTS.md — mirrored from CLAUDE.md..."
        agents_mirror "$CLAUDE_MD" "$AGENTS_MD"
    else
        echo "  [NEW] Creating AGENTS.md (Codex)..."
        {
            cat << 'AGENTS_EOF'
# AGENTS.md

This file provides guidance to Codex and other coding agents working in this repository.

AGENTS_EOF
            printf '%s\n\n' "$AGENTS_SESSION_CHECK"
            cat << 'AGENTS_EOF'
## Project Overview

- Describe the repository purpose and the main workflows for contributors.
- Keep instructions focused on reliable, low-risk changes.

## Working Expectations

- Prefer existing project conventions over introducing new patterns.
- Validate changes with the project's relevant test or build commands.
- Call out risky assumptions or missing context when they affect implementation.

## Build & Test Commands

- Add the repository-specific commands for install, build, test, and lint here.
- Prefer invoking the existing scripts or package-manager tasks.

## Plan 文件镜像（重要）

harness 默认把 plan 写到 `~/.claude/plans/<session>.md`（系统路径，不在项目内），无法被 git 追踪。
为保证 `.claude/plans/` 里有项目级副本，**每次退出 plan 模式之前必须先执行以下步骤**：

1. 从 plan mode 的 system message 里拿到 plan 的 `file_path`（绝对路径）
2. `mkdir -p .claude/plans`
3. `cp <file_path> .claude/plans/$(basename <file_path>)`
4. 在副本末尾追加一行：`<!-- mirror source: <file_path> -->`
5. **完成上述 4 步之后再退出 plan 模式**

注：`settings.local.json` 里的 `plansDirectory` 字段是预留配置，当前 harness 版本不读取，仍需通过本规则手动镜像。
AGENTS_EOF
        } > "$AGENTS_MD"
    fi
    manifest_record "$(basename "$AGENTS_MD")"
    CREATED=$((CREATED + 1))
elif agents_is_untouched_template "$AGENTS_MD" && agents_claude_has_real_content "$CLAUDE_MD"; then
    # AGENTS.md 还是没动过的模板，而 CLAUDE.md 已有真实约定 → 重新同步
    sync_agents_from_claude
    manifest_record "$(basename "$AGENTS_MD")"
    CREATED=$((CREATED + 1))
else
    echo "  [KEEP] AGENTS.md — preserving existing content"
    SKIPPED=$((SKIPPED + 1))
fi

# Plan 镜像规则：镜像正文里没有就补上（已有则跳过）
if pmr_inject "$TARGET" "AGENTS.md"; then
    CREATED=$((CREATED + 1))
fi

# ── .codex/AGENTS.md (软连接 → ../AGENTS.md) ────────────────────────────────────
# 新布局：以 .claude/ 为主，.codex/ 内容都是软连接到 .claude/ ，
# 唯一例外是 .codex/AGENTS.md 与 .claude/CLAUDE.md —— 它们是给对方工具
# 直接读取的入口文件，symlink 指向项目根的 AGENTS.md / CLAUDE.md。
CODEX_AGENTS="$TARGET/$CODEX_DIR/AGENTS.md"
if [[ ! -e "$CODEX_AGENTS" && ! -L "$CODEX_AGENTS" ]]; then
    if [[ -f "$AGENTS_MD" ]]; then
        ln -s "../AGENTS.md" "$CODEX_AGENTS"
        echo "  [NEW] Symlinked $CODEX_DIR/AGENTS.md → ../AGENTS.md"
        manifest_record "$CODEX_DIR/AGENTS.md"
        CREATED=$((CREATED + 1))
    else
        echo "  [SKIP] $CODEX_DIR/AGENTS.md symlink — project-root AGENTS.md missing"
    fi
else
    echo "  [KEEP] $CODEX_DIR/AGENTS.md — preserving existing"
    SKIPPED=$((SKIPPED + 1))
fi

# ── .claude/CLAUDE.md 软连接到项目根 CLAUDE.md ────────────────────────────
CLAUDE_SYMLINK="$TARGET/$CLAUDE_DIR/CLAUDE.md"
if [[ ! -e "$CLAUDE_SYMLINK" && ! -L "$CLAUDE_SYMLINK" ]]; then
    if [[ -f "$CLAUDE_MD" ]]; then
        ln -s "../CLAUDE.md" "$CLAUDE_SYMLINK"
        echo "  [NEW] Symlinked $CLAUDE_DIR/CLAUDE.md → ../CLAUDE.md"
        manifest_record "$CLAUDE_DIR/CLAUDE.md"
        CREATED=$((CREATED + 1))
    fi
else
    : # 已存在（实文件或 symlink）就不动
fi

# ── .codex/<sub> 软连接到 ../.claude/<sub>（rules / skills / commands / plans / progress） ──
# Additive：目标实目录已存在则跳过 symlink；目标不存在则也无 .claude/<sub> 可指。
for sub in rules skills commands plans progress; do
    target_link="$TARGET/$CODEX_DIR/$sub"
    target_real="$TARGET/$CLAUDE_DIR/$sub"
    if [[ -d "$target_real" ]] && [[ ! -e "$target_link" && ! -L "$target_link" ]]; then
        ln -s "../$CLAUDE_DIR/$sub" "$target_link"
        echo "  [NEW] Symlinked $CODEX_DIR/$sub → ../$CLAUDE_DIR/$sub"
        manifest_record "$CODEX_DIR/$sub"
        CREATED=$((CREATED + 1))
    fi
done

# ── 安装 bundled 命令：Claude 斜杠命令 + Codex 技能（additive：已存在不动） ──
# 正文优先用项目里已经存在的 .claude/commands/<name>.md（用户可能改过），
# 没有才从 assets 拷贝。Codex 技能只在 SKILL.md 不存在时生成。
if [[ -d "$SKILL_DIR/assets/commands" ]]; then
    mkdir -p "$TARGET/$CLAUDE_DIR/commands"
    while IFS= read -r cmd_base; do
        [[ -n "$cmd_base" ]] || continue
        src_cmd="$SKILL_DIR/assets/commands/${cmd_base}.md"
        target_cmd="$TARGET/$CLAUDE_DIR/commands/${cmd_base}.md"
        if [[ ! -e "$target_cmd" && ! -L "$target_cmd" ]]; then
            cp "$src_cmd" "$target_cmd"
            echo "  [NEW] Installed command: $CLAUDE_DIR/commands/${cmd_base}.md"
            manifest_record "$CLAUDE_DIR/commands/${cmd_base}.md"
            CREATED=$((CREATED + 1))
        fi

        # 有 .codex 就放 .codex/skills；没有才落到低优先级的 .agents/skills。
        # 安装时 .codex 已经建好，正常初始化不会走 .agents。
        skill_parent_rel="$(codex_skill_parent_rel)"
        skill_file="$TARGET/${skill_parent_rel}/${cmd_base}/SKILL.md"
        agents_dir="$TARGET/.agents/skills/${cmd_base}"
        agents_skill="${agents_dir}/SKILL.md"
        if [[ -e "$skill_file" || -L "$skill_file" ]]; then
            :
        else
            if [[ "$skill_parent_rel" == ".agents/skills" ]]; then
                ensure_agents_skills_dir || continue
            fi
            # .codex/skills 若是软链，真实目录在 .claude/skills。manifest 记真实路径，
            # teardown 先删软链时仍能删掉技能目录。
            if [[ -L "$TARGET/$skill_parent_rel" ]]; then
                manifest_skill_dir="$CLAUDE_DIR/skills/${cmd_base}"
            else
                manifest_skill_dir="${skill_parent_rel}/${cmd_base}"
            fi
            if [[ ! -d "$TARGET/$manifest_skill_dir" ]]; then
                mkdir -p "$TARGET/$manifest_skill_dir"
                manifest_record "$manifest_skill_dir"
            fi
            if [[ "$skill_parent_rel" != ".agents/skills" && -f "$agents_skill" ]]; then
                # 上一版装在低优先级目录。目标还没有文件时把用户改过的正文搬过来。
                cp "$agents_skill" "$skill_file"
                echo "  [NEW] Moved Codex skill .agents/skills/${cmd_base} → ${skill_parent_rel}/${cmd_base}"
            else
                {
                    printf '%s\n' '---'
                    printf 'name: %s\n' "$cmd_base"
                    printf 'description: "%s"\n' "$(bundled_skill_description "$cmd_base")"
                    printf '%s\n' '---'
                    printf '\n'
                    # 调用名不同，步骤相同。写在正文开头，避免 Codex 去找 commands 目录。
                    printf 'Codex 用 `$%s` 调用本技能，步骤与 Claude Code 的 `/%s` 相同。\n\n' "$cmd_base" "$cmd_base"
                    cat "$target_cmd"
                } > "$skill_file"
                echo "  [NEW] Installed Codex skill: ${skill_parent_rel}/${cmd_base}/SKILL.md"
            fi
            manifest_record "${manifest_skill_dir}/SKILL.md"
            CREATED=$((CREATED + 1))
        fi

        # 高优先级目录里已经有同一份文件时，删掉 .agents 里仅含 SKILL.md 的副本。
        # 两边内容不同就都留着，避免盖掉用户只改在低优先级目录里的版本。
        if [[ "$skill_parent_rel" != ".agents/skills" && -f "$agents_skill" && -f "$skill_file" ]] \
            && cmp -s "$agents_skill" "$skill_file"; then
            agents_extra="$(find "$agents_dir" -mindepth 1 ! -name 'SKILL.md' -print 2>/dev/null | head -n 1)"
            if [[ -z "$agents_extra" ]]; then
                rm -f "$agents_skill"
                rmdir "$agents_dir" 2>/dev/null || true
                rmdir "$TARGET/.agents/skills" 2>/dev/null || true
                rmdir "$TARGET/.agents" 2>/dev/null || true
            fi
        fi
    done < <(bundled_command_names)
fi

# ── CodeGraph initialization ────────────────────────────────────────────
echo "  → Checking CodeGraph..."

# codegraph 官方安装脚本默认装到 ~/.local/bin，但 GUI 启动的 agent 进程常常
# 没把它带进 PATH（表现为「CLI 未安装」）—— 这里显式补查。
CODEGRAPH_BIN="$(command -v codegraph 2>/dev/null || true)"
if [[ -z "$CODEGRAPH_BIN" && -x "$HOME/.local/bin/codegraph" ]]; then
    CODEGRAPH_BIN="$HOME/.local/bin/codegraph"
    export PATH="$HOME/.local/bin:$PATH"
fi

if [[ -n "$CODEGRAPH_BIN" ]]; then
    echo "    codegraph CLI: $CODEGRAPH_BIN ($("$CODEGRAPH_BIN" --version 2>/dev/null || echo 'ok'))"
else
    echo "    ⚠ codegraph CLI is not installed."
    echo "      Install: curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh"
fi

if [[ -n "$(ci_resolve .codegraph 2>/dev/null)" ]]; then
    echo "  [KEEP] .codegraph/ — already initialized"
    SKIPPED=$((SKIPPED + 1))
else
    if [[ -n "$CODEGRAPH_BIN" ]]; then
        echo "  [NEW] Running codegraph init..."
        if "$CODEGRAPH_BIN" init "$TARGET" 2>&1 | sed 's/^/    /'; then
            echo "  ✓ CodeGraph initialized"
            manifest_record_tree "$CODEGRAPH_DIR"
            CREATED=$((CREATED + 1))
        else
            echo "  ⚠ codegraph init failed (non-fatal)"
        fi
    else
        echo "  [SKIP] codegraph init (CLI not installed)"
        SKIPPED=$((SKIPPED + 1))
    fi
fi

# ── .claude/progress/ (autonomous dev tracking) ─────────────────────────
# PROGRESS_README / PROBLEMS_MD 已在 Phase 2 顶部用 CLAUDE_DIR 解析
# .codex/AGENTS.md 是软连接到 ../AGENTS.md，规则块已通过 pmr_inject 写到根 AGENTS.md

if [[ ! -f "$PROGRESS_README" ]]; then
    echo "  [NEW] Creating .claude/progress/README.md..."
    cat > "$PROGRESS_README" << 'PROGRESS_README_EOF'
# 开发进度总览

> 由 project-init 自动创建 · 每个 Stage 完成后更新

## 📊 当前状态

- **项目**: <!-- 项目名称 -->
- **任务目标**: <!-- /goal 或 /loop 设置的总目标 -->
- **当前阶段**: Stage 001
- **总体进度**: 0/1 stages
- **最后更新**: <!-- YYYY-MM-DD HH:MM -->

---

## 📋 Stage 列表

| # | Stage | 名称 | 状态 | 备注 |
|---|-------|------|------|------|
| 001 | — | <!-- 任务名 --> | ⏳ 规划中 | — |

<!--
状态图例:
  ⏳ 规划中 — 尚未开始
  🔄 进行中 — 正在开发
  ✅ 已完成 — 开发+验证通过
  🔴 已跳过 — 超过重试上限
  ⏸️ 搁置   — 等待外部条件
-->

---

## 📈 进度统计

- **总 Stages**: 1
- **已完成**: 0
- **进行中**: 0
- **已跳过**: 0

---

## 🚧 已知问题速览

→ 详见 [problems.md](problems.md)

<!-- 此处只列当前未解决的问题 -->

| # | 问题简述 | Stage | 尝试次数 | 状态 |
|---|---------|-------|---------|------|
| — | — | — | — | — |

---

## 📝 下一步

- [ ] 开始 Stage 001
PROGRESS_README_EOF
    manifest_record "$CLAUDE_DIR/progress/README.md"
    CREATED=$((CREATED + 1))
else
    echo "  [KEEP] .claude/progress/README.md — preserving existing content"
    SKIPPED=$((SKIPPED + 1))
fi

if [[ ! -f "$PROBLEMS_MD" ]]; then
    echo "  [NEW] Creating .claude/progress/problems.md..."
    cat > "$PROBLEMS_MD" << 'PROBLEMS_EOF'
# 问题踩坑记录

> 记录开发过程中反复遇到的问题、尝试过的方案、以及最终解决方式。
> 同一个问题多次遇到时，更新「出现次数」而非新建条目。

## 📊 问题统计

- **总记录数**: 0
- **已解决**: 0
- **已跳过 (>5次)**: 0
- **搁置中**: 0

---

## 问题索引

| # | 问题简述 | 涉及 Stage | 出现次数 | 状态 |
|---|---------|-----------|---------|------|
| — | — | — | — | — |

<!--
状态图例:
  ✅ 已解决 — 找到方案并验证通过
  🔴 已跳过 — 超过 5 次尝试，暂时放弃
  ⏸️ 搁置   — 等待外部条件（依赖更新、API 修复等）
  🔍 分析中 — 正在排查根因
-->

---

## 问题详情

<!--
模板：

### 问题 N: 简短描述

- **首次发现**: YYYY-MM-DD | Stage XXX
- **状态**: ✅已解决 / 🔴已跳过 / ⏸️搁置
- **出现次数**: X/5
- **严重程度**: 🔴阻塞 / 🟡影响进度 / 🟢可绕过

#### 症状
- 错误信息: `...`
- 触发条件: ...
- 影响范围: ...

#### 尝试过的方案
1. **方案描述** — 结果: 失败
   - 原因: ...
2. **方案描述** — 结果: ✅ 成功
   - 关键点: ...

#### 最终方案

#### 经验总结
-->
PROBLEMS_EOF
    manifest_record "$CLAUDE_DIR/progress/problems.md"
    CREATED=$((CREATED + 1))
else
    echo "  [KEEP] .claude/progress/problems.md — preserving existing content"
    SKIPPED=$((SKIPPED + 1))
fi

# ── .claude/memory/MEMORY.md (项目级长期记忆索引) ─────────────────────────
# 区别于 .claude/progress/（按 Stage 滚动），本目录存跨会话 / 不再变的长期知识：
# 设计决策、长期约束、已知坑、本项目特有约定。MEMORY.md 自身每次会话加载到上下文，
# 单篇事实以独立的 <slug>.md 文件存储，正文用 [[name]] 互链。
if [[ ! -f "$MEMORY_INDEX" ]]; then
    echo "  [NEW] Creating $CLAUDE_DIR/memory/MEMORY.md..."
    cat > "$MEMORY_INDEX" << 'MEMORY_EOF'
# MEMORY

> 项目级长期记忆索引。每次会话开始时被加载到上下文，正文事实以单独 `<slug>.md` 文件存储。
>
> 与 `.claude/progress/` 的区别：progress 按 Stage / Issue 滚动更新，memory 存**跨 Stage 不变**的事实（设计决策、长期约束、已知坑、命名约定）。

## 怎么用

- **新增一条记忆**：在 `.claude/memory/` 目录下新建一个 `<kebab-case-slug>.md`，文件含 YAML frontmatter（`name` / `description` / `type: feedback|reference|project`）。
- **在本索引登记**：在下方列表里加一行 `- [标题](<slug>.md) — 一句话摘要`。
- **关联**：在其它 memory 文件里用 `[[<slug>]]` 互相引用。
- **修改 / 删除**：直接编辑 `.md` 正文；本索引的链接会自动跟随。

## 不要什么

- 不要把**当前任务进度**写到这里 —— 那是 `.claude/progress/` 的职责。
- 不要把**敏感信息**（密码、API key、token）写到这里。

## 索引

| # | 标题 | 类型 | 摘要 |
|---|------|------|------|
| — | — | — | — |
MEMORY_EOF
    manifest_record "$CLAUDE_DIR/memory/MEMORY.md"
    CREATED=$((CREATED + 1))
else
    echo "  [KEEP] $CLAUDE_DIR/memory/MEMORY.md — preserving existing"
    SKIPPED=$((SKIPPED + 1))
fi

# ── Mark initialization done ────────────────────────────────────────────
# INIT_MARKER 跟随已解析的 CLAUDE_DIR（用户已有 .Claude/ 时也写入 .Claude/.init-done）
INIT_MARKER="$TARGET/$CLAUDE_DIR/.init-done"
manifest_record "$CLAUDE_DIR/.init-done"
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$INIT_MARKER"

# Keep teardown ownership explicit. Only paths created by this run are
# eligible for automatic removal; user-added files in shared directories stay.
if [[ ! -f "$MANIFEST" ]]; then
    printf '%s\n' '# project-init created paths' > "$MANIFEST"
fi
for created_path in "${CREATED_PATHS[@]}"; do
    if ! grep -Fxq "$created_path" "$MANIFEST" 2>/dev/null; then
        printf '%s\n' "$created_path" >> "$MANIFEST"
    fi
done

# ══════════════════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Setup complete — $CREATED created, $SKIPPED preserved"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "   Next steps:"
echo "   1. Put project conventions in CLAUDE.md — AGENTS.md mirrors it for Codex"
echo "   2. Review .claude/progress/README.md (autonomous dev tracking)"
echo "   3. Run 'codegraph status' to verify indexing"
echo "   4. Restart your agent to pick up the new config"
echo ""
echo "   🌀 Autonomous development:"
echo "   Use /loop or /goal to start autonomous dev mode."
echo "   Progress tracked in .claude/progress/ (README.md + stage-NNN.md + problems.md)"
echo "   Each module is verified before advancing; issues failing >5 times are skipped."
