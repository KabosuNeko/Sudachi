#!/bin/bash
#
# Sudachi Player
# SPDX-License-Identifier: MIT
# 

CONF="$HOME/.config/sudachi"
DL="$HOME/Downloads/Sudachi-Downloaded"
HIST="$CONF/history.log"
FAV="$CONF/favorites.log"
PROGRESS="$CONF/progress.log"
CACHE="$CONF/cache"
SOURCE_FILE="$CONF/source.conf"
CONFIG_FILE="$CONF/config"
PLAYER_DEFAULT="mpv"
QUALITY=""

mkdir -p "$CONF" "$DL" "$CACHE"
[ ! -f "$HIST" ] && touch "$HIST"
[ ! -f "$FAV" ] && touch "$FAV"
[ ! -f "$PROGRESS" ] && touch "$PROGRESS"

API_SOURCE="ophim1"
API_PHIMAPI="https://phimapi.com"
API_NGUONC="https://phim.nguonc.com"
API_OPHIM1="https://ophim1.com"

[ -f "$SOURCE_FILE" ] && API_SOURCE=$(cat "$SOURCE_FILE")
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

I_SEARCH="󱇓 "
I_NEW="󰎁 "
I_BROWSE="󰖟 "
I_FILTER="󱄤 "
I_HIST="󰋚 "
I_FAV="󰋑 "
I_SOURCE="󰳏 "
I_PLAYER=" "
I_SETTINGS="󰒓 "
I_DIR=" "
I_EXIT="󰈆 "
I_ANIME=" "
I_QUA="󱤵 "

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


kiem_tra_phu_thuoc() {
    local missing=()
    command -v fzf &>/dev/null  || missing+=("fzf")
    command -v jq &>/dev/null   || missing+=("jq")
    command -v curl &>/dev/null || missing+=("curl")

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${C_Y}⚠ Thiếu các gói bắt buộc: ${missing[*]}${C_R}"
        echo -e "${C_C}Vui lòng cài đặt trước khi chạy Sudachi.${C_R}"
        echo -e "${C_C}  Arch:   sudo pacman -S ${missing[*]}${C_R}"
        echo -e "${C_C}  Debian: sudo apt install ${missing[*]}${C_R}"
        exit 1
    fi
}


cleanup() {
    rm -f "$CACHE"/preview_*.sh "$CACHE"/search_*.sh
}
trap cleanup EXIT SIGINT SIGTERM


ghi_debug() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$CACHE/debug.log"
}

get_base_url() {
    case "$API_SOURCE" in
        nguonc)  echo "$API_NGUONC" ;;
        phimapi) echo "$API_PHIMAPI" ;;
        *)       echo "$API_OPHIM1" ;;
    esac
}


goi_api() {
    local endpoint="$1"
    local base_url=$(get_base_url)
    local url="${base_url}${endpoint}"


    local cache_key=$(echo -n "$url" | md5sum | cut -d' ' -f1)
    local cache_file="$CACHE/${cache_key}.json"

    if [[ -f "$cache_file" ]]; then
        local age=$(find "$cache_file" -mmin -60 2>/dev/null)
        if [[ -n "$age" ]]; then
            cat "$cache_file"
            return
        else
            rm -f "$cache_file"
        fi
    fi


    local res attempt
    for attempt in 1 2 3; do
        res=$(curl -s --connect-timeout 10 --max-time 30 "$url" 2>/dev/null)
        if echo "$res" | jq -e . >/dev/null 2>&1 && ! echo "$res" | grep -q '"error"'; then
            echo "$res" > "$cache_file"
            echo "$res"
            return
        fi
        ghi_debug "goi_api attempt $attempt failed for $url"
        [[ $attempt -lt 3 ]] && sleep 1
    done

    ghi_debug "goi_api all 3 attempts failed for $url — response: $(echo "$res" | head -c 200)"
    return 1
}

kiem_tra_player() {
    local has_mpv=$(command -v mpv &>/dev/null && echo 1 || echo 0)
    local has_vlc=$(command -v vlc &>/dev/null && echo 1 || echo 0)
    
    if [[ -n "$PLAYER_DEFAULT" ]]; then
        if [[ "$PLAYER_DEFAULT" == "mpv" && $has_mpv -eq 1 ]] || \
           [[ "$PLAYER_DEFAULT" == "vlc" && $has_vlc -eq 1 ]]; then
            return 0
        fi
    fi
    
    if [[ $has_mpv -eq 1 ]]; then
        PLAYER_DEFAULT="mpv"
    elif [[ $has_vlc -eq 1 ]]; then
        PLAYER_DEFAULT="vlc"
    else
        echo -e "${C_Y}⚠ Không tìm thấy MPV hoặc VLC!${C_R}"
        echo -e "${C_C}Vui lòng cài đặt: sudo pacman -S mpv${C_R}"
        exit 1
    fi
}


play_video() {
    local url="$1"
    local title="$2"
    
    case "$PLAYER_DEFAULT" in
        vlc)
            local vlc_args=("$url" "--meta-title=$title" "--no-video-title-show")
            [[ -n "$QUALITY" ]] && vlc_args+=("--preferred-resolution=$QUALITY")
            vlc "${vlc_args[@]}" >/dev/null 2>&1 &
            ;;
        *)
            local mpv_args=("$url" "--title=$title" "--force-window")
            if [[ -n "$QUALITY" ]]; then
                mpv_args+=("--ytdl-format=bestvideo[height<=${QUALITY}]+bestaudio/best[height<=${QUALITY}]/best")
            fi
            mpv "${mpv_args[@]}" >/dev/null 2>&1 &
            ;;
    esac
}

dang_tai() { echo -e "${C_C} Đang tải...${C_R}"; }
thong_bao_loi() { echo -e "${C_Y}  $1${C_R}"; sleep 2; }


xu_ly_phimapi_v3() {
    echo "$1" | jq -r '.items[] | 
        (if .quality then " [" + .quality + (if .lang then "-" + .lang else "" end) + "]" else "" end) as $tag |
        "\(.name)|\(.year // "N/A")\($tag)|\(.country[0].name // "N/A")|\(.episode_current // "N/A")|\(.slug)|\(.poster_url)"' 2>/dev/null
}

xu_ly_phimapi_v1() {
    echo "$1" | jq -r --arg cdn "$2" '.data.items[] | 
        (if .quality then " [" + .quality + (if .lang then "-" + .lang else "" end) + "]" else "" end) as $tag |
        "\(.name)|\(.year // "N/A")\($tag)|\(.country[0].name // "N/A")|\(.episode_current // "N/A")|\(.slug)|\($cdn)/\(.poster_url)"' 2>/dev/null
}

xu_ly_nguonc() {
    echo "$1" | jq -r '.items[] | 
        (if .quality then " [" + .quality + (if .lang then "-" + .lang else "" end) + "]" else "" end) as $tag |
        "\(.name)|\(.year // "N/A")\($tag)|\(.country[0].name // "N/A")|\(.current_episode // "N/A")|\(.slug)|\(.thumb_url)"' 2>/dev/null
}

xu_ly_ophim1() {
    echo "$1" | jq -r --arg cdn "$2" '.data.items[] | 
        (if .quality then " [" + .quality + (if .lang then "-" + .lang else "" end) + "]" else "" end) as $tag |
        "\(.name)|\(.year // "N/A")\($tag)|\(.country[0].name // "N/A")|\(.episode_current // "N/A")|\(.slug)|\($cdn)/\(.poster_url)"' 2>/dev/null
}


tao_script_xem_truoc() {
    local script="$CACHE/preview_$$.sh"
    cat > "$script" << EOF
#!/bin/bash
IFS='|' read -r ten nam quocgia trangthai slug anh <<< "\$1"
source="$API_SOURCE"

echo -e "\033[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo -e "\033[1;33m  \${ten}\033[0m"
echo -e "\033[1;32m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo ""
[[ -n "\$nam" && "\$nam" != "null" ]] && echo -e "  \033[0;36m󰃰 Năm:\033[0m \$nam"
[[ -n "\$quocgia" && "\$quocgia" != "null" ]] && echo -e "  \033[0;36m󰇧 Quốc gia:\033[0m \$quocgia"
[[ -n "\$trangthai" && "\$trangthai" != "null" ]] && echo -e "  \033[0;36m󱖫 Trạng thái:\033[0m \$trangthai"
echo ""

img_url=""
if [[ "\$source" == "ophim1" && -n "\$slug" ]]; then
    img_res=\$(curl -s --max-time 3 "$API_OPHIM1/v1/api/phim/\${slug}/images" 2>/dev/null)
    if [[ -n "\$img_res" ]]; then
        img_url=\$(echo "\$img_res" | jq -r '(.data.images[] | select(.type=="poster") | .file_path) // .data.images[0].file_path // ""' 2>/dev/null | head -1)
        [[ -n "\$img_url" && "\$img_url" != "null" ]] && img_url="https://image.tmdb.org/t/p/w500\${img_url}"
    fi
fi

[[ -z "\$img_url" || "\$img_url" == "null" ]] && img_url="\$anh"


if [[ -n "\$img_url" && "\$img_url" != "null" ]]; then
    if command -v chafa &>/dev/null; then
        curl -s --max-time 5 "\$img_url" 2>/dev/null | chafa -s 35x18 - 2>/dev/null &
        wait
    fi
fi
EOF
    chmod +x "$script"
    echo "$script"
}


xem_tap() {
    local slug="$1" ten="$2"
    dang_tai
    
    local res ds_tap server_name

    case "$API_SOURCE" in
        nguonc)
            res=$(goi_api "/api/film/$slug")
            [[ -z "$res" ]] && { thong_bao_loi "Không lấy được thông tin"; return; }


            local server_count=$(echo "$res" | jq '.movie.episodes | length' 2>/dev/null)
            local server_idx=0

            if [[ "$server_count" -gt 1 ]]; then
                local server_list=$(echo "$res" | jq -r '.movie.episodes[] | .server_name' 2>/dev/null)
                server_name=$(echo "$server_list" | fzf "${FZF_OPTS[@]}" --prompt="SERVER > " --header="Chọn server" --height=40%)
                [[ -z "$server_name" ]] && return
                server_idx=$(echo "$res" | jq -r --arg sn "$server_name" '[.movie.episodes[].server_name] | to_entries[] | select(.value==$sn) | .key' 2>/dev/null | head -1)
            fi

            ds_tap=$(echo "$res" | jq -r --argjson idx "$server_idx" '.movie.episodes[$idx].items[] | "\(.name)|\(.embed)"' 2>/dev/null)
            [[ -z "$ds_tap" ]] && ds_tap=$(echo "$res" | jq -r --argjson idx "$server_idx" '.movie.episodes[$idx].items[] | "\(.name)|\(.m3u8)"' 2>/dev/null)
            ;;
        phimapi)
            res=$(goi_api "/phim/$slug")
            [[ -z "$res" ]] && { thong_bao_loi "Không lấy được thông tin"; return; }

            local server_count=$(echo "$res" | jq '.episodes | length' 2>/dev/null)
            local server_idx=0

            if [[ "$server_count" -gt 1 ]]; then
                local server_list=$(echo "$res" | jq -r '.episodes[] | .server_name' 2>/dev/null)
                server_name=$(echo "$server_list" | fzf "${FZF_OPTS[@]}" --prompt="SERVER > " --header="Chọn server" --height=40%)
                [[ -z "$server_name" ]] && return
                server_idx=$(echo "$res" | jq -r --arg sn "$server_name" '[.episodes[].server_name] | to_entries[] | select(.value==$sn) | .key' 2>/dev/null | head -1)
            fi

            ds_tap=$(echo "$res" | jq -r --argjson idx "$server_idx" '.episodes[$idx].server_data[] | "\(.name)|\(.link_m3u8)"' 2>/dev/null)
            ;;
        *)
            res=$(goi_api "/v1/api/phim/$slug")
            [[ -z "$res" ]] && { thong_bao_loi "Không lấy được thông tin"; return; }

            local server_count=$(echo "$res" | jq '.data.item.episodes | length' 2>/dev/null)
            local server_idx=0

            if [[ "$server_count" -gt 1 ]]; then
                local server_list=$(echo "$res" | jq -r '.data.item.episodes[] | .server_name' 2>/dev/null)
                server_name=$(echo "$server_list" | fzf "${FZF_OPTS[@]}" --prompt="SERVER > " --header="Chọn server" --height=40%)
                [[ -z "$server_name" ]] && return
                server_idx=$(echo "$res" | jq -r --arg sn "$server_name" '[.data.item.episodes[].server_name] | to_entries[] | select(.value==$sn) | .key' 2>/dev/null | head -1)
            fi

            ds_tap=$(echo "$res" | jq -r --argjson idx "$server_idx" '.data.item.episodes[$idx].server_data[] | "\(.name)|\(.link_m3u8)"' 2>/dev/null)
            ;;
    esac
    
    [[ -z "$ds_tap" ]] && { thong_bao_loi "Không có tập phim"; return; }


    local last_ep=""
    if [[ -f "$PROGRESS" ]]; then
        last_ep=$(grep "^${slug}|" "$PROGRESS" | tail -1 | cut -d'|' -f2)
    fi
    local continue_header=""
    [[ -n "$last_ep" ]] && continue_header="  ▶ Tiếp: Tập ${last_ep}"

    while true; do
        local chon=$(echo "$ds_tap" | fzf "${FZF_OPTS[@]}" \
            --header="󰟴 $ten${continue_header:+  │  }${continue_header}" --prompt="CHỌN TẬP > " \
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
                grep -v "^.*|.*|${slug}|" "$HIST" > "$HIST.tmp" && mv "$HIST.tmp" "$HIST"
                echo "$(date +%s)|$tieu_de|$slug|$url" >> "$HIST"

                grep -v "^${slug}|" "$PROGRESS" > "$PROGRESS.tmp" && mv "$PROGRESS.tmp" "$PROGRESS"
                echo "${slug}|${tap}" >> "$PROGRESS"
                continue_header="  ▶ Tiếp: Tập ${tap}"

                play_video "$url" "$tieu_de"
                ;;
            tab)
                local file=$(echo "$tieu_de" | sed 's/ /_/g; s/[^a-zA-Z0-9_.-]//g').mp4
                yt-dlp "$url" -o "$DL/$file" --downloader aria2c -N 8 >/dev/null 2>&1 &
                command -v notify-send >/dev/null && notify-send "Sudachi" " Đang tải: $tieu_de"
                ;;
            ctrl-f)
                if ! grep -q "|${slug}|" "$FAV" 2>/dev/null && ! grep -q "|${slug}$" "$FAV" 2>/dev/null; then
                    echo "$ten|$slug|${_fav_nam:-}|${_fav_anh:-}" >> "$FAV"
                fi
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
    
    if [[ -n "$chon" ]]; then
        _fav_nam=$(echo "$chon" | cut -d'|' -f2)
        _fav_anh=$(echo "$chon" | cut -d'|' -f6)
        xem_tap "$(echo "$chon" | cut -d'|' -f5)" "$(echo "$chon" | cut -d'|' -f1)"
    fi
}

hien_thi_danh_sach_phan_trang() {
    local prompt="$1"
    local fetch_callback="$2"
    local page=1
    local preview=$(tao_script_xem_truoc)
    
    while true; do
        local items=$($fetch_callback "$page")
        
        if [[ -z "$items" ]]; then
            if [[ $page -gt 1 ]]; then
                ((page--))
                continue
            fi
            thong_bao_loi "Không có kết quả"
            rm -f "$preview"
            return
        fi
        
        local output=$(echo "$items" | fzf "${FZF_OPTS[@]}" \
            --delimiter='|' --with-nth=1,2 \
            --preview="$preview {}" --preview-window=right:45%:wrap \
            --header="$prompt - Trang $page  |  ← → Chuyển trang" \
            --prompt="$prompt > " \
            --expect=right,left,enter)
        
        local key=$(echo "$output" | head -1)
        local chon=$(echo "$output" | tail -n +2)
        
        case "$key" in
            right)
                ((page++))
                continue
                ;;
            left)
                [[ $page -gt 1 ]] && ((page--))
                continue
                ;;
            enter|"")
                if [[ -n "$chon" ]]; then
                    rm -f "$preview"
                    _fav_nam=$(echo "$chon" | cut -d'|' -f2)
                    _fav_anh=$(echo "$chon" | cut -d'|' -f6)
                    xem_tap "$(echo "$chon" | cut -d'|' -f5)" "$(echo "$chon" | cut -d'|' -f1)"
                    return
                else
                    rm -f "$preview"
                    return
                fi
                ;;
        esac
    done
}


fetch_chung() {
    local loai="$1" p="$2" res cdn
    case "$API_SOURCE" in
        nguonc)
            res=$(goi_api "/api/films/${loai}?page=${p}")
            [[ -z "$res" ]] && return
            xu_ly_nguonc "$res"
            ;;
        phimapi)
            res=$(goi_api "/v1/api/${loai}?page=${p}&limit=30&sort_field=modified.time&sort_type=desc")
            [[ -z "$res" ]] && return
            cdn=$(echo "$res" | jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""')
            xu_ly_phimapi_v1 "$res" "$cdn"
            ;;
        *)
            res=$(goi_api "/v1/api/${loai}?page=${p}&limit=30&sort_field=modified.time&sort_type=desc")
            [[ -z "$res" ]] && return
            cdn=$(echo "$res" | jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""')
            xu_ly_ophim1 "$res" "$cdn"
            ;;
    esac
}

tao_script_tim_kiem() {
    local script="$CACHE/search_$$.sh"
    cat > "$script" << EOF
#!/bin/bash
[[ -z "\$1" || \${#1} -lt 2 ]] && exit 0
q="\${1// /%20}"
source="$API_SOURCE"

case "\$source" in
    nguonc)
        res=\$(curl -s --max-time 5 "$API_NGUONC/api/films/search?keyword=\${q}" 2>/dev/null)
        [[ -z "\$res" ]] && exit 0
        echo "\$res" | jq -r '.items[] | (if .quality then " [" + .quality + (if .lang then "-" + .lang else "" end) + "]" else "" end) as \$tag | "\(.name)|\(.year // "N/A")\(\$tag)|\(.country[0].name // "N/A")|\(.current_episode // "N/A")|\(.slug)|\(.thumb_url)"' 2>/dev/null
        ;;
    phimapi)
        res=\$(curl -s --max-time 5 "$API_PHIMAPI/v1/api/tim-kiem?keyword=\${q}&limit=20" 2>/dev/null)
        [[ -z "\$res" ]] && exit 0
        cdn=\$(echo "\$res" | jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""')
        echo "\$res" | jq -r --arg cdn "\$cdn" '.data.items[] | (if .quality then " [" + .quality + (if .lang then "-" + .lang else "" end) + "]" else "" end) as \$tag | "\(.name)|\(.year // "N/A")\(\$tag)|\(.country[0].name // "N/A")|\(.episode_current // "N/A")|\(.slug)|\(\$cdn)/\(.poster_url)"' 2>/dev/null
        ;;
    *)
        res=\$(curl -s --max-time 5 "$API_OPHIM1/v1/api/tim-kiem?keyword=\${q}&limit=20" 2>/dev/null)
        [[ -z "\$res" ]] && exit 0
        cdn=\$(echo "\$res" | jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""')
        echo "\$res" | jq -r --arg cdn "\$cdn" '.data.items[] | (if .quality then " [" + .quality + (if .lang then "-" + .lang else "" end) + "]" else "" end) as \$tag | "\(.name)|\(.year // "N/A")\(\$tag)|\(.country[0].name // "N/A")|\(.episode_current // "N/A")|\(.slug)|\(\$cdn)/\(.poster_url)"' 2>/dev/null
        ;;
esac
EOF
    chmod +x "$script"
    echo "$script"
}

tim_kiem() {
    local search=$(tao_script_tim_kiem)
    local preview=$(tao_script_xem_truoc)
    
    local chon=$(echo "" | fzf "${FZF_OPTS[@]}" \
        --prompt="󱇒 TÌM > " --header="Nhập từ khóa..." --phony \
        --delimiter='|' --with-nth=1,2 \
        --bind "change:reload:sleep 0.2; $search {q} || true" \
        --preview="$preview {}" --preview-window=right:45%:wrap)
    
    rm -f "$search" "$preview"
    [[ -n "$chon" ]] && xem_tap "$(echo "$chon" | cut -d'|' -f5)" "$(echo "$chon" | cut -d'|' -f1)"
}

phim_moi() {
    dang_tai
    local res items cdn
    
    case "$API_SOURCE" in
        nguonc)
            res=$(goi_api "/api/films/phim-moi-cap-nhat?page=1")
            [[ -z "$res" ]] && { thong_bao_loi "Lỗi kết nối"; return; }
            items=$(xu_ly_nguonc "$res")
            ;;
        phimapi)
            res=$(goi_api "/danh-sach/phim-moi-cap-nhat-v3?page=1")
            [[ -z "$res" ]] && { thong_bao_loi "Lỗi kết nối"; return; }
            items=$(xu_ly_phimapi_v3 "$res")
            ;;
        *)
            res=$(goi_api "/v1/api/home")
            [[ -z "$res" ]] && { thong_bao_loi "Lỗi kết nối"; return; }
            cdn=$(echo "$res" | jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""')
            items=$(xu_ly_ophim1 "$res" "$cdn")
            ;;
    esac
    
    hien_thi_danh_sach "$items" "PHIM MỚI"
}

duyet_phim() {
    local menu
    
    case "$API_SOURCE" in
        nguonc)
            menu="󰎁  Phim Đang Chiếu|phim-dang-chieu
󰎁  Phim Bộ|phim-bo
󰎁  Phim Lẻ|phim-le
󰎁  Hoạt Hình|hoat-hinh"
            ;;
        phimapi)
            menu="󰎁  Phim Bộ|phim-bo
󰎁  Phim Lẻ|phim-le
󰎁  TV Shows|tv-shows
󰎁  Hoạt Hình|hoat-hinh"
            ;;
        *)
            menu="󰎁  Phim Mới|phim-moi
󰎁  Phim Bộ|phim-bo
󰎁  Phim Lẻ|phim-le
󰎁  TV Shows|tv-shows
󰎁  Hoạt Hình|hoat-hinh
󰎁  Phim Chiếu Rạp|phim-chieu-rap
󰎁  Phim Vietsub|phim-vietsub
󰎁  Phim Thuyết Minh|phim-thuyet-minh"
            ;;
    esac
    
    local chon=$(echo -e "$menu" | fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth=1 --prompt="DUYỆT > " --height=50%)
    [[ -z "$chon" ]] && return
    
    local loai=$(echo "$chon" | cut -d'|' -f2)
    local ten=$(echo "$chon" | cut -d'|' -f1 | sed 's/󰎁  //')
    
    fetch_duyet_phim() {
        fetch_chung "danh-sach/${loai}" "$1"
    }
    
    hien_thi_danh_sach_phan_trang "$ten" fetch_duyet_phim
}


loc_theo_the_loai() {
    dang_tai
    local res ds
    
    case "$API_SOURCE" in
        nguonc)
            res=$(curl -s --max-time 5 "${API_NGUONC}/api/the-loai" 2>/dev/null)
            ds=$(echo "$res" | jq -r '.[] | "\(.name)|\(.slug)"' 2>/dev/null)

            if [[ -z "$ds" ]]; then
                ds="Hành Động|hanh-dong
Tình Cảm|tinh-cam
Hài Hước|hai-huoc
Kinh Dị|kinh-di
Viễn Tưởng|vien-tuong
Hoạt Hình|hoat-hinh
Phiêu Lưu|phieu-luu
Tâm Lý|tam-ly
Cổ Trang|co-trang
Võ Thuật|vo-thuat"
                ghi_debug "loc_theo_the_loai: nguonc API fallback to hardcoded"
            fi
            ;;
        phimapi)
            res=$(goi_api "/the-loai")
            [[ -z "$res" ]] && { thong_bao_loi "Lỗi"; return; }
            ds=$(echo "$res" | jq -r '.[] | "\(.name)|\(.slug)"' 2>/dev/null)
            ;;
        *)
            res=$(goi_api "/v1/api/the-loai")
            [[ -z "$res" ]] && { thong_bao_loi "Lỗi"; return; }
            ds=$(echo "$res" | jq -r '.data.items[] | "\(.name)|\(.slug)"' 2>/dev/null)
            ;;
    esac
    
    local chon=$(echo -e "$ds" | fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth=1 --prompt="THỂ LOẠI > ")
    [[ -z "$chon" ]] && return
    
    local slug=$(echo "$chon" | cut -d'|' -f2)
    local ten=$(echo "$chon" | cut -d'|' -f1)
    
    fetch_the_loai() {
        fetch_chung "the-loai/${slug}" "$1"
    }
    
    hien_thi_danh_sach_phan_trang "$ten" fetch_the_loai
}

loc_theo_quoc_gia() {
    dang_tai
    local res ds
    
    case "$API_SOURCE" in
        nguonc)
            res=$(curl -s --max-time 5 "${API_NGUONC}/api/quoc-gia" 2>/dev/null)
            ds=$(echo "$res" | jq -r '.[] | "\(.name)|\(.slug)"' 2>/dev/null)

            if [[ -z "$ds" ]]; then
                ds="Âu Mỹ|au-my
Hàn Quốc|han-quoc
Trung Quốc|trung-quoc
Nhật Bản|nhat-ban
Thái Lan|thai-lan
Việt Nam|viet-nam
Ấn Độ|an-do
Đài Loan|dai-loan
Hồng Kông|hong-kong
Philippines|philippines"
                ghi_debug "loc_theo_quoc_gia: nguonc API fallback to hardcoded"
            fi
            ;;
        phimapi)
            res=$(goi_api "/quoc-gia")
            [[ -z "$res" ]] && { thong_bao_loi "Lỗi"; return; }
            ds=$(echo "$res" | jq -r '.[] | "\(.name)|\(.slug)"' 2>/dev/null)
            ;;
        *)
            res=$(goi_api "/v1/api/quoc-gia")
            [[ -z "$res" ]] && { thong_bao_loi "Lỗi"; return; }
            ds=$(echo "$res" | jq -r '.data.items[] | "\(.name)|\(.slug)"' 2>/dev/null)
            ;;
    esac
    
    local chon=$(echo -e "$ds" | fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth=1 --prompt="QUỐC GIA > ")
    [[ -z "$chon" ]] && return
    
    local slug=$(echo "$chon" | cut -d'|' -f2)
    local ten=$(echo "$chon" | cut -d'|' -f1)
    
    fetch_quoc_gia() {
        fetch_chung "quoc-gia/${slug}" "$1"
    }
    
    hien_thi_danh_sach_phan_trang "$ten" fetch_quoc_gia
}

loc_theo_nam() {
    local nam_hien_tai=$(date +%Y)
    local ds=""
    for ((y=nam_hien_tai; y>=2000; y--)); do ds+="$y\n"; done
    
    local chon=$(echo -e "$ds" | fzf "${FZF_OPTS[@]}" --prompt="NĂM > " --height=50%)
    [[ -z "$chon" ]] && return
    
    local nam_chon="$chon"
    

    fetch_nam() {
        local p="$1"
        case "$API_SOURCE" in
            nguonc) fetch_chung "nam-phat-hanh/${nam_chon}" "$p" ;;
            phimapi)
                local res cdn
                res=$(goi_api "/v1/api/nam/${nam_chon}?page=${p}&limit=30&sort_field=modified.time&sort_type=desc")
                [[ -z "$res" ]] && return
                cdn=$(echo "$res" | jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""')
                xu_ly_phimapi_v1 "$res" "$cdn"
                ;;
            *)
                local res cdn
                res=$(goi_api "/v1/api/nam-phat-hanh/${nam_chon}?page=${p}&limit=30&sort_field=modified.time&sort_type=desc")
                [[ -z "$res" ]] && return
                cdn=$(echo "$res" | jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""')
                xu_ly_ophim1 "$res" "$cdn"
                ;;
        esac
    }
    
    hien_thi_danh_sach_phan_trang "Năm $chon" fetch_nam
}

che_do_anime() {

    fetch_anime() {
        local p="$1"
        case "$API_SOURCE" in
            nguonc) fetch_chung "quoc-gia/nhat-ban" "$p" ;;
            phimapi)
                local res cdn
                res=$(goi_api "/v1/api/danh-sach/hoat-hinh?page=${p}&country=nhat-ban&sort_field=modified.time&sort_type=desc")
                [[ -z "$res" ]] && return
                cdn=$(echo "$res" | jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""')
                xu_ly_phimapi_v1 "$res" "$cdn"
                ;;
            *)
                local res cdn
                res=$(goi_api "/v1/api/danh-sach/hoat-hinh?page=${p}&country=nhat-ban&sort_field=modified.time&sort_type=desc")
                [[ -z "$res" ]] && return
                cdn=$(echo "$res" | jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""')
                xu_ly_ophim1 "$res" "$cdn"
                ;;
        esac
    }

    hien_thi_danh_sach_phan_trang "Anime" fetch_anime
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
    
    play_video "$(echo "$chon" | cut -d'|' -f4)" "$(echo "$chon" | cut -d'|' -f2)"
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
        ctrl-d)
            grep -v "|${slug}|" "$FAV" | grep -v "|${slug}$" > "$FAV.tmp" && mv "$FAV.tmp" "$FAV"
            ;;
    esac
}

chon_nguon() {
    local phimapi_mark="" nguonc_mark="" ophim1_mark=""
    
    case "$API_SOURCE" in
        phimapi) phimapi_mark=" (đang dùng)" ;;
        nguonc)  nguonc_mark=" (đang dùng)" ;;
        *)       ophim1_mark=" (đang dùng)" ;;
    esac
    
    local menu="󱃾  Ophim1${ophim1_mark}|ophim1
󱃾  PhimAPI${phimapi_mark}|phimapi
󱃾  Nguonc${nguonc_mark}|nguonc"
    
    local chon=$(echo -e "$menu" | fzf "${FZF_OPTS[@]}" \
        --delimiter='|' --with-nth=1 --prompt="NGUỒN > " --height=40% \
        --header="Chọn nguồn dữ liệu phim")
    [[ -z "$chon" ]] && return
    
    local new_source=$(echo "$chon" | cut -d'|' -f2)


    if [[ "$new_source" != "$API_SOURCE" ]]; then
        rm -f "$CACHE"/*.json
        ghi_debug "Cache cleared: source switched from $API_SOURCE to $new_source"
    fi

    API_SOURCE="$new_source"
    echo "$API_SOURCE" > "$SOURCE_FILE"
}

chon_player() {
    local mpv_mark="" vlc_mark=""
    local has_mpv=$(command -v mpv &>/dev/null && echo 1 || echo 0)
    local has_vlc=$(command -v vlc &>/dev/null && echo 1 || echo 0)
    
    [[ "$PLAYER_DEFAULT" == "mpv" ]] && mpv_mark=" (đang dùng)"
    [[ "$PLAYER_DEFAULT" == "vlc" ]] && vlc_mark=" (đang dùng)"
    
    local menu=""
    [[ $has_mpv -eq 1 ]] && menu+="  MPV${mpv_mark} (Khuyên dùng)|mpv\n"
    [[ $has_vlc -eq 1 ]] && menu+="  VLC${vlc_mark}|vlc"
    
    [[ -z "$menu" ]] && { thong_bao_loi "Không có trình phát"; return; }
    
    local chon=$(echo -e "$menu" | fzf "${FZF_OPTS[@]}" \
        --delimiter='|' --with-nth=1 --prompt="TRÌNH PHÁT > " --height=40% \
        --header="Chọn trình phát mặc định")
    [[ -z "$chon" ]] && return
    
    PLAYER_DEFAULT=$(echo "$chon" | cut -d'|' -f2)
    echo "PLAYER_DEFAULT=\"$PLAYER_DEFAULT\"" > "$CONFIG_FILE"
    [[ -n "$QUALITY" ]] && echo "QUALITY=\"$QUALITY\"" >> "$CONFIG_FILE"
}


chon_chat_luong() {
    local current_mark_1080="" current_mark_720="" current_mark_480="" current_mark_auto=""
    
    case "$QUALITY" in
        1080) current_mark_1080=" (đang dùng)" ;;
        720)  current_mark_720=" (đang dùng)" ;;
        480)  current_mark_480=" (đang dùng)" ;;
        *)    current_mark_auto=" (đang dùng)" ;;
    esac
    
    local menu="  Auto (Tốt nhất)${current_mark_auto}|auto
  1080p (FHD)${current_mark_1080}|1080
  720p (HD)${current_mark_720}|720
  480p (SD)${current_mark_480}|480"
    
    local chon=$(echo -e "$menu" | fzf "${FZF_OPTS[@]}" \
        --delimiter='|' --with-nth=1 --prompt="CHẤT LƯỢNG > " --height=40% \
        --header="Chọn chất lượng phát")
    [[ -z "$chon" ]] && return
    
    local selected=$(echo "$chon" | cut -d'|' -f2)
    [[ "$selected" == "auto" ]] && QUALITY="" || QUALITY="$selected"
    
    echo "PLAYER_DEFAULT=\"$PLAYER_DEFAULT\"" > "$CONFIG_FILE"
    [[ -n "$QUALITY" ]] && echo "QUALITY=\"$QUALITY\"" >> "$CONFIG_FILE"
}

cai_dat() {
    local menu="${I_PLAYER}Chọn Trình Phát|player
${I_SOURCE}Đổi Nguồn|nguon
${I_QUA}Chất Lượng|quality
${I_DIR}Mở Thư Mục|folder"
    
    local chon=$(echo -e "$menu" | fzf "${FZF_OPTS[@]}" \
        --delimiter='|' --with-nth=1 --prompt="CÀI ĐẶT > " --height=40%)
    [[ -z "$chon" ]] && return
    
    case "$(echo "$chon" | cut -d'|' -f2)" in
        player)  chon_player ;;
        nguon)   chon_nguon ;;
        quality) chon_chat_luong ;;
        folder)  thunar "$DL" 2>/dev/null || dolphin "$DL" 2>/dev/null || xdg-open "$DL" ;;
    esac
}

hien_banner() {
    clear
    local nguon_text player_text quality_text
    case "$API_SOURCE" in
        nguonc)  nguon_text="Nguonc" ;;
        phimapi) nguon_text="PhimAPI" ;;
        *)       nguon_text="Ophim1" ;;
    esac
    case "$PLAYER_DEFAULT" in
        vlc) player_text="VLC" ;;
        *)   player_text="MPV" ;;
    esac
    case "$QUALITY" in
        1080) quality_text="1080p" ;;
        720)  quality_text="720p" ;;
        480)  quality_text="480p" ;;
        *)    quality_text="Auto" ;;
    esac
    
    echo ""
    echo -e "${C_G}             ⢀⣀⣀⣀⣀⣀⣀⣀⣀⣀${C_R}"
    echo -e "${C_G} ⢀⣀⣠⣤⣴⣶⡶⢿⣿⣿⣿⠿⠿⠿⠿⠟⠛⢋⣁⣤⡴⠂⣠⡆${C_R}"
    echo -e "${C_G} ⠈⠙⠻⢿⣿⣿⣿⣶⣤⣤⣤⣤⣤⣴⣶⣶⣿⣿⣿⡿⠋⣠⣾⣿${C_R}     ${C_Y}Sudachi Player${C_R}"
    echo -e "${C_G} ⢀⣴⣤⣄⡉⠛⠻⠿⠿⣿⣿⣿⣿⡿⠿⠟⠋⣁⣤⣾⣿⣿⣿${C_R}      ${C_C}Git: KabosuNeko${C_R}"
    echo -e "${C_G} ⣠⣾⣿⣿⣿⣿⣶⣶⣤⣤⣤⣤⣤⣤⣶⣾⣿⣿⣿⣿⣿⣿⣿⡇${C_R}     ${C_M}Nguồn: ${nguon_text}${C_R}"
    echo -e "${C_G} ⣰⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇${C_R}    ${C_C}Player: ${player_text} | ${quality_text}${C_R}"
    echo -e "${C_G} ⢰⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠁${C_R}"
    echo -e "${C_G}  ⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠇⢸⡟⢸⡟${C_R}"
    echo -e "${C_G} ⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⢿⣷⡿⢿⡿⠁${C_R}"
    echo -e "${C_G} ⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡟⢁⣴⠟⢀⣾⠃${C_R}"
    echo -e "${C_G} ⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠛⣉⣿⠿⣿⣶⡟⠁${C_R}"
    echo -e "${C_G} ⢿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠿⠛⣿⣏⣸⡿⢿⣯⣠⣴⠿⠋${C_R}"
    echo -e "${C_G} ⢸⣿⣿⣿⣿⣿⣿⣿⣿⠿⠶⣾⣿⣉⣡⣤⣿⠿⠛⠁${C_R}"
    echo -e "${C_G} ⢸⣿⣿⣿⣿⡿⠿⠿⠿⠶⠾⠛⠛⠛⠉⠁${C_R}"
    echo ""
}

menu_chinh() {
    echo -e "${I_SEARCH}Tìm Kiếm\n${I_NEW}Phim Mới\n${I_BROWSE}Duyệt Phim\n${I_ANIME}Anime\n${I_FILTER}Lọc Nâng Cao\n${I_HIST}Lịch Sử\n${I_FAV}Yêu Thích\n${I_SETTINGS}Cài Đặt\n${I_EXIT}Thoát" | \
        fzf "${FZF_OPTS[@]}" --prompt="MENU > " --height=50%
}


kiem_tra_phu_thuoc
kiem_tra_player

while true; do
    hien_banner
    case "$(menu_chinh)" in
        *"Tìm Kiếm"*)   tim_kiem ;;
        *"Phim Mới"*)   phim_moi ;;
        *"Duyệt Phim"*) duyet_phim ;;
        *"Anime"*)      che_do_anime ;;
        *"Lọc Nâng Cao"*) loc_nang_cao ;;
        *"Lịch Sử"*)    lich_su ;;
        *"Yêu Thích"*)  yeu_thich ;;
        *"Cài Đặt"*)    cai_dat ;;
        *"Thoát"*)      exit 0 ;;
    esac
done