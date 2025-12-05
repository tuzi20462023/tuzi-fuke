# Git 完整知识总结

> 创建日期：2025-12-03
> 项目：tuzi-fuke（地球新主——兔子）
> 基于实际开发经验整理

---

## 一、Git 核心概念

### 1.1 仓库结构

```
📁 tuzi-fuke/                    ← 工作目录（你看到的文件）
    ├── 📁 .git/                 ← Git 仓库（隐藏目录，存储所有历史）
    │       ├── objects/         ← 所有文件的历史版本（压缩存储）
    │       ├── refs/            ← 分支和标签指针
    │       ├── HEAD             ← 当前所在分支
    │       └── config           ← 仓库配置
    │
    ├── 📁 tuzi-fuke/            ← 源代码目录
    ├── 📄 README.md
    └── ...
```

### 1.2 三个区域

```
┌─────────────────┐    git add    ┌─────────────────┐   git commit   ┌─────────────────┐
│   工作目录       │ ───────────► │   暂存区         │ ─────────────► │   仓库          │
│  Working Dir    │              │  Staging Area   │               │  Repository     │
│                 │              │                 │               │                 │
│  你编辑的文件    │              │  准备提交的文件   │               │  已保存的历史    │
└─────────────────┘              └─────────────────┘               └─────────────────┘
        │                                                                   │
        │◄──────────────────── git checkout ────────────────────────────────┘
```

---

## 二、Worktree 深度解析

### 2.1 为什么 Worktree 省空间？

**普通复制 vs Worktree：**

```
【普通复制】                              【Worktree】

tuzi-fuke/          85M                  tuzi-fuke/          85M (主仓库)
    └── .git/       80M                      └── .git/       80M (共享！)
    └── 源代码       5M                       └── 源代码       5M

tuzi-fuke-copy/     85M                  tuzi-fuke-explore/   748K
    └── .git/       80M (重复!)              └── .git (链接)   几KB
    └── 源代码       5M                       └── 源代码        748K

总计：170M                                总计：~86M
```

**关键点：**
- `.git` 目录存储所有历史，占用 80-90% 空间
- Worktree 共享主仓库的 `.git`，只创建源代码副本
- 节省空间 = 不重复存储 Git 历史

### 2.2 实际空间占用

```bash
# 查看各目录大小
du -sh /Users/mikeliu/Desktop/tuzi-fuke           # 85M  (主仓库)
du -sh /Users/mikeliu/Desktop/tuzi-fuke-building  # 1.3M (worktree)
du -sh /Users/mikeliu/Desktop/tuzi-fuke-explore   # 748K (worktree)
```

### 2.3 Worktree 常用命令

```bash
# 查看所有 worktree
git worktree list

# 创建新 worktree（在指定路径检出指定分支）
git worktree add ../tuzi-fuke-新功能 feature/新功能

# 创建新 worktree 并同时创建新分支
git worktree add -b feature/新分支 ../tuzi-fuke-新功能

# 删除 worktree
git worktree remove ../tuzi-fuke-某功能

# 清理无效的 worktree 引用
git worktree prune
```

---

## 三、分支同步与合并

### 3.1 同步远程代码到本地分支

```bash
# 场景：main 分支有新代码，需要同步到 feature/explore

# 方法一：在 explore worktree 中合并 main
cd /Users/mikeliu/Desktop/tuzi-fuke-explore
git fetch origin                    # 获取远程最新
git merge origin/main               # 合并 main 到当前分支

# 方法二：rebase（保持线性历史）
git fetch origin
git rebase origin/main
```

### 3.2 合并分支到 main

```bash
# 场景：feature/explore 开发完成，合并到 main

cd /Users/mikeliu/Desktop/tuzi-fuke  # 切到主仓库
git fetch origin                      # 获取最新
git merge origin/feature/explore      # 合并 explore 分支
git push origin main                  # 推送到远程
```

### 3.3 解决合并冲突

```bash
# 冲突时 Git 会标记文件
<<<<<<< HEAD
这是当前分支的代码
=======
这是要合并进来的代码
>>>>>>> feature/explore

# 解决步骤：
# 1. 编辑文件，保留需要的代码
# 2. 删除冲突标记（<<<<, ====, >>>>）
# 3. git add 冲突文件
# 4. git commit
```

---

## 四、远程仓库操作

### 4.1 基本操作

```bash
# 查看远程仓库
git remote -v

# 获取远程更新（不合并）
git fetch origin

# 获取并合并（= fetch + merge）
git pull origin main

# 推送到远程
git push origin main

# 推送新分支到远程
git push -u origin feature/新分支
```

### 4.2 查看远程分支

```bash
# 查看所有分支（本地 + 远程）
git branch -a

# 输出示例：
* main                           ← 当前分支
  feature/explore                ← 本地分支
  remotes/origin/main            ← 远程分支
  remotes/origin/feature/explore ← 远程分支
```

---

## 五、存储空间管理

### 5.1 占用空间的主要来源

| 来源 | 大小 | 说明 |
|------|------|------|
| `.git` 目录 | 80M+ | Git 历史，压缩存储 |
| Xcode DerivedData | 几百M~几G | 构建缓存，可清理 |
| node_modules | 几百M | 依赖包，可重建 |
| Pods | 几十M~几百M | CocoaPods 依赖 |

### 5.2 清理命令

```bash
# 清理 Xcode 构建缓存（最有效！）
rm -rf ~/Library/Developer/Xcode/DerivedData/tuzi-fuke-*

# 清理 Git 垃圾（压缩历史）
git gc --aggressive

# 查看 Git 仓库大小
du -sh .git

# 查看大文件
git rev-list --objects --all | \
  git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' | \
  sed -n 's/^blob //p' | \
  sort -rnk2 | head -10
```

### 5.3 我的项目实际占用

```
tuzi-fuke (主仓库)           85M   ← 包含 .git 历史
tuzi-fuke-building          1.3M  ← worktree，只有源码
tuzi-fuke-explore           748K  ← worktree，只有源码
Xcode DerivedData           1.2G  ← 构建缓存（可清理）
─────────────────────────────────
总计约：1.4G（清理后约 87M）
```

---

## 六、Git 状态查看

### 6.1 常用查看命令

```bash
# 查看当前状态
git status

# 查看当前分支
git branch --show-current

# 查看提交历史
git log --oneline -10

# 查看图形化历史
git log --oneline --graph --all

# 查看某文件的修改历史
git log --oneline -- 文件路径

# 查看两个分支的差异
git diff main..feature/explore
```

### 6.2 理解 git status 输出

```
On branch feature/explore              ← 当前分支
Your branch is up to date with 'origin/feature/explore'  ← 与远程同步

Changes to be committed:               ← 已暂存，等待提交
  (use "git restore --staged <file>..." to unstage)
        modified:   SomeFile.swift

Changes not staged for commit:         ← 已修改，未暂存
  (use "git add <file>..." to update what will be committed)
        modified:   AnotherFile.swift

Untracked files:                       ← 新文件，未跟踪
  (use "git add <file>..." to include in what will be committed)
        NewFile.swift
```

---

## 七、常见问题与解决

### 7.1 合并时文件冲突

```bash
# 问题：Your local changes would be overwritten by merge
# 原因：本地有未提交的修改

# 解决方法一：先提交
git add -A && git commit -m "保存当前修改"
git merge origin/main

# 解决方法二：先暂存
git stash
git merge origin/main
git stash pop

# 解决方法三：放弃本地修改（慎用！）
git checkout -- 文件名
git merge origin/main
```

### 7.2 不小心在错误分支开发

```bash
# 场景：在 main 分支开发了，应该在 feature 分支

# 方法一：创建新分支保存修改
git stash                              # 暂存修改
git checkout -b feature/新功能          # 创建并切换分支
git stash pop                          # 恢复修改

# 方法二：直接切换（如果没有冲突）
git checkout feature/新功能
```

### 7.3 撤销操作

```bash
# 撤销工作目录的修改（未暂存）
git checkout -- 文件名

# 撤销暂存（已 add 但未 commit）
git restore --staged 文件名

# 撤销最近一次提交（保留修改）
git reset --soft HEAD~1

# 撤销最近一次提交（丢弃修改，慎用！）
git reset --hard HEAD~1
```

---

## 八、最佳实践

### 8.1 分支命名规范

```
feature/功能名     ← 新功能开发
bugfix/问题描述    ← 修复 bug
hotfix/紧急修复    ← 生产环境紧急修复
release/v1.0.0    ← 发布版本
```

### 8.2 提交信息规范

```
feat: 添加用户登录功能          ← 新功能
fix: 修复登录按钮点击无响应      ← 修复 bug
docs: 更新 README              ← 文档修改
refactor: 重构用户模块         ← 重构代码
chore: 更新依赖版本            ← 杂项维护
```

### 8.3 Worktree 工作流程

```bash
# 1. 在对应 worktree 目录开发
cd /Users/mikeliu/Desktop/tuzi-fuke-explore

# 2. 开发前先同步 main 最新代码
git fetch origin
git merge origin/main

# 3. 开发、测试、提交
git add -A
git commit -m "feat: 添加探索功能"
git push origin feature/explore

# 4. 开发完成后，切到主仓库合并
cd /Users/mikeliu/Desktop/tuzi-fuke
git merge origin/feature/explore
git push origin main
```

---

## 九、给 AI 的提示词模板

### 开始新功能开发

```
我在 /Users/mikeliu/Desktop/tuzi-fuke-explore 目录，对应 feature/explore 分支。

请先同步 main 最新代码：
git fetch origin
git merge origin/main

然后继续开发 [功能名称]。
```

### 合并到 main

```
我在 /Users/mikeliu/Desktop/tuzi-fuke 目录，对应 main 分支。

请帮我合并 feature/explore 分支到 main：
1. git fetch origin
2. git merge origin/feature/explore
3. 解决冲突（如果有）
4. git push origin main
```

### 检查项目状态

```
请检查以下内容：
1. 当前分支：git branch --show-current
2. 工作目录状态：git status
3. 与远程的差异：git log origin/main..HEAD --oneline
4. 存储空间占用：du -sh .git 和 Xcode DerivedData
```

---

## 十、速查表

### 日常操作

| 操作 | 命令 |
|------|------|
| 查看状态 | `git status` |
| 查看分支 | `git branch -a` |
| 切换分支 | `git checkout 分支名` |
| 创建分支 | `git checkout -b 新分支名` |
| 暂存修改 | `git add -A` |
| 提交 | `git commit -m "信息"` |
| 推送 | `git push origin 分支名` |
| 拉取 | `git pull origin 分支名` |
| 合并 | `git merge 分支名` |

### Worktree 操作

| 操作 | 命令 |
|------|------|
| 查看 worktree | `git worktree list` |
| 创建 worktree | `git worktree add 路径 分支名` |
| 删除 worktree | `git worktree remove 路径` |
| 清理无效 | `git worktree prune` |

### 清理操作

| 操作 | 命令 |
|------|------|
| 清理 Xcode 缓存 | `rm -rf ~/Library/Developer/Xcode/DerivedData/项目名-*` |
| 压缩 Git 历史 | `git gc --aggressive` |
| 查看目录大小 | `du -sh 目录` |

---

*文档创建于 2025-12-03，基于 tuzi-fuke 项目开发经验整理*
