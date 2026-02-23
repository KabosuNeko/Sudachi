# Sudachi Player

Trình phát Phim Vietsub dành cho người dùng Linux.

## 📋 Tổng quan

Bộ công cụ này bao gồm:
- **Sudachi.sh**: Script với giao diện FZF được "Gạo".
- **Xem trước hình ảnh**: Tích hợp hiển thị ảnh ngay trong terminal.
- Tối ưu hóa cấu hình **MPV** để xem phim & **yt-dlp** để tải xuống.

## Preview
<img width="1919" height="1079" alt="image" src="https://github.com/user-attachments/assets/e51a0cc5-4443-4691-b769-0aa8b3414f2d" />

---

## 🧩 Yêu cầu hệ thống (Dependencies)

Để chạy Sudachi, bạn cần cài đặt các gói sau:

### 1. Cốt lõi (Bắt buộc)
* **[fzf](https://github.com/junegunn/fzf)**: Trái tim của giao diện. Dùng để tìm kiếm mờ (fuzzy finding) và hiển thị menu.
* **[jq](https://stedolan.github.io/jq/)**: Bộ xử lý JSON, cần thiết để đọc dữ liệu từ API.
* **[mpv](https://mpv.io/) or [vlc](https://www.videolan.org/)**: Trình phát media. Dùng để stream phim.
* **[curl](https://curl.se/)**: Dùng để tải dữ liệu từ API.

### 2. Tiện ích (Rất khuyên dùng)
* **[chafa](https://github.com/hpjansson/chafa)**: Đồ họa Terminal. Bắt buộc nếu muốn có tính năng **Xem trước hình ảnh**.
* **[yt-dlp](https://github.com/yt-dlp/yt-dlp)** & **[aria2](https://github.com/aria2/aria2)**: Cần thiết để hỗ trợ tải xuống đa luồng tốc độ cao.

---

## 🛠️ Cài đặt

Chọn bản phân phối (distro) của bạn bên dưới để cài đặt các gói cần thiết.

#### 🐧 Arch Linux / Arch-Based
```bash
sudo pacman -S fzf jq curl yt-dlp chafa aria2 libnotify
# Mpv
sudo pacman -S mpv
# Vlc
sudo pacman -S vlc
```

#### 🍥 Debian / Ubuntu / Kali Linux / Linux Mint
```bash
sudo apt update
sudo apt install fzf jq curl aria2 libnotify-bin chafa
# Mpv
sudo apt install mpv
# Vlc
sudo apt install vlc

# Lưu ý: Phiên bản 'yt-dlp' trong apt thường bị lỗi thời.
# Bạn nên cài đặt bản binary mới nhất theo cách sau:
sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
sudo chmod a+rx /usr/local/bin/yt-dlp
```

#### 🎩 Fedora / RHEL / CentOS
```bash
sudo dnf install fzf jq curl yt-dlp chafa aria2 libnotify

# Mpv
sudo dnf install mpv
# Vlc
sudo dnf install vlc
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

## Block ADS (nâng cao)
Mặc dù MPV/VLC đã loại bỏ hoàn toàn quảng cáo Popup/Banner, nhưng tất nhiên các chủ api họ tính cả rồi :)) vẫn sẽ có những qc chèn thẳng vào video và khi tua nó sẽ ngay lập tức chạy lại từ đầu khiến ta cực kì khó chịu. Để tránh việc này thì chúng ta sẽ setup một dns ở cấp hệ thống, khuyên dùng nextdns vì nó free thừa cho nhu cầu dùng cơ bản và tốc độ rất ổn.
- Trước tiên hãy truy cập vào [nextdns](https://my.nextdns.io/) và tạo một tài khoản cho riêng bạn sau đó:

### 1. Privacy
- Vào tab Privacy > Add a Blocklist, thêm 3 list này:

    ✅ hostsVN (Chặn quảng cáo đặc thù Việt Nam)

    ✅ ABPVN List (Bộ lọc quảng cáo Việt Nam nổi tiếng)

    ✅ HaGeZi - Multi PRO (Bộ lọc quốc tế cực mạnh chặn Tracker)

### 2. Security
- Vào tab Security, bật tất cả tính năng (ngoại trừ Block Dynamic DNS Hostnames):

    🚀 Quan trọng nhất: Block Newly Registered Domains (NRDs): Chặn các trang nhà cái/cờ bạc vừa mới lập trong 30 ngày gần đây để chạy quảng cáo. 

### 3. Setup
- Tại ngay tab setup của [nextdns](https://my.nextdns.io/) hãy đọc setup guide nó đã ghi rõ và chi tiết, khuyên dùng nextdns-cli (NextDNS Command-Line Client) vì dễ quản lí và bật/tắt dns khi cần thiết. 

---

## 🙏 Credits

- **[PhimAPI](https://phimapi.com), [OPhim](https://ophim.cc), [NguonC](https://nguonc.com)** - Cung cấp API phim.
- **[FZF](https://github.com/junegunn/fzf)** - Công cụ tìm kiếm mờ dòng lệnh.

---

## License

Dự án này được phân phối dưới giấy phép **MIT License**. Xem file [LICENSE](LICENSE) để biết thêm thông tin.
