---
name: bash2zsh
description: 将用户环境从 Bash 迁移到 Zsh with Oh-My-Zsh，包括安装配置、插件优化、补全设置、nerdctl 支持等。当用户提到安装 zsh、迁移 bashrc、配置 oh-my-zsh、zsh 插件、nerdctl 补全时使用。
---

# Bash to Zsh 迁移助手

## 工作流程

### Step 1: 检查当前环境

```bash
# 检查 zsh 是否已安装
which zsh && zsh --version

# 检查 oh-my-zsh 是否已安装
ls ~/.oh-my-zsh 2>/dev/null && echo "已安装" || echo "未安装"
```

### Step 2: 安装 Oh-My-Zsh（如未安装）

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
```

### Step 3: 询问用户迁移配置

**询问用户是否迁移现有 .bashrc 配置**，包括：
- Go 环境变量 (GOROOT, GOPATH, GOMODCACHE)
- PATH 配置
- 常用别名
- Claude Code / API 配置
- Containerd / kubectl / nerdctl 配置

**示例交互**：
```
是否迁移以下配置？
- Go 环境变量: GOROOT, GOPATH
- PATH: /home/hurl, /home/zarf-dir, /root/buildkit 等
- 别名: ll, la, l, vi, kge, ctr, nerdctl
- API 配置: ANTHROPIC_*, DeepSeek 模型
```

### Step 4: 配置插件

**推荐插件**：
```zsh
plugins=(git docker kubectl golang ansible archlinux)
```

**不建议使用的插件**（名称错误）：
- ❌ `k8s` → 应使用 `kubectl`
- ❌ `go` → 应使用 `golang`

### Step 5: 第三方工具补全配置

#### 通用检测流程

对于**非 oh-my-zsh 内置**的工具（如 nerdctl、helm、flux 等），按以下流程处理：

```bash
# 1. 检测工具是否已安装
which <tool> && <tool> version

# 2. 如果已安装，询问用户是否配置 zsh 补全
# 3. 如果用户同意，检查是否支持 zsh 补全
<tool> completion zsh > /dev/null 2>&1 && echo "支持" || echo "不支持"
# 4. 配置补全和别名
```

#### 常用第三方工具补全

| 工具 | 安装状态检测 | 补全命令 |
|------|-------------|---------|
| nerdctl | `which nerdctl` | `nerdctl completion zsh` |
| helm | `which helm` | `helm completion zsh` |
| flux | `which flux` | `flux completion zsh` |
| kustomize | `which kustomize` | `kustomize completion zsh` |
| istio | `which istioctl` | `istioctlx crab completion zsh` |
| argocd | `which argocd` | `argocd completion zsh` |

#### 交互示例

```
检测到以下工具已安装：
- nerdctl v2.0.0-beta.5
- helm v3.x
- kubectl v1.28

是否需要为以下工具配置 zsh 补全？
[1] nerdctl - 容器管理 (推荐)
[2] helm - Helm 图表
[3] 全选
[4] 跳过
```

### Step 6: 高级配置（可选）

#### 禁用补全询问提示
```zsh
# 添加到 ~/.zshrc 在 source $ZSH/oh-my-zsh.sh 之后
setopt MENU_COMPLETE
zstyle ':completion:*' verbose no
```

#### 常用插件说明

| 插件 | 功能 |
|------|------|
| git | 提供 gst, gc, gp 等别名 |
| docker | 提供 dps, di 等别名 |
| kubectl | kubectl 命令补全 |
| golang | go 命令补全 |
| ansible | ansible-* 命令补全 |
| archlinux | pacman 补全 |

### Step 7: 设置默认 Shell

```bash
# 系统默认 shell
chsh -s /bin/zsh

# VSCode 终端默认使用 zsh
# 在 ~/.config/Code/User/settings.json 或 /root/.vscode-server/data/Machine/settings.json 中添加：
"terminal.integrated.defaultProfile.linux": "zsh"
```

### Step 8: 验证配置

```bash
source ~/.zshrc

# 验证别名
which gst  # 应输出: gst: aliased to git status

# 验证 nerdctl 补全
nerdctl <Tab>  # 应显示 nerdctl 子命令补全

# 验证插件
echo $plugins
```

## 迁移检查清单

执行迁移时，逐项与用户确认：

```
迁移检查清单：
- [ ] 是否安装 oh-my-zsh
- [ ] 是否备份原有 .zshrc
- [ ] 是否迁移 .bashrc 环境变量
- [ ] 是否配置推荐插件
- [ ] 是否检测第三方工具 (nerdctl/helm/flux 等)
- [ ] 是否配置第三方工具补全
- [ ] 是否添加第三方工具别名
- [ ] 是否设置补全优化
- [ ] 是否设置默认 shell
- [ ] 是否配置 VSCode
```

## 不迁移的配置

以下内容通常**不需要迁移**到 zsh：
- Bash 特定语法（如 `[[ ]]` 可保留但 zsh 不需要）
- `~/.bash_aliases`（应直接合并到 .zshrc）
- Bash 完成脚本（oh-my-zsh 已有更好的补全）
