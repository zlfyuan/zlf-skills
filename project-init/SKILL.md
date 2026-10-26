---
name: project-init
description: >
  自动检测并初始化编程项目，管理自主开发循环。
  每次启动 Claude Code 或 Codex 时触发 —— 检测当前目录是否是编程项目，
  如果是则自动创建 .claude/ 和 .codex/ 目录结构（.codex/ 全部软连接到 .claude/）、
  初始化 CLAUDE.md / AGENTS.md、.claude/progress/ 状态追踪目录、配置默认权限、
  安装 /z-commit /z-push /z-commit-push（Claude 写入 .claude/commands；有 .codex 时 Codex 写入 .codex/skills，否则写入低优先级的 .agents/skills）、添加 CodeGraph MCP 并执行 codegraph init。
  当用户使用 /loop 或 /goal 命令启动自主开发循环时，触发并强制执行自主开发规则：
  维护 .claude/progress/ 状态追踪（README.md 总索引 + stage-NNN.md 阶段文件 + problems.md 踩坑记录）、
  每个模块编译验证后才能推进、最终用户视角完整测试、
  同一问题修复超过 5 次则记录到 problems.md 并跳过。
  手动触发方式：输入 "init project"、"setup project"、"初始化项目"、"项目初始化"、
  "autonomous development"、"自主开发" 等关键词。
  IMPORTANT: 当用户在非代码目录中向 Claude 提问代码问题时，使用此技能检查项目类型并给出适当提示。
  IMPORTANT: 当用户使用 /loop 或 /goal 启动自主开发任务时，使用此技能强制执行开发循环规则和 PROGRESS.md 状态追踪。
license: MIT
---

# Project Init — 项目自动初始化

为每个编程项目建立统一的基础设施：项目指令文件、权限配置、CodeGraph 代码图索引、自主开发追踪，以及一组 git 快捷命令。在 **Claude Code** 和 **Codex** 中行为一致，`.codex/` 下全部内容是软连接到 `.claude/`（除 `AGENTS.md` 入口文件）。

---

## 目录

- [概览](#概览)
- [何时触发](#何时触发)
- [会话开始检查（禁止大小写幻觉）](#会话开始检查禁止大小写幻觉)
- [创建的项目结构](#创建的项目结构)
- [执行流程](#执行流程)
- [Bundled 斜杠命令](#bundled-斜杠命令)
- [关键子系统](#关键子系统)
- [自主开发循环（/loop、/goal）](#自主开发循环loopgoal)
- [脚本参考](#脚本参考)
- [检测「编程项目」的标准](#检测编程项目的标准)
- [卸载 / 回滚（teardown）](#卸载--回滚teardown)
- [Additive-Only 原则](#additive-only-原则)
- [安装位置与依赖](#安装位置与依赖)

---

## 概览

`project-init` 把"项目状态 + 代理指令文件 + 开发工具链"打包成一个一键动作：

| 维度 | 之前 | 之后 |
|------|------|------|
| 项目指令 | 无 / 各家工具各自找 | 根目录 `CLAUDE.md` + `AGENTS.md`（由 CLAUDE.md 镜像生成）+ `.claude/CLAUDE.md`、`.codex/AGENTS.md` 软连接 |
| 权限 | 全部默认 deny | `.claude/settings.local.json` 带 npm / go / cargo / git / codegraph 等常用白名单 |
| CodeGraph | 需要手动 `codegraph init` | 自动检测 CLI 并执行 `codegraph init` |
| Plan 存档 | 写到 `~/.claude/plans/`（项目外，git 看不到） | Plan 镜像规则注入到所有指令文件，强制 cp 到 `.claude/plans/` |
| Git 快捷方式 | `/commit`、`/push` 等无统一约定 | `/z-commit`、`/z-push`、`/z-commit-push` 三条自动化斜杠命令 |
| 自主开发 | 自由发挥 | `.claude/progress/` 强制维护 `README.md` + `stage-NNN.md` + `problems.md` |

**核心原则**：只增不删、只补不改。对用户已有内容一律保留。

---

## 何时触发

### 自动触发（Claude Code / Codex SessionStart hook）

每次新会话开始时，`auto-init.sh` 检查 `.claude/.init-done`：

- 存在，且 Codex 技能已在（有 `.codex` 时看 `.codex/skills/`，否则看低优先级的 `.agents/skills/`）→ 已初始化，跳过
- 存在，但对应位置的技能还缺 → 再跑一次 `setup-project.sh` 补上
- 不存在 → `detect-code-project.sh` 判断 → 是编程项目就跑 `setup-project.sh`

### 手动触发关键词

不论 Claude Code 还是 Codex，会话里输入下列任意一条即可触发：

| 中文 | 英文 |
|------|------|
| 初始化项目 / 项目初始化 | `init project` |
| 配置项目 | `setup project` |
| 自主开发 | `autonomous development` |

执行链路：

1. `bash scripts/detect-code-project.sh <dir>` —— 判断是否是编程项目
2. 是 → `bash scripts/setup-project.sh <dir>` —— 增量初始化
3. 否 → 提示用户切换到正确的代码项目目录（不阻塞工作）

### 会话开始检查（禁止大小写幻觉）

Agent 判定「项目有没有初始化」时，必须遵守：

1. **规范名永远全小写**：`.claude/`、`.codex/`。setup 创建的就是这两个名字。
2. **禁止把产品名写成路径**。不要检查 `.Codex/`、`.Claude/`、`.CODEX/`。产品叫 Codex，目录叫 `.codex/`。
3. **检查必须大小写不敏感**。推荐：
   ```bash
   find . -maxdepth 1 \( -iname '.claude' -o -iname '.codex' \)
   ```
4. **命中 `.codex/` 或 `.claude/` 任一 → 已初始化，继续任务。** 不要因为 `ls .Codex` / Glob `.Codex` 找不到就停下。两者都没有才提醒用户跑 project-init。

---

## 创建的项目结构

初始化（**可重入，additive-only**）后会得到如下布局：

```text
project-root/
├── CLAUDE.md                 # Claude Code 项目指令（由 `claude /init` 代码库感知生成）
├── AGENTS.md                 # Codex / 其他代理 项目指令（由 CLAUDE.md 镜像生成）
├── .claude/                  # 主目录 —— 全部实文件，承担 config + 状态存储
│   ├── CLAUDE.md             # symlink → ../CLAUDE.md
│   ├── settings.local.json   # 项目级权限配置 + plansDirectory
│   ├── rules/                # 项目规则目录
│   ├── skills/               # 项目级技能目录
│   ├── commands/             # 自定义命令目录（含 /z-commit /z-push /z-commit-push 模板）
│   ├── plans/                # Plan 模式计划存档（由镜像规则强制填充）
│   ├── progress/             # 🌀 自主开发状态追踪
│   │   ├── README.md         #   总索引（Stage 列表 + 进度统计 + 问题速览）
│   │   ├── stage-NNN.md      #   每个阶段的 目标 / 子任务 / 执行日志
│   │   └── problems.md       #   踩坑知识库（出现次数 / 最终方案）
│   ├── memory/               # 项目级长期记忆（跨会话加载的事实/约定/已知坑）
│   │   └── MEMORY.md         #   索引：每条记忆一行摘要，正文以独立 <slug>.md 存放
│   ├── .project-init-manifest # setup 创建清单，供 teardown 精确清理
│   └── .init-done            # 一次性初始化完成标记
├── .codex/                   # 镜像目录 —— 除 AGENTS.md 外其余都软连接到 .claude/
│   ├── AGENTS.md             # symlink → ../AGENTS.md
│   ├── rules/                # symlink → ../.claude/rules
│   ├── skills/               # symlink → ../.claude/skills（有 .codex 时 z-commit 等技能写在这里）
│   ├── commands/             # symlink → ../.claude/commands（Codex 不读这个目录）
│   ├── plans/                # symlink → ../.claude/plans
│   └── progress/             # symlink → ../.claude/progress
└── .codegraph/               # CodeGraph 索引数据（由 codegraph init 自动生成）
```

### 布局哲学

以 `.claude/` 为 config 和状态的真实存储，`.codex/` 通过软连接复用。Codex 不读 `.claude/commands/`。有 `.codex` 时，同一份命令正文写到 `.codex/skills/<name>/SKILL.md`（经 skills 软链落在 `.claude/skills/`）。没有 `.codex` 才用低优先级目录 `.agents/skills/`。

**唯一例外**：`.codex/AGENTS.md` 和 `.claude/CLAUDE.md` 是对方工具在自己目录下寻找入口文件的"门面"，它们通过软连接指向项目根的 `AGENTS.md` / `CLAUDE.md`。

**Additive 安全**：用户已有 `.codex/<sub>` 实目录 / 实文件时不会被替换为软连接；只在该子项不存在时才建软连接。

---

## 执行流程

`auto-init.sh` 是入口；真实的判定 + 初始化调用图：

```text
┌─────────────────────────────┐
│  检查 .claude/.init-done    │
│  ├─ 在且 Codex 技能在 → 跳过│
│  ├─ 在但技能缺 → setup 补齐 │
│  └─ 不存在 → 继续判定       │
└─────────────┬───────────────┘
              ▼
┌─────────────────────────────┐
│  detect-code-project.sh     │
│  编程项目判定               │
│  ├─ 包管理标记 (优先级最高) │
│  ├─ 源代码文件 ≥ 5 个       │
│  └─ .git 历史含代码         │
└─────────────┬───────────────┘
              ▼
   ┌──────────┴──────────┐
   ▼                     ▼
┌──────────┐      ┌──────────────┐
│ 是代码   │      │ 非代码项目   │
│ 项目     │      │ 写告警到     │
│          │      │ CLAUDE.md /  │
│ setup.sh │      │ AGENTS.md    │
└──────────┘      └──────────────┘
```

`setup-project.sh` 内部又分两阶段：

1. **Phase 1 · Audit** —— 用 `ci_resolve`（大小写不敏感）扫描目标项目，对每一项输出 `[NEW] / [KEEP] / [SKIP]`，**不写盘**
2. **Phase 2 · Create** —— **只**为 Phase 1 标 `[NEW]` 的项创建文件 / 软连接 / 配置文件

可重入：再次运行看到全 `[KEEP]` 立即退出，零副作用。

---

## Bundled 斜杠命令

`project-init` 在 setup 时把 `assets/commands/` 里的三条模板装到两个入口。正文只维护一份：

| 工具 | 安装位置 | 怎么调用 |
|------|----------|----------|
| Claude Code | `.claude/commands/<name>.md` | `/z-commit`、`/z-push`、`/z-commit-push` |
| Codex（有 `.codex`，含 `.Codex` 等大小写变体） | `.codex/skills/<name>/SKILL.md` | `$z-commit`、`$z-push`、`$z-commit-push` |
| Codex（没有 `.codex`） | `.agents/skills/<name>/SKILL.md` | 同上，低优先级 |

Codex 不扫描 `.claude/commands/`，也不扫描 `.codex/commands/`。有 `.codex` 时技能放在 `.codex/skills/`（project-init 里这个目录软链到 `.claude/skills/`）。`.agents/skills/` 只在项目没有 `.codex` 时使用。两边内容相同的副本不会各留一份，避免 Codex 把同一个命令列两次。

三条命令的行为：

| 命令 | 行为 |
|------|------|
| `/z-commit` | `git add -A` + 自动生成中文 commit message（基于 `git diff --stat`） → 回车确认 → `git commit`。**不** push。 |
| `/z-push` | `git push`（无上游自动 `--set-upstream`，**绝不** `--force`）。本地有未提交改动会先拦截。 |
| `/z-commit-push` | commit + push 合一步：先扫状态，若已有未推送 commit 则跳过 commit 单走 push；否则合并 preview 一次性确认。 |

**触发规则**（在每个命令的 `.md` 里有完整步骤）：

- `/z-commit`：agent 看 `git diff --stat` → 写 Conventional Commits 中文 message → 显示预览 → `read -r -p` 让用户回车 → `git add -A && git commit`
- `/z-push`：agent 看 `git status`、`git rev-parse --abbrev-ref HEAD`、`git config --get-regexp '^branch\.'` → 显示 preview → 确认 → `git push`
- `/z-commit-push`：上述两条合一起，统一一次确认

覆盖保护：setup-project.sh 只在目标命令文件**不存在**时才拷贝；用户定制过的同名命令不会被覆盖。

---

## 关键子系统

### 1. CLAUDE.md 生成 —— 调用 `claude /init`

**`CLAUDE.md` 不由 project-init 自己写模板**，而是调用 Claude Code 内置的 `/init` 走代码库感知生成；project-init 在末尾追加 Plan 镜像规则。

调用方式（`setup-project.sh` 中自动执行，180s 超时）：

```bash
cd "$TARGET" && \
claude --bare --permission-mode acceptEdits \
  --allowedTools "Write,Read,Glob,Grep,Bash(ls:*),Bash(find:*),Bash(cat:*),Bash(wc:*),Bash(head:*)" \
  -p "/init" < /dev/null
```

| flag | 为何必须 |
|------|---------|
| `--bare` | 否则 subprocess 触发 `SessionStart` hook，钩子链里就是 `auto-init.sh → setup.sh`，会先写占位 `CLAUDE.md` 让 `/init` 的 `Write` 被拒 |
| `--permission-mode acceptEdits` | 允许 `/init` 写入生成的 `CLAUDE.md`，但不绕过其它工具的权限检查 |
| `< /dev/null` | 后台 + 重定向时 stdin 不是 TTY，claude 报 "no stdin data received in 3s" 退出 0 不写文件 |
| `--allowedTools "Write,..."` | 显式列工具子集，避免依赖默认 allowlist |

**回退策略**：`claude` 未装 / `/init` 退出非零 / 超时 / 产物 < 500 字节 → 写带明显占位说明的 heredoc，文件里提示用户手动跑覆盖。

```bash
# 手动重跑
claude --bare --permission-mode acceptEdits \
  --allowedTools "Write,Read,Glob,Grep,Bash(ls:*),Bash(find:*),Bash(cat:*),Bash(wc:*)" \
  -p "/init" < /dev/null
bash scripts/setup-project.sh "$TARGET"   # 让 Plan 镜像规则被补上
```

### 2. AGENTS.md 同步 —— 由 CLAUDE.md 镜像生成

项目约定只写一份在 `CLAUDE.md`，`AGENTS.md`（Codex 的入口文件）由它镜像生成 —— 两份文件各维护一遍必然漂移。实现见 `scripts/agents-mirror.sh`。

| 场景 | 行为 |
|------|------|
| `CLAUDE.md` 有真实约定，`AGENTS.md` 不存在 | `[NEW]` 镜像生成 |
| `AGENTS.md` 仍是没动过的模板，`CLAUDE.md` 有真实约定 | `[SYNC]` 重新镜像 |
| `AGENTS.md` 已被用户改过 | `[KEEP]` 原样保留 |
| `CLAUDE.md` 缺失 / 仍是占位模板 | `[NEW]` 退回 project-init 自带模板 |

镜像时的 Codex 侧适配：

| 适配项 | 处理 |
|--------|------|
| 标题 | `# CLAUDE.md` → `# AGENTS.md` |
| Claude 专属内容 | `/compact` 斜杠命令、`ExitPlanMode` API 整行剔除 |
| Plan 镜像规则 | 整段换成 Codex 措辞（`PMR_AGENTS_BLOCK`） |
| 会话开始检查 | `CLAUDE.md` 里没有就补 Codex 版标准块（规范名全小写 `.codex/`） |

**「没动过的模板」判据**：模板抬头文案 + 模板占位句都还在 → 视为未改动，可安全重新生成；否则一律保留（additive-only）。

### 3. Plan 文件镜像规则 —— 自动注入到所有指令文件

harness 默认把 plan 写到全局 `~/.claude/plans/<session>.md`（**项目外**，git 追踪不到）。即使 `settings.local.json` 配了 `plansDirectory`，当前 Claude Code 版本**不读取**该字段（已实测）。

因此 setup-project.sh 会在 `CLAUDE.md`、`AGENTS.md` 自动注入 Plan 镜像规则，告诉 agent：

1. 从 plan mode 的 system message 拿 plan 的 `file_path`（绝对路径）
2. `mkdir -p .claude/plans`
3. `cp <file_path> .claude/plans/$(basename <file_path>)`
4. 在副本末尾追加 `<!-- mirror source: <file_path> -->`
5. 完成上述 4 步**之后**再 `ExitPlanMode`

| 场景 | 行为 |
|------|------|
| 文件不存在 | `[NEW]` 创建并嵌入完整 Plan 镜像规则 |
| 文件已含 Plan 镜像规则 | `[KEEP]` 原样保留 |
| 文件存在但缺规则 | `[KEEP]` 主体 + 追加规则（如 `/init` 创建的 `CLAUDE.md`） |

**已有项目批量迁移**：

```bash
bash scripts/inject-plan-mirror.sh /path/to/project   # 单项目
bash scripts/inject-plan-mirror.sh --dry-run /path/to/project   # 仅预览
bash scripts/inject-plan-mirror.sh --recursive /path/to/codebase # 扫描所有含 .claude/ 的子项目
```

`pmr_inject` 函数 + 规则块文本在共享 lib `scripts/plan-mirror-rules.sh`，setup / inject 共用同一份逻辑。

### 4. 默认 `.claude/settings.local.json` 权限

合并式创建，缺什么加什么，**不覆盖**已有权限：

- **包管理器**：`Bash(npm:*)` / `Bash(yarn:*)` / `Bash(pnpm:*)` / `Bash(bun:*)` / `Bash(pip:*)` / `Bash(pip3:*)`
- **运行时**：`Bash(node:*)` / `Bash(python:*)` / `Bash(go:*)` / `Bash(cargo:*)` / `Bash(javac:*)` / `Bash(swift:*)`
- **构建**：`Bash(xcodebuild:*)` / `Bash(make:*)` / `Bash(cmake:*)` / `Bash(mvn:*)` / `Bash(gradle:*)`
- **VCS / 网络**：不自动放行 `git`、`curl` 或 Web 工具，首次使用时由用户确认
- **CodeGraph**：`Bash(codegraph:*)`
- **shell helpers**：`Bash(ls:*)` / `Bash(cat:*)` / `Bash(find:*)` / `Bash(grep:*)` / `Bash(mkdir:*)` 等
- **文件 / 网络**：不自动放行全局文件读写和网络访问，避免意外泄露敏感内容
- **预留**：`plansDirectory = .claude/plans`（forward-compat，等未来 harness 支持时自动生效）

### 5. CodeGraph 集成

| 状态 | 行为 |
|------|------|
| `codegraph` CLI 已安装 | 自动 `codegraph init "$TARGET"` 创建 `.codegraph/` 索引 |
| 未安装 | 给出 `curl -fsSL ... install.sh | sh` 提示，其它初始化照常进行 |

**PATH 兜底**：`codegraph` 官方安装脚本默认装到 `~/.local/bin`，但 GUI 启动的 agent 进程常常没把它带进 PATH（表现为"CLI 未安装"）。setup 会显式补查 `$HOME/.local/bin/codegraph` 并把它加进 PATH 再调用。

**MCP 侧同一个坑**：`~/.claude.json` 里的 `mcpServers.codegraph.command` 若写裸 `codegraph`，MCP 进程同样会因 PATH 缺失而连不上（报 `ENOENT: Executable not found in $PATH: codegraph`）。两个修法：

- 配绝对路径 `"command": "/Users/<you>/.local/bin/codegraph"`（推荐，不依赖 PATH）
- 或把 `~/.local/bin/codegraph` 软链到 PATH 里已有的目录（如 `/opt/homebrew/bin/`）

**注意**：CodeGraph 只索引受支持语言的源码（`.ts` / `.py` / `.go` / `.swift` …）。纯 `.md` / `.sh` / `.json` 的仓库会提示 "No supported source files found" —— 这是正常现象，不是安装失败。 |

### 6. 项目级长期记忆 —— `.claude/memory/`

每次 setup 会创建 `.claude/memory/MEMORY.md`（additive：已有则不动）。**MEMORY.md 每次会话开始时加载到上下文**，是 agent 跨 Stage 滚动时仍需复用的"长期事实"。

**与 `.claude/progress/` 的关系**：

| `.claude/progress/` | `.claude/memory/` |
|---------------------|---------------------|
| 按 Stage / Issue 滚动更新 | 跨 Stage **不变**的事实 |
| 一次性笔记：当下任务进度 | 设计决策、长期约束、命名约定、已知坑 |
| 一完成 Stage 就归档 / 清理 | 一直累积，越用越值钱 |

**怎么写新条目**：

1. 在 `.claude/memory/<kebab-case-slug>.md` 新建文件，frontmatter 含 `name` / `description` / `type: feedback|reference|project`
2. 在 `MEMORY.md` 的索引表加一行 `- [标题](<slug>.md) — 一句话摘要`
3. 文件之间互相 `[[<slug>]]` 引用

**禁写**：

- 当前任务进度（属于 progress）
- 敏感信息：密码 / API key / token
- 临时性的 chat 内容

### 7. 大小写不敏感路径解析（fix）

`scripts/ci-path.sh` 共享 lib 提供 `ci_topdir` / `ci_resolve` / `ci_exists` / `ci_canon`，POSIX-sh 兼容（bash / zsh 均可 source）。setup / teardown / inject / detect 都通过它处理 `.Codex/` `.CLAUDE/` 等用户手建变体：

- 文档统一小写（`.claude/` `.codex/`）
- 实际检查大小写不敏感（命中后保留用户原大小写）
- 已有 case-variant 时复用而非创建平行 `.claude/` / `.codex/` 副本
- agent 会话开始检查同样遵守此规则（见「何时触发」），禁止把产品名写成 `.Codex/` 再当缺失

---

## 自主开发循环（/loop、/goal）

当 `/loop` 或 `/goal` 被触发，**必须严格遵守**以下 4 条规则，全程自主推进，除非遇到无法自行解决的阻塞问题。

### 规则 1 · 状态追踪 → `.claude/progress/`

```text
.claude/progress/
├── README.md     # 总索引：当前阶段、Stage 列表、进度统计、问题速览
├── stage-001.md  # 阶段文件：🎯 目标 / 📋 子任务 / 📝 执行日志 / 🚧 问题 / ✅ 验证
├── stage-002.md
└── problems.md   # 踩坑记录：问题索引 + 每个问题的症状 / 尝试 / 最终方案
```

**stage-NNN.md 模板**：

```markdown
# Stage 001: 任务名称
- 状态: 🔄 进行中 | 开始: YYYY-MM-DD | 尝试: 0/5

## 🎯 目标
## 📋 子任务
## 📝 执行日志（时间线）
## 🚧 遇到的问题（链接到 problems.md）
## ✅ 验证记录
```

**更新时机**：每完成一个 Stage → 更新 README.md 统计 + 推对应 stage-NNN.md 状态。**不要攒到最后补**。

### 规则 2 · 开发-验证闭环

```text
┌──────────┐    编译/运行      ┌──────────┐
│ 完成模块 │ ──────────────→  │ 验证通过? │
└──────────┘                  └─────┬────┘
                             ├─ 是 → 更新 PROGRESS，推进下一模块
                             └─ 否 → 修复错误，重新验证
```

- 每完成一个功能模块立即编译运行验证
- 有报错就修，修完再验证，通过才推进下一个
- 纯脚本项目用调用 / 单测验证
- 每通过一个 Stage 在对应 `stage-NNN.md` 打 ✅ 并更新 README 统计

### 规则 3 · 最终用户视角验证

全部模块完成后做一次端到端：

- 用户典型操作流程走一遍
- 边界情况：空输入、极值、并发、网络断开
- UI：错误提示是否清晰、交互是否顺畅
- 结果写到对应 `stage-NNN.md` 的「验证记录」

### 规则 4 · 防死循环 — 5 次上限

同一问题修复 **>5 次** 仍未解决，**立即停止**并：

1. 写进 `problems.md`，标 `🔴 已跳过`
2. 当前 `stage-NNN.md` 记跳过决策，README 标 `🔴 已跳过`
3. **继续推进其他任务** —— 不要被一个卡点阻塞全部
4. 最终总结里列出所有被跳过的

**同问题的判定**：相同错误信息 / 相同症状。换了方法仍是同症状 → 算同问题；症状变了（不同错误）→ 算新问题，重置计数。

---

## 脚本参考

| 脚本 | 用途 | 退出码 |
|------|------|--------|
| `scripts/auto-init.sh` | Hook 入口，协调 detect + setup | `0`=完成/已初始化 / `1`=非代码项目 / `2`=错误 |
| `scripts/detect-code-project.sh` | 编程项目判定 | `0`=是 / `1`=否 |
| `scripts/setup-project.sh` | 完整项目初始化（additive） | `0`=成功 / `1`=失败 |
| `scripts/teardown-project.sh` | 反向操作：清理 setup 所有产物 | `0`=清理完成 / `1`=无产物/部分失败 / `2`=用户中止 |
| `scripts/inject-plan-mirror.sh` | 批量迁移 Plan 镜像规则到已有项目 | `0`=全部成功 / `1`=部分失败 / `2`=参数错误 |
| `scripts/plan-mirror-rules.sh` | **共享 lib**：Plan 规则块 + `pmr_inject` | 不可直接执行 |
| `scripts/agents-mirror.sh` | **共享 lib**：CLAUDE.md → AGENTS.md 同步 | 不可直接执行 |
| `scripts/ci-path.sh` | **共享 lib**：大小写不敏感路径解析 helpers | 不可直接执行 |

---

## 检测「编程项目」的标准

`detect-code-project.sh` 使用宽松策略，以下任一条件满足即判定为编程项目：

**① 包管理 / 构建系统标记文件**（优先级最高）

- Node.js: `package.json`
- iOS / Swift: `Podfile` / `Package.swift` / `*.xcodeproj` / `*.xcworkspace`
- Rust: `Cargo.toml` · Go: `go.mod` · Python: `setup.py` / `pyproject.toml` / `requirements.txt` / `Pipfile`
- Ruby: `Gemfile` · JVM: `pom.xml` / `build.gradle` / `build.gradle.kts` / `build.sbt`
- C/C++: `CMakeLists.txt` / `Makefile` · PHP: `composer.json`
- Dart: `pubspec.yaml` · Elixir: `mix.exs` · Haskell: `stack.yaml` / `*.cabal`
- 通用: `Dockerfile` / `docker-compose.yml` / `deno.json[c]` / `bun.lock`

**② 源代码文件数量** ≥ 5 个（或 ≥ 总文件数 5%；排除 `node_modules/`、`Pods/`、`vendor/`、`dist/`、`build/`、`__pycache__/` 等依赖 / 构建目录）

**③ `.git` 目录含代码历史**（用 `git ls-files` 命中任一 `*.swift` / `*.ts` / `*.js` / `*.py` / `*.go` / `*.rs` …）

---

## 卸载 / 回滚（teardown）

`teardown-project.sh` 是 `setup-project.sh` 的对偶 —— 移除项目中被 project-init 创建的产物，让目录回到 setup 之前的状态。

**清理范围**：

| 路径 | 默认行为 |
|------|---------|
| `.claude/` / `.codex/` / `.codegraph/` | 只删除 setup manifest 中记录的文件和软连接；目录仅在变空后删除 |
| 根目录 `CLAUDE.md` / `AGENTS.md` | **仅当**匹配 project-init 指纹才删（AGENTS.md 的指纹 = 模板占位句还在）；用户改过的版本保留并提示 |
| `.gitignore` | 精确剥离 `# project-init generated local agent files` 块（多段同名块也能清干净，用户自己的忽略项不动） |
| `.claude/settings.local.json` | **默认保留**（合并了用户权限）；`--purge-config` 才在指纹匹配时删除 |

**使用示例**：

```bash
bash scripts/teardown-project.sh                    # 交互式
bash scripts/teardown-project.sh --yes              # 跳过确认
bash scripts/teardown-project.sh --dry-run          # 仅审计
bash scripts/teardown-project.sh --keep-config      # 保留 CLAUDE.md / AGENTS.md / settings
bash scripts/teardown-project.sh --purge-config     # 同步移除 settings.local.json
bash scripts/teardown-project.sh --backup --yes     # 删前打包 .project-init-backup-*.tar.gz
```

**安全策略**：
- 用户改过的文件通过指纹识别，**不匹配默认不动**
- `--yes` 才删无指纹的"用户内容"，且单独打印 ⚠ 警告
- `--dry-run` 始终安全
- 退出码 `2` = 用户中止了 prompt

---

## Additive-Only 原则

初始化脚本严格遵守**只增不删、只补不改**：

- **已有文件 → 保留不动**。如果 `CLAUDE.md`、`AGENTS.md` 等已存在，**绝不覆盖**（唯一例外：`AGENTS.md` 还是没动过的模板而 `CLAUDE.md` 已有真实约定 → 重新镜像，见「关键子系统 2」）
- **已有 `settings.local.json` → 智能合并**。只添加缺失的推荐权限和 `plansDirectory` 设置，已有的完全保留
- **已有 `.codegraph/` → 跳过**。不重复索引
- **已有目录 → 保留不动**。`mkdir -p` 对已有目录无副作用
- **只在缺少时才创建**。审计阶段会扫描所有项，报告中明确标 `[KEEP]` 保留的与 `[NEW]` 新建的
- **重复运行 `setup-project.sh` 是安全的**，已存在项一条 `[KEEP]` 之后立即退出，不损坏任何内容

---

## 安装位置与依赖

**位置**：此技能是**用户级技能**，存放在 `~/.claude/skills/project-init/`（或 `~/.codex/skills/project-init/`）。

**自动触发**：依赖 `SessionStart` hook（写在 `settings.local.json` 里），但当前 Claude Code 版本**不读取**该项目级配置，所以现在主要靠 agent 启动时通过关键词识别 / 用户手动触发。

**依赖**：
- `bash` 3.2+ / `zsh` 兼容（POSIX-sh 兼容）
- `find`（GNU 或 BSD macOS 10.12+）
- `python3`（用于 settings.local.json 与 plansDirectory 合并）
- 可选：`claude` CLI（用于 `/init` 生成 CLAUDE.md；缺失回退到 heredoc 占位）
- 可选：`codegraph` CLI（缺失则跳过索引创建）

**初始化标记**：`.claude/.init-done` 让 hook 不必每次重审，内容是初始化时间戳（ISO 8601）。对应位置的 Codex 技能还缺时会再跑一次 setup 补齐。有 `.codex` 时看 `.codex/skills/`，否则看 `.agents/skills/`。

---

## 备注

- 所有生成的模板文件都包含 `<!-- TODO -->` 标记，让用户在第一次见到时知道哪里需要补
- `assets/commands/` 的命令模板只是**初次安装的种子**，用户完全可以自定义自己的版本覆盖
- 大小写行为详见 `.claude/memory/codex-dir-lowercase.md`（规范名 `.codex/`，禁止检查 `.Codex/`）
- Plan 文件镜像规则详见随仓 `CLAUDE.md` 顶部「Plan 文件镜像（重要）」章节
