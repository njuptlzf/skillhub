---
name: bash2zsh
description: Migrates user environment from Bash to Zsh with Oh-My-Zsh, including installation, plugin optimization, completion setup, and nerdctl support. Use when user mentions installing zsh, migrating bashrc, configuring oh-my-zsh, zsh plugins, or nerdctl completion.
---

# Bash to Zsh Migration Assistant

## Workflow

### Step 1: Check Current Environment

```bash
# Check if zsh is installed
which zsh && zsh --version

# Check if oh-my-zsh is installed
ls ~/.oh-my-zsh 2>/dev/null && echo "Installed" || echo "Not installed"
```

### Step 2: Install Oh-My-Zsh (if not installed)

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
```

### Step 3: Ask User About Configuration Migration

**Ask user whether to migrate existing .bashrc configuration**, including:
- Go environment variables (GOROOT, GOPATH, GOMODCACHE)
- PATH configuration
- Common aliases
- Claude Code / API configuration
- Containerd / kubectl / nerdctl configuration

**Example interaction**:
```
Should we migrate the following configuration?
- Go environment variables: GOROOT, GOPATH
- PATH: /home/hurl, /home/zarf-dir, /root/buildkit, etc.
- Aliases: ll, la, l, vi, kge, ctr, nerdctl
- API config: ANTHROPIC_*, DeepSeek models
```

### Step 4: Configure Plugins

**Recommended plugins**:
```zsh
plugins=(git docker kubectl golang ansible archlinux)
```

**Plugins not recommended** (incorrect names):
- ❌ `k8s` → should use `kubectl`
- ❌ `go` → should use `golang`

### Step 5: Third-Party Tool Completion Configuration

#### General Detection Process

For tools **not built into oh-my-zsh** (such as nerdctl, helm, flux, etc.), follow this process:

```bash
# 1. Check if tool is installed
which <tool> && <tool> version

# 2. If installed, ask user whether to configure zsh completion
# 3. If user agrees, check if zsh completion is supported
<tool> completion zsh > /dev/null 2>&1 && echo "Supported" || echo "Not supported"
# 4. Configure completion and aliases
```

#### Common Third-Party Tool Completions

| Tool | Installation Check | Completion Command |
|------|-------------------|-------------------|
| nerdctl | `which nerdctl` | `nerdctl completion zsh` |
| helm | `which helm` | `helm completion zsh` |
| flux | `which flux` | `flux completion zsh` |
| kustomize | `which kustomize` | `kustomize completion zsh` |
| istio | `which istioctl` | `istioctlx crab completion zsh` |
| argocd | `which argocd` | `argocd completion zsh` |

#### Interaction Example

```
Detected the following tools are installed:
- nerdctl v2.0.0-beta.5
- helm v3.x
- kubectl v1.28

Would you like to configure zsh completion for the following tools?
[1] nerdctl - Container management (Recommended)
[2] helm - Helm charts
[3] Select all
[4] Skip
```

### Step 6: Advanced Configuration (Optional)

#### Disable Completion Query Prompt
```zsh
# Add to ~/.zshrc after source $ZSH/oh-my-zsh.sh
setopt MENU_COMPLETE
zstyle ':completion:*' verbose no
```

#### Common Plugin Descriptions

| Plugin | Function |
|--------|----------|
| git | Provides gst, gc, gp aliases |
| docker | Provides dps, di aliases |
| kubectl | kubectl command completion |
| golang | go command completion |
| ansible | ansible-* command completion |
| archlinux | pacman completion |

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
source ~/.zshrc

# Verify aliases
which gst  # Should output: gst: aliased to git status

# Verify nerdctl completion
nerdctl <Tab>  # Should show nerdctl subcommand completion

# Verify plugins
echo $plugins
```

## Migration Checklist

When executing migration, confirm each item with user:

```
Migration Checklist:
- [ ] Is oh-my-zsh installed
- [ ] Is original .zshrc backed up
- [ ] Are .bashrc environment variables migrated
- [ ] Are recommended plugins configured
- [ ] Are third-party tools detected (nerdctl/helm/flux, etc.)
- [ ] Are third-party tool completions configured
- [ ] Are third-party tool aliases added
- [ ] Is completion optimization set
- [ ] Is default shell set
- [ ] Is VSCode configured
```

## Configurations NOT to Migrate

The following typically do **NOT need to be migrated** to zsh:
- Bash-specific syntax (e.g., `[[ ]]` can be kept but not needed in zsh)
- `~/.bash_aliases` (should be merged directly into .zshrc)
- Bash completion scripts (oh-my-zsh has better completion built-in)
