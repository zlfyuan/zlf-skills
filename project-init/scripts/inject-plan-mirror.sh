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
# 规则块文本与注入逻辑与 setup-project.sh 共用（source plan-mirror-rules.sh），
# 这样新项目和老项目拿到的规则永远一致。
#
# 退出码：0=全部成功, 1=部分失败, 2=参数错误

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/plan-mirror-rules.sh"

DRY_RUN=false
RECURSIVE=false
TARGETS=()

for arg in "$@"; do
    case "$arg" in
        --dry-run)  DRY_RUN=true ;;
        --recursive|-r) RECURSIVE=true ;;
        --help|-h)
            sed -n '2,21p' "$0"
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

# 让 pmr_inject 看到 DRY_RUN
export DRY_RUN

process_project() {
    local project="$1"
    echo ""
    echo "→ $project"

    if [[ ! -d "$project" ]]; then
        echo "  ❌ 目录不存在"
        return 1
    fi

    local injected=0
    local skipped=0
    local failed=0

    for rel in "CLAUDE.md" "AGENTS.md" ".codex/AGENTS.md"; do
        pmr_inject "$project" "$rel"
        case $? in
            0) injected=$((injected + 1)) ;;
            1|2) skipped=$((skipped + 1)) ;;
            *) failed=$((failed + 1)) ;;
        esac
    done

    echo "  → injected=$injected skipped=$skipped failed=$failed"
    if [[ $failed -gt 0 ]]; then
        echo "  ⚠ 部分失败"
        return 1
    fi
    return 0
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
if [[ "$DRY_RUN" == "true" ]]; then
    echo "📦 处理 $TOTAL 个项目 (DRY-RUN)"
else
    echo "📦 处理 $TOTAL 个项目"
fi

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