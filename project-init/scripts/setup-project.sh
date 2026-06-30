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

# ── Source shared Plan mirror rules (lib) ───────────────────────────────
# 让 setup-project.sh 能复用 inject-plan-mirror.sh 的规则块文本与注入逻辑。
# 新文件仍用 heredoc 一次性写入（更快），已有文件 [KEEP] 时再调用 pmr_inject 追加。
source "$SCRIPT_DIR/plan-mirror-rules.sh"

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
    "Bash(git:*)"
    "Bash(curl:*)"
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
    "Read(*)"
    "Edit(*)"
    "Write(*)"
    "WebFetch(*)"
    "WebSearch(*)"
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
    if [[ -f "$TARGET/$path" ]]; then
        AUDIT_EXISTING+=("  ✓ $label — already exists")
        return 1
    else
        AUDIT_NEW+=("  + $label — will create")
        return 0
    fi
}

check_dir() {
    local path="$1"
    local label="$2"
    if [[ -d "$TARGET/$path" ]]; then
        AUDIT_EXISTING+=("  ✓ $label/ — already exists")
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
if [[ -f "$TARGET/.claude/progress/README.md" ]]; then
    AUDIT_EXISTING+=("  ✓ .claude/progress/README.md — already exists")
else
    AUDIT_NEW+=("  + .claude/progress/README.md — will create")
fi
if [[ -f "$TARGET/.claude/progress/problems.md" ]]; then
    AUDIT_EXISTING+=("  ✓ .claude/progress/problems.md — already exists")
else
    AUDIT_NEW+=("  + .claude/progress/problems.md — will create")
fi

# Audit files
check_file "CLAUDE.md"                      "CLAUDE.md"                      || true
check_file "AGENTS.md"                      "AGENTS.md"                      || true
check_file ".codex/AGENTS.md"               ".codex/AGENTS.md"               || true
check_file ".gitignore"                     ".gitignore"                     || true
check_file ".claude/settings.local.json"    ".claude/settings.local.json"    || true

# Audit codegraph
if [[ -d "$TARGET/.codegraph" ]]; then
    AUDIT_EXISTING+=("  ✓ .codegraph/ — already initialized")
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

# ── Create missing directories (mkdir -p is idempotent, safe) ───────────
echo "  → Ensuring directory structure..."
mkdir -p "$TARGET/.claude/skills"
mkdir -p "$TARGET/.claude/rules"
mkdir -p "$TARGET/.claude/commands"
mkdir -p "$TARGET/.claude/plans"
mkdir -p "$TARGET/.claude/progress"
mkdir -p "$TARGET/.codex"

# ── .gitignore ─────────────────────────────────────────────────────────
GITIGNORE_FILE="$TARGET/.gitignore"
if [[ ! -f "$GITIGNORE_FILE" ]]; then
    echo "  [NEW] Creating .gitignore..."
    cat > "$GITIGNORE_FILE" << 'GITIGNORE_EOF'
# project-init generated local agent files
.claude/
.codex/
.codegraph/
CLAUDE.md
AGENTS.md
GITIGNORE_EOF
    CREATED=$((CREATED + 1))
else
    echo "  [MERGE] .gitignore — adding missing ignore rules..."
    touch "$GITIGNORE_FILE"
    MISSING=()
    for entry in '.claude/' '.codex/' '.codegraph/' 'CLAUDE.md' 'AGENTS.md'; do
        if ! grep -Fxq "$entry" "$GITIGNORE_FILE"; then
            MISSING+=("$entry")
        fi
    done
    if [[ ${#MISSING[@]} -gt 0 ]]; then
        {
            printf '\n# project-init generated local agent files\n'
            printf '%s\n' "${MISSING[@]}"
        } >> "$GITIGNORE_FILE"
    fi
    SKIPPED=$((SKIPPED + 1))
fi

# ── CLAUDE.md ────────────────────────────────────────────────────────────
# 优先调用 `claude /init` 生成代码库感知的 CLAUDE.md，再追加 Plan 镜像规则。
# /init 用 --bare 跳过 SessionStart hooks（避免 auto-init 递归写入占位文件）。
# 失败时回退到带占位说明的 heredoc，并清楚提示用户。
CLAUDE_MD="$TARGET/CLAUDE.md"
INIT_OK=false

if [[ ! -f "$CLAUDE_MD" ]]; then
    if command -v claude >/dev/null 2>&1; then
        echo "  [NEW] Generating CLAUDE.md via 'claude /init' (codebase-aware)..."
        INIT_STDERR_LOG="$TARGET/.claude/.init-stderr.log"
        # 两个必须的 trick：
        # 1. `< /dev/null` —— 后台 + 输出重定向时 stdin 不是 TTY，claude 会报
        #    "Warning: no stdin data received in 3s" 然后退出 0 不写文件
        # 2. `--dangerously-skip-permissions` —— `-p` 模式下 Write 等工具默认需要
        #    permission prompt（无 TTY 时直接失败）。这是 `-p` 模式推荐的标准做法
        #    （claude --help 明确推荐 sandbox 内用），且不改变 /init 行为，只是
        #    跳过权限弹窗让 Write 真正能落盘
        (
            cd "$TARGET" && \
            claude --bare --dangerously-skip-permissions \
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
SETTINGS_LOCAL="$TARGET/.claude/settings.local.json"
if [[ ! -f "$SETTINGS_LOCAL" ]]; then
    echo "  [NEW] Creating .claude/settings.local.json..."
    # Build JSON with python3 for proper formatting
    python3 -c "
import json
data = {
    'plansDirectory': '.claude/plans',
    'permissions': {
        'allow': [
            'Bash(npm:*)', 'Bash(npx:*)', 'Bash(yarn:*)', 'Bash(pnpm:*)', 'Bash(bun:*)',
            'Bash(pip:*)', 'Bash(pip3:*)', 'Bash(python:*)', 'Bash(python3:*)',
            'Bash(node:*)', 'Bash(go:*)', 'Bash(cargo:*)', 'Bash(rustc:*)',
            'Bash(javac:*)', 'Bash(mvn:*)', 'Bash(gradle:*)',
            'Bash(make:*)', 'Bash(cmake:*)', 'Bash(xcodebuild:*)', 'Bash(swift:*)',
            'Bash(git:*)', 'Bash(curl:*)', 'Bash(codegraph:*)',
            'Bash(ls:*)', 'Bash(cat:*)', 'Bash(find:*)', 'Bash(grep:*)', 'Bash(wc:*)',
            'Bash(which:*)', 'Bash(echo:*)', 'Bash(mkdir:*)', 'Bash(cd:*)',
            'Read(*)', 'Edit(*)', 'Write(*)', 'WebFetch(*)', 'WebSearch(*)'
        ]
    }
}
with open('$SETTINGS_LOCAL', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"
    CREATED=$((CREATED + 1))
else
    # Merge: add missing permissions + plansDirectory if absent
    echo "  [MERGE] .claude/settings.local.json — adding missing permissions..."
    python3 -c "
import json

with open('$SETTINGS_LOCAL', 'r') as f:
    data = json.load(f)

# Track what we added
added = []

# Ensure plansDirectory
if 'plansDirectory' not in data:
    data['plansDirectory'] = '.claude/plans'
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
    'Bash(git:*)', 'Bash(curl:*)', 'Bash(codegraph:*)',
    'Bash(ls:*)', 'Bash(cat:*)', 'Bash(find:*)', 'Bash(grep:*)', 'Bash(wc:*)',
    'Bash(which:*)', 'Bash(echo:*)', 'Bash(mkdir:*)', 'Bash(cd:*)',
    'Read(*)', 'Edit(*)', 'Write(*)', 'WebFetch(*)', 'WebSearch(*)'
]

for perm in recommended:
    if perm not in existing:
        data['permissions']['allow'].append(perm)
        added.append(perm)

with open('$SETTINGS_LOCAL', 'w') as f:
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
AGENTS_MD="$TARGET/AGENTS.md"
if [[ ! -f "$AGENTS_MD" ]]; then
    echo "  [NEW] Creating AGENTS.md (Codex)..."
    cat > "$AGENTS_MD" << 'AGENTS_EOF'
# AGENTS.md

This file provides guidance to Codex and other coding agents working in this repository.

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
    CREATED=$((CREATED + 1))
else
    echo "  [KEEP] AGENTS.md — preserving existing content"
    SKIPPED=$((SKIPPED + 1))
    # 已存在但缺少 Plan 镜像规则 → 自动追加
    if pmr_inject "$TARGET" "AGENTS.md"; then
        CREATED=$((CREATED + 1))
    fi
fi

# ── .codex/AGENTS.md ────────────────────────────────────────────────────
CODEX_AGENTS="$TARGET/.codex/AGENTS.md"
if [[ ! -f "$CODEX_AGENTS" ]]; then
    echo "  [NEW] Creating .codex/AGENTS.md..."
    cat > "$CODEX_AGENTS" << 'CODEX_EOF'
# Codex Project Instructions

This file is read by Codex when working in this project.

## Project Notes

- Add repo-specific expectations here so Codex follows the same conventions as human contributors.
- Prefer the project's existing commands and architecture over introducing bespoke workflows.

## Plan 文件镜像

harness 默认把 plan 写到 `~/.claude/plans/<session>.md`（系统路径）。退出 plan 模式之前必须把副本镜像到 `.claude/plans/`，步骤：

1. 从 plan mode 的 system message 拿到 plan 的 `file_path`（绝对路径）
2. `mkdir -p .claude/plans`
3. `cp <file_path> .claude/plans/$(basename <file_path>)`
4. 在副本末尾追加 `<!-- mirror source: <file_path> -->`
5. 完成后再退出 plan 模式

`plansDirectory` 字段当前不生效，必须靠本规则手动镜像。
CODEX_EOF
    CREATED=$((CREATED + 1))
else
    echo "  [KEEP] .codex/AGENTS.md — preserving existing content"
    SKIPPED=$((SKIPPED + 1))
    # 已存在但缺少 Plan 镜像规则 → 自动追加
    if pmr_inject "$TARGET" ".codex/AGENTS.md"; then
        CREATED=$((CREATED + 1))
    fi
fi

# ── CodeGraph initialization ────────────────────────────────────────────
echo "  → Checking CodeGraph..."

if command -v codegraph &> /dev/null; then
    echo "    codegraph CLI: $(codegraph --version 2>/dev/null || echo 'ok')"
else
    echo "    ⚠ codegraph CLI is not installed."
    echo "      Install: curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh | sh"
fi

if [[ -d "$TARGET/.codegraph" ]]; then
    echo "  [KEEP] .codegraph/ — already initialized"
    SKIPPED=$((SKIPPED + 1))
else
    if command -v codegraph &> /dev/null; then
        echo "  [NEW] Running codegraph init..."
        if codegraph init "$TARGET" 2>&1 | sed 's/^/    /'; then
            echo "  ✓ CodeGraph initialized"
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
PROGRESS_DIR="$TARGET/.claude/progress"
PROGRESS_README="$PROGRESS_DIR/README.md"
PROBLEMS_MD="$PROGRESS_DIR/problems.md"

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
    CREATED=$((CREATED + 1))
else
    echo "  [KEEP] .claude/progress/problems.md — preserving existing content"
    SKIPPED=$((SKIPPED + 1))
fi

# ── Mark initialization done ────────────────────────────────────────────
INIT_MARKER="$TARGET/.claude/.init-done"
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$INIT_MARKER"

# ══════════════════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════════════════
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Setup complete — $CREATED created, $SKIPPED preserved"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "   Next steps:"
echo "   1. Edit CLAUDE.md / AGENTS.md with project-specific instructions"
echo "   2. Review .claude/progress/README.md (autonomous dev tracking)"
echo "   3. Run 'codegraph status' to verify indexing"
echo "   4. Restart your agent to pick up the new config"
echo ""
echo "   🌀 Autonomous development:"
echo "   Use /loop or /goal to start autonomous dev mode."
echo "   Progress tracked in .claude/progress/ (README.md + stage-NNN.md + problems.md)"
echo "   Each module is verified before advancing; issues failing >5 times are skipped."
