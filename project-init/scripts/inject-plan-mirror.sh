#!/usr/bin/env bash
# inject-plan-mirror.sh — 把 Plan 文件镜像规则追加到已有项目的 CLAUDE.md/AGENTS.md
#
# 用法：
#   bash scripts/inject-plan-mirror.sh <project-dir> [<project-dir> ...]
#   bash scripts/inject-plan-mirror.sh --dry-run <project-dir>
#   bash scripts/inject-plan-mirror.sh --recursive <root-dir>     # 扫描所有含 .claude/ 的子项目
#
# 行为：
#   - 对每个 <project-dir>，依次检查 CLAUDE.md、AGENTS.md、.codex/AGENTS.md
#   - 如果文件不存在，跳过（不创建）
#   - 如果文件已包含 "Plan 文件镜像" 章节，跳过（避免重复追加）
#   - 否则，把规则块追加到文件末尾（已有内容不动）
#
# 退出码：0=全部成功, 1=部分失败, 2=参数错误

set -u

DRY_RUN=false
RECURSIVE=false
TARGETS=()

for arg in "$@"; do
    case "$arg" in
        --dry-run)  DRY_RUN=true ;;
        --recursive|-r) RECURSIVE=true ;;
        --help|-h)
            sed -n '2,16p' "$0"
            exit 0
            ;;
        -*)
            echo "❌ 未知选项: $arg" >&2
            exit 2
            ;;
        *)
            TARGETS+=("$arg")
            ;;
    esac
done

if [[ ${#TARGETS[@]} -eq 0 ]]; then
    echo "❌ 用法: $0 [--dry-run] [--recursive] <project-dir> [...]" >&2
    exit 2
fi

# 规则块 — 与 setup-project.sh heredoc 内容保持一致
read -r -d '' CLAUDE_BLOCK <<'BLOCK' || true

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

read -r -d '' AGENTS_BLOCK <<'BLOCK' || true

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

read -r -d '' CODEX_BLOCK <<'BLOCK' || true

## Plan 文件镜像

harness 默认把 plan 写到 `~/.claude/plans/<session>.md`（系统路径）。退出 plan 模式之前必须把副本镜像到 `.claude/plans/`，步骤：

1. 从 plan mode 的 system message 拿到 plan 的 `file_path`（绝对路径）
2. `mkdir -p .claude/plans`
3. `cp <file_path> .claude/plans/$(basename <file_path>)`
4. 在副本末尾追加 `<!-- mirror source: <file_path> -->`
5. 完成后再退出 plan 模式

`plansDirectory` 字段当前不生效，必须靠本规则手动镜像。
BLOCK

MARKER="## Plan 文件镜像"

inject_to_file() {
    local project="$1"
    local rel_path="$2"
    local block="$3"
    local full_path="$project/$rel_path"

    if [[ ! -f "$full_path" ]]; then
        echo "    ⊘ $rel_path — 不存在，跳过"
        return 0
    fi

    if grep -qF "$MARKER" "$full_path"; then
        echo "    ✓ $rel_path — 已包含镜像规则，跳过"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo "    [DRY] $rel_path — 将追加 $(echo "$block" | wc -l) 行规则"
        return 0
    fi

    # 用 printf 避免 heredoc 在函数里被吞换行
    printf '\n%s\n' "$block" >> "$full_path"
    echo "    + $rel_path — 已追加镜像规则"
    return 0
}

process_project() {
    local project="$1"
    echo ""
    echo "→ $project"

    if [[ ! -d "$project" ]]; then
        echo "  ❌ 目录不存在"
        return 1
    fi

    local rc=0
    inject_to_file "$project" "CLAUDE.md"          "$CLAUDE_BLOCK"  || rc=1
    inject_to_file "$project" "AGENTS.md"          "$AGENTS_BLOCK"  || rc=1
    inject_to_file "$project" ".codex/AGENTS.md"   "$CODEX_BLOCK"   || rc=1

    if [[ $rc -ne 0 ]]; then
        echo "  ⚠ 部分失败"
    fi
    return $rc
}

if [[ "$RECURSIVE" == true ]]; then
    # 扫描所有含 .claude/ 的子目录（深度 ≤ 4，避开 node_modules 等）
    SCAN_ROOT="${TARGETS[0]}"
    if [[ ! -d "$SCAN_ROOT" ]]; then
        echo "❌ 根目录不存在: $SCAN_ROOT" >&2
        exit 2
    fi
    echo "🔍 递归扫描: $SCAN_ROOT (深度 ≤ 4, 排除 node_modules/.git/build/dist)"
    while IFS= read -r dir; do
        TARGETS+=("$dir")
    done < <(find "$SCAN_ROOT" -maxdepth 4 -type d -name ".claude" \
                -not -path "*/node_modules/*" \
                -not -path "*/.git/*" \
                -not -path "*/build/*" \
                -not -path "*/dist/*" \
                -not -path "*/vendor/*" \
                2>/dev/null | sed 's|/.claude$||')
fi

TOTAL=${#TARGETS[@]}
OK=0
FAIL=0
echo "📦 处理 $TOTAL 个项目${DRY_RUN:+ (DRY-RUN)}"

for project in "${TARGETS[@]}"; do
    if process_project "$project"; then
        OK=$((OK + 1))
    else
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "================"
echo "✓ 成功: $OK / $TOTAL"
if [[ $FAIL -gt 0 ]]; then
    echo "✗ 失败: $FAIL"
    exit 1
fi
if [[ "$DRY_RUN" == true ]]; then
    echo "（这是 DRY-RUN，没有改动文件）"
fi
exit 0