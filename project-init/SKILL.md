---
name: project-init
description: >
  自动检测并初始化编程项目，管理自主开发循环。
  每次启动 Claude Code 或 Codex 时触发 —— 检查当前目录是否是编程项目，
  如果是则自动创建 .claude/ 和 .codex/ 目录结构、初始化 CLAUDE.md / AGENTS.md、
  .claude/progress/ 状态追踪目录、配置默认权限、添加 CodeGraph MCP 并执行 codegraph init。
  当用户使用 /loop 或 /goal 命令启动自主开发循环时，触发并强制执行自主开发规则：
  维护 .claude/progress/ 状态追踪（README.md 总索引 + stage-NNN.md 阶段文件 + problems.md 踩坑记录）、
  每个模块编译验证后才能推进、最终用户视角完整测试、
  同一问题修复超过 5 次则记录到 problems.md 并跳过。
  手动触发方式：输入 "init project"、"setup project"、"初始化项目"、"项目初始化"、
  "autonomous development"、"自主开发" 等关键词。
  IMPORTANT: 当用户在非代码目录中向 Claude 提问代码问题时，使用此技能检查项目类型并给出适当提示。
  IMPORTANT: 当用户使用 /loop 或 /goal 启动自主开发任务时，使用此技能强制执行开发循环规则和 PROGRESS.md 状态追踪。
---

# Project Init — 项目自动初始化

## 概述

这个技能负责在 Claude Code 或 Codex 中自动检测和初始化代码项目。它确保每个编程项目都有正确的基础设施：代理指令文件、权限配置、CodeGraph 代码图索引，以及自主开发循环所需的 `.claude/progress/` 状态追踪目录。

当用户使用 `/loop` 或 `/goal` 命令启动自主开发任务时，此技能强制执行开发规则，确保 Agent 自主推进、不频繁停下来等待确认。进度数据存储在 `.claude/progress/` 目录中，项目根目录保持整洁。

---

## 🌀 自主开发循环规则

当 `/loop` 或 `/goal` 被触发时，**必须严格遵守以下 4 条规则**，全程自主推进，除非遇到无法自行解决的阻塞问题。

### 规则 1：状态追踪 → .claude/progress/

进度追踪文件全部放在 `.claude/progress/` 目录下，结构如下：

```
.claude/progress/
├── README.md          # 总索引：当前阶段、Stage 列表、进度统计、问题速览
├── stage-001.md       # 阶段文件：每个 Stage 的目标、子任务、执行日志
├── stage-002.md       # （第二个 Stage 时创建）
├── ...
└── problems.md        # 踩坑记录：反复遇到的问题、尝试方案、最终解决方式
```

**README.md** — 总仪表盘，自动维护：
- 当前阶段和总体进度
- Stage 列表（编号、名称、状态、备注）
- 进度统计（已完成 / 进行中 / 已跳过）
- 当前未解决问题的速览表

**stage-NNN.md** — 每个阶段的详细记录：
```markdown
# Stage 001: 任务名称
- 状态: 🔄 进行中 | 开始: YYYY-MM-DD | 尝试: 0/5

## 🎯 目标
## 📋 子任务
## 📝 执行日志（时间线）
## 🚧 遇到的问题（链接到 problems.md）
## ✅ 验证记录
```

**problems.md** — 踩坑知识库：
- 问题索引表（编号、简述、涉及 Stage、出现次数、状态）
- 每个问题的详情：症状、尝试方案、最终方案、经验总结
- 同一个问题重复出现时**更新出现次数**，不新建条目

**更新时机**：每完成一个 Stage 就更新 README.md 中的统计和 Stage 状态，同时在对应的 stage-NNN.md 中追加执行日志。不要攒到最后一次性补。

### 规则 2：开发-验证闭环

```
┌──────────┐    编译/运行      ┌──────────┐
│ 完成模块 │ ──────────────→  │ 验证通过? │
└──────────┘                  └─────┬────┘
                             ├─ 是 → 更新 PROGRESS.md，推进下一模块
                             └─ 否 → 修复错误，重新验证
```

- **每完成一个功能模块**，立即编译运行，用实际运行结果验证
- **有报错就修**，修完再验证，通过后才推进下一个模块
- **不要攒到最后一起测** —— 问题越早发现越容易定位
- 每完成一个 Stage，在对应的 stage-NNN.md 中打 ✅ 并更新 README.md 统计
- 对于无需编译的项目（如纯脚本），用实际调用或单元测试来验证

### 规则 3：最终用户视角验证

全部功能开发完成后，**以用户视角**做一次完整的端到端测试：

- 用户会怎么使用这个功能？按用户的典型操作流程走一遍
- 边界情况：空输入、极端值、并发操作、网络断开等
- 如果有 UI，检查交互流程是否顺畅、错误提示是否清晰
- 将测试结果记录到对应 stage-NNN.md 的「验证记录」区块，更新 README.md 状态为 ✅

### 规则 4：防死循环 — 5 次上限

同一个问题修复超过 **5 次**仍未解决，**立即停止**：

1. 在 `problems.md` 中记录详细情况（症状 + 所有尝试），标记为 `🔴 已跳过`
2. 在当前 stage-NNN.md 中记录跳过决策，在 README.md 中标记该 Stage 为 `🔴 已跳过`
3. **继续推进其他任务** —— 不要让一个卡点阻塞全部进度
4. 在最终总结时列出所有被跳过的问题（problems.md 中有完整索引）

**什么算「同一个问题」**：相同的错误信息、相同的症状表现，即使用不同的方法尝试也算同一个问题。如果症状变了（不同的错误），那是新问题，重新计数。

---

## 工作流程

### 自动化流程（通过 Hook 触发）

每次会话开始时，`auto-init.sh` 会运行以下检测流程：

```
┌─────────────────────────────┐
│  检查 .claude/.init-done   │
│  ├─ 存在 → 已完成，跳过     │
│  └─ 不存在 → 继续检测       │
└─────────────┬───────────────┘
              ▼
┌─────────────────────────────┐
│  detect-code-project.sh    │
│  检测是否是编程项目          │
│  ├─ 包管理文件 (package.json│
│  │  Podfile, Cargo.toml...) │
│  ├─ 源代码文件 (>= 5个)     │
│  └─ .git 含代码历史         │
└─────────────┬───────────────┘
              ▼
    ┌─────────┴─────────┐
    │                   │
    ▼                   ▼
┌──────────┐    ┌──────────────┐
│ 是代码项目│    │ 非代码项目    │
└─────┬────┘    └──────┬───────┘
      │                │
      ▼                ▼
┌──────────────┐  ┌────────────────┐
│ setup-project│  │ 创建警告文件    │
│ .sh 初始化   │  │ CLAUDE.md      │
│              │  │ AGENTS.md      │
│ • .claude/  │  │ 提示用户切换    │
│ • .codex/   │  │ 到代码项目目录  │
│ • codegraph │  └────────────────┘
│ • settings  │
└──────────────┘
```

### 手动触发

用户可以通过以下关键词手动触发：

- `init project` / `setup project` / `initialize project`
- `初始化项目` / `项目初始化`
- `setup this project` / `configure project`

手动触发时，技能会：
1. 运行 `scripts/detect-code-project.sh` 检测项目类型
2. 如果检测为编程项目，运行 `scripts/setup-project.sh` 初始化
3. 如果检测为非编程项目，告知用户并询问是否确认继续

## 初始化内容

### 目录结构

初始化后会创建以下结构：

```
project-root/
├── CLAUDE.md                 # Claude Code 项目指令（由 `claude /init` 生成，见下）
├── AGENTS.md                 # Codex / 其他代理 项目指令
├── .claude/
│   ├── settings.local.json   # 项目级权限配置 + plansDirectory（预留字段，当前不生效）
│   ├── rules/                # 项目规则目录
│   ├── skills/               # 项目级技能目录
│   ├── commands/             # 自定义命令目录
│   ├── plans/                # Plan 模式计划存档（由镜像规则填充）
│   ├── progress/             # 🌀 自主开发状态追踪
│   │   ├── README.md         #   总索引（Stage 列表 + 进度统计）
│   │   ├── stage-001.md      #   阶段文件（目标/子任务/执行日志）
│   │   └── problems.md       #   踩坑记录（问题索引 + 详情）
│   └── .init-done            # 初始化完成标记
├── .codex/
│   └── AGENTS.md             # Codex 目录级指令
└── .codegraph/               # CodeGraph 索引数据 (由 codegraph init 创建)
```

### 🧠 CLAUDE.md 生成：调用 `claude /init`

`CLAUDE.md` **不是** project-init 自己写的占位模板，而是由 `claude /init`
（Claude Code 内置的「分析当前代码库并生成 CLAUDE.md」斜杠命令）生成的代码库感知内容，
最后再由 project-init 把 Plan 镜像规则追加到末尾。

**调用方式**（`setup-project.sh` 在 CLAUDE.md 不存在时自动执行）：

```bash
cd "$TARGET" && \
claude --bare --dangerously-skip-permissions \
  --allowedTools "Write,Read,Glob,Grep,Bash(ls:*),Bash(find:*),Bash(cat:*),Bash(wc:*),Bash(head:*)" \
  -p "/init" < /dev/null
```

**每个 flag 为什么必须：**

- **`--bare`** — 不加的话，subprocess 会触发用户的 `SessionStart` hook，
  而 hook 链上就是 `auto-init.sh → setup-project.sh`，会先把占位 CLAUDE.md 写好，
  导致 `/init` 申请 `Write` 时被拒。`--bare` 跳过 hooks（以及 CLAUDE.md auto-discovery
  等副作用），让 `/init` 在干净环境里跑。
- **`--dangerously-skip-permissions`** — `-p` 模式下 Write / Edit / Bash 默认需要
  permission prompt（无 TTY 时直接失败），加上这个 flag 才会让 `/init` 真正能落盘。
  这是 `-p` 模式推荐的标准做法（`claude --help` 明确推荐 sandbox 内用）。
- **`< /dev/null`** — 后台 + 输出重定向时 stdin 不是 TTY，claude 会报
  "Warning: no stdin data received in 3s" 然后退出 0 不写文件。显式喂空 stdin 解决。
- **`--allowedTools "Write,..."`** — 显式列出 /init 需要的工具子集，避免依赖默认 allowlist。

**超时：** 180s（`/init` 对小项目 < 30s，大仓库很少超过 2 分钟）。

**回退策略：** 如果 `claude` CLI 没装、`/init` 退出非零、超时、
或产物太小 / 仍含占位文本，则回退到带明显占位说明的 heredoc，
并在文件里告诉用户如何手动重跑 `claude /init` 覆盖。

**手动重跑覆盖（任何时候）：**

```bash
claude --bare --dangerously-skip-permissions \
  --allowedTools "Write,Read,Glob,Grep,Bash(ls:*),Bash(find:*),Bash(cat:*),Bash(wc:*)" \
  -p "/init" < /dev/null
# 然后再跑一次 setup-project.sh 让 Plan 镜像规则被补上：
bash scripts/setup-project.sh "$TARGET"
```

### 📋 Plan 文件镜像规则（自动注入）

harness 默认把 plan 写到全局 `~/.claude/plans/<session>.md`（**不在项目内**，git 无法追踪）。即使项目级 `settings.local.json` 配置了 `plansDirectory`，**当前 Claude Code 版本不读取该字段**（已实测：cc-switch 项目的 `.claude/plans/` 为空，而 `~/.claude/plans/` 有 13 个文件）。

因此 setup-project.sh 会在 `CLAUDE.md`、`AGENTS.md`、`.codex/AGENTS.md` 三个文件末尾**自动注入 Plan 镜像规则**，告诉 Agent：

1. 从 plan mode system message 拿到 plan 的 `file_path`（绝对路径）
2. `mkdir -p .claude/plans`
3. `cp <file_path> .claude/plans/$(basename <file_path>)`
4. 在副本末尾追加 `<!-- mirror source: <file_path> -->`
5. **完成上述 4 步之后再调用 ExitPlanMode**

**何时自动注入：**

| 场景 | 行为 |
|------|------|
| 文件不存在 | `[NEW]` 创建并嵌入完整 Plan 镜像规则 |
| 文件已包含 Plan 镜像规则 | `[KEEP]` 原样保留 |
| 文件存在但**缺少** Plan 镜像规则 | `[KEEP]` 主体内容 + 追加镜像规则（如 `/init` 创建的 CLAUDE.md） |

`settings.local.json` 里的 `plansDirectory` 字段保留，作为 forward-compat 字段，等未来 harness 支持时自动生效。

### 已有项目迁移（手动工具）

`setup-project.sh` 已经会在 `[KEEP]` 分支自动追加 Plan 镜像规则，覆盖绝大多数迁移场景。仅在以下情况手动运行 `inject-plan-mirror.sh`：

- **批量迁移**：用 `--recursive` 扫描一棵目录树（含 `.claude/` 的子目录全部处理）
- **预览**：用 `--dry-run` 看会改哪些文件，不实际写盘
- **CI / 定时任务**：在 setup-project.sh 之外的钩子里调用

```bash
# 单项目
bash scripts/inject-plan-mirror.sh /path/to/project

# 预览
bash scripts/inject-plan-mirror.sh --dry-run /path/to/project

# 递归扫描
bash scripts/inject-plan-mirror.sh --recursive /path/to/codebase
```

规则块文本与注入函数从 `scripts/plan-mirror-rules.sh` 复用 —— setup-project.sh 和 inject-plan-mirror.sh 共用同一份逻辑，新老项目拿到的规则永远一致。

### 默认 settings.local.json 权限

初始化会创建一个宽松但安全的默认权限配置，允许常见的开发工具链命令：

- 包管理器：npm, npx, yarn, pnpm, bun, pip, pip3
- 编程语言运行时：node, python, go, cargo, javac, swift
- 构建工具：xcodebuild, make, cmake, mvn, gradle
- 版本控制：git
- 文件操作：ls, cat, find, grep, mkdir, curl
- 文件读写：Read, Edit, Write
- 网络：WebFetch, WebSearch
- CodeGraph：codegraph 命令

用户可以在初始化后根据需要调整权限。

### CodeGraph 集成

技能会自动检测 CodeGraph CLI 是否已安装：
- **已安装** → 自动运行 `codegraph init` 创建 `.codegraph/` 索引
- **未安装** → 给出安装提示，初始化其他内容照常进行

## 脚本说明

| 脚本 | 用途 | 退出码 |
|------|------|--------|
| `scripts/auto-init.sh` | Hook 入口，协调检测和初始化 | 0=完成/已初始化, 1=非代码项目, 2=错误 |
| `scripts/detect-code-project.sh` | 检测目录是否是编程项目 | 0=是, 1=否 |
| `scripts/setup-project.sh` | 执行完整的项目初始化 | 0=成功, 1=失败 |
| `scripts/teardown-project.sh` | 反向操作：清理 setup 创建的所有产物 | 0=清理完成, 1=无产物/部分失败, 2=用户中止 |
| `scripts/inject-plan-mirror.sh` | 批量迁移工具：把 Plan 镜像规则追加到已有项目的 `CLAUDE.md`/`AGENTS.md` 末尾 | 0=全部成功, 1=部分失败, 2=参数错误 |
| `scripts/plan-mirror-rules.sh` | **共享 lib**：Plan 镜像规则块 + `pmr_inject` 函数（被 setup / inject 共同 source） | 不可直接执行 |

## 判断「编程项目」的标准

检测脚本使用宽松策略，以下任一条件满足即判定为编程项目：

1. **包管理标记文件**（优先级最高）
   - Node.js: `package.json`
   - iOS/Swift: `Podfile`, `Package.swift`, `*.xcodeproj`, `*.xcworkspace`
   - Rust: `Cargo.toml`
   - Go: `go.mod`
   - Python: `setup.py`, `pyproject.toml`, `requirements.txt`, `Pipfile`
   - Ruby: `Gemfile`
   - Java/Kotlin: `pom.xml`, `build.gradle`, `build.gradle.kts`
   - C/C++: `CMakeLists.txt`, `Makefile`
   - 等等...

2. **源代码文件数量**（≥ 5 个，或占总文件数 ≥ 5%）
   - 排除 `node_modules/`, `Pods/`, `vendor/`, `dist/`, `build/` 等依赖/构建目录

3. **`.git` 目录包含代码历史**

## 非编程项目行为

当检测到非编程项目时，技能会：
1. 创建 `CLAUDE.md` 和 `AGENTS.md` 包含友好提示
2. 提示用户切换到正确的代码项目目录
3. 不会阻止其他类型的使用（如文档编辑、数据分析等）

用户可以手动覆盖：`touch .claude/.init-done`

## 使用 codegraph 初始化

当用户想要为特定项目重新初始化 CodeGraph 时：

```bash
# 检测并初始化
bash scripts/detect-code-project.sh && bash scripts/setup-project.sh

# 仅重新初始化 CodeGraph
codegraph init

# 查看 CodeGraph 状态
codegraph status
```

## 卸载 / 清理（teardown）

`teardown-project.sh` 是 `setup-project.sh` 的对偶脚本：移除 project-init 在项目中创建的所有产物，让目录回到 setup 之前的状态。

**清理范围：**

- `.claude/` 整个目录（包含 `settings.local.json`、`progress/`、`plans/`、`skills/`、`rules/`、`commands/`、`.init-done` 等）
- `.codex/` 整个目录
- `.codegraph/` 整个目录（已尝试 `codegraph clean`）
- 根目录 `CLAUDE.md` / `AGENTS.md` —— **仅当**内容匹配 project-init 模板指纹（包含 `This file provides working guidance…` + `## Plan 文件镜像` 等独有片段）；用户改过的版本会保留并提示
- `.gitignore` —— 精确剥离 `# project-init generated local agent files` 块；如果整文件都是 setup 创建的，直接删除整文件
- `.claude/settings.local.json` —— **默认保留**（合并了用户权限），加 `--purge-config` 才会在指纹匹配时删除

**使用示例：**

```bash
# 交互式（默认会逐项确认）
bash scripts/teardown-project.sh

# 跳过所有确认
bash scripts/teardown-project.sh --yes

# 仅审计，不实际删除
bash scripts/teardown-project.sh --dry-run

# 保留根 CLAUDE.md / AGENTS.md / settings.local.json
bash scripts/teardown-project.sh --keep-config

# 删除前先打包备份到项目根
bash scripts/teardown-project.sh --backup --yes
```

**安全策略：**

- 默认对每个可能被用户改过的文件做指纹识别，不匹配就跳过
- `--yes` 才删除无指纹的"用户内容"文件，且会单独打印 ⚠ 警告
- `--dry-run` 始终安全，只打印审计结果
- 退出码 2 表示用户中止了 prompt

## ⚠️ 增量原则（Additive-Only）

初始化脚本遵循**只增不删、只补不改**的原则：

- **已有文件 → 保留不动**。如果 `CLAUDE.md`、`AGENTS.md`、`PROGRESS.md` 等已存在，**绝不覆盖**
- **已有 settings.local.json → 智能合并**。只添加缺失的推荐权限和 `plansDirectory` 设置，已有的权限和配置**完全保留**
- **已有 .codegraph/ → 跳过**。不重复索引
- **已有目录 → 保留不动**。`mkdir -p` 对已有目录无副作用
- **只在缺少时才创建**。审计阶段会扫描所有项，报告中会明确标出 `[KEEP]` 保留的和 `[NEW]` 新建的

重复运行 `setup-project.sh` 是安全的，不会损坏任何已有内容。

## 注意事项

- 此技能是**用户级技能**，存放在 `~/.claude/skills/project-init/`
- 自动触发依赖 `SessionStart` hook 配置（在 `settings.local.json` 中）
- 初始化标记文件 `.claude/.init-done` 确保每个项目只初始化一次
- CodeGraph 安装失败不会阻塞其他初始化步骤
- 所有生成的模板文件都包含 `<!-- TODO -->` 标记，需要用户完善
