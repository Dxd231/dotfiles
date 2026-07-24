# .dotfiles...

> A very personal configuration files repo.

![OS](https://img.shields.io/badge/OS-Arch-Linux%20-informational?style=flat-square&logo=linux)
![Shell](https://img.shields.io/badge/Shell-Bash%20%2F%20Zsh-4EAA25?style=flat-square&logo=gnu-bash)
![Editor](https://img.shields.io/badge/Editor-Neovim-57A143?style=flat-square&logo=neovim)

---

## 🧰 Key Components

| Tool | Description | Configuration Path |
| :--- | :--- | :--- |
| **Shell** | Bash / Zsh configs & custom aliases | `~/.bashrc`, `~/.zshrc` |
| **Terminal** | Alacritty terminal emulator themes & keybinds | `~/.config/alacritty/` |
| **Editor** | Neovim plugins, keymaps, and LSP settings | `~/.config/nvim/` |
| **Git** | Global git settings & custom command shortcuts | `~/.gitconfig` |

---

## 🚀 Quick Setup on a New Machine

Clone and apply these dotfiles on a fresh machine:

```bash
# 1. Define configuration alias
alias config='/usr/bin/git --git-dir=$HOME/.cfg/ --work-tree=$HOME'

# 2. Add gitignore to prevent tracking home directory clutter
echo ".cfg" >> .gitignore

# 3. Clone the bare repository
git clone --bare git@github.com:Dxd231/dotfiles.git $HOME/.cfg

# 4. Checkout configurations
config checkout

# 5. Hide untracked files from git status
config config --local status.showUntrackedFiles no
