# Sudachi Player

My personal CLI Vietsub Media Watcher configuration, focused on aesthetics, speed, and minimalism for Linux users.

## 📋 Overview

This tool suite includes:
- **Sudachi CLI** script with a heavily "Riced" FZF interface.
- **Multi-Source Engine** automatically switching between PhimAPI, Ophim.
- **Image Preview** integration directly in the terminal.
- Optimized **MPV** streaming & **yt-dlp** downloading configuration.

## Preview

<img width="1920" height="1080" alt="2026-01-17_23-32" src="https://github.com/user-attachments/assets/aa500a25-4b0d-4810-9850-977753e77331" />


## 🎨 Interface: Riced FZF

This tool transforms your terminal into a mini cinema browser with a floating window interface, removing the clutter of traditional CLI tools.

**Highlights:**

1.  🛍️ **Floating Window:** The menu floats in the center with rounded borders, creating a modern look.
2.  🖼️ **Image Preview:** Uses `chafa` to load high-res anime posters instantly as you scroll.
3.  ✨ **Nerd Fonts:** Fully integrated icons for a visual and seamless experience.

---

## 🧩 Dependencies

To run Sudachi properly, your system needs the following packages:

### 1. Core (Required)
* **[fzf](https://github.com/junegunn/fzf)**: The heart of the interface. Used for fuzzy finding and menu rendering.
* **[jq](https://stedolan.github.io/jq/)**: JSON processor, required to parse API data.
* **[mpv](https://mpv.io/)**: The best media player for Linux. Used for streaming.
* **[curl](https://curl.se/)**: For fetching API data.

### 2. Utilities (Highly Recommended)
* **[chafa](https://github.com/hpjansson/chafa)**: Terminal graphics. Required for **Image Preview**.
* **[yt-dlp](https://github.com/yt-dlp/yt-dlp)** & **[aria2](https://github.com/aria2/aria2)**: Required for multi-threaded high-speed downloading.

---

## 🛠️ Installation

### 1. Install Dependencies

Select your distribution below to install the required packages.

#### 🐧 Arch Linux / Arch-Based
```bash
sudo pacman -S fzf jq curl mpv yt-dlp chafa aria2 libnotify
```

#### 🍥 Debian / Ubuntu / Kali Linux / Linux Mint
```bash
sudo apt update
sudo apt install fzf jq curl mpv aria2 libnotify-bin chafa

# Note: The 'yt-dlp' version in apt is often outdated.
# We recommend installing the latest binary:
sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
sudo chmod a+rx /usr/local/bin/yt-dlp
```

#### 🎩 Fedora / RHEL / CentOS
```bash
sudo dnf install fzf jq curl mpv yt-dlp chafa aria2 libnotify
```

### 2. Run Script

**Run it directly**
```bash
bash -c "$(curl -sL https://raw.githubusercontent.com/KabosuNeko/sudachi/main/sudachi.sh)"
```

**Alias**
```bash
# You can alias it in your shell by
alias sudachi='bash -c "$(curl -sL https://raw.githubusercontent.com/KabosuNeko/sudachi/main/sudachi.sh)"'
# Now you can run 'sudachi' from anywhere
```

---

## 🎮 Controls

Inside the Episode Selection menu:

| Key | Action |
| :--- | :--- |
| **`ENTER`** | ▶️ **Stream** (Open MPV) |
| **`TAB`** | ⬇️ **Download** (Save to `~/Downloads/Sudachi-Downloaded`) |
| **`CTRL + F`** | ❤️ Add to **Favorites** |
| **`ESC`** | 🔙 Back / Exit |

---

## ⚙️ Configuration

The script auto-generates configuration files at `~/.config/sudachi`.

- **History:** `~/.config/sudachi/history.log`
- **Favorites:** `~/.config/sudachi/favorites.log`
- **Download Dir:** `~/Downloads/Sudachi-Downloaded` (Edit script to change)

---

## 🙏 Credits

- **[PhimAPI](https://phimapi.com)** & **[Ophim](https://ophim.cc)** - API.
- **[FZF](https://github.com/junegunn/fzf)** - Command-line fuzzy finder.

---
