# .dotfiles...

> A very personal configuration files repo.

![Arch Linux](https://img.shields.io/badge/OS-Arch%20Linux-1793D1?style=flat-square&logo=arch-linux&logoColor=white)
![Hyprland](https://img.shields.io/badge/WM-Hyprland-555555?style=flat-square&logo=hyprland&logoColor=00f0ff)
![Quickshell](https://img.shields.io/badge/Shell%20UI-Quickshell-8A2BE2?style=flat-square&logo=qt&logoColor=white)
![Zsh](https://img.shields.io/badge/Shell-Zsh-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white)
![Neovim](https://img.shields.io/badge/Editor-Neovim-57A143?style=flat-square&logo=neovim&logoColor=white)
---

## Keeping Track Of:

| Tool | Description | Configuration Path |
| :--- | :--- | :--- |
| **Shell** | Zsh configs & custom aliases | `~/.zshrc` |
| **Terminal** | Kitty terminal emulator themes & keybinds | `~/.config/kitty/` |
| **Editor** | Neovim plugins, keymaps, and LSP settings | `~/.config/nvim/` |
| **Git** | Global git settings & custom command shortcuts | `~/.gitconfig` |

---

## Syncing

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
````
![sakurako](./git-images/9f7b72dfb7a07ef9c0b13c9906725232-568952216.jpg)
