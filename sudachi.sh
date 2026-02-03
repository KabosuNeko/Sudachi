#!/bin/bash

CONF="$HOME/.config/sudachi"
DL="$HOME/Downloads/Sudachi-Downloaded"
HIST="$CONF/history.log"
FAV="$CONF/favorites.log"
CACHE="$CONF/cache"

mkdir -p "$CONF" "$DL" "$CACHE"
[ ! -f "$HIST" ] && touch "$HIST"
[ ! -f "$FAV" ] && touch "$FAV"

API="https://phimapi.com"

I_SEARCH=" "
I_NEW="󰎁 "
I_BROWSE="󰖟 "
I_FILTER=" "
I_HIST=" "
I_FAV=" "
I_DIR=" "
I_EXIT="󰈆 "

C_G='\033[1;32m'
C_Y='\033[1;33m'
C_C='\033[0;36m'
C_M='\033[1;35m'
C_R='\033[0m'

FZF_OPTS=(
    "--border=rounded" "--margin=5%,10%" "--padding=1"
    "--layout=reverse" "--pointer=" "--marker= "
    "--color=bg:-1,bg+:-1"
    "--color=fg:#d8dee9,fg+:#a3be8c,hl:#ebcb8b,hl+:#ebcb8b"
    "--color=border:#a3be8c,prompt:#81a1c1,pointer:#ebcb8b"
    "--color=info:#e5e9f0,header:#81a1c1"
)

goi_api() {
    local res
    res=$(curl -s --connect-timeout 10 --max-time 30 "${API}$1" 2>/dev/null)
    echo "$res" | jq -e . >/dev/null 2>&1 && ! echo "$res" | grep -q '"error"' && echo "$res"
}

dang_tai() { echo -e "${C_C}⏳ Đang tải...${C_R}"; }
thong_bao_loi() { echo -e "${C_Y}⚠️  $1${C_R}"; sleep 2; }

tao_script_xem_truoc() {
    local script="$CACHE/preview_$$.sh"
    cat > "$script" << 'EOF'
#!/bin/bash
IFS='|' read -r ten nam quocgia trangthai slug anh <<< "$1"
echo -e "\033[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "\033[1;33m📽️  ${ten}\033[0m"
echo -e "\033[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo ""
[[ -n "$nam" && "$nam" != "null" ]] && echo -e "  \033[0;36m📅 Năm:\033[0m $nam"
[[ -n "$quocgia" && "$quocgia" != "null" ]] && echo -e "  \033[0;36m🌍 Quốc gia:\033[0m $quocgia"
[[ -n "$trangthai" && "$trangthai" != "null" ]] && echo -e "  \033[0;36m📺 Trạng thái:\033[0m $trangthai"
echo ""
if [[ -n "$anh" && "$anh" != "null" ]]; then
    command -v chafa &>/dev/null && curl -s --max-time 5 "$anh" 2>/dev/null | chafa -s 35x18 - 2>/dev/null
fi
EOF
    chmod +x "$script"
    echo "$script"
}

xem_tap() {
    local slug="$1" ten="$2"
    dang_tai
    
    local res=$(goi_api "/phim/$slug")
    [[ -z "$res" ]] && { thong_bao_loi "Không lấy được thông tin"; return; }
    
    local ds_tap=$(echo "$res" | jq -r '.episodes[0].server_data[] | "\(.name)|\(.link_m3u8)"' 2>/dev/null)
    [[ -z "$ds_tap" ]] && { thong_bao_loi "Không có tập phim"; return; }
    
    while true; do
        local chon=$(echo "$ds_tap" | fzf "${FZF_OPTS[@]}" \
            --header="📺 $ten" --prompt="CHỌN TẬP > " \
            --delimiter='|' --with-nth=1 \
            --preview="echo 'Enter: Xem | Tab: Tải | Ctrl-F: Lưu'" \
            --preview-window=top:3:wrap --expect=enter,tab,ctrl-f)
        
        local phim=$(head -1 <<< "$chon")
        local data=$(tail -n +2 <<< "$chon")
        [[ -z "$data" ]] && break
        
        local tap=$(echo "$data" | cut -d'|' -f1)
        local url=$(echo "$data" | cut -d'|' -f2)
        local tieu_de="${ten} - Tập ${tap}"
        
        case "$phim" in
            enter)
                sed -i "/$slug/d" "$HIST"
                echo "$(date +%s)|$tieu_de|$slug|$url" >> "$HIST"
                mpv "$url" --title="$tieu_de" --force-window >/dev/null 2>&1 &
                ;;
            tab)
                local file=$(echo "$tieu_de" | sed 's/ /_/g; s/[^a-zA-Z0-9_.-]//g').mp4
                yt-dlp "$url" -o "$DL/$file" --downloader aria2c -N 8 >/dev/null 2>&1 &
                command -v notify-send >/dev/null && notify-send "Sudachi" "📥 Đang tải: $tieu_de"
                ;;
            ctrl-f)
                grep -q "$slug" "$FAV" 2>/dev/null || echo "$ten|$slug" >> "$FAV"
                ;;
        esac
    done
}

hien_thi_danh_sach() {
    local items="$1" prompt="$2"
    [[ -z "$items" ]] && { thong_bao_loi "Không có kết quả"; return; }
    
    local preview=$(tao_script_xem_truoc)
    
    local chon=$(echo "$items" | fzf "${FZF_OPTS[@]}" \
        --delimiter='|' --with-nth=1,2 \
        --preview="$preview {}" --preview-window=right:45%:wrap \
        --prompt="$prompt > ")
    
    rm -f "$preview"
    
    [[ -n "$chon" ]] && xem_tap "$(echo "$chon" | cut -d'|' -f5)" "$(echo "$chon" | cut -d'|' -f1)"
}

xu_ly_v3() {
    echo "$1" | jq -r '.items[] | "\(.name)|\(.year // "N/A")|\(.country[0].name // "N/A")|\(.episode_current // "N/A")|\(.slug)|\(.poster_url)"' 2>/dev/null
}

xu_ly_v1() {
    echo "$1" | jq -r --arg cdn "$2" '.data.items[] | "\(.name)|\(.year // "N/A")|\(.country[0].name // "N/A")|\(.episode_current // "N/A")|\(.slug)|\($cdn)/\(.poster_url)"' 2>/dev/null
}

tao_script_tim_kiem() {
    local script="$CACHE/search_$$.sh"
    cat > "$script" << 'EOF'
#!/bin/bash
[[ -z "$1" || ${#1} -lt 2 ]] && exit 0
q="${1// /%20}"
res=$(curl -s --max-time 5 "https://phimapi.com/v1/api/tim-kiem?keyword=${q}&limit=20" 2>/dev/null)
[[ -z "$res" ]] && exit 0
cdn=$(echo "$res" | jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""')
echo "$res" | jq -r --arg cdn "$cdn" '.data.items[] | "\(.name)|\(.year // "N/A")|\(.country[0].name // "N/A")|\(.episode_current // "N/A")|\(.slug)|\($cdn)/\(.poster_url)"' 2>/dev/null
EOF
    chmod +x "$script"
    echo "$script"
}

tim_kiem() {
    local search=$(tao_script_tim_kiem)
    local preview=$(tao_script_xem_truoc)
    
    local chon=$(echo "" | fzf "${FZF_OPTS[@]}" \
        --prompt="🔍 TÌM > " --header="Nhập từ khóa..." --phony \
        --delimiter='|' --with-nth=1,2 \
        --bind "change:reload:sleep 0.2; $search {q} || true" \
        --preview="$preview {}" --preview-window=right:45%:wrap)
    
    rm -f "$search" "$preview"
    [[ -n "$chon" ]] && xem_tap "$(echo "$chon" | cut -d'|' -f5)" "$(echo "$chon" | cut -d'|' -f1)"
}

phim_moi() {
    dang_tai
    local res=$(goi_api "/danh-sach/phim-moi-cap-nhat-v3?page=1")
    [[ -z "$res" ]] && { thong_bao_loi "Lỗi kết nối"; return; }
    hien_thi_danh_sach "$(xu_ly_v3 "$res")" "PHIM MỚI"
}

duyet_phim() {
    local menu="󰎁  Phim Bộ|phim-bo
󰎁  Phim Lẻ|phim-le
󰎁  TV Shows|tv-shows
󰎁  Hoạt Hình|hoat-hinh"
    
    local chon=$(echo -e "$menu" | fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth=1 --prompt="DUYỆT > " --height=40%)
    [[ -z "$chon" ]] && return
    
    local loai=$(echo "$chon" | cut -d'|' -f2)
    dang_tai
    
    local res=$(goi_api "/v1/api/danh-sach/${loai}?page=1&limit=30&sort_field=modified.time&sort_type=desc")
    [[ -z "$res" ]] && { thong_bao_loi "Lỗi kết nối"; return; }
    
    local cdn=$(echo "$res" | jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""')
    local ten=$(echo "$chon" | cut -d'|' -f1 | sed 's/󰎁  //')
    hien_thi_danh_sach "$(xu_ly_v1 "$res" "$cdn")" "$ten"
}

loc_theo_the_loai() {
    dang_tai
    local res=$(goi_api "/the-loai")
    [[ -z "$res" ]] && { thong_bao_loi "Lỗi"; return; }
    
    local ds=$(echo "$res" | jq -r '.[] | "\(.name)|\(.slug)"' 2>/dev/null)
    local chon=$(echo "$ds" | fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth=1 --prompt="THỂ LOẠI > ")
    [[ -z "$chon" ]] && return
    
    local slug=$(echo "$chon" | cut -d'|' -f2)
    local ten=$(echo "$chon" | cut -d'|' -f1)
    dang_tai
    
    res=$(goi_api "/v1/api/the-loai/${slug}?page=1&limit=30&sort_field=modified.time&sort_type=desc")
    [[ -z "$res" ]] && { thong_bao_loi "Lỗi"; return; }
    
    local cdn=$(echo "$res" | jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""')
    hien_thi_danh_sach "$(xu_ly_v1 "$res" "$cdn")" "$ten"
}

loc_theo_quoc_gia() {
    dang_tai
    local res=$(goi_api "/quoc-gia")
    [[ -z "$res" ]] && { thong_bao_loi "Lỗi"; return; }
    
    local ds=$(echo "$res" | jq -r '.[] | "\(.name)|\(.slug)"' 2>/dev/null)
    local chon=$(echo "$ds" | fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth=1 --prompt="QUỐC GIA > ")
    [[ -z "$chon" ]] && return
    
    local slug=$(echo "$chon" | cut -d'|' -f2)
    local ten=$(echo "$chon" | cut -d'|' -f1)
    dang_tai
    
    res=$(goi_api "/v1/api/quoc-gia/${slug}?page=1&limit=30&sort_field=modified.time&sort_type=desc")
    [[ -z "$res" ]] && { thong_bao_loi "Lỗi"; return; }
    
    local cdn=$(echo "$res" | jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""')
    hien_thi_danh_sach "$(xu_ly_v1 "$res" "$cdn")" "$ten"
}

loc_theo_nam() {
    local nam_hien_tai=$(date +%Y)
    local ds=""
    for ((y=nam_hien_tai; y>=2000; y--)); do ds+="$y\n"; done
    
    local chon=$(echo -e "$ds" | fzf "${FZF_OPTS[@]}" --prompt="NĂM > " --height=50%)
    [[ -z "$chon" ]] && return
    
    dang_tai
    local res=$(goi_api "/v1/api/nam/${chon}?page=1&limit=30&sort_field=modified.time&sort_type=desc")
    [[ -z "$res" ]] && { thong_bao_loi "Lỗi"; return; }
    
    local cdn=$(echo "$res" | jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""')
    hien_thi_danh_sach "$(xu_ly_v1 "$res" "$cdn")" "Năm $chon"
}

loc_nang_cao() {
    local menu="  Thể Loại|theloai
  Quốc Gia|quocgia
  Năm|nam"
    
    local chon=$(echo -e "$menu" | fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth=1 --prompt="LỌC > " --height=40%)
    [[ -z "$chon" ]] && return
    
    case "$(echo "$chon" | cut -d'|' -f2)" in
        theloai) loc_theo_the_loai ;;
        quocgia) loc_theo_quoc_gia ;;
        nam)     loc_theo_nam ;;
    esac
}

lich_su() {
    [[ ! -s "$HIST" ]] && { thong_bao_loi "Chưa có lịch sử"; return; }
    
    local chon=$(sort -rn "$HIST" | fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth=2 --prompt="LỊCH SỬ > ")
    [[ -z "$chon" ]] && return
    
    mpv "$(echo "$chon" | cut -d'|' -f4)" --title="$(echo "$chon" | cut -d'|' -f2)" --force-window >/dev/null 2>&1 &
}

yeu_thich() {
    [[ ! -s "$FAV" ]] && { thong_bao_loi "Chưa có yêu thích"; return; }
    
    local chon=$(sort -u "$FAV" | fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth=1 \
        --prompt="YÊU THÍCH > " --expect=enter,ctrl-d \
        --preview="echo 'Enter: Xem | Ctrl-D: Xóa'" --preview-window=top:2:wrap)
    
    local phim=$(head -1 <<< "$chon")
    local data=$(tail -n +2 <<< "$chon")
    [[ -z "$data" ]] && return
    
    local slug=$(echo "$data" | cut -d'|' -f2)
    local ten=$(echo "$data" | cut -d'|' -f1)
    
    case "$phim" in
        enter)  xem_tap "$slug" "$ten" ;;
        ctrl-d) sed -i "/$slug/d" "$FAV" ;;
    esac
}

hien_banner() {
    clear
    echo ""
    echo -e "${C_Y} ⢀⣀⣀⣀⣀⣀⣀⣀⣀⣀${C_R}"
    echo -e "${C_Y} ⢀⣀⣠⣤⣴⣶⡶⢿⣿⣿⣿⠿⠿⠿⠿⠟⠛⢋⣁⣤⡴⠂⣠⡆${C_R}"
    echo -e "${C_Y} ⠈⠙⠻⢿⣿⣿⣿⣶⣤⣤⣤⣤⣤⣴⣶⣶⣿⣿⣿⡿⠋⣠⣾⣿${C_R}    ${C_G}Sudachi Player${C_R}"
    echo -e "${C_Y} ⢀⣴⣤⣄⡉⠛⠻⠿⠿⣿⣿⣿⣿⡿⠿⠟⠋⣁⣤⣾⣿⣿⣿${C_R}     ${C_C}Git: KabosuNeko${C_R}"
    echo -e "${C_Y} ⣠⣾⣿⣿⣿⣿⣶⣶⣤⣤⣤⣤⣤⣤⣶⣾⣿⣿⣿⣿⣿⣿⣿⡇${C_R}   ${C_C}Nguồn: PhimAPI${C_R}"
    echo -e "${C_Y} ⣰⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇${C_R}"
    echo -e "${C_Y} ⢰⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠁${C_R}"
    echo -e "${C_Y} ⢀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠇⢸⡟⢸⡟${C_R}"
    echo -e "${C_Y} ⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⢿⣷⡿⢿⡿⠁${C_R}"
    echo -e "${C_Y} ⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡟⢁⣴⠟⢀⣾⠃${C_R}"
    echo -e "${C_Y} ⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠛⣉⣿⠿⣿⣶⡟⠁${C_R}"
    echo -e "${C_Y} ⢿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠿⠛⣿⣏⣸⡿⢿⣯⣠⣴⠿⠋${C_R}"
    echo -e "${C_Y} ⢸⣿⣿⣿⣿⣿⣿⣿⣿⠿⠶⣾⣿⣉⣡⣤⣿⠿⠛⠁${C_R}"
    echo -e "${C_Y} ⢸⣿⣿⣿⣿⡿⠿⠿⠿⠶⠾⠛⠛⠛⠉⠁${C_R}"
    echo ""
}

menu_chinh() {
    echo -e "${I_SEARCH}Tìm Kiếm\n${I_NEW}Phim Mới\n${I_BROWSE}Duyệt Phim\n${I_FILTER}Lọc Nâng Cao\n${I_HIST}Lịch Sử\n${I_FAV}Yêu Thích\n${I_DIR}Mở Thư Mục\n${I_EXIT}Thoát" | \
        fzf "${FZF_OPTS[@]}" --prompt="MENU > " --height=50%
}

while true; do
    hien_banner
    case "$(menu_chinh)" in
        *"Tìm Kiếm"*)   tim_kiem ;;
        *"Phim Mới"*)   phim_moi ;;
        *"Duyệt Phim"*) duyet_phim ;;
        *"Lọc Nâng Cao"*) loc_nang_cao ;;
        *"Lịch Sử"*)    lich_su ;;
        *"Yêu Thích"*)  yeu_thich ;;
        *"Mở Thư Mục"*) thunar "$DL" 2>/dev/null || dolphin "$DL" 2>/dev/null || xdg-open "$DL" ;;
        *"Thoát"*)      exit 0 ;;
    esac
done