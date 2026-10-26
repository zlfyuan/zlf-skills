#!/usr/bin/env bash
# agents-mirror.sh — CLAUDE.md → AGENTS.md 同步（让 Codex 侧复用同一份项目约定）
#
# 背景：根目录 CLAUDE.md 是 Claude Code 的项目指令，AGENTS.md 是 Codex 的入口。
#       两份文件各写一遍项目约定必然漂移 —— 本库把 CLAUDE.md 的内容镜像到
#       AGENTS.md，并做 Codex 侧适配：
#         · 标题换成 AGENTS.md
#         · 剔除 Claude 专属内容（/compact 斜杠命令、ExitPlanMode API）
#         · Plan 镜像规则整段换成 Codex 版措辞（PMR_AGENTS_BLOCK）
#         · CLAUDE.md 里没有「会话开始之前」检查时，补上 Codex 版标准块
#
# 被以下脚本 source:
#   - setup-project.sh
#
# 提供:
#   agents_mirror <claude_md> <agents_md>      用 CLAUDE.md 生成 AGENTS.md
#   agents_is_untouched_template <file>        文件是否仍是未改动的 project-init 模板
#   agents_claude_has_real_content <file>      CLAUDE.md 是否已有真实项目内容
#
# 退出码:
#   agents_mirror: 0 = 成功 / 1 = CLAUDE.md 不存在或不可读

# ── Guard: 防止直接执行 / 重复 source ──────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ $(basename "$0") 是一个共享库，请用 source 加载，不要直接执行。" >&2
    exit 1
fi
[[ -n "${AMR_LOADED:-}" ]] && return 0
AMR_LOADED=1

# Plan 镜像规则块（Codex 措辞）来自 plan-mirror-rules.sh —— 未加载时自己加载
# BASH_SOURCE 在 zsh 下为空，回退用 $0（zsh source 时 $0 = 被 source 的文件）
_AMR_SELF="${BASH_SOURCE[0]:-$0}"
_AMR_SCRIPT_DIR="$(cd "$(dirname "$_AMR_SELF")" && pwd)"
if [[ -z "${PMR_LOADED:-}" ]]; then
    # shellcheck disable=SC1091
    source "$_AMR_SCRIPT_DIR/plan-mirror-rules.sh"
fi
unset _AMR_SCRIPT_DIR _AMR_SELF

# ── Codex 侧标准「会话开始之前」检查块 ──────────────────────────────────
# 规范目录永远全小写 `.codex/` / `.claude/`：Codex 会把产品名幻觉成 `.Codex/`，
# 在大小写敏感 FS / 字面 glob 上把已初始化的项目当成缺失。
read -r -d '' AGENTS_SESSION_CHECK <<'BLOCK' || true
**会话开始之前：**

- 如果是编程相关的项目，检测项目根是否有 `.codex/` 或 `.claude/`（大小写不敏感。规范名全小写 `.codex/` / `.claude/`，禁止把产品名写成 `.Codex/` / `.Claude/` 再当缺失）。命中任一 → 已初始化，继续任务。两者都没有 → 提醒使用 project-init，停止。
BLOCK

# ── 正文镜像：剔除 Claude 专属内容 + 原位替换 Plan 镜像段 ────────────────
# awk 规则说明:
#   1. Plan 镜像段整段丢弃，在原位置换成 Codex 版规则块（PMR_AGENTS_BLOCK）
#   2. `/compact` 斜杠命令、ExitPlanMode API 是 Claude 专属 → 整行丢弃
#   3. `# CLAUDE.md` 标题行丢弃（AGENTS.md 有自己的标题）
#   4. 去掉正文开头的空行
agents_mirror_body() {
    local claude_md="$1"
    AGENTS_PLAN_BLOCK="$PMR_AGENTS_BLOCK" awk '
        BEGIN { in_plan = 0; started = 0; prev_blank = 0; block = ENVIRON["AGENTS_PLAN_BLOCK"] }

        # 处于 Plan 镜像段内：一直丢到下一个标题 / HTML 注释为止
        in_plan {
            if ($0 ~ /^##[[:space:]]/ || $0 ~ /^<!--/) { in_plan = 0 }
            else { next }
        }

        # Plan 镜像段起点 → 原位换成 Codex 版
        # 规则块缺失（PMR_AGENTS_BLOCK 为空）时保留原文，不做替换，避免丢内容
        /^##[[:space:]]*Plan[[:space:]]*文件镜像/ {
            if (block == "") { print; next }
            in_plan = 1
            started = 1
            print block
            print ""
            prev_blank = 1
            next
        }

        # AGENTS.md 有自己的标题
        /^#[[:space:]]*CLAUDE\.md[[:space:]]*$/ { next }

        # Claude 专属内容
        /\/compact|ExitPlanMode/ { next }

        {
            if (started == 0 && $0 ~ /^[[:space:]]*$/) { next }
            started = 1
            # 折叠连续空行（剔除 Claude 专属行后可能留下连续空行）
            if (prev_blank == 1 && $0 ~ /^[[:space:]]*$/) { next }
            prev_blank = ($0 ~ /^[[:space:]]*$/ ? 1 : 0)
            print
        }
    ' "$claude_md"
}

# ── agents_mirror <claude_md> <agents_md> ──────────────────────────────
# 用 CLAUDE.md 生成 AGENTS.md（Codex 侧适配见文件头注释）。
agents_mirror() {
    local claude_md="$1"
    local agents_md="$2"

    [[ -f "$claude_md" && -r "$claude_md" ]] || return 1

    {
        printf '# AGENTS.md\n\n'
        printf 'This file provides guidance to Codex and other coding agents working in this repository.\n\n'
        printf '> 本文件由 project-init 从根目录 `CLAUDE.md` 同步生成 —— 项目约定以 `CLAUDE.md` 为准。\n\n'
    } > "$agents_md"

    # CLAUDE.md 里没有「会话开始之前」检查 → 补 Codex 版标准块
    if ! grep -q '会话开始之前' "$claude_md"; then
        printf '%s\n\n' "$AGENTS_SESSION_CHECK" >> "$agents_md"
    fi

    agents_mirror_body "$claude_md" >> "$agents_md"
}

# ── agents_is_untouched_template <file> ────────────────────────────────
# 返回 0 = 文件仍是 project-init 生成、用户没改过的 AGENTS.md 模板。
# 判据：模板固定文案还在（含占位句）→ 视为未改动，可安全重新生成。
agents_is_untouched_template() {
    local file="$1"
    [[ -f "$file" ]] || return 1
    grep -qF "This file provides guidance to Codex and other coding agents" "$file" \
        && grep -qF "Describe the repository purpose and the main workflows for contributors." "$file"
}

# ── agents_claude_has_real_content <file> ───────────────────────────────
# 返回 0 = CLAUDE.md 里已有真实项目约定（不是 project-init 的占位模板）。
agents_claude_has_real_content() {
    local file="$1"
    [[ -f "$file" ]] || return 1
    ! grep -qF "<!-- project-init: placeholder -->" "$file" \
        && ! grep -qF "Describe the repository purpose and primary user workflow." "$file"
}
