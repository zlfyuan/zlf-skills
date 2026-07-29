# /z-push — 推送到远端（不做 commit）

把当前分支推送到 `origin` 对应的远端分支。如果上游还没设置，自动 `git push --set-upstream origin <branch>`。

## 执行步骤

1. **前置校验**
   - `git rev-parse --is-inside-work-tree`：不是 git 仓库则提示并退出。
   - `git status --porcelain`：若有未提交改动，立即提示"本地有未提交改动，先跑 `/z-commit` 或手动提交"并退出。
   - `git rev-parse --abbrev-ref HEAD`：拿到当前分支名。

2. **发现远端**
   - `git remote -v`：若没配 `origin`，提示用户先 `git remote add origin <url>` 并退出。
   - `git config --get-regexp '^branch\.'`：检查当前分支是否已有上游配置。

3. **预览 + 确认**
   - 打印：
     ```
     ── 计划推送 ─────────────────────────────
     分支: <branch>
     目标: <remote>/<branch>
     提交数量: N  (git rev-list --count @{u}..HEAD)
     上游状态: 已设置 / 首次推送
     ─────────────────────────────────
     ```
   - 用 `read -r -p "Continue? [y/N] "` 让用户回车确认。

4. **执行推送**
   - 已有上游：`git push origin <branch>`
   - 没有上游：`git push --set-upstream origin <branch>`（告诉用户这是首次推送，建立 tracking）
   - 远端拒绝（例如 non-fast-forward）→ 打印提示而非强推：**永远不要 `--force`**，告诉用户先 `git pull --rebase` 或 `git fetch && git merge`。

5. **结果汇报**
   - 成功后打印 `git log -1 --oneline` 加一句 `✓ 已推送到 origin/<branch>`。
   - 失败时把远端 stderr 完整保留，并提示常见修复路径。

## 不要做的事

- **不要 commit**：`/z-push` 只 push。`/z-commit` 单独做。
- **不要 force push**：`--force` / `--force-with-lease` 都不会自动加；用户明示才能用。
- **不要 push 多个分支**：只动当前分支。
- **不要改 user.email / user.name**：若 git 提示"please tell me who you are"，让用户自己配置。

## 示例

用户：`/z-push`

agent 输出：

```
── 计划推送 ─────────────────────────────
分支: feat/add-z-commands
目标: origin/feat/add-z-commands
提交数量: 3
上游状态: 已设置
─────────────────────────────────
Continue? [y/N]
```
