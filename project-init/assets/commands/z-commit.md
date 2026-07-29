# /z-commit — 提交代码（不走 push）

把当前 working tree 的改动提交到本地 git。不做 push —— push 用 `/z-push` 单独做。

## 执行步骤

1. **前置校验**
   - `git rev-parse --is-inside-work-tree`：确认在 git 仓库里；否则直接提示"当前目录不是 git 仓库"。
   - `git status --short`：扫一下改动范围。无任何输出时直接告知"无需要提交的改动"并退出。
   - `git log -1 --oneline`：在 commit message 开头可以 hint 上次提交，方便续写。

2. **生成 commit message**
   - 读取 `git diff --stat` 和 `git diff --name-status`，按改动文件类型（feat / fix / chore / docs / refactor / test 等 Conventional Commits 风格）自动分类。
   - 中文标题，prefix 一栏（`<type>: <中文简述>`）；超过 72 字符则换行写 body。
   - body 列出要点（哪些文件、为什么改），但不要照搬整段 diff。

3. **预览 + 确认**
   - 打印一段预览：
     ```
     ── 计划提交 ─────────────────────────────
     分支: <current branch>
     文件:
       M  src/foo.py
       A  src/bar.py
     Commit message:
       ─────────────────────────────────
       feat: 添加 XX 功能

       - 新增 src/bar.py
       - 修改 src/foo.py 配合 XX 逻辑
       ─────────────────────────────────
     ```
   - 用 `read -r -p "Continue? [y/N] "` 让用户回车确认。`y`/`Y`/`yes` 之外全部 abort。

4. **执行提交**
   - `git add -A`（用户已同意则把未跟踪文件也带上）
   - `git commit -m "<message>"`（多行 message 用 heredoc 传入 `git commit -F -`）

5. **结果汇报**
   - 打印 `git log -1 --stat` 的输出，再总结一句"✓ 已提交 <short SHA>"。

## 不要做的事

- **不要 push**：`/z-commit` 不动远端。push 用 `/z-push`。
- **不要 amend**：`--amend` 容易改写别处的提交，需要的时候用户自己说。
- **不要跳过确认**：即使 message 看起来简单，确认步骤不能省，避免误提。

## 示例

用户：`/z-commit`

agent 输出：

```
── 计划提交 ─────────────────────────────
分支: feat/add-z-commands
文件:
  M  project-init/SKILL.md
  +  project-init/assets/commands/z-commit.md
  +  project-init/assets/commands/z-push.md
  +  project-init/assets/commands/z-commit-push.md
Commit message:
  ─────────────────────────────────
  feat(project-init): 添加 /z-commit /z-push /z-commit-push 三个斜杠命令

  - 新增 assets/commands/ 下三份命令模板
  - SKILL.md 目录结构更新为软连接布局
  ─────────────────────────────────
Continue? [y/N]
```
