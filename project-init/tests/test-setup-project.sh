#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

run_setup() {
    PATH=/usr/bin:/bin bash "$ROOT_DIR/scripts/setup-project.sh" "$1"
}

run_setup "$TMP_DIR" >/dev/null

for file in "$TMP_DIR/CLAUDE.md" "$TMP_DIR/AGENTS.md" "$TMP_DIR/.codex/AGENTS.md"; do
    if grep -q '<!-- TODO' "$file"; then
        echo "Found placeholder TODO in $file" >&2
        exit 1
    fi
done

if [[ ! -f "$TMP_DIR/.gitignore" ]]; then
    echo "Missing .gitignore" >&2
    exit 1
fi

for pattern in '.claude/' '.codex/' '.codegraph/' 'CLAUDE.md' 'AGENTS.md'; do
    if ! grep -Fq "$pattern" "$TMP_DIR/.gitignore"; then
        echo "Missing gitignore pattern: $pattern" >&2
        exit 1
    fi
done

# ── 软连接布局检查 ──────────────────────────────────────────────
# 1. .codex/AGENTS.md 必须是软连接指向 ../AGENTS.md
if [[ ! -L "$TMP_DIR/.codex/AGENTS.md" ]]; then
    echo "FAIL: .codex/AGENTS.md 不是软连接" >&2
    exit 1
fi
AGENTS_LINK=$(readlink "$TMP_DIR/.codex/AGENTS.md")
if [[ "$AGENTS_LINK" != "../AGENTS.md" ]]; then
    echo "FAIL: .codex/AGENTS.md 指向 $AGENTS_LINK（应为 ../AGENTS.md）" >&2
    exit 1
fi

# 2. .claude/CLAUDE.md 必须是软连接指向 ../CLAUDE.md
if [[ ! -L "$TMP_DIR/.claude/CLAUDE.md" ]]; then
    echo "FAIL: .claude/CLAUDE.md 不是软连接" >&2
    exit 1
fi
CLAUDE_LINK=$(readlink "$TMP_DIR/.claude/CLAUDE.md")
if [[ "$CLAUDE_LINK" != "../CLAUDE.md" ]]; then
    echo "FAIL: .claude/CLAUDE.md 指向 $CLAUDE_LINK（应为 ../CLAUDE.md）" >&2
    exit 1
fi

# 3. .codex/{rules,skills,commands,plans,progress} 都应该是软连接指向 ../.claude/<sub>
for sub in rules skills commands plans progress; do
    link="$TMP_DIR/.codex/$sub"
    if [[ ! -L "$link" ]]; then
        echo "FAIL: .codex/$sub 不是软连接" >&2
        exit 1
    fi
    target=$(readlink "$link")
    if [[ "$target" != "../.claude/$sub" ]]; then
        echo "FAIL: .codex/$sub 指向 $target（应为 ../.claude/$sub）" >&2
        exit 1
    fi
done

# 4. bundled 命令应被安装到 .claude/commands/
for cmd in z-commit z-push z-commit-push; do
    if [[ ! -f "$TMP_DIR/.claude/commands/$cmd.md" ]]; then
        echo "FAIL: .claude/commands/$cmd.md 未安装" >&2
        exit 1
    fi
done

# 5. .claude/memory/MEMORY.md 应被创建为长期记忆索引模板
if [[ ! -f "$TMP_DIR/.claude/memory/MEMORY.md" ]]; then
    echo "FAIL: .claude/memory/MEMORY.md 未创建" >&2
    exit 1
fi
if [[ ! -f "$TMP_DIR/.claude/.project-init-manifest" ]]; then
    echo "FAIL: setup manifest 未创建" >&2
    exit 1
fi
if command -v python3 >/dev/null 2>&1 && python3 - "$TMP_DIR/.claude/settings.local.json" <<'PY'
import json, sys
allow = set(json.load(open(sys.argv[1]))['permissions']['allow'])
for forbidden in ('Bash(curl:*)', 'Bash(git:*)', 'Read(*)', 'Edit(*)', 'Write(*)', 'WebFetch(*)', 'WebSearch(*)'):
    if forbidden in allow:
        raise SystemExit(f'unsafe default permission: {forbidden}')
PY
then
    :
fi
if ! grep -q "^## 索引$" "$TMP_DIR/.claude/memory/MEMORY.md"; then
    echo "FAIL: .claude/memory/MEMORY.md 缺少 '## 索引' 段" >&2
    exit 1
fi

# 6. additive：第二次跑 setup 不应破坏既有软连接 / 命令 / MEMORY.md
run_setup "$TMP_DIR" >/dev/null
for cmd in z-commit z-push z-commit-push; do
    if [[ ! -f "$TMP_DIR/.claude/commands/$cmd.md" ]]; then
        echo "FAIL: 第二次 setup 后 .claude/commands/$cmd.md 丢失（破坏了 additive 原则）" >&2
        exit 1
    fi
done
if [[ ! -L "$TMP_DIR/.codex/AGENTS.md" || "$(readlink "$TMP_DIR/.codex/AGENTS.md")" != "../AGENTS.md" ]]; then
    echo "FAIL: 第二次 setup 破坏了 .codex/AGENTS.md 软连接" >&2
    exit 1
fi
if [[ ! -f "$TMP_DIR/.claude/memory/MEMORY.md" ]]; then
    echo "FAIL: 第二次 setup 破坏了 .claude/memory/MEMORY.md" >&2
    exit 1
fi

# ── 大小写变体用例：用户已有 `.Codex/` `.CLAUDE/`（非规范小写）──────────
# setup 应该复用它们，而不是在旁边再创建一个 `.codex/` `.claude/` 平行副本。
CASE_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR" "$CASE_DIR"' EXIT
mkdir -p "$CASE_DIR/.Codex" "$CASE_DIR/.CLAUDE"

run_setup "$CASE_DIR" >/dev/null

# 1. 不能出现平行的 `.codex/` `.claude/` 副本
if [[ -d "$CASE_DIR/.codex" || -d "$CASE_DIR/.claude" ]]; then
    echo "FAIL: setup 在用户已有的 .Codex/.CLAUDE 旁边又创建了平行副本" >&2
    ls -la "$CASE_DIR" >&2
    exit 1
fi

# 2. 既有 .Codex/.CLAUDE 必须被复用并填进内容
if [[ ! -f "$CASE_DIR/.Codex/AGENTS.md" ]]; then
    echo "FAIL: setup 未在用户已有的 .Codex/ 里写入 AGENTS.md" >&2
    exit 1
fi
if [[ ! -f "$CASE_DIR/.CLAUDE/settings.local.json" ]]; then
    echo "FAIL: setup 未在用户已有的 .CLAUDE/ 里写入 settings.local.json" >&2
    exit 1
fi

# 3. settings.local.json 里的 plansDirectory 必须与实际目录大小写一致
if command -v python3 >/dev/null 2>&1; then
    PLANS_DIR=$(python3 -c "import json; print(json.load(open('$CASE_DIR/.CLAUDE/settings.local.json'))['plansDirectory'])")
    if [[ "$PLANS_DIR" != ".CLAUDE/plans" ]]; then
        echo "FAIL: settings.local.json plansDirectory=$PLANS_DIR（应为 .CLAUDE/plans 与实际目录大小写一致）" >&2
        exit 1
    fi
fi

# 4. teardown 应能识别变体并清理
if ! bash "$ROOT_DIR/scripts/teardown-project.sh" "$CASE_DIR" --dry-run >/dev/null 2>&1; then
    echo "FAIL: teardown --dry-run 异常退出" >&2
    exit 1
fi

# 5. teardown --yes 应清理 setup 产物，同时默认保留 settings.local.json
PATH=/usr/bin:/bin bash "$ROOT_DIR/scripts/teardown-project.sh" "$CASE_DIR" --yes >/dev/null 2>&1
if [[ ! -f "$CASE_DIR/.CLAUDE/settings.local.json" ]]; then
    echo "FAIL: teardown 默认误删了 settings.local.json" >&2
    exit 1
fi
if [[ -e "$CASE_DIR/.Codex" ]]; then
    echo "FAIL: teardown 未清理变体 .Codex 产物" >&2
    exit 1
fi
rm -rf "$CASE_DIR"

# ── detector / auto-init on a source-only project ───────────────────────
DETECT_DIR="$(mktemp -d)"
for file in a.py b.py c.py d.py e.py; do touch "$DETECT_DIR/$file"; done
if [[ "$(PATH=/usr/bin:/bin bash "$ROOT_DIR/scripts/detect-code-project.sh" "$DETECT_DIR")" != "CODE_PROJECT" ]]; then
    echo "FAIL: source-only project detection failed" >&2
    exit 1
fi
if ! PATH=/usr/bin:/bin bash "$ROOT_DIR/scripts/auto-init.sh" "$DETECT_DIR" >/dev/null; then
    echo "FAIL: auto-init failed for source-only project" >&2
    exit 1
fi
if [[ ! -f "$DETECT_DIR/.claude/.init-done" ]]; then
    echo "FAIL: auto-init did not create initialization marker" >&2
    exit 1
fi
rm -rf "$DETECT_DIR"

# ── teardown must preserve pre-existing shared directories ─────────────
SAFE_DIR="$(mktemp -d)"
mkdir -p "$SAFE_DIR/.claude" "$SAFE_DIR/.codex" "$SAFE_DIR/.codegraph"
printf user > "$SAFE_DIR/.claude/keep.txt"
printf user > "$SAFE_DIR/.codex/keep.txt"
printf user > "$SAFE_DIR/.codegraph/keep.txt"
PATH=/usr/bin:/bin bash "$ROOT_DIR/scripts/teardown-project.sh" "$SAFE_DIR" --yes >/dev/null
for file in "$SAFE_DIR/.claude/keep.txt" "$SAFE_DIR/.codex/keep.txt" "$SAFE_DIR/.codegraph/keep.txt"; do
    if [[ ! -f "$file" ]]; then
        echo "FAIL: teardown 删除了用户文件 $file" >&2
        exit 1
    fi
done
rm -rf "$SAFE_DIR"

echo "setup-project regression checks passed (incl. case-variant reuse)"
