# Sudachi

<p align="center">
  <img src="https://github.com/user-attachments/assets/55e3eb61-f479-40c1-be9a-6dd0b4c3b400" alt="Sudachi Logo" style="width: 192px" />
</p>
<p align="center">
  <a href="https://github.com/KabosuNeko/sudachi/actions/workflows/ci.yml"><img src="https://github.com/KabosuNeko/sudachi/actions/workflows/ci.yml/badge.svg" alt="CI" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License" /></a>
  <a href="#y%C3%AAu-c%E1%BA%A7u"><img src="https://img.shields.io/badge/platform-Linux-2ea44f.svg" alt="Platform" /></a>
  <a href="#c%C3%A0i-%C4%91%E1%BA%B7t"><img src="https://img.shields.io/badge/shell-bash-89e051.svg" alt="Bash" /></a>
</p>

Trình phim/TV/anime phụ đề Việt chạy thẳng trong terminal: tìm phim, chọn tập, phát bằng `mpv`/`vlc` — kèm lọc quảng cáo và tải tập về máy.

## Điểm chính

- **Hai nguồn phim**: PhimAPI và OPhim, đổi qua lại trong Cài đặt
- **Lọc quảng cáo HLS**: cắt khối ad giữa tập trước khi phát, ghép lại mốc thời gian clip tài trợ để tua không nhảy
- **Tải tập**: `yt-dlp` + `aria2c` đa luồng, thông báo desktop khi xong
- **Poster trong terminal**: preview bằng `chafa` (Kitty/Sixel)
- **Lịch sử, yêu thích, xem tiếp**: mở lại đúng tập và đúng chỗ đang xem dở
- **CLI flags**: tìm nhanh, xem tiếp, phim mới, anime, tiến độ tải

## Yêu cầu

**Bắt buộc:** `fzf` + `jq` + `curl`, kèm `mpv` (khuyên dùng) hoặc `vlc`.

**Khuyến nghị thêm:**

| Gói | Dùng cho |
|---|---|
| `chafa` | Poster preview trong terminal |
| `yt-dlp` + `aria2c` | Tải tập đa luồng |
| `notify-send` | Thông báo khi tải xong |
| `ffmpeg` + `ffprobe` | Ghép mốc thời gian clip tài trợ để tua mượt (thiếu vẫn phát bình thường) |

### Cài theo distro

**Arch**
```bash
sudo pacman -S fzf jq curl mpv yt-dlp chafa aria2 libnotify ffmpeg
```

**Debian/Ubuntu**
```bash
sudo apt install fzf jq curl mpv aria2 libnotify-bin chafa ffmpeg
# yt-dlp từ apt thường bản cũ — cài binary thủ công:
sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
sudo chmod a+rx /usr/local/bin/yt-dlp
```

**Fedora**
```bash
sudo dnf install fzf jq curl mpv yt-dlp chafa aria2 libnotify ffmpeg
```

## Cài đặt

**Chạy trực tiếp (không cần cài):**
```bash
bash -c "$(curl -sL https://raw.githubusercontent.com/KabosuNeko/sudachi/main/sudachi.sh)"
```

**Alias trong `~/.bashrc` / `~/.zshrc` (fish: `~/.config/fish/config.fish`):**
```bash
alias sudachi='bash -c "$(curl -sL https://raw.githubusercontent.com/KabosuNeko/sudachi/main/sudachi.sh)"'
```

## Cách dùng

```bash
sudachi                # Mở menu TUI
sudachi -s "tên phim"  # Tìm kiếm phim trực tiếp
sudachi -c             # Xem tiếp tập gần nhất
sudachi -l             # Danh sách phim mới
sudachi -a             # Danh mục anime
sudachi -d             # Tiến độ và danh sách tải phim
sudachi -h             # Trợ giúp
```

### Phím tắt (chọn tập)

| Phím | Chức năng |
| :--- | :--- |
| **Enter** | Phát tập |
| **Tab** | Tải tập (`~/Downloads/Sudachi-Downloaded`) |
| **Ctrl+F** | Thêm vào yêu thích |
| **Esc** | Quay lại / thoát |

## Cấu hình

Tự tạo tại `~/.config/sudachi/`:

| File | Nội dung |
|---|---|
| `config` | Trình phát (`mpv`/`vlc`), chất lượng, chặn quảng cáo |
| `source.conf` | Nguồn phim đang dùng |
| `history.log` · `favorites.log` · `progress.log` | Lịch sử xem, yêu thích, tập đang xem dở |
| `cache/` | Cache API, poster, playlist đã lọc và clip đã ghép (`Cài đặt → Xóa cache` để dọn) |

## Nguồn phim

| Nguồn | API |
|---|---|
| [PhimAPI](https://phimapi.com) | `https://phimapi.com` |
| [OPhim](https://ophim.cc) | `https://ophim1.com` |

## Chặn quảng cáo HLS

Với phim từ phimapi, khối quảng cáo chèn giữa tập được lọc trước khi phát — tua tới/lui không còn nhảy về đầu.

- Playlist HLS được tải, cắt các segment khớp `HLS_AD_PATTERNS` (`ads*/`, `promo*/`, `/v*/<hash>/segment_`) rồi cache tại `cache/<hash>-clean.m3u8`. Khối segment ngoài thư mục phim ngay sau `#EXT-X-KEY:METHOD=NONE` cũng bị coi là quảng cáo, kể cả khi CDN đổi tên đường dẫn; segment trong đúng thư mục phim không bao giờ bị cắt
- **Chất lượng** (Cài đặt → Chất lượng) chọn đúng variant HLS: mặc định bản cao nhất, chọn 720p sẽ lấy variant ≤ 720p
- Clip `convertv*` là cảnh phim thật kèm text tài trợ nhưng bị CDN đặt lại mốc thời gian; `ffmpeg` ghép chúng về đúng dòng thời gian phim nên tua qua đoạn này đứng yên. Các clip liền nhau thành từng cụm, mỗi cụm neo vào segment phim ngay trước nó — playlist nhiều cụm vẫn ghép đúng. Thiếu `ffmpeg`/`ffprobe` thì giữ nguyên dấu `DISCONTINUITY` — vẫn phát bình thường
- Phát bằng VLC: thêm `--no-input-fast-seek` (tua chính xác) và `--network-caching=3000` (đệm segment từ xa); tùy chọn chất lượng giữ nguyên
- Nếu lần tải lại playlist gặp lỗi, chương trình dùng bản đã lọc trong cache; CDN đổi layout ad sẽ được ghi cảnh báo vào `cache/debug.log`
- Tải phim (Tab) giữ nguyên stream gốc (có ad) — chỉ lọc khi phát

## Credits

UI: [fzf](https://github.com/junegunn/fzf) · Phát phim: [mpv](https://mpv.io/) / [VLC](https://www.videolan.org/vlc/)

MIT License.
