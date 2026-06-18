# Sudachi

<p><br/></p>
<p align="center">
  <img src="https://github.com/user-attachments/assets/55e3eb61-f479-40c1-be9a-6dd0b4c3b400" alt="Sudachi Logo" style="width: 192px" />
</p>
<p><br/></p>

A Linux terminal-based Vietnamese-subtitled movie/TV/anime player.

## Dependencies

**Required:** `fzf` + `jq` + `curl` — plus `mpv` or `vlc` for playback.

**Optional:** `chafa` (poster preview), `yt-dlp` + `aria2c` (multi-thread downloads), `notify-send` (download notification).

### Installation by distro

**Arch**
```bash
sudo pacman -S fzf jq curl mpv yt-dlp chafa aria2 libnotify
```

**Debian/Ubuntu**
```bash
sudo apt install fzf jq curl mpv aria2 libnotify-bin chafa
# yt-dlp from apt is often outdated — install binary manually:
sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
sudo chmod a+rx /usr/local/bin/yt-dlp
```

**Fedora**
```bash
sudo dnf install fzf jq curl mpv yt-dlp chafa aria2 libnotify
```

## Quick start

### Run directly (no install)
```bash
bash -c "$(curl -sL https://raw.githubusercontent.com/KabosuNeko/sudachi/main/sudachi.sh)"
```

### Or add an alias to `~/.bashrc`
```bash
alias sudachi='bash -c "$(curl -sL https://raw.githubusercontent.com/KabosuNeko/sudachi/main/sudachi.sh)"'
```

## Key bindings (episode picker)

| Key | Action |
| :--- | :--- |
| **Enter** | Play |
| **Tab** | Download (saves to `~/Downloads/Sudachi-Downloaded`) |
| **Ctrl+F** | Add to favorites |
| **Esc** | Go back / exit |

## Configuration

Auto-created at `~/.config/sudachi/`:
- `config` — player (`mpv`/`vlc`) and quality
- `source.conf` — API source name
- `history.log` — watch history
- `favorites.log` — favorite movies
- `progress.log` — in-progress episodes
- `cache/` — API response cache (cleared when source changes)

## API sources

| Source | Base URL |
|--------|----------|
| [PhimAPI](https://phimapi.com) | `https://phimapi.com` |
| [OPhim](https://ophim.cc) | `https://ophim1.com` |
| [NguonC](https://nguonc.com) | `https://phim.nguonc.com` |
| [AniMapper](https://animapper.net) | `https://api.animapper.net/api/v1` |

## Credits

UI: [fzf](https://github.com/junegunn/fzf)

MIT License.
