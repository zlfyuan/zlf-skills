#!/usr/bin/env bash
# plan-mirror-rules.sh — Plan 文件镜像规则的共享定义 + 注入函数
#
# 被以下脚本 source:
#   - setup-project.sh       (新文件用 heredoc 嵌入；已有文件若缺少则 pmr_inject 追加)
#   - inject-plan-mirror.sh  (迁移工具，逐项目注入；支持 --recursive / --dry-run)
#
# 提供:
#   PMR_CLAUDE_BLOCK / PMR_AGENTS_BLOCK / PMR_CODEX_BLOCK — 三种规则块文本
#   PMR_MARKER                                              — 检测已有规则的关键字
#   pmr_block_for <rel_path>                                — 按文件名返回对应规则块
#   pmr_inject <project_dir> <rel_path> [block]             — 注入（缺则追加，已有则跳过）
#
# pmr_inject 返回码:
#   0 = 已注入（文件被修改）
#   1 = 已包含规则（跳过，未修改）
#   2 = 文件不存在（跳过，未修改）
#   3 = 目录不存在 / 未知 rel_path
#
# 环境变量:
#   DRY_RUN=true — pmr_inject 仅打印，不写盘（仍返回 1 = 视为"未改动"）

# ── Guard: 防止直接执行 / 重复 source ──────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "❌ $(basename "$0") 是一个共享库，请用 source 加载，不要直接执行。" >&2
    exit 1
fi
[[ -n "${PMR_LOADED:-}" ]] && return 0
PMR_LOADED=1

# ── 规则块（与 setup-project.sh heredoc 内容同步）──────────────────────
read -r -d '' PMR_CLAUDE_BLOCK <<'BLOCK' || true

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
BLOCK

read -r -d '' PMR_AGENTS_BLOCK <<'BLOCK' || true

## Plan 文件镜像（重要）

harness 默认把 plan 写到 `~/.claude/plans/<session>.md`（系统路径，不在项目内），无法被 git 追踪。
为保证 `.claude/plans/` 里有项目级副本，**每次退出 plan 模式之前必须先执行以下步骤**：

1. 从 plan mode 的 system message 里拿到 plan 的 `file_path`（绝对路径）
2. `mkdir -p .claude/plans`
3. `cp <file_path> .claude/plans/$(basename <file_path>)`
4. 在副本末尾追加一行：`<!-- mirror source: <file_path> -->`
5. **完成上述 4 步之后再退出 plan 模式**

注：`settings.local.json` 里的 `plansDirectory` 字段是预留配置，当前 harness 版本不读取，仍需通过本规则手动镜像。
BLOCK

read -r -d '' PMR_CODEX_BLOCK <<'BLOCK' || true

## Plan 文件镜像

harness 默认把 plan 写到 `~/.claude/plans/<session>.md`（系统路径）。退出 plan 模式之前必须把副本镜像到 `.claude/plans/`，步骤：

1. 从 plan mode 的 system message 拿到 plan 的 `file_path`（绝对路径）
2. `mkdir -p .claude/plans`
3. `cp <file_path> .claude/plans/$(basename <file_path>)`
4. 在副本末尾追加 `<!-- mirror source: <file_path> -->`
5. 完成后再退出 plan 模式

`plansDirectory` 字段当前不生效，必须靠本规则手动镜像。
BLOCK

PMR_MARKER="## Plan 文件镜像"

# ── pmr_block_for <rel_path> ─────────────────────────────────────────────
# 按文件名返回对应规则块；输出到 stdout。未知 rel_path 返回空 + rc=1。
pmr_block_for() {
    case "$1" in
        CLAUDE.md)         printf '%s' "$PMR_CLAUDE_BLOCK" ;;
        AGENTS.md)         printf '%s' "$PMR_AGENTS_BLOCK" ;;
        .codex/AGENTS.md)  printf '%s' "$PMR_CODEX_BLOCK" ;;
        *)                 return 1 ;;
    esac
}

# ── pmr_inject <project_dir> <rel_path> [block] ─────────────────────────
# 把规则块追加到 <project>/<rel_path>（如果尚未包含）。
#   $1 — 项目根目录
#   $2 — 相对路径（CLAUDE.md / AGENTS.md / .codex/AGENTS.md）
#   $3 — (可选) 显式规则块；空则按 rel_path 自动选择
# Env:
#   DRY_RUN=true — 只打印，不写盘
pmr_inject() {
    local project="$1"
    local rel_path="$2"
    local block="${3:-}"

    if [[ ! -d "$project" ]]; then
        echo "    ⊘ $rel_path — 项目目录不存在: $project"
        return 3
    fi

    local full_path="$project/$rel_path"

    if [[ ! -f "$full_path" ]]; then
        echo "    ⊘ $rel_path — 不存在，跳过"
        return 2
    fi

    if [[ -z "$block" ]]; then
        if ! block="$(pmr_block_for "$rel_path")"; then
            echo "    ⊘ $rel_path — 未定义规则块"
            return 3
        fi
    fi

    if grep -qF "$PMR_MARKER" "$full_path"; then
        echo "    ✓ $rel_path — 已包含镜像规则，跳过"
        return 1
    fi

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo "    [DRY] $rel_path — 将追加 $(printf '%s\n' "$block" | wc -l) 行规则"
        return 1
    fi

    printf '\n%s\n' "$block" >> "$full_path"
    echo "    + $rel_path — 已追加镜像规则"
    return 0
}