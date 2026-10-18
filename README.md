# dotfiles

Arch, Hyprland, Quickshell, Neovim. Colours come from the wallpaper through matugen.

<img src="assets/desktop.png" width="800">

## What is in here

- `.config/quickshell`: the shell. Bar, dock, launcher, notifications, lock screen, wallpaper switcher, clipboard, control center and a few panels of my own (below).
- `.config/hypr`: Hyprland config in Lua.
- `.config/matugen`: templates that turn the wallpaper colours into Quickshell, Hyprland and editor themes.
- `.config/mpv`: mpv config and scripts, including the one that logs Japanese-audio playback for the immersion tracker.
- `.config/nvim`: LazyVim.
- `wallpaper/`: wallpapers.

## Panels

**Focus timer.** Pomodoro in the bar clock. Focus, short break and long break roll into each other without stopping. A finished focus session counts toward a task.

<img src="assets/focus.png" width="800">

**Immersion tracker.** Counts time spent on Japanese media. mpv playback is logged automatically when the audio is Japanese. Books from ttu and manga from Kavita are read from their own data. There is a daily goal, a streak and a heatmap.

<img src="assets/immersion.png" width="800">

**Tasks.** Daily habits with a target per day, reminders, a streak and a heatmap.

<img src="assets/tasks.png" width="800">

Also in there: screenshots and screen recording (grim, gpu-screen-recorder), an OCR snip overlay for manga (manga-ocr or PaddleOCR), synced lyrics for whatever is playing, and a wallpaper picker.

## Setup

The repo is a bare repo with `$HOME` as the work tree.

```sh
git clone --bare git@github.com:Dxd231/dotfiles.git $HOME/.cfg
alias cfg='git --git-dir=$HOME/.cfg --work-tree=$HOME'
cfg checkout        # move any existing files out of the way first
cfg config status.showUntrackedFiles no
```

Needed for the shell: quickshell, hyprland, matugen, awww, cliphist, wl-clipboard, grim, slurp, gpu-screen-recorder, mpv. Optional: manga-ocr or paddleocr for the OCR overlay, ydotool.

Fonts: Google Sans and Zen Maru Gothic.

Quickshell hot-reloads, but a new component file needs a shell restart before it is picked up.
