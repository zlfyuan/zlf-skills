#!/usr/bin/env bash
# ci-path.sh — case-insensitive path resolution helpers for project-init.
#
# 用途：
#   在大小写敏感的文件系统上，把用户手建的 `.Claude/`、`.Codex/`、`CLAUDE.MD`
#   等大小写变体视作与规范小写 `.claude/`、`.codex/` 等价。这样 setup / teardown
#   在审计阶段会复用它们，而不是在旁边再创建一个平行的 sibling 目录。
#
# 调用者须 export：
#   TARGET — 项目根目录的绝对路径
#
# 调用方式：source 加载，不要直接执行。
# 公用 API：
#   ci_topdir  <basename>      → 命中则打印实际顶层项名（保留用户大小写）；否则空
#   ci_resolve <rel>           → 多段逐段大小写不敏感匹配，打印实际磁盘上的相对路径
#   ci_exists  <rel>           → 0 表示命中，1 表示未命中（布尔短路）
#   ci_canon   <rel>           → 已存在则用解析名；否则回退到原 <rel> 当作规范小写目标
#
# 兼容性：纯 POSIX + 标准的 `find -print` + `head -n 1`（bash / zsh / sh / ksh 均可 source）。

# ── 内部：在指定目录下找第一个大小写不敏感的子项（保留用户大小写） ────────
_ci_find_one() {
    [ -d "$1" ] || return 1
    # `find -print | head -n 1` 是 POSIX 安全的；`-quit` 不是 POSIX
    find "$1" -mindepth 1 -maxdepth 1 -iname "$2" -print 2>/dev/null | head -n 1
}

# ── ci_topdir <basename> ─────────────────────────────────────────────────────
# 只接受单段名（不带 '/'）；找到则打印实际顶层项名（含用户大小写），否则空。
# 总是返回 0；调用方用 `[ -n "$(ci_topdir ...)" ]` 判断命中与否。
ci_topdir() {
    pattern="$1"
    case "$pattern" in
        */*) echo "ci_topdir: 只接受单段名: $pattern" >&2; return 1 ;;
    esac
    found=$(_ci_find_one "$TARGET" "$pattern")
    if [ -n "$found" ]; then
        echo "${found##*/}"
    else
        echo ""
    fi
    return 0
}

# ── ci_resolve <rel> ─────────────────────────────────────────────────────────
# 把 <rel>（相对 TARGET 的多段路径）按 '/' 拆分，每段大小写不敏感匹配一次。
# 命中则打印出实际磁盘上的相对路径（保留用户大小写）；任何段缺失则返回非 0。
ci_resolve() {
    rel="$1"
    [ -z "$rel" ] && return 1
    current="$TARGET"
    actual=""
    rest="$rel"
    while [ -n "$rest" ]; do
        # 用 shell 内建参数展开切第一个 '/' 之前/之后，不依赖数组
        case "$rest" in
            */*) seg="${rest%%/*}"; rest="${rest#${seg}/}" ;;
            *)   seg="$rest"; rest="" ;;
        esac
        [ -z "$seg" ] && continue
        found=$(_ci_find_one "$current" "$seg") || return 1
        [ -n "$found" ] || return 1
        if [ -z "$actual" ]; then
            actual="${found##*/}"
        else
            actual="$actual/${found##*/}"
        fi
        current="$found"
    done
    [ -n "$actual" ] && echo "$actual"
}

# ── ci_exists <rel> ─────────────────────────────────────────────────────────
# 布尔短路：0 表示命中（大小写不敏感），1 表示没有。
ci_exists() {
    [ -n "$(ci_resolve "$1" 2>/dev/null)" ]
}

# ── ci_canon <rel> ──────────────────────────────────────────────────────────
# 命中则用解析名；否则回退到原 <rel>（视为规范小写），用作 mkdir/cat/rm 的目标默认值，
# 保证已有 case-variant 会被复用、不会再去创平行 sibling。
ci_canon() {
    resolved="$(ci_resolve "$1" 2>/dev/null)" || resolved="$1"
    echo "$resolved"
}
