# Sudachi Player

Trình phát Phim Vietsub dành cho người dùng Linux.

## 📋 Tổng quan

Bộ công cụ này bao gồm:
- **Sudachi.sh**: Script với giao diện FZF được "Gạo".
- **Xem trước hình ảnh**: Tích hợp hiển thị ảnh ngay trong terminal.
- Tối ưu hóa cấu hình **MPV** để xem phim & **yt-dlp** để tải xuống.

## Preview
<img width="1920" height="1080" alt="abc" src="https://github.com/user-attachments/assets/b4012097-2b3a-4475-aa8d-47455c6d43ec" />


## 🎨 Giao diện: FZF Riced

Công cụ này biến terminal của bạn thành một rạp phim thu nhỏ với giao diện cửa sổ nổi, loại bỏ sự lộn xộn của các công cụ CLI truyền thống.

**Điểm nổi bật:**

1.  🛍️ **Cửa sổ nổi (Floating Window):** Menu hiển thị lơ lửng ở chính giữa với các viền bo tròn, tạo cảm giác hiện đại.
2.  🖼️ **Xem trước hình ảnh:** Sử dụng `chafa` để tải poster anime độ phân giải cao ngay lập tức khi bạn lướt qua danh sách.
3.  ✨ **Nerd Fonts:** Tích hợp đầy đủ các icon để mang lại trải nghiệm trực quan và liền mạch.

---

## 🧩 Yêu cầu hệ thống (Dependencies)

Để chạy Sudachi, bạn cần cài đặt các gói sau:

### 1. Cốt lõi (Bắt buộc)
* **[fzf](https://github.com/junegunn/fzf)**: Trái tim của giao diện. Dùng để tìm kiếm mờ (fuzzy finding) và hiển thị menu.
* **[jq](https://stedolan.github.io/jq/)**: Bộ xử lý JSON, cần thiết để đọc dữ liệu từ API.
* **[mpv](https://mpv.io/)**: Trình phát media tốt nhất cho Linux. Dùng để stream phim.
* **[curl](https://curl.se/)**: Dùng để tải dữ liệu từ API.

### 2. Tiện ích (Rất khuyên dùng)
* **[chafa](https://github.com/hpjansson/chafa)**: Đồ họa Terminal. Bắt buộc nếu muốn có tính năng **Xem trước hình ảnh**.
* **[yt-dlp](https://github.com/yt-dlp/yt-dlp)** & **[aria2](https://github.com/aria2/aria2)**: Cần thiết để hỗ trợ tải xuống đa luồng tốc độ cao.

---

## 🛠️ Cài đặt

Chọn bản phân phối (distro) của bạn bên dưới để cài đặt các gói cần thiết.

#### 🐧 Arch Linux / Arch-Based
```bash
sudo pacman -S fzf jq curl mpv yt-dlp chafa aria2 libnotify
```

#### 🍥 Debian / Ubuntu / Kali Linux / Linux Mint
```bash
sudo apt update
sudo apt install fzf jq curl mpv aria2 libnotify-bin chafa

# Lưu ý: Phiên bản 'yt-dlp' trong apt thường bị lỗi thời.
# Bạn nên cài đặt bản binary mới nhất theo cách sau:
sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
sudo chmod a+rx /usr/local/bin/yt-dlp
```

#### 🎩 Fedora / RHEL / CentOS
```bash
sudo dnf install fzf jq curl mpv yt-dlp chafa aria2 libnotify
```

### 2. Chạy Script

**Chạy trực tiếp**
```bash
bash -c "$(curl -sL https://raw.githubusercontent.com/KabosuNeko/sudachi/main/sudachi.sh)"
```

**Tạo Alias (Lệnh tắt)**
```bash
# Bạn có thể tạo alias trong shell (như .bashrc hoặc .zshrc)
alias sudachi='bash -c "$(curl -sL https://raw.githubusercontent.com/KabosuNeko/sudachi/main/sudachi.sh)"'

# Bây giờ bạn chỉ cần gõ 'sudachi' từ bất cứ đâu để chạy
```

---

## 🎮 Điều khiển

Bên trong menu Chọn Tập Phim:

| Phím | Hành động |
| :--- | :--- |
| **`ENTER`** | ▶️ **Xem phim** (Mở MPV) |
| **`TAB`** | ⬇️ **Tải xuống** (Lưu vào `~/Downloads/Sudachi-Downloaded`) |
| **`CTRL + F`** | ❤️ Thêm vào **Yêu thích** |
| **`ESC`** | 🔙 Quay lại / Thoát |

---

## ⚙️ Config

Script sẽ tự động tạo các file cấu hình tại thư mục `~/.config/sudachi`.

- **Lịch sử xem:** `~/.config/sudachi/history.log`
- **Danh sách yêu thích:** `~/.config/sudachi/favorites.log`
- **Thư mục tải xuống:** `~/Downloads/Sudachi-Downloaded`

---

## 🙏 Credits

- **[PhimAPI](https://phimapi.com)** - Cung cấp API phim.
- **[FZF](https://github.com/junegunn/fzf)** - Công cụ tìm kiếm mờ dòng lệnh.

---

## License

Dự án này được cấp phép theo giấy phép **GNU General Public License v3.0**. Xem file [LICENSE](LICENSE) để biết thêm chi tiết.
