---
name: bash2zsh
description: Lightweight Zsh setup: starship prompt + keybindings + completions. Use when user mentions installing zsh, configuring zsh, starship, zsh shortcuts, or zsh completion.
---

# Lightweight Zsh Configuration Assistant

## Core Philosophy

**Lightweight, Fast, Maintainable**:
- Use starship as prompt (Rust-powered, blazing fast)
- Custom keybindings for cursor navigation
- Streamlined completion configuration
- No dependency on oh-my-zsh

## Components

| Component | Purpose | Features |
|-----------|---------|----------|
| starship | Terminal prompt | Fast startup, cross-platform |
| Keybindings | Cursor navigation | Ctrl+arrows for word jumping |
| Completion | Enhanced completion | menu-complete, use-cache |

## Workflow

### Step 1: Check Current Environment

```bash
which zsh && zsh --version
which starship && starship --version
cat ~/.zshrc
cat ~/.bashrc
```

### Step 2: Backup Original Config

```bash
cp ~/.zshrc ~/.zshrc.bak.$(date +%Y%m%d)
```

### Step 3: Install Starship (if needed)

```bash
# Linux/macOS
curl -sS https://starship.rs/install.sh | sh

# Or: brew install starship
```

### Step 4: Generate Core .zshrc

Create a clean .zshrc with the following structure:

```zsh
# ═══════════════════════════════════════════════════════════════════════
# Lightweight Zsh Configuration
# ═══════════════════════════════════════════════════════════════════════

# ---- 1. STARSHIP ----
eval "$(starship init zsh)"

# ---- 2. KEYBINDINGS ----
bindkey "^[[1;5C" forward-word
bindkey "^[[1;5D" backward-word
bindkey "^A" beginning-of-line
bindkey "^E" end-of-line
bindkey "^W" backward-kill-word
bindkey "^U" kill-whole-line

# ---- 3. COMPLETION ----
setopt MENU_COMPLETE
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*' use-cache on
autoload -Uz compinit && compinit -C

# ---- 4. HISTORY ----
setopt HIST_IGNORE_DUPS SHARE_HISTORY NO_BEEP

# ═══════════════════════════════════════════════════════════════════════
# MIGRATED FROM ~/.bashrc (add below)
# ═══════════════════════════════════════════════════════════════════════
```

### Step 5: Ask User About Migration

**Must ask user which configurations to migrate from ~/.bashrc**:

```
Detected the following in ~/.bashrc. Which ones to migrate?

[1] Go environment (GOROOT, GOPATH, GOMODCACHE)
[2] Custom PATH additions
[3] API Config (ANTHROPIC_*, DEEPSEEK_*)
[4] kubectl aliases (k, kg, kd, kge, etc.)
[5] containerd/nerdctl aliases
[6] Other aliases
[7] kubectl completion
[8] helm completion
[9] All of the above
[10] Custom selection
```

### Step 6: Configure starship.toml (Optional)

```bash
mkdir -p ~/.config
cp /path/to/starship.toml ~/.config/starship.toml
```

Or use default config: `starship preset catppuccin-mocha > ~/.config/starship.toml`

### Step 7: Set Default Shell (Optional)

```bash
chsh -s /bin/zsh
```

### Step 8: Verify Configuration

```bash
source ~/.zshrc
echo $starship_version
bindkey | grep forward-word
```

## Troubleshooting

### Keybindings Not Working

```bash
# Check keycodes: press Ctrl+v, then the shortcut
# Common mappings:
bindkey "^[[1;5D" backward-word   # Ctrl+Left
bindkey "^[[1;5C" forward-word    # Ctrl+Right
bindkey "^[[1;3D" backward-word   # Alt+Left
bindkey "^[[1;3C" forward-word    # Alt+Right
```

### SSH Keybindings Fail

```zsh
bindkey -e  # Enable emacs mode
```

### tmux Conflict

```zsh
# In ~/.tmux.conf:
set -g default-terminal "xterm-256color"
```

## Migration Checklist

```
- [ ] Backup ~/.zshrc
- [ ] Check environment
- [ ] Install starship
- [ ] Generate core .zshrc
- [ ] Ask user → migrate ~/.bashrc configs
- [ ] Configure starship.toml
- [ ] Set default shell
- [ ] Verify
```

## Additional Resources

- For starship presets: `starship preset list`
- For keycode detection: press Ctrl+v in zsh
- For zsh-autosuggestions: see [reference.md](reference.md)
