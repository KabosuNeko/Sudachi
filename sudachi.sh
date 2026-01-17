#!/bin/bash

CONF="$HOME/.config/sudachi"
DL="$HOME/Downloads/Sudachi-Downloaded"
HIST="$CONF/history.log"
FAV="$CONF/favorites.log"

mkdir -p "$CONF" "$DL"
[ ! -f "$HIST" ] && touch "$HIST"
[ ! -f "$FAV" ] && touch "$FAV"

HOSTS=("https://phimapi.com" "https://ophim.cc")

I_SEARCH=" "
I_HIST=" "
I_FAV=" "
I_DIR=" "
I_EXIT=" "

C_G='\033[1;32m'
C_Y='\033[1;33m'
C_C='\033[0;36m'
C_R='\033[0m'

FZF_OPTS=(
    "--border=rounded" "--margin=5%,10%" "--padding=1"
    "--layout=reverse" "--pointer=" "--marker= "
    "--color=bg:-1,bg+:-1"
    "--color=fg:#d8dee9,fg+:#a3be8c,hl:#ebcb8b,hl+:#ebcb8b"
    "--color=border:#a3be8c,prompt:#81a1c1,pointer:#ebcb8b"
    "--color=info:#e5e9f0,header:#81a1c1"
)

req() {
    for h in "${HOSTS[@]}"; do
        r=$(curl -s --connect-timeout 5 "$h$1")
        echo "$r" | jq -e . >/dev/null 2>&1 && ! echo "$r" | grep -q "error" && echo "$r" && return 0
    done
    return 1
}

xem_tap() {
    slug=$1; title=$2
    echo -e "${C_C}Đang lấy danh sách tập...${C_R}"
    
    res=$(req "/phim/$slug")
    [ -z "$res" ] && return

    list=$(echo "$res" | jq -r '.episodes[0].server_data[] | "\(.name)|\(.link_m3u8)"')

    while true; do
        sel=$(echo "$list" | fzf "${FZF_OPTS[@]}" \
            --header="$title" --prompt="CHỌN TẬP > " --delimiter='|' --with-nth=1 \
            --preview="echo 'Enter: Xem | Tab: Tải | Ctrl-F: Lưu' && echo '-----------------' && echo {1}" \
            --preview-window=top:3:wrap --expect=enter,tab,ctrl-f)
        
        key=$(head -1 <<< "$sel"); data=$(tail -n +2 <<< "$sel")
        [ -z "$data" ] && break

        ep=$(echo "$data" | cut -d'|' -f1)
        url=$(echo "$data" | cut -d'|' -f2)
        full="${title} - Tập ${ep}"

        if [ "$key" == "enter" ]; then
            sed -i "/$slug/d" "$HIST"
            echo "$(date +%s)|$full|$slug|$url" >> "$HIST"
            mpv "$url" --title="$full" --force-window >/dev/null 2>&1 &
        
        elif [ "$key" == "tab" ]; then
            safe=$(echo "$full" | sed 's/ /_/g').mp4
            yt-dlp "$url" -o "$DL/$safe" --downloader aria2c -N 8 >/dev/null 2>&1 &
            command -v notify-send >/dev/null && notify-send "Sudachi" "Đang tải: $full"
        
        elif [ "$key" == "ctrl-f" ]; then
            echo "$title|$slug" >> "$FAV"
        fi
    done
}

tim_kiem() {
    echo -e "${C_Y}Nhập tên phim...${C_R}"
    q=$(echo "" | fzf "${FZF_OPTS[@]}" --prompt="TÌM KIẾM > " --print-query --height=20% | head -1)
    [ -z "$q" ] && return
    
    q_safe=${q// /%20}
    res=$(req "/v1/api/tim-kiem?keyword=$q_safe&limit=20")
    [ -z "$res" ] && return

    cdn=$(echo "$res" | jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""')
    items=$(echo "$res" | jq -r --arg cdn "$cdn" '.data.items[] | "\(.name)|\(.year)|\(.slug)|\($cdn)/\(.poster_url)"')
    
    sel=$(echo "$items" | fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth=1,2 \
        --preview "curl -s {4} | chafa -s 40x20 - 2>/dev/null" \
        --preview-window=right:50%:noborder --prompt="KẾT QUẢ > ")
    
    [ -n "$sel" ] && xem_tap "$(echo "$sel" | cut -d'|' -f3)" "$(echo "$sel" | cut -d'|' -f1)"
}

lich_su() {
    [ ! -s "$HIST" ] && return
    sel=$(sort -rn "$HIST" | fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth=2 --prompt="LỊCH SỬ > ")
    [ -n "$sel" ] && mpv "$(echo "$sel" | cut -d'|' -f4)" --force-window >/dev/null 2>&1 &
}

yeu_thich() {
    [ ! -s "$FAV" ] && return
    sel=$(sort -u "$FAV" | fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth=1 --prompt="YÊU THÍCH > ")
    [ -n "$sel" ] && xem_tap "$(echo "$sel" | cut -d'|' -f2)" "$(echo "$sel" | cut -d'|' -f1)"
}

while true; do
    clear
    echo -e "${C_Y} ⢀⣀⣀⣀⣀⣀⣀⣀⣀⣀${C_R}"
    echo -e "${C_Y} ⢀⣀⣠⣤⣴⣶⡶⢿⣿⣿⣿⠿⠿⠿⠿⠟⠛⢋⣁⣤⡴⠂⣠⡆${C_R}"
    echo -e "${C_Y} ⠈⠙⠻⢿⣿⣿⣿⣶⣤⣤⣤⣤⣤⣴⣶⣶⣿⣿⣿⡿⠋⣠⣾⣿${C_R}    ${C_G}Sudachi Player${C_R}"
    echo -e "${C_Y} ⢀⣴⣤⣄⡉⠛⠻⠿⠿⣿⣿⣿⣿⡿⠿⠟⠋⣁⣤⣾⣿⣿⣿${C_R}     ${C_C}Git: KabosuNeko${C_R}"
    echo -e "${C_Y} ⣠⣾⣿⣿⣿⣿⣿⣶⣶⣤⣤⣤⣤⣤⣤⣶⣾⣿⣿⣿⣿⣿⣿⣿⡇${C_R}   ${C_C}Nguồn: PhimAPI, Ophim${C_R}"
    echo -e "${C_Y} ⣰⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇${C_R}"
    echo -e "${C_Y} ⢰⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠁${C_R}"
    echo -e "${C_Y} ⢀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠇⢸⡟⢸⡟${C_R}"
    echo -e "${C_Y} ⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⢿⣷⡿⢿⡿⠁${C_R}"
    echo -e "${C_Y} ⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡟⢁⣴⠟⢀⣾⠃${C_R}"
    echo -e "${C_Y} ⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠛⣉⣿⠿⣿⣶⡟⠁${C_R}"
    echo -e "${C_Y} ⢿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠿⠛⣿⣏⣸⡿⢿⣯⣠⣴⠿⠋${C_R}"
    echo -e "${C_Y} ⢸⣿⣿⣿⣿⣿⣿⣿⣿⠿⠶⣾⣿⣉⣡⣤⣿⠿⠛⠁${C_R}"
    echo -e "${C_Y} ⢸⣿⣿⣿⣿⡿⠿⠿⠿⠶⠾⠛⠛⠛⠉⠁${C_R}"
    
    opt=$(echo -e "${I_SEARCH} Tìm Kiếm\n${I_HIST} Lịch Sử\n${I_FAV} Yêu Thich\n${I_DIR} Mở Thư Mục\n${I_EXIT} Thoát" | \
        fzf "${FZF_OPTS[@]}" --prompt="MENU > " --height=40%)
    
    case "$opt" in
        *"Tìm"*) tim_kiem ;;
        *"Lịch"*) lich_su ;;
        *"Yêu"*) yeu_thich ;;
        *"Mở"*) thunar "$DL" 2>/dev/null || dolphin "$DL" 2>/dev/null || xdg-open "$DL" ;;
        *"Thoát"*) exit 0 ;;
    esac
done