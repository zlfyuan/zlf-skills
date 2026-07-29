# /z-commit-push — 一次性提交并推送

把 `/z-commit` + `/z-push` 合二为一：先按 `/z-commit` 的规则生成 message、确认、提交，再直接推送到上游。

## 执行步骤

1. **本地工作区检查**
   - 不是 git 仓库 → 退出。
   - **先检查未推送的 commit**（`git log @{u}..HEAD` 不为空）→ 跳过 commit，直接提示"已有 N 个本地提交待推送，是否继续推送？"，让用户二选一：
     - 答 y → 只 push
     - 答 no → 退出
   - 没有未推送 commit 且 `git status --short` 为空 → 告知"无需要提交的改动"并退出。

2. **生成 commit message + 预览**
   - 与 `/z-commit` 同一套：看 `git diff --stat` + `git diff --name-status`，自动写 Conventional Commits 风格的中文 message。
   - 预览块同时显示计划 commit 摘要 + push 目标 + 待推提交数 = 0。

3. **统一确认**
   - 把 commit、push 两条行动合在一段打印：
     ```
     ── 计划 ─────────────────────────────
     分支: <branch>
     目标: origin/<branch>
     提交消息:
       feat(<scope>): <中文简述>

       <要点>
     上游状态: 已设置 / 首次推送（会 --set-upstream）
     ─────────────────────────────────
     ```
   - 用 `read -r -p "Continue? [y/N] "` 回车确认。

4. **执行**
   - 已有上游：`git add -A && git commit -F - < message && git push origin <branch>`
   - 没有上游：最后一步用 `git push --set-upstream origin <branch>`

5. **结果汇报**
   - 成功：`git log -1 --stat` + `✓ 已提交并推送 <short SHA> 到 origin/<branch>`。
   - commit 成功但 push 失败：保留 commit，告知本地已经成功 commit，单独运行 `/z-push` 重试 + 给出远端 stderr 摘要。

## 不要做的事

- **不要 force push**：失败就停下，让用户决定。
- **不要 add 半个仓库**：默认 `git add -A`；若用户有需要精确选择的文件，请走 `/z-commit` + 手动 add。
- **不要在 commit 里嵌 `:wq`、`Signed-off-by` 等额外标记**：除非用户显式要求。

## 示例

用户：`/z-commit-push`

agent 输出：

```
── 计划 ─────────────────────────────
分支: feat/add-z-commands
目标: origin/feat/add-z-commands
提交消息:
  feat(project-init): 添加 /z-commit /z-push /z-commit-push 三个斜杠命令

  - 新增 assets/commands/ 下三份命令模板
  - SKILL.md 目录结构更新为软连接布局
上游状态: 已设置
─────────────────────────────────
Continue? [y/N]
```
