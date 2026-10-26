#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

run_setup() {
    # HOME 指到临时目录：避免 setup 命中真实的 ~/.local/bin/codegraph
    # （那会让测试顺带跑 codegraph init，行为依赖开发机环境）
    HOME="$TMP_DIR/fakehome" PATH=/usr/bin:/bin bash "$ROOT_DIR/scripts/setup-project.sh" "$1"
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
# 有 .codex 时技能放在已被 .codex/ 忽略的目录里，不要再忽略 .agents/skills/。
if grep -Fq '.agents/skills/' "$TMP_DIR/.gitignore"; then
    echo "FAIL: 有 .codex 时不应把 .agents/skills/ 写进 .gitignore" >&2
    exit 1
fi

# ── 生成的 AGENTS.md 必须把规范目录写成小写 .codex/ ────────────────
# Codex 会把产品名幻觉成 `.Codex/`，字面检查会把已初始化项目当成缺失。
if ! grep -q '\.codex/' "$TMP_DIR/AGENTS.md"; then
    echo "FAIL: generated AGENTS.md 未提及小写 .codex/" >&2
    exit 1
fi
if ! grep -q '大小写不敏感' "$TMP_DIR/AGENTS.md"; then
    echo "FAIL: generated AGENTS.md 缺少大小写不敏感检查说明" >&2
    exit 1
fi
if grep -q '检测是否有.Codex/' "$TMP_DIR/AGENTS.md"; then
    echo "FAIL: generated AGENTS.md 把 .Codex/ 当成检查目标" >&2
    exit 1
fi
if ! grep -q '禁止.*\.Codex/' "$TMP_DIR/AGENTS.md"; then
    echo "FAIL: generated AGENTS.md 未标明禁止检查 .Codex/" >&2
    exit 1
fi

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

# 4. bundled 命令应被安装到 .claude/commands/。
# 有 .codex 时 Codex 技能放在 .codex/skills（软链到 .claude/skills），不放 .agents。
for cmd in z-commit z-push z-commit-push; do
    if [[ ! -f "$TMP_DIR/.claude/commands/$cmd.md" ]]; then
        echo "FAIL: .claude/commands/$cmd.md 未安装" >&2
        exit 1
    fi
    skill="$TMP_DIR/.codex/skills/$cmd/SKILL.md"
    if [[ ! -f "$skill" ]]; then
        echo "FAIL: .codex/skills/$cmd/SKILL.md 未安装（Codex 发现不到命令）" >&2
        exit 1
    fi
    if [[ -e "$TMP_DIR/.agents/skills/$cmd" ]]; then
        echo "FAIL: 已有 .codex 时不应再安装低优先级 .agents/skills/$cmd" >&2
        exit 1
    fi
    if ! grep -q "^name: $cmd$" "$skill"; then
        echo "FAIL: $skill 缺少 name: $cmd" >&2
        exit 1
    fi
    if ! grep -q '^description: "' "$skill"; then
        echo "FAIL: $skill 缺少 description" >&2
        exit 1
    fi
    # 正文必须来自命令模板，而不是另一份改写过的步骤
    if ! grep -q "/$cmd" "$skill"; then
        echo "FAIL: $skill 没有复用命令模板正文" >&2
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

# 6b. 用户改过的 Codex skill 不能被第二次 setup 覆盖
printf 'custom-skill-body\n' > "$TMP_DIR/.codex/skills/z-commit/SKILL.md"
run_setup "$TMP_DIR" >/dev/null
if ! grep -q 'custom-skill-body' "$TMP_DIR/.codex/skills/z-commit/SKILL.md"; then
    echo "FAIL: 第二次 setup 覆盖了用户的 .codex/skills/z-commit/SKILL.md" >&2
    exit 1
fi

# 6c. 已初始化项目缺 skill 时，重跑 setup 必须补上（不能在审计阶段提前退出）
rm -rf "$TMP_DIR/.codex/skills/z-push"
run_setup "$TMP_DIR" >/dev/null
if [[ ! -f "$TMP_DIR/.codex/skills/z-push/SKILL.md" ]]; then
    echo "FAIL: 已初始化项目重跑 setup 没有补上 .codex/skills/z-push" >&2
    exit 1
fi

# 6d. 低优先级 .agents 里的同名技能，在 .codex 还没有时搬过去，避免列两次
rm -rf "$TMP_DIR/.codex/skills/z-commit"
mkdir -p "$TMP_DIR/.agents/skills/z-commit"
printf 'moved-from-agents\n' > "$TMP_DIR/.agents/skills/z-commit/SKILL.md"
run_setup "$TMP_DIR" >/dev/null
if ! grep -q 'moved-from-agents' "$TMP_DIR/.codex/skills/z-commit/SKILL.md"; then
    echo "FAIL: 没有把 .agents/skills/z-commit 搬到 .codex/skills" >&2
    exit 1
fi
if [[ -e "$TMP_DIR/.agents/skills/z-commit" ]]; then
    echo "FAIL: 搬到 .codex 后仍留着内容相同的 .agents 副本" >&2
    exit 1
fi

# 6e. 用户改过的 Claude 命令应成为新 skill 的正文
FLOW_DIR="$(mktemp -d)"
mkdir -p "$FLOW_DIR/.claude/commands"
printf 'USER-COMMAND-MARKER\n' > "$FLOW_DIR/.claude/commands/z-commit.md"
run_setup "$FLOW_DIR" >/dev/null
if ! grep -q 'USER-COMMAND-MARKER' "$FLOW_DIR/.codex/skills/z-commit/SKILL.md"; then
    echo "FAIL: Codex skill 没有复用已有的 .claude/commands/z-commit.md" >&2
    rm -rf "$FLOW_DIR"
    exit 1
fi
if ! grep -q 'USER-COMMAND-MARKER' "$FLOW_DIR/.claude/commands/z-commit.md"; then
    echo "FAIL: setup 覆盖了用户的 .claude/commands/z-commit.md" >&2
    rm -rf "$FLOW_DIR"
    exit 1
fi
rm -rf "$FLOW_DIR"

# ── 大小写变体用例：用户已有 `.Codex/` `.CLAUDE/`（非规范小写）──────────
# setup 应该复用它们，而不是在旁边再创建一个 `.codex/` `.claude/` 平行副本。
CASE_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR" "$CASE_DIR"' EXIT
mkdir -p "$CASE_DIR/.Codex" "$CASE_DIR/.CLAUDE"

run_setup "$CASE_DIR" >/dev/null

# 1. 不能出现平行的 `.codex/` `.claude/` 副本
#    用目录列表做大小写精确比对：macOS 默认文件系统大小写不敏感，
#    `[[ -d "$CASE_DIR/.codex" ]]` 会把用户的 `.Codex` 也算成命中。
if ls -a "$CASE_DIR" | grep -Fxq '.codex' || ls -a "$CASE_DIR" | grep -Fxq '.claude'; then
    echo "FAIL: setup 在用户已有的 .Codex/.CLAUDE 旁边又创建了平行副本" >&2
    ls -la "$CASE_DIR" >&2
    exit 1
fi

# 2. 既有 .Codex/.CLAUDE 必须被复用并填进内容
if [[ ! -f "$CASE_DIR/.Codex/AGENTS.md" ]]; then
    echo "FAIL: setup 未在用户已有的 .Codex/ 里写入 AGENTS.md" >&2
    exit 1
fi
if [[ ! -f "$CASE_DIR/.Codex/skills/z-commit/SKILL.md" ]]; then
    echo "FAIL: 已有 .Codex 时技能应放进 .Codex/skills" >&2
    exit 1
fi
if ls -a "$CASE_DIR" | grep -Fxq '.agents'; then
    echo "FAIL: 已有 .Codex 时不应创建低优先级 .agents" >&2
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
if [[ ! -f "$DETECT_DIR/.codex/skills/z-commit/SKILL.md" ]]; then
    echo "FAIL: auto-init 没有安装 Codex skill" >&2
    exit 1
fi
# 已有 .init-done 的旧项目缺 skill 时，hook 不能直接跳过
rm -rf "$DETECT_DIR/.codex/skills/z-commit"
if ! PATH=/usr/bin:/bin bash "$ROOT_DIR/scripts/auto-init.sh" "$DETECT_DIR" >/dev/null; then
    echo "FAIL: auto-init 在已初始化项目上补 Codex skill 失败" >&2
    exit 1
fi
if [[ ! -f "$DETECT_DIR/.codex/skills/z-commit/SKILL.md" ]]; then
    echo "FAIL: auto-init 没有给已初始化项目补上 Codex skill" >&2
    exit 1
fi
# 没有 .codex 时，低优先级 .agents/skills 算已安装，hook 不应再造一个 .codex
AGENTS_ONLY="$(mktemp -d)"
mkdir -p "$AGENTS_ONLY/.claude"
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$AGENTS_ONLY/.claude/.init-done"
for cmd in z-commit z-push z-commit-push; do
    mkdir -p "$AGENTS_ONLY/.agents/skills/$cmd"
    printf 'name: %s\n' "$cmd" > "$AGENTS_ONLY/.agents/skills/$cmd/SKILL.md"
done
if ! PATH=/usr/bin:/bin bash "$ROOT_DIR/scripts/auto-init.sh" "$AGENTS_ONLY" >/dev/null; then
    echo "FAIL: 仅有 .agents 技能时 auto-init 不应失败" >&2
    rm -rf "$AGENTS_ONLY"
    exit 1
fi
if [[ -d "$AGENTS_ONLY/.codex" || -L "$AGENTS_ONLY/.codex" ]]; then
    echo "FAIL: 没有 .codex 且 .agents 技能已在时，auto-init 不应新建 .codex" >&2
    rm -rf "$AGENTS_ONLY"
    exit 1
fi
rm -rf "$DETECT_DIR" "$AGENTS_ONLY"

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

# ── CLAUDE.md → AGENTS.md 同步 ──────────────────────────────────────────
# 用户已有真实 CLAUDE.md 时，AGENTS.md 应由它镜像生成（Codex 侧适配），
# 而不是 project-init 的英文占位模板 —— 两份文件各写一遍必然漂移。
MIRROR_DIR="$(mktemp -d)"
REFRESH_DIR=""
trap 'rm -rf "$TMP_DIR" "$CASE_DIR" "$MIRROR_DIR" ${REFRESH_DIR:+"$REFRESH_DIR"}' EXIT
cat > "$MIRROR_DIR/CLAUDE.md" <<'MIRROR_EOF'
# CLAUDE.md

**会话开始之前：**

- 检测项目根是否有 `.claude/` 或 `.codex/`（大小写不敏感）。

写代码一定要写注释⚠️

禁止将含有密码、API Key、Token 的代码提交到 Git

## Plan 文件镜像（重要）

harness 默认把 plan 写到 `~/.claude/plans/<session>.md`。
每次调用 `ExitPlanMode` 之前必须先执行镜像步骤。

<!-- CODEGRAPH_START -->

## CodeGraph

用 `codegraph explore` 查代码。
<!-- CODEGRAPH_END -->
MIRROR_EOF

run_setup "$MIRROR_DIR" >/dev/null

# 1. CLAUDE.md 的项目约定必须同步到 AGENTS.md
if ! grep -qF '写代码一定要写注释' "$MIRROR_DIR/AGENTS.md"; then
    echo "FAIL: AGENTS.md 没有同步 CLAUDE.md 的项目约定" >&2
    exit 1
fi
if ! grep -qF '禁止将含有密码、API Key、Token 的代码提交到 Git' "$MIRROR_DIR/AGENTS.md"; then
    echo "FAIL: AGENTS.md 没有同步 CLAUDE.md 的密钥禁令" >&2
    exit 1
fi

# 2. Claude 专属内容必须剔除
if grep -qF 'ExitPlanMode' "$MIRROR_DIR/AGENTS.md"; then
    echo "FAIL: AGENTS.md 残留 Claude 专属的 ExitPlanMode" >&2
    exit 1
fi

# 3. Plan 镜像规则整段换成 Codex 措辞
if ! grep -qF '每次退出 plan 模式之前' "$MIRROR_DIR/AGENTS.md"; then
    echo "FAIL: AGENTS.md 的 Plan 镜像规则没有换成 Codex 措辞" >&2
    exit 1
fi

# 4. CodeGraph 段落要保留
if ! grep -qF '<!-- CODEGRAPH_START -->' "$MIRROR_DIR/AGENTS.md"; then
    echo "FAIL: AGENTS.md 丢失了 CodeGraph 段落" >&2
    exit 1
fi

# 5. 不能残留英文占位模板
if grep -qF 'Describe the repository purpose' "$MIRROR_DIR/AGENTS.md"; then
    echo "FAIL: AGENTS.md 仍是英文占位模板" >&2
    exit 1
fi

# 6. teardown 不得删掉已同步（= 用户内容）的 AGENTS.md
bash "$ROOT_DIR/scripts/teardown-project.sh" "$MIRROR_DIR" </dev/null >/dev/null 2>&1 || true
if [[ ! -f "$MIRROR_DIR/AGENTS.md" ]]; then
    echo "FAIL: teardown 删除了已同步的 AGENTS.md" >&2
    exit 1
fi
rm -rf "$MIRROR_DIR"

# ── AGENTS.md 仍是模板时，重跑 setup 应从 CLAUDE.md 刷新 ────────────────
REFRESH_DIR="$(mktemp -d)"
run_setup "$REFRESH_DIR" >/dev/null
if ! grep -qF 'Describe the repository purpose and the main workflows for contributors.' "$REFRESH_DIR/AGENTS.md"; then
    echo "FAIL: 没有 CLAUDE.md 时 AGENTS.md 应回退到 project-init 模板" >&2
    exit 1
fi
cat > "$REFRESH_DIR/CLAUDE.md" <<'REFRESH_EOF'
# CLAUDE.md

项目约定：写代码一定要写注释⚠️
REFRESH_EOF
# 第二次跑：没有新文件可建 → 走「已完全初始化」的早退分支，仍必须同步 AGENTS.md
REFRESH_OUT=$(run_setup "$REFRESH_DIR" 2>&1)
if ! printf '%s' "$REFRESH_OUT" | grep -qF '[SYNC] AGENTS.md'; then
    echo "FAIL: 已初始化项目重跑 setup 没有触发 AGENTS.md 同步" >&2
    exit 1
fi
if ! grep -qF '写代码一定要写注释' "$REFRESH_DIR/AGENTS.md"; then
    echo "FAIL: AGENTS.md 仍是模板时没有从 CLAUDE.md 刷新" >&2
    exit 1
fi
if grep -qF 'Describe the repository purpose' "$REFRESH_DIR/AGENTS.md"; then
    echo "FAIL: 刷新后 AGENTS.md 仍残留模板占位" >&2
    exit 1
fi
rm -rf "$REFRESH_DIR"

# ── teardown 剥离 .gitignore 块：多段同名块都要清干净 ───────────────────
GITIGNORE_DIR="$(mktemp -d)"
# .gitignore 必须在 setup 之前就存在（否则 setup 会把它写进 manifest，
# teardown 直接删整个文件，就测不到「剥离」这条路径了）。
# 前两行是用户自己的忽略项 —— 剥离时必须原样保留。
printf '%s\n' 'node_modules/' '.claude/' '# project-init generated local agent files' '.claude/' '.codex/' '.codegraph/' '' '# project-init generated local agent files' 'CLAUDE.md' 'AGENTS.md' > "$GITIGNORE_DIR/.gitignore"
run_setup "$GITIGNORE_DIR" >/dev/null
bash "$ROOT_DIR/scripts/teardown-project.sh" "$GITIGNORE_DIR" --yes >/dev/null 2>&1
if grep -qF 'project-init generated local agent files' "$GITIGNORE_DIR/.gitignore"; then
    echo "FAIL: teardown 没剥掉 .gitignore 里的 project-init 块" >&2
    exit 1
fi
if grep -qFxq 'AGENTS.md' "$GITIGNORE_DIR/.gitignore" || grep -qFxq 'CLAUDE.md' "$GITIGNORE_DIR/.gitignore"; then
    echo "FAIL: teardown 剥离后仍残留 CLAUDE.md / AGENTS.md 条目" >&2
    exit 1
fi
if ! grep -qFxq 'node_modules/' "$GITIGNORE_DIR/.gitignore"; then
    echo "FAIL: teardown 剥离时误删了用户自己的忽略项" >&2
    exit 1
fi
CLAUDE_IGNORE_COUNT=$(grep -cFx '.claude/' "$GITIGNORE_DIR/.gitignore" || true)
if [[ "$CLAUDE_IGNORE_COUNT" -ne 1 ]]; then
    echo "FAIL: teardown 剥离时误删了用户自己的 .claude/ 忽略项" >&2
    exit 1
fi
rm -rf "$GITIGNORE_DIR"

# ── setup 补 .gitignore 缺失条目时不得新起同名块 ───────────────────────
MERGE_DIR="$(mktemp -d)"
printf '%s\n' 'node_modules/' '# project-init generated local agent files' '.claude/' '.codex/' '.codegraph/' > "$MERGE_DIR/.gitignore"
run_setup "$MERGE_DIR" >/dev/null
BLOCK_COUNT=$(grep -cFx '# project-init generated local agent files' "$MERGE_DIR/.gitignore" || true)
if [[ "$BLOCK_COUNT" -ne 1 ]]; then
    echo "FAIL: setup 补缺失条目时新起了第 ${BLOCK_COUNT} 个 project-init 块" >&2
    exit 1
fi
for entry in 'CLAUDE.md' 'AGENTS.md' '.claude/' '.codex/' '.codegraph/'; do
    if ! grep -Fxq "$entry" "$MERGE_DIR/.gitignore"; then
        echo "FAIL: setup 后 .gitignore 缺少条目 $entry" >&2
        exit 1
    fi
done
if ! grep -Fxq 'node_modules/' "$MERGE_DIR/.gitignore"; then
    echo "FAIL: setup 改动了用户自己的 .gitignore 条目" >&2
    exit 1
fi
rm -rf "$MERGE_DIR"

# ── teardown 不得整份删掉含用户内容的 .gitignore ─────────────────────────
# 旧判据「文件 ≤ 7 行即认为是 setup 建的」会误删用户自己的忽略项
# （例：用户原本只有 `node_modules/` 一行，setup 补完条目后刚好 ≤ 7 行）。
KEEP_DIR="$(mktemp -d)"
printf 'node_modules/\n' > "$KEEP_DIR/.gitignore"
run_setup "$KEEP_DIR" >/dev/null
bash "$ROOT_DIR/scripts/teardown-project.sh" "$KEEP_DIR" --yes >/dev/null 2>&1
if [[ ! -f "$KEEP_DIR/.gitignore" ]]; then
    echo "FAIL: teardown 整份删掉了含用户内容的 .gitignore" >&2
    exit 1
fi
if ! grep -Fxq 'node_modules/' "$KEEP_DIR/.gitignore"; then
    echo "FAIL: teardown 删掉了用户自己的 .gitignore 条目" >&2
    exit 1
fi
if grep -qFxq 'AGENTS.md' "$KEEP_DIR/.gitignore"; then
    echo "FAIL: teardown 没剥掉 .gitignore 里的 project-init 条目" >&2
    exit 1
fi
if grep -qFxq '.agents/skills/z-commit/' "$KEEP_DIR/.gitignore"; then
    echo "FAIL: teardown 没剥掉 Codex skill 的 gitignore 条目" >&2
    exit 1
fi
rm -rf "$KEEP_DIR"

echo "setup-project regression checks passed (incl. case-variant reuse + CLAUDE→AGENTS sync)"
