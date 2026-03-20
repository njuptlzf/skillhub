---
name: bash2zsh
description: Migrates user environment from Bash to Zsh with Oh-My-Zsh, including installation, plugin optimization, completion setup, and nerdctl support. Use when user mentions installing zsh, migrating bashrc, configuring oh-my-zsh, zsh plugins, or nerdctl completion.
---

# Bash to Zsh Migration Assistant

## Core Principle

**Separate system default configurations from user customizations**:
- `.zshrc` keeps only oh-my-zsh default template content
- **All custom configurations** (including commented ones) are migrated to `~/.zshrc.custom` appended at the end
- Avoids user config being overwritten during oh-my-zsh upgrades

## Workflow

### Step 1: Check Current Environment

```bash
# Check if zsh is installed
which zsh && zsh --version

# Check if oh-my-zsh is installed
ls ~/.oh-my-zsh 2>/dev/null && echo "Installed" || echo "Not installed"

# Compare current .zshrc with oh-my-zsh template to find customizations
diff <(curl -s https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/templates/zshrc.zsh-template) ~/.zshrc
```

### Step 2: Analyze Current Customizations

**Content types that MUST be migrated**:

| Type | Examples | Description |
|------|----------|-------------|
| Environment Variables | `export GOROOT`, `export GOPATH`, `export PATH` | Go environment, third-party bins |
| API Config | `export ANTHROPIC_*`, `export DEEPSEEK_*` | Claude Code config |
| Aliases | `alias ll=`, `alias vi=vim`, `alias kge=` | Custom command shortcuts |
| Functions | `swapoff -a`, `nvm loading` | Initialization scripts |
| Completion Config | `fpath=`, `source <(kubectl completion zsh)` | Third-party tool completions |
| Completion Optimization | `setopt MENU_COMPLETE`, `zstyle ':completion:*'` | Zsh interaction optimization |
| Commented Config | `# CASE_SENSITIVE="true"` | User uncommented options |
| Plugin List | `plugins=(git docker kubectl golang)` | Non-default plugins |

**oh-my-zsh default template line reference** (based on oh-my-zsh/templates/zshrc.zsh-template):

| Content | Default Line | Customization Indicator |
|---------|--------------|------------------------|
| ZSH_THEME | 11 | `ZSH_THEME="robbyrussell"` |
| plugins | 73 | `plugins=(git)` ← common modification |
| source $ZSH/oh-my-zsh.sh | 75 | Template fixed position |
| User configuration comment | 77 | Comment marks start of user zone |

### Step 3: Install Oh-My-Zsh (if not installed)

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
```

### Step 4: Migrate Customizations

#### 4.1 Backup Original Config

```bash
# Backup current .zshrc
cp ~/.zshrc ~/.zshrc.bak.$(date +%Y%m%d%H%M%S)
```

#### 4.2 Generate Clean .zshrc

```bash
# Download official template
curl -s https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/templates/zshrc.zsh-template > ~/.zshrc
```

#### 4.3 Extract and Migrate Custom Config

**Method A: Auto-extract using diff**

```bash
# Extract lines not in template (including comments)
git diff --no-index \
  <(curl -s https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/templates/zshrc.zsh-template) \
  ~/.zshrc.bak.* 2>/dev/null | grep '^\+[^+]' | sed 's/^\+//' >> ~/.zshrc.custom
```

**Method B: Manual Identification**

Append custom config zone to end of `.zshrc`:

```zsh
# ═══════════════════════════════════════════════════════════════════════
# ══ CUSTOM CONFIGURATIONS - Do not edit above this line ══
# ═══════════════════════════════════════════════════════════════════════
# Edit customizations in ~/.zshrc.custom or below this marker

# ---- Plugins ----
plugins=(git docker kubectl golang ansible archlinux)

# ---- nerdctl zsh completion ----
fpath=(~/.zsh/completion $fpath)
autoload -Uz compinit && compinit

# ---- Go Environment Variables ----
export GOROOT=/root/go
export GOPATH=/home/user/go
export PATH=$GOROOT/bin:$GOPATH/bin:$PATH
export GOMODCACHE=$GOPATH/pkg/mod

# ---- Other PATH Configurations ----
export PATH=/root/.local/bin:$PATH
export PATH=/home/zarf-dir:$PATH
export PATH=/home/hurl/hurl-4.3.0-x86_64-unknown-linux-gnu/bin:$PATH
export PATH=/root/buildkit/bin:/home/oras:/home/flux/:$PATH

# ---- Claude Code Environment Variables ----
export ANTHROPIC_MAX_RETRIES=9999999
export ANTHROPIC_BASE_URL='https://api.siliconflow.cn/'
export ANTHROPIC_API_TOKEN='sk-xxx'
export ANTHROPIC_API_KEY='sk-xxx'

# ---- DeepSeek Model Config ----
export ANTHROPIC_MODEL='deepseek-ai/DeepSeek-V3.2'

# ---- Containerd Config ----
export CONTAINERD_ADDRESS="unix:///run/containerd/containerd.sock"

# ---- Alias Settings ----
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias vi=vim
alias kge="kubectl get event --sort-by='.metadata.creationTimestamp'"
alias ctr="ctr --address=/run/k3s/containerd/containerd.sock"
alias nerdctl="nerdctl --address=/run/containerd/containerd.sock"

# ---- kubectl completion ----
source <(kubectl completion zsh)

# ---- Completion Optimization ----
setopt MENU_COMPLETE
zstyle ':completion:*' verbose no

# ---- nerdctl alias config ----
alias nbl='nerdctl build'
alias ncls='nerdctl container ls'
alias nps='nerdctl ps'
# ... other nerdctl aliases

# ═══════════════════════════════════════════════════════════════════════
# ══ END OF CUSTOM CONFIGURATIONS ══
# ═══════════════════════════════════════════════════════════════════════
```

### Step 5: Ask User About Configuration Migration

**Must ask user which configurations to migrate**:

```
Detected the following custom configurations. Migrate?

[1] Go environment variables: GOROOT, GOPATH, GOMODCACHE (Recommended)
[2] Third-party PATH: /root/buildkit, /home/oras, /home/flux
[3] Claude Code API: ANTHROPIC_*, DeepSeek models
[4] nerdctl config: aliases + completion
[5] kubectl completion
[6] Custom aliases: ll, la, l, vi, kge
[7] NVM config
[8] Completion optimization: setopt MENU_COMPLETE
[9] Migrate all
[10] Custom selection
```

### Step 6: Third-Party Tool Completion Configuration

#### General Detection Process

```bash
# 1. Check if tool is installed
which <tool> && <tool> version

# 2. Check if zsh completion is supported
<tool> completion zsh > /dev/null 2>&1 && echo "Supported" || echo "Not supported"

# 3. Generate completion and save
<tool> completion zsh > ~/.zsh/completion/_<tool>
```

#### Common Third-Party Tool Completions

| Tool | Installation Check | Completion Command |
|------|-------------------|-------------------|
| nerdctl | `which nerdctl` | `nerdctl completion zsh` |
| helm | `which helm` | `helm completion zsh` |
| flux | `which flux` | `flux completion zsh` |
| kustomize | `which kustomize` | `kustomize completion zsh` |
| istio | `which istioctl` | `istioctl completion zsh` |
| argocd | `which argocd` | `argocd completion zsh` |

### Step 7: Set Default Shell

```bash
# System default shell
chsh -s /bin/zsh

# VSCode terminal default to zsh
# Add to ~/.config/Code/User/settings.json or /root/.vscode-server/data/Machine/settings.json:
"terminal.integrated.defaultProfile.linux": "zsh"
```

### Step 8: Verify Configuration

```bash
# Reload configuration
source ~/.zshrc

# Verify oh-my-zsh loaded
echo $ZSH_VERSION  # Should output: 5.x.x

# Verify plugins
echo $plugins  # Should show configured plugins

# Verify customizations loaded
type ll  # Should show alias definition
type nerdctl  # Should show alias with --address flag

# Verify completion
nerdctl <Tab><Tab>  # Should show nerdctl subcommands
```

## Migration Checklist

```
Migration Checklist:
- [ ] Backup original .zshrc
- [ ] Download clean oh-my-zsh template to .zshrc
- [ ] Extract all custom lines (including commented)
- [ ] Append customizations to .zshrc.custom or bottom of .zshrc
- [ ] Ask user which configurations to migrate
- [ ] Configure plugins (non-default plugins)
- [ ] Configure third-party tool completions
- [ ] Configure tool-specific aliases
- [ ] Configure completion optimization
- [ ] Set default shell (chsh)
- [ ] Configure VSCode terminal
- [ ] Verify all configurations work
```

## Configuration NOT to Migrate

| Type | Reason | Handling |
|------|--------|----------|
| Bash-specific syntax `[[ ]]` | zsh compatible but not needed | Keep in custom zone |
| Bash completion scripts | oh-my-zsh provides better completion | Skip, configure oh-my-zsh completion |
| oh-my-zsh template comments | Already in template | No need to duplicate |

## Customization Zone Template

Copy this template to end of `.zshrc` as custom configuration zone:

```zsh
# ═══════════════════════════════════════════════════════════════════════
# ══ CUSTOM CONFIGURATIONS ══
# All custom configurations should be placed below this line.
# This zone is preserved during oh-my-zsh upgrades.
# ═══════════════════════════════════════════════════════════════════════

# ---- Plugins (Non-default) ----
# oh-my-zsh defaults to plugins=(git), following are custom plugins
plugins=(git docker kubectl golang ansible archlinux)

# ---- Completion Config (Non-oh-my-zsh built-in) ----
# nerdctl zsh completion
fpath=(~/.zsh/completion $fpath)
autoload -Uz compinit && compinit

# kubectl completion
source <(kubectl completion zsh)

# ---- Environment Variables ----
# Go environment
export GOROOT=/root/go
export GOPATH=/home/user/go
export PATH=$GOROOT/bin:$GOPATH/bin:$PATH
export GOMODCACHE=$GOPATH/pkg/mod

# Claude Code API config
export ANTHROPIC_BASE_URL='https://api.siliconflow.cn/'
export ANTHROPIC_API_KEY='sk-xxx'

# ---- Completion Optimization ----
setopt MENU_COMPLETE
zstyle ':completion:*' verbose no

# ---- Aliases ----
# Basic aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias vi=vim

# nerdctl aliases
alias nerdctl="nerdctl --address=/run/containerd/containerd.sock"
alias ncls='nerdctl container ls'
alias nps='nerdctl ps'
# ...

# ═══════════════════════════════════════════════════════════════════════
# ══ END OF CUSTOM CONFIGURATIONS ══
# ═══════════════════════════════════════════════════════════════════════
```
