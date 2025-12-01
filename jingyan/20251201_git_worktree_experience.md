# Git Worktree 并行开发经验总结

**日期**: 2025年12月1日
**项目**: tuzi-fuke (地球新主复刻版)

---

## 背景

在开发 iOS 圈地游戏时，遇到需要**并行开发多个功能**的场景：

- 圈地功能（需要深入优化）
- 通信功能（独立开发）

如果用普通分支切换，每次切换都要 stash/commit，不能同时开两个窗口开发。

---

## 为什么选择 Worktree 方案

| 方案             | 优点            | 缺点               |
| -------------- | ------------- | ---------------- |
| **普通分支**       | 简单，一个目录       | 切换分支要 stash，不能并行 |
| **克隆多份仓库**     | 独立            | 浪费空间，同步麻烦        |
| **Worktree** ✅ | 共享 .git，可并行开发 | 初始设置稍复杂          |

**Worktree 优势**：

1. 两个目录共享同一个 Git 仓库
2. 可以同时开两个 Claude Code 窗口并行开发
3. 各分支互不干扰
4. 完成后 PR 合并回 main

---

## 实施步骤

### 1. 准备工作

```bash
# 确保当前代码已提交
git add .
git commit -m "完成圈地核心功能"
```

### 2. 创建 GitHub 仓库（使用 GitHub MCP）

MCP 工具可以直接创建仓库：

```
mcp__github__create_repository
- name: tuzi-fuke
- description: 地球新主复刻版 - iOS圈地游戏
- private: false
```

### 3. 配置 Git Remote

```bash
# 添加远程仓库（推荐用 SSH 方式）
git remote add origin git@github.com:tuzi20462023/tuzi-fuke.git

# 推送 main 分支
git push -u origin main
```

**注意**：如果用 HTTPS 方式报 403 错误，改用 SSH：

```bash
git remote set-url origin git@github.com:用户名/仓库名.git
```

### 4. 创建 Worktree

```bash
# 创建圈地功能分支的 worktree
git worktree add -b feature/claiming ~/Desktop/tuzi-fuke-claiming

# 创建通信功能分支的 worktree
git worktree add -b feature/communication ~/Desktop/tuzi-fuke-communication

# 查看所有 worktree
git worktree list
```

### 5. 推送分支到 GitHub

```bash
# 在各自目录推送
cd ~/Desktop/tuzi-fuke-claiming
git push -u origin feature/claiming

cd ~/Desktop/tuzi-fuke-communication
git push -u origin feature/communication
```

---

## 最终目录结构

```
~/Desktop/
├── tuzi-fuke/                    # main 分支（稳定版基准）
├── tuzi-fuke-claiming/           # feature/claiming 分支（圈地功能）
└── tuzi-fuke-communication/      # feature/communication 分支（通信功能）
```

---

## 日常开发工作流

### 开发时

```bash
# 窗口1：开发圈地
cd ~/Desktop/tuzi-fuke-claiming
# 用 Claude Code 开发...

# 窗口2：开发通信
cd ~/Desktop/tuzi-fuke-communication
# 用 Claude Code 开发...
```

### 提交代码

```bash
# 在各自目录
git add .
git commit -m "功能描述"
git push
```

### 合并到 main

1. 在 GitHub 上创建 Pull Request
2. 代码审查
3. 合并 PR
4. 本地更新 main：
   
   ```bash
   cd ~/Desktop/tuzi-fuke
   git pull
   ```

---

## 关于项目文档目录

项目中的文档目录：

- `jingyan/` - 开发经验记录（如本文档）
- `jiaoxue/` - 教学文档
- `guihua/` - 规划文档

**这些文档跟代码一起提交是好习惯**，方便：

- 以后查阅踩坑经验
- 团队成员学习
- 记录决策原因

---

## 常用命令速查

```bash
# 查看所有 worktree
git worktree list

# 删除 worktree
git worktree remove ~/Desktop/tuzi-fuke-claiming

# 查看分支
git branch -a

# 切换分支（普通方式，worktree 不需要）
git checkout 分支名
```

---

## 遇到的问题

### 问题1：HTTPS 推送 403 错误

**原因**：GitHub Token 权限问题
**解决**：改用 SSH 方式

```bash
git remote set-url origin git@github.com:用户名/仓库名.git
```

### 问题2：GitHub 上看不到分支

**原因**：分支只在本地，还没推送
**解决**：推送分支

```bash
git push -u origin 分支名
```

---

## 总结

Worktree 方案非常适合：

- 需要并行开发多个功能
- 想同时开多个 IDE/编辑器窗口
- 不想频繁切换分支

一句话：**一个仓库，多个目录，各自独立开发**。
