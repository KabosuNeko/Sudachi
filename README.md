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

Trình phim/TV/anime phụ đề Việt chạy thẳng trong terminal: tìm phim, chọn tập, phát bằng `mpv`/`vlc`, tải tập về máy. Nguồn phim lấy từ addon K20 (đã lọc quảng cáo sẵn).

## Điểm chính

- **Nguồn K20**: KKPhim, VSMov, NguonC (tìm kiếm gộp) và AnimeVietsub; quảng cáo đã được K20 lọc trên server
- **Duyệt và lọc**: mọi danh mục của K20, lọc theo danh mục, thể loại, quốc gia, năm
- **Tải tập**: `yt-dlp` tải song song nhiều đoạn, thông báo desktop khi xong
- **Poster trong terminal**: preview bằng `chafa` (Kitty/Sixel)
- **Lịch sử, yêu thích, xem tiếp**: mở lại đúng tập; `mpv` nhớ chỗ đang xem dở
- **CLI flags**: tìm nhanh, xem tiếp, phim mới, anime, tiến độ tải

## Yêu cầu

Chỉ hỗ trợ Linux. **Bắt buộc:** `fzf` (>= 0.60) + `jq` + `curl`, kèm `mpv` (khuyên dùng) hoặc `vlc`. Trên Arch/CachyOS, VLC cần thêm `vlc-plugin-dvb` và `vlc-plugin-ffmpeg` mới phát được phim (thiếu thì Sudachi báo và tạm dùng mpv).

**Khuyến nghị thêm:**

| Gói | Dùng cho |
|---|---|
| `chafa` (+ `imagemagick`) | Poster preview trong terminal |
| `yt-dlp` | Tải tập |
| `notify-send` | Thông báo khi tải xong |
| `python3` | Chỉ cần để phát/tải phim nguồn NguonC (proxy cục bộ) |

### Cài theo distro

**Arch**
```bash
sudo pacman -S fzf jq curl mpv yt-dlp chafa imagemagick libnotify
```

**Debian/Ubuntu**
```bash
sudo apt install jq curl mpv libnotify-bin chafa imagemagick
# fzf từ apt quá cũ (Debian 12: 0.38, Ubuntu 24.04: 0.44) — cài bản mới từ
# https://github.com/junegunn/fzf/releases
# yt-dlp từ apt thường bản cũ — cài binary thủ công:
sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
sudo chmod a+rx /usr/local/bin/yt-dlp
```

**Fedora**
```bash
sudo dnf install fzf jq curl mpv yt-dlp chafa ImageMagick libnotify
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

### Menu

- **Tìm phim**: gõ để tìm trong KKPhim, VSMov, NguonC và danh sách K20 Anime
- **Xem tiếp**: phim đã xem gần đây kèm tập và thời gian; Enter mở danh sách tập ở đúng tập kế, Ctrl+D xóa
- **Khám phá**: phim mới, anime mới và mọi danh mục của K20; trong danh sách bấm **Ctrl+G** để lọc theo thể loại, quốc gia, năm
- **Yêu thích**, **Tải về**, **Cài đặt**

Esc luôn quay lại màn trước; Esc ở menu chính để thoát.

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
| `config` | Trình phát (`PLAYER_DEFAULT=mpv` hoặc `vlc`) |
| `history.log` · `favorites.log` · `progress.log` | Lịch sử xem, yêu thích, tập đang xem dở |
| `~/.cache/sudachi/` | Cache API, poster và log tải (`Cài đặt → Xóa cache` để dọn, kể cả các lượt tải đã xong) |

## Nguồn phim

Toàn bộ phim lấy từ hai addon Stremio của K20, gọi thẳng qua HTTP:

- **K20** (`sc.k-20.xyz`): KKPhim, VSMov, NguonC, STP, CLBPX. Tìm kiếm hỏi cùng lúc KKPhim, VSMov và NguonC; cùng một phim ở nhiều kho chỉ hiện một dòng kèm danh sách kho, ví dụ `[kkphim, nguonc]`, và khi mở sẽ hỏi chọn nguồn.
- **K20 Anime** (`anime.k-20.xyz`): AnimeVietsub, dùng cho mục Anime và Duyệt. Addon này không tự tìm kiếm được, nên Sudachi lưu sẵn danh sách khoảng 250 phim nó đang hiển thị (làm mới mỗi giờ) và tìm trong đó; kết quả có nhãn `[animevietsub]`. Ảnh bìa, thể loại và tóm tắt (tiếng Anh) lấy từ Kitsu vì K20 Anime không có tóm tắt và CDN ảnh của AnimeVietsub hay bị nhà mạng chặn. Nhiều phim cũ K20 Anime không còn link phát.

K20 lọc quảng cáo trên server. Riêng KKPhim, K20 cắt luôn các đoạn `convertv` (cảnh phim thật có chữ tài trợ đè lên, khoảng 25 giây mỗi tập), nên Sudachi tự dựng lại playlist KKPhim: chỉ bỏ quảng cáo, giữ đủ cảnh. Với mpv, Sudachi ghép các đoạn bằng EDL (file dòng thời gian của mpv) nên đồng hồ chạy liền và tua đúng cả trong đoạn `convertv`; đổi lại, mở tập KKPhim chậm hơn vài giây. VLC không đọc được EDL nên tua ngay trong đoạn `convertv` có thể nhảy sai. Không cần ffmpeg hay python. Khi một tập có nhiều bản (Vietsub, Thuyết minh), Sudachi hỏi chọn bản nào.

Các nguồn đều là bên thứ ba và có thể đổi hoặc chết bất cứ lúc nào. Lịch sử và yêu thích từ phiên bản cũ (PhimAPI, VSMov, NguonC tự làm) có thể không mở được nữa; xóa bằng Ctrl+D trong Yêu thích.

## Credits

UI: [fzf](https://github.com/junegunn/fzf) · Phát phim: [mpv](https://mpv.io/) / [VLC](https://www.videolan.org/vlc/)

MIT License.
