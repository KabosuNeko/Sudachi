# Sudachi

<p><br/></p>
<p align="center">
  <img src="https://github.com/user-attachments/assets/55e3eb61-f479-40c1-be9a-6dd0b4c3b400" alt="Sudachi Logo" style="width: 192px" />
</p>
<p><br/></p>

Trình phim/TV/anime phụ đề Việt chạy trong Terminal, dành cho Linux.

## Dependencies

**Bắt buộc:** `fzf` + `jq` + `curl` — kèm `mpv` hoặc `vlc` để phát.

**Khuyến nghị thêm:** `chafa` (poster preview), `yt-dlp` + `aria2c` (tải đa luồng), `notify-send` (thông báo khi tải xong).

### Cài đặt theo distro

**Arch**
```bash
sudo pacman -S fzf jq curl mpv yt-dlp chafa aria2 libnotify
```

**Debian/Ubuntu**
```bash
sudo apt install fzf jq curl mpv aria2 libnotify-bin chafa
# yt-dlp từ apt thường bản cũ — hãy cài binary thủ công:
sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
sudo chmod a+rx /usr/local/bin/yt-dlp
```

**Fedora**
```bash
sudo dnf install fzf jq curl mpv yt-dlp chafa aria2 libnotify
```

## Quick start

### Chạy trực tiếp (không cần cài đặt)
```bash
bash -c "$(curl -sL https://raw.githubusercontent.com/KabosuNeko/sudachi/main/sudachi.sh)"
```

### Hoặc thêm alias vào `~/.bashrc`
```bash
alias sudachi='bash -c "$(curl -sL https://raw.githubusercontent.com/KabosuNeko/sudachi/main/sudachi.sh)"'
```

## Hệ thống Phím tắt (episode picker)

| Phím | Chức năng |
| :--- | :--- |
| **Enter** | Phát |
| **Tab** | Tải xuống (lưu vào `~/Downloads/Sudachi-Downloaded`) |
| **Ctrl+F** | Thêm vào Yêu thích |
| **Esc** | Quay lại / thoát |

## Cấu hình

Tự động tạo tại `~/.config/sudachi/`:
- `config` — player (`mpv`/`vlc`) và chất lượng
- `source.conf` — tên API source
- `history.log` — lịch sử xem
- `favorites.log` — phim yêu thích
- `progress.log` — tập đang xem dở
- `cache/` — cache response từ API (bị xoá khi đổi source)

## API sources

| Source | Base URL |
|--------|----------|
| [PhimAPI](https://phimapi.com) | `https://phimapi.com` |
| [OPhim](https://ophim.cc) | `https://ophim1.com` |

## Chặn quảng cáo giữa tập (phimapi)

Khi phát phim từ phimapi, các khối quảng cáo bị chèn giữa tập sẽ được **lọc tự động trước khi phát** — hết ad giữa phim, và tua tới/tua lui hoạt động bình thường.

Cách hoạt động:
- Playlist HLS được tải về và lọc bỏ các segment quảng cáo (pattern trong biến `HLS_AD_PATTERNS`, bắt được cả CDN `kkphimplayer6` lẫn `kkphimplayer7` cùng các biến thể `ads*/`, `promo*/`)
- Bản đã lọc được cache tại `~/.config/sudachi/cache/<hash>-clean.m3u8`
- **Tự phát hiện CDN đổi layout ad**: nếu playlist có dấu hiệu quảng cáo (DISCONTINUITY) nhưng không khớp pattern nào, chương trình ghi cảnh báo vào `cache/debug.log` để bạn biết cần cập nhật pattern
- Nếu có bất kỳ lỗi nào khi lọc, chương trình **tự phát stream gốc** — xem phim không bao giờ bị gián đoạn
- **Tải phim (Tab) giữ nguyên stream gốc** (có ad) — chỉ lọc khi phát

## Credits

UI: [fzf](https://github.com/junegunn/fzf)

MIT License.
