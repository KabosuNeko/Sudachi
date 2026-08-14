#!/bin/bash
# noqa: SIZE_OK — single-file architecture required by README curl one-liner install

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

TEMP_FILES=()
[ ! -f "$PROGRESS" ] && touch "$PROGRESS"

API_SOURCE="phimapi"
API_PHIMAPI="https://phimapi.com"
API_OPHIM1="https://ophim1.com"

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
I_CACHE="󰃢 "

C_G='\033[1;32m'
C_Y='\033[1;33m'
C_C='\033[0;36m'
C_M='\033[1;35m'
C_R='\033[0m'

load_settings() {
    local line key value raw_source

    if [[ -f "$SOURCE_FILE" ]]; then
        IFS= read -r raw_source < "$SOURCE_FILE" || raw_source=""
        case "$raw_source" in
            ophim1|phimapi) API_SOURCE="$raw_source" ;;
        esac
    fi

    [[ -f "$CONFIG_FILE" ]] || return

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
        [[ "$line" != *"="* ]] && continue

        key="${line%%=*}"
        value="${line#*=}"

        key="${key//[[:space:]]/}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"

        value="${value%\"}"
        value="${value#\"}"
        value="${value%\'}"
        value="${value#\'}"

        case "$key" in
            PLAYER_DEFAULT)
                case "$value" in
                    mpv|vlc) PLAYER_DEFAULT="$value" ;;
                esac
                ;;
            QUALITY)
                case "$value" in
                    1080|720|480) QUALITY="$value" ;;
                    auto|"") QUALITY="" ;;
                esac
                ;;
        esac
    done < "$CONFIG_FILE"
}

save_settings() {
    {
        printf 'PLAYER_DEFAULT=%s\n' "$PLAYER_DEFAULT"
        printf 'QUALITY=%s\n' "$QUALITY"
    } > "$CONFIG_FILE"
    printf '%s\n' "$API_SOURCE" > "$SOURCE_FILE"
}

add_menu_numbers() {
    awk '{printf "%d. %s\n", NR, $0}'
}

add_list_numbers() {
    awk '{printf "%d. |%s\n", NR, $0}'
}

FZF_OPTS=(
    "--border=bold"
    "--margin=2%,8%,3%,8%"
    "--padding=1,2"
    "--layout=reverse-list"
    "--info=inline"
    "--preview-window=right:45%:border-bold"

    "--pointer=█"
    "--marker=✓"
    "--ellipsis=…"

    "--color=bg:-1,bg+:-1,gutter:-1"
    "--color=fg:7,fg+:14"
    "--color=hl:1,hl+:3"
    "--color=border:8,label:14"
    "--color=prompt:4,pointer:14,marker:2"
    "--color=spinner:10,info:8,header:5"
    "--color=preview-fg:7,preview-border:8,preview-scrollbar:8"
    "--color=query:7"
)


check_dependencies() {
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
    for tmpfile in "${TEMP_FILES[@]}"; do
        [[ -f "$tmpfile" ]] && rm -f "$tmpfile"
    done
}

register_temp() {
    TEMP_FILES+=("$1")
}
trap cleanup EXIT SIGINT SIGTERM


log_debug() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$CACHE/debug.log"
}

hash_url() {
    local input="$1"

    if command -v md5sum >/dev/null 2>&1; then
        printf '%s' "$input" | md5sum | cut -d' ' -f1
        return
    fi

    if command -v md5 >/dev/null 2>&1; then
        printf '%s' "$input" | md5 -q
        return
    fi

    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$input" | sha256sum | cut -d' ' -f1
        return
    fi

    printf '%s' "$input" | cksum | cut -d' ' -f1
}

# HLS_AD_PATTERNS -- awk ERE alternation matching known ad-segment URIs in HLS
# playlists. Extendable: append new patterns separated by '|'.
HLS_AD_PATTERNS='convertv8/|^/v8/[0-9a-f]+/segment_'

# hls_absolutize_url <base> <uri> -- resolve a playlist URI against a base URL.
# Pure bash, no curl. Echoes: absolute uris as-is, root-relative uris prefixed
# with scheme://host of base, relative uris joined to the base directory, and
# an empty string for an empty uri.
hls_absolutize_url() {
    local base="$1" uri="$2" scheme rest host dir

    if [[ -z "$uri" ]]; then
        printf '%s' ''
        return
    fi

    case "$uri" in
        http://*|https://*)
            printf '%s' "$uri"
            ;;
        /*)
            scheme="${base%%://*}"
            rest="${base#*://}"
            host="${rest%%/*}"
            printf '%s://%s%s' "$scheme" "$host" "$uri"
            ;;
        *)
            scheme="${base%%://*}"
            rest="${base#*://}"
            dir="${rest%/*}"
            printf '%s://%s/%s' "$scheme" "$dir" "$uri"
            ;;
    esac
}

# hls_strip_ads <base> -- read a media playlist on stdin, write the filtered
# playlist to stdout. awk accumulates pending tag lines (EXT-X-DISCONTINUITY,
# EXT-X-KEY:METHOD=NONE, EXTINF); when the following segment URI matches
# HLS_AD_PATTERNS the pending tags and the URI are dropped (ad block removed),
# otherwise pending tags are flushed and the URI is absolutized via
# hls_absolutize_url. While inside a dropped ad block (indrop=1) further
# DISCONTINUITY/KEY:NONE tags are dropped too (closing brackets of the ad
# block) so the kept movie segments stay continuous. All other lines pass
# through verbatim.
hls_strip_ads() {
    local base="$1"

    awk -v adpat="$HLS_AD_PATTERNS" '
        {
            if ($0 ~ /^#EXT-X-DISCONTINUITY$/ || $0 ~ /^#EXT-X-KEY:METHOD=NONE/) {
                if (!indrop) pend[n++] = $0
                next
            }
            if ($0 ~ /^#EXTINF/) {
                pend[n++] = $0
                next
            }
            if ($0 !~ /^#/ && $0 != "") {
                if ($0 ~ adpat) {
                    n = 0
                    indrop = 1
                    next
                }
                indrop = 0
                for (i = 0; i < n; i++) print pend[i]
                n = 0
                print
                next
            }
            for (i = 0; i < n; i++) print pend[i]
            n = 0
            print
        }
        END {
            for (i = 0; i < n; i++) print pend[i]
        }
    ' | while IFS= read -r line; do
        if [[ "$line" != '#'* ]] && [[ -n "$line" ]]; then
            printf '%s\n' "$(hls_absolutize_url "$base" "$line")"
        else
            printf '%s\n' "$line"
        fi
    done
}

# hls_fetch_clean <url> -- fetch an HLS playlist (master or media), strip ad
# segments via hls_strip_ads, absolutize segment URIs, cache the result as
# $CACHE/<hash>-clean.m3u8 and echo its local path. If the fetched playlist is
# a master (contains #EXT-X-STREAM-INF) the first variant playlist is fetched
# instead. On ANY failure echoes the original url unchanged and returns 0
# (silent fallback: playback must never break).
hls_fetch_clean() {
    local url="$1" master variant media out tmp hash
    master=$(curl -fsS --connect-timeout 10 --max-time 10 "$url" 2>/dev/null) || {
        echo "$url"
        return 0
    }
    if printf '%s' "$master" | grep -q '^#EXT-X-STREAM-INF'; then
        variant=$(printf '%s\n' "$master" | awk '/^#EXT-X-STREAM-INF/{getline; print; exit}')
        media=$(hls_absolutize_url "$url" "$variant")
    else
        media="$url"
    fi
    [[ -z "$media" ]] && {
        echo "$url"
        return 0
    }
    out=$(curl -fsS --connect-timeout 10 --max-time 10 "$media" 2>/dev/null) || {
        echo "$url"
        return 0
    }
    [[ -z "$out" ]] && {
        echo "$url"
        return 0
    }
    hash=$(hash_url "$url")
    tmp="$CACHE/.tmp-$$.m3u8"
    if printf '%s\n' "$out" | hls_strip_ads "$media" > "$tmp"; then
        if mv -f "$tmp" "$CACHE/$hash-clean.m3u8" 2>/dev/null; then
            echo "$CACHE/$hash-clean.m3u8"
        else
            rm -f "$tmp"
            echo "$url"
            return 0
        fi
    else
        rm -f "$tmp"
        echo "$url"
        return 0
    fi
}

is_cache_fresh() {
    local file="$1" max_age="$2" now mtime

    printf -v now '%(%s)T' -1

    mtime=$(stat -c %Y "$file" 2>/dev/null) || mtime=$(stat -f %m "$file" 2>/dev/null) || return 1

    (( now - mtime < max_age ))
}

sanitize_field() {
    local value="$1"
    value="${value//$'\n'/ }"
    value="${value//$'\r'/ }"
    value="${value//|/-}"
    printf '%s' "$value"
}

get_base_url() {
    case "$API_SOURCE" in
        phimapi)   echo "$API_PHIMAPI" ;;
        *)         echo "$API_OPHIM1" ;;
    esac
}


call_api() {
    local endpoint="$1"
    local base_url=$(get_base_url)
    local url="${base_url}${endpoint}"


    local cache_key
    cache_key=$(hash_url "$url")
    local cache_file="$CACHE/${cache_key}.json"

    if [[ -f "$cache_file" ]]; then
        if is_cache_fresh "$cache_file" 3600; then
            cat "$cache_file"
            return
        else
            rm -f "$cache_file"
        fi
    fi


    local res attempt
    for attempt in 1 2 3; do
        res=$(curl -fsS --connect-timeout 10 --max-time 30 "$url" 2>/dev/null)
        if jq -e '(. != null) and (.status != "error") and (has("error") | not)' <<< "$res" >/dev/null 2>&1; then
            echo "$res" > "$cache_file"
            echo "$res"
            return
        fi
        log_debug "call_api attempt $attempt failed for $url"
        [[ $attempt -lt 3 ]] && sleep 1
    done

    log_debug "call_api all 3 attempts failed for $url — response: ${res:0:200}"
    return 1
}

record_history() {
    local slug="$1" title="$2" url="$3" tmp safe_title safe_url
    safe_title=$(sanitize_field "$title")
    safe_url=$(sanitize_field "$url")

    tmp=$(mktemp "$CACHE/history.XXXXXX") || return 1

    if ! awk -F'|' -v s="$slug" '$3 != s' "$HIST" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi

    printf -v now '%(%s)T' -1
    printf '%s|%s|%s|%s\n' "$now" "$safe_title" "$slug" "$safe_url" >> "$tmp"
    mv "$tmp" "$HIST"
}

record_progress() {
    local slug="$1" ep="$2" tmp
    tmp=$(mktemp "$CACHE/progress.XXXXXX") || return 1

    if ! awk -F'|' -v s="$slug" '$1 != s' "$PROGRESS" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi

    printf '%s|%s\n' "$slug" "$ep" >> "$tmp"
    mv "$tmp" "$PROGRESS"
}

add_favorite() {
    local title="$1" slug="$2" year="$3" poster="$4"
    local tmp
    local safe_title safe_year safe_poster
    safe_title=$(sanitize_field "$title")
    safe_year=$(sanitize_field "$year")
    safe_poster=$(sanitize_field "$poster")
    printf -v timestamp '%(%s)T' -1

    tmp=$(mktemp "$CACHE/favorites.XXXXXX") || return 1

    if ! awk -F'|' -v s="$slug" '{
        if ($2 == s || $3 == s) next
        print
    }' "$FAV" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi

    printf '%s|%s|%s|%s|%s\n' "$timestamp" "$safe_title" "$slug" "$safe_year" "$safe_poster" >> "$tmp"
    mv "$tmp" "$FAV"
}

remove_favorite() {
    local slug="$1"
    local tmp
    tmp=$(mktemp "$CACHE/favorites.XXXXXX") || return 1

    if ! awk -F'|' -v s="$slug" '{
        if ($2 == s || $3 == s) next
        print
    }' "$FAV" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi

    mv "$tmp" "$FAV"
}

download_episode() {
    local url="$1" title="$2" file

    if ! command -v yt-dlp >/dev/null 2>&1; then
        show_error "Thiếu yt-dlp để tải phim"
        return 1
    fi

    file="${title//[[:space:]]/_}"
    file="${file//[!a-zA-Z0-9_.-]/}.mp4"
    [[ "$file" == ".mp4" ]] && printf -v file 'sudachi_%(%s)T.mp4' -1

    if command -v aria2c >/dev/null 2>&1; then
        yt-dlp "$url" -o "$DL/$file" --downloader aria2c -N 8 >/dev/null 2>&1 &
    else
        yt-dlp "$url" -o "$DL/$file" >/dev/null 2>&1 &
    fi

    command -v notify-send >/dev/null 2>&1 && notify-send "Sudachi" " Đang tải: $title"
}

check_player() {
    local has_mpv=0; command -v mpv &>/dev/null && has_mpv=1
    local has_vlc=0; command -v vlc &>/dev/null && has_vlc=1

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
    local url="$1" title="$2"
    shift 2
    local extra_args=("$@")

    # HLS streams: strip mid-roll ad segments via hls_fetch_clean (falls back
    # to the original URL on any failure, so playback never breaks).
    if [[ "$url" == *".m3u8"* ]]; then
        url=$(hls_fetch_clean "$url")
    fi

    case "$PLAYER_DEFAULT" in
        vlc)
            local vlc_args=("$url" "--meta-title=$title" "--no-video-title-show" "${extra_args[@]}")
            [[ -n "$QUALITY" ]] && vlc_args+=("--preferred-resolution=$QUALITY")
            vlc "${vlc_args[@]}" >/dev/null 2>&1 &
            ;;
        *)
            local mpv_args=("$url" "--title=$title" "--force-window" "${extra_args[@]}")
            # Seekable demuxer cache for HLS: enables smooth seek on the
            # cleaned playlist. NOT --force-seekable=yes (breaks HLS, mpv#11990).
            if [[ "$url" == *".m3u8"* ]]; then
                mpv_args+=("--cache=yes")
                # Local cleaned playlist: ffmpeg hls demuxer restricts segment
                # protocols to file,crypto,data by default and refuses https
                # segments, stalling playback every few seconds. Force hls and
                # whitelist the segment protocols (mpv#14792).
                if [[ "$url" == /* ]]; then
                    mpv_args+=("--demuxer-lavf-format=hls")
                    mpv_args+=('--demuxer-lavf-o=protocol_whitelist="https,http,file,tcp,tls,crypto,data"')
                fi
            fi
            if [[ -n "$QUALITY" ]]; then
                mpv_args+=("--ytdl-format=bestvideo[height<=${QUALITY}]+bestaudio/best[height<=${QUALITY}]/best")
            fi
            mpv "${mpv_args[@]}" >/dev/null 2>&1 &
            ;;
    esac
}

show_loading() { echo -e "${C_C} Đang tải...${C_R}"; }
show_error() { echo -e "${C_Y}  $1${C_R}"; sleep 2; }


parse_phimapi_v3() {
    jq -r '.items[] |
        (if .quality then " [" + .quality + (if .lang then "-" + .lang else "" end) + "]" else "" end) as $tag |
        "\(.name)|\(.year // "N/A")\($tag)|\(.country[0].name // "N/A")|\(.episode_current // "N/A")|\(.slug)|\(.poster_url)"' <<< "$1" 2>/dev/null
}

parse_v1_items() {
    # Shared by phimapi and ophim1 — both return the same .data.items[] shape.
    jq -r --arg cdn "$2" '.data.items[] |
        (if .quality then " [" + .quality + (if .lang then "-" + .lang else "" end) + "]" else "" end) as $tag |
        "\(.name)|\(.year // "N/A")\($tag)|\(.country[0].name // "N/A")|\(.episode_current // "N/A")|\(.slug)|\($cdn)/\(.poster_url)"' <<< "$1" 2>/dev/null
}


create_preview_script() {
    local script
    script=$(mktemp "$CACHE/preview.XXXXXX.sh") || return 1
    register_temp "$script"
    cat > "$script" << EOF
#!/bin/bash
IFS='|' read -r ten nam quocgia trangthai slug anh <<< "\$1"
ten=\$(echo "\$ten" | sed 's/^[0-9]*\. //')
source="$API_SOURCE"

echo -e "\033[1;36m  \${ten}\033[0m"
echo -e "\033[1;30m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m"
echo ""
[[ -n "\$nam" && "\$nam" != "null" ]] && echo -e "  \033[0;35m󰃰 Năm:\033[0m \$nam"
[[ -n "\$quocgia" && "\$quocgia" != "null" ]] && echo -e "  \033[0;36m󰇧 Quốc gia:\033[0m \$quocgia"
[[ -n "\$trangthai" && "\$trangthai" != "null" ]] && echo -e "  \033[0;36m󱖫 Trạng thái:\033[0m \$trangthai"
echo ""

img_url="\$anh"
if [[ "\$source" == "ophim1" && -n "\$slug" ]]; then
    img_res=\$(curl -fsS --max-time 3 "${API_OPHIM1}/v1/api/phim/\${slug}/images" 2>/dev/null)
    if [[ -n "\$img_res" ]]; then
        tmdb_url=\$(echo "\$img_res" | jq -r '(.data.images[] | select(.type=="poster") | .file_path) // .data.images[0].file_path // ""' 2>/dev/null | head -1)
        [[ -n "\$tmdb_url" && "\$tmdb_url" != "null" ]] && img_url="https://image.tmdb.org/t/p/w500\${tmdb_url}"
    fi
fi

if [[ -n "\$img_url" && "\$img_url" != "null" ]]; then
    if command -v chafa &>/dev/null; then
        chafa_fmt="symbols"
        case "\$TERM" in
            st-*|st)   chafa_fmt="kitty" ;;
            xterm-kitty|kitty*) chafa_fmt="kitty" ;;
            foot*|contour|mlterm*|yaft*) chafa_fmt="sixel" ;;
        esac
        curl -fsS --max-time 5 "\$img_url" 2>/dev/null | chafa -f "\$chafa_fmt" -s 35x18 - 2>/dev/null &
        wait
    fi
fi
EOF
    chmod +x "$script"
    echo "$script"
}


pick_server() {
    local res="$1" episodes_path="$2"
    local idx=0

    local parsed name_list
    parsed=$(jq -r '
        ['${episodes_path}'[] | .server_name] as $names
        | ($names | length) as $count
        | "COUNT=\($count)", $names[]
    ' <<< "$res" 2>/dev/null) || return 1

    local count
    IFS= read -r count <<< "$parsed"
    count="${count#COUNT=}"

    if [[ "${count:-0}" -gt 1 ]]; then
        name_list="${parsed#*$'\n'}"
        local name
        name=$(add_menu_numbers <<< "$name_list" | fzf "${FZF_OPTS[@]}" --prompt="SERVER > " --header="Chọn server" --height=40%)
        [[ -z "$name" ]] && return 1
        name="${name#*. }"

        idx=0
        while IFS= read -r sn; do
            [[ "$sn" == "$name" ]] && { printf '%s\n' "$idx"; return; }
            ((idx++))
        done <<< "$name_list"
    fi

    printf '%s\n' "$idx"
}

watch_episode() {
    local slug="$1" ten="$2"

    show_loading

    local res ds_tap server_idx

    res=$(call_api "/phim/$slug")
    [[ -z "$res" ]] && { show_error "Không lấy được thông tin"; return; }

    server_idx=$(pick_server "$res" '.episodes') || return
    ds_tap=$(jq -r --argjson idx "$server_idx" '.episodes[$idx].server_data[] | "\(.name)|\(.link_m3u8)"' <<< "$res" 2>/dev/null)

    [[ -z "$ds_tap" ]] && { show_error "Không có tập phim"; return; }


    local last_ep=""
    if [[ -f "$PROGRESS" ]]; then
        last_ep=$(awk -F'|' -v s="$slug" '$1 == s {ep=$2} END {if (ep != "") print ep}' "$PROGRESS")
    fi
    local continue_header=""
    [[ -n "$last_ep" ]] && continue_header="  ▶ Tiếp: Tập ${last_ep}"

    local chon=""
    local phim=""
    local data=""

    while true; do
        chon=""
        phim=""
        data=""

        chon=$(fzf "${FZF_OPTS[@]}" \
            --header="󰟴 $ten${continue_header:+  │  }${continue_header}" --prompt="CHỌN TẬP > " \
            --delimiter='|' --with-nth=1 \
            --preview="echo 'Enter: Xem | Tab: Tải | Ctrl-F: Lưu'" \
            --preview-window=top:3:wrap --expect=enter,tab,ctrl-f <<< "$ds_tap")
        [[ -z "$chon" ]] && break

        IFS= read -r phim <<< "$chon"
        [[ "$chon" == *$'\n'* ]] && data="${chon#*$'\n'}"
        [[ -z "$data" ]] && break

    local tap="${data%%|*}"
    local url="${data#*|}"
        local tieu_de="${ten} - Tập ${tap}"

        case "$phim" in
            enter)
                record_history "$slug" "$tieu_de" "$url" || show_error "Không ghi được lịch sử"
                record_progress "$slug" "$tap" || show_error "Không ghi được tiến độ"
                continue_header="  ▶ Tiếp: Tập ${tap}"

                play_video "$url" "$tieu_de"
                ;;
            tab)
                download_episode "$url" "$tieu_de"
                ;;
            ctrl-f)
                add_favorite "$ten" "$slug" "" "" || show_error "Không lưu được yêu thích"
                ;;
        esac
    done
}

show_list() {
    local items="$1" prompt="$2"
    [[ -z "$items" ]] && { show_error "Không có kết quả"; return; }

    local preview
    preview=$(create_preview_script) || { show_error "Không tạo được preview"; return; }

        local chon=$(add_menu_numbers <<< "$items" | fzf "${FZF_OPTS[@]}" \
            --delimiter='|' --with-nth=1,2 \
            --preview="$preview {}" --preview-window=right:45%:wrap \
            --prompt="$prompt > ")

    rm -f "$preview"

    if [[ -n "$chon" ]]; then
        local arr=()
        IFS='|' read -ra arr <<< "$chon"
        watch_episode "${arr[4]}" "${arr[0]#*. }"
    fi
}

show_paginated_list() {
    local prompt="$1"
    local fetch_callback="$2"
    local page=1
    local preview
    preview=$(create_preview_script) || { show_error "Không tạo được preview"; return; }

    while true; do
        local items=$($fetch_callback "$page")

        if [[ -z "$items" ]]; then
            if [[ $page -gt 1 ]]; then
                ((page--))
                continue
            fi
            show_error "Không có kết quả"
            rm -f "$preview"
            return
        fi

        local output=$(add_menu_numbers <<< "$items" | fzf "${FZF_OPTS[@]}" \
            --delimiter='|' --with-nth=1,2 \
            --preview="$preview {}" --preview-window=right:45%:wrap \
            --header="$prompt - Trang $page  |  ← → Chuyển trang" \
            --prompt="$prompt > " \
            --expect=right,left,enter)

        local key chon
        IFS= read -r key <<< "$output"
        [[ "$output" == *$'\n'* ]] && chon="${output#*$'\n'}"

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
                rm -f "$preview"
                if [[ -n "$chon" ]]; then
                    local arr=()
                    IFS='|' read -ra arr <<< "$chon"
                    watch_episode "${arr[4]}" "${arr[0]#*. }"
                fi
                return
                ;;
        esac
    done
}


fetch_list() {
    local loai="$1" p="$2" res cdn
    res=$(call_api "/v1/api/${loai}?page=${p}&limit=30&sort_field=modified.time&sort_type=desc")
    [[ -z "$res" ]] && return
    cdn=$(jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""' <<< "$res")
    parse_v1_items "$res" "$cdn"
}

create_search_script() {
    local script
    script=$(mktemp "$CACHE/search.XXXXXX.sh") || return 1
    register_temp "$script"
    cat > "$script" << EOF
#!/bin/bash
[[ -z "\$1" || \${#1} -lt 2 ]] && exit 0
q=\$(jq -rn --arg q "\$1" '\$q|@uri' 2>/dev/null) || exit 0
source="$API_SOURCE"

case "\$source" in
    phimapi) base="${API_PHIMAPI}" ;;
    *)       base="${API_OPHIM1}" ;;
esac
res=\$(curl -fsS --max-time 5 "\${base}/v1/api/tim-kiem?keyword=\${q}&limit=20" 2>/dev/null)
[[ -z "\$res" ]] && exit 0
cdn=\$(echo "\$res" | jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""')
echo "\$res" | jq -r --arg cdn "\$cdn" '.data.items[] | (if .quality then " [" + .quality + (if .lang then "-" + .lang else "" end) + "]" else "" end) as \$tag | "\(.name)|\(.year // "N/A")\(\$tag)|\(.country[0].name // "N/A")|\(.episode_current // "N/A")|\(.slug)|\(\$cdn)/\(.poster_url)"' 2>/dev/null
EOF
    chmod +x "$script"
    echo "$script"
}

search() {

    local search preview
    search=$(create_search_script) || { show_error "Không tạo được script tìm kiếm"; return; }
    preview=$(create_preview_script) || { rm -f "$search"; show_error "Không tạo được preview"; return; }

    local chon=$(echo "" | fzf "${FZF_OPTS[@]}" \
        --prompt="󱇒 TÌM > " --header="Nhập từ khóa..." --phony \
        --delimiter='|' --with-nth=1,2 \
        --bind "change:reload:sleep 0.2; $search {q} | awk '{printf \"%d. %s\\n\", NR, \$0}' || true" \
        --preview="$preview {}" --preview-window=right:45%:wrap)

    rm -f "$search" "$preview"
    if [[ -n "$chon" ]]; then
        local arr=()
        IFS='|' read -ra arr <<< "$chon"
        watch_episode "${arr[4]}" "${arr[0]#*. }"
    fi
}

new_releases() {
    case "$API_SOURCE" in
        phimapi)
            show_loading
            local res
            res=$(call_api "/danh-sach/phim-moi-cap-nhat-v3?page=1")
            [[ -z "$res" ]] && { show_error "Lỗi kết nối"; return; }
            show_list "$(parse_phimapi_v3 "$res")" "PHIM MỚI"
            ;;
        *)
            show_loading
            local res cdn
            res=$(call_api "/v1/api/danh-sach/phim-moi-cap-nhat-v3?page=1")
            [[ -z "$res" ]] && { show_error "Lỗi kết nối"; return; }
            cdn=$(jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""' <<< "$res")
            show_list "$(parse_v1_items "$res" "$cdn")" "PHIM MỚI"
            ;;
    esac
}

browse() {
    local menu

    case "$API_SOURCE" in
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

    local chon=$(echo -e "$menu" | add_menu_numbers | fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth=1 --prompt="DUYỆT > " --height=50%)
    [[ -z "$chon" ]] && return

    local loai="${chon#*|}"
    local ten_raw="${chon%%|*}"
    local ten="${ten_raw#*. }"

    fetch_browse() {
        fetch_list "danh-sach/${loai}" "$1"
    }

    show_paginated_list "$ten" fetch_browse
}


filter_by_genre() {
    show_loading
    local res ds

    res=$(call_api "/the-loai")
    [[ -z "$res" ]] && { show_error "Lỗi"; return; }
    ds=$(jq -r '.[] | "\(.name)|\(.slug)"' <<< "$res" 2>/dev/null)

    local chon=$(echo -e "$ds" | add_menu_numbers | fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth=1 --prompt="THỂ LOẠI > ")
    [[ -z "$chon" ]] && return

    local slug="${chon#*|}"
    local ten_raw="${chon%%|*}"
    local ten="${ten_raw#*. }"

    fetch_genre() {
        fetch_list "the-loai/${slug}" "$1"
    }

    show_paginated_list "$ten" fetch_genre
}

filter_by_country() {
    show_loading
    local res ds

    res=$(call_api "/quoc-gia")
    [[ -z "$res" ]] && { show_error "Lỗi"; return; }
    ds=$(jq -r '.[] | "\(.name)|\(.slug)"' <<< "$res" 2>/dev/null)

    local chon=$(echo -e "$ds" | add_menu_numbers | fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth=1 --prompt="QUỐC GIA > ")
    [[ -z "$chon" ]] && return

    local slug="${chon#*|}"
    local ten_raw="${chon%%|*}"
    local ten="${ten_raw#*. }"

    fetch_country() {
        fetch_list "quoc-gia/${slug}" "$1"
    }

    show_paginated_list "$ten" fetch_country
}

filter_by_year() {
    local nam_hien_tai=${CURRENT_YEAR:-$(date +%Y)}
    local ds="" y
    for ((y = nam_hien_tai; y >= 2000; y--)); do
        ds+="$y"$'\n'
    done
    ds="${ds%$'\n'}"

    local chon=$(echo -e "$ds" | add_menu_numbers | fzf "${FZF_OPTS[@]}" --prompt="NĂM > " --height=50%)
    [[ -z "$chon" ]] && return

    local nam_chon="${chon#*. }"


    fetch_year() {
        fetch_list "nam/${nam_chon}" "$1"
    }

    show_paginated_list "Năm $nam_chon" fetch_year
}

anime_mode() {

    fetch_anime() {
        local p="$1"
        local res cdn
        res=$(call_api "/v1/api/danh-sach/hoat-hinh?page=${p}&country=nhat-ban&sort_field=modified.time&sort_type=desc")
        [[ -z "$res" ]] && return
        cdn=$(jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""' <<< "$res")
        parse_v1_items "$res" "$cdn"
    }

    show_paginated_list "Anime" fetch_anime
}

advanced_filter() {
    local menu="  Thể Loại|theloai
  Quốc Gia|quocgia
  Năm|nam"

    local chon=$(echo -e "$menu" | add_menu_numbers | fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth=1 --prompt="LỌC > " --height=40%)
    [[ -z "$chon" ]] && return

    case "${chon#*|}" in
        theloai) filter_by_genre ;;
        quocgia) filter_by_country ;;
        nam)     filter_by_year ;;
    esac
}

history() {
    [[ ! -s "$HIST" ]] && { show_error "Chưa có lịch sử"; return; }

    local chon=$(sort -rn "$HIST" | add_list_numbers | fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth=1,3 --prompt="LỊCH SỬ > ")
    [[ -z "$chon" ]] && return
    chon="${chon#*| }"
    IFS='|' read -r _ slug _ url _ <<< "$chon"
    play_video "$url" "$slug"
}


favorites() {
    [[ ! -s "$FAV" ]] && { show_error "Chưa có yêu thích"; return; }

    local parsed_favs
    # Old favorites lacked a poster field (4 fields). Skip them silently.
    # Current format has 5 fields: timestamp|title|slug|year|poster.
    parsed_favs=$(awk -F'|' '{
        if (NF >= 5) print
    }' "$FAV" | sort -t'|' -k1,1rn | awk '{ sub(/^[^|]*[|]/, ""); print }')

    [[ -z "$parsed_favs" ]] && { show_error "Chưa có yêu thích"; return; }

    local chon=$(fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth=1 \
        --prompt="YÊU THÍCH > " --expect=enter,ctrl-d \
        --preview="echo 'Enter: Xem | Ctrl-D: Xóa'" --preview-window=top:2:wrap <<< "$parsed_favs")

    local phim data
    IFS= read -r phim <<< "$chon"
    [[ "$chon" == *$'\n'* ]] && data="${chon#*$'\n'}"
    [[ -z "$data" ]] && return

    local slug="${data#*|}"
    local ten="${data%%|*}"

    case "$phim" in
        enter)  watch_episode "$slug" "$ten" ;;
        ctrl-d)
            remove_favorite "$slug" || show_error "Không xóa được yêu thích"
            ;;
    esac
}

check_source_status() {
    local url="$1"
    curl -fsS --max-time 2 --head "$url" &>/dev/null && echo "✓" || echo "✗"
}

select_source() {
    local phimapi_mark="" ophim1_mark=""

    case "$API_SOURCE" in
        phimapi)   phimapi_mark=" (đang dùng)" ;;
        *)         ophim1_mark=" (đang dùng)" ;;
    esac

    echo -e "${C_C} Kiểm tra kết nối nguồn...${C_R}"
    local st_ophim st_phimapi
    st_ophim=$(check_source_status "$API_OPHIM1")
    st_phimapi=$(check_source_status "$API_PHIMAPI")

    local menu="󱃾  Ophim ${st_ophim}${ophim1_mark}|ophim1
󱃾  PhimAPI ${st_phimapi}${phimapi_mark}|phimapi"

    local chon=$(echo -e "$menu" | add_menu_numbers | fzf "${FZF_OPTS[@]}" \
        --delimiter='|' --with-nth=1 --prompt="NGUỒN > " --height=40% \
        --header="Chọn nguồn dữ liệu phim")
    [[ -z "$chon" ]] && return

    local new_source="${chon#*|}"

    if [[ "$new_source" != "$API_SOURCE" ]]; then
        rm -f "$CACHE"/*.json
        log_debug "Cache cleared: source switched from $API_SOURCE to $new_source"
    fi

    API_SOURCE="$new_source"
    save_settings
}

select_player() {
    local mpv_mark="" vlc_mark=""
    local has_mpv=$(command -v mpv &>/dev/null && echo 1 || echo 0)
    local has_vlc=$(command -v vlc &>/dev/null && echo 1 || echo 0)

    [[ "$PLAYER_DEFAULT" == "mpv" ]] && mpv_mark=" (đang dùng)"
    [[ "$PLAYER_DEFAULT" == "vlc" ]] && vlc_mark=" (đang dùng)"

    local menu=""
    [[ $has_mpv -eq 1 ]] && menu+="  MPV${mpv_mark} (Khuyên dùng)|mpv\n"
    [[ $has_vlc -eq 1 ]] && menu+="  VLC${vlc_mark}|vlc"

    [[ -z "$menu" ]] && { show_error "Không có trình phát"; return; }

    local chon=$(echo -e "$menu" | add_menu_numbers | fzf "${FZF_OPTS[@]}" \
        --delimiter='|' --with-nth=1 --prompt="TRÌNH PHÁT > " --height=40% \
        --header="Chọn trình phát mặc định")
    [[ -z "$chon" ]] && return

    PLAYER_DEFAULT="${chon#*|}"
    save_settings
}


select_quality() {
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

    local chon=$(echo -e "$menu" | add_menu_numbers | fzf "${FZF_OPTS[@]}" \
        --delimiter='|' --with-nth=1 --prompt="CHẤT LƯỢNG > " --height=40% \
        --header="Chọn chất lượng phát")
    [[ -z "$chon" ]] && return

    local selected="${chon#*|}"
    [[ "$selected" == "auto" ]] && QUALITY="" || QUALITY="$selected"

    save_settings
}

clear_cache() {
    local json_files=("$CACHE"/*.json)
    local count=0
    for f in "${json_files[@]}"; do
        [[ -f "$f" ]] && ((count++))
    done
    rm -f "$CACHE"/*.json
    log_debug "Cache cleared manually: $count files removed"
    echo -e "${C_G}  Đã xóa ${count} file cache.${C_R}"
    sleep 1
}

settings() {
    local menu="Chọn Trình Phát ${I_PLAYER}|player
Đổi Nguồn ${I_SOURCE}|nguon
Chất Lượng ${I_QUA}|quality
Mở Thư Mục ${I_DIR}|folder
Xóa Cache ${I_CACHE}|cache"

    local chon=$(echo -e "$menu" | add_menu_numbers | fzf "${FZF_OPTS[@]}" \
        --delimiter='|' --with-nth=1 --prompt="CÀI ĐẶT > " --height=40%)
    [[ -z "$chon" ]] && return

    case "${chon#*|}" in
        player)  select_player ;;
        nguon)   select_source ;;
        quality) select_quality ;;
        folder)  thunar "$DL" 2>/dev/null || dolphin "$DL" 2>/dev/null || xdg-open "$DL" ;;
        cache)   clear_cache ;;
    esac
}

show_banner() {
    printf '\033[H\033[2J'
    local nguon_text player_text quality_text
    case "$API_SOURCE" in
        phimapi)   nguon_text="PhimAPI" ;;
        *)         nguon_text="Ophim" ;;
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
}

main_menu() {
    local menu_items=""

    menu_items+="Tìm Kiếm ${I_SEARCH}\n"
    menu_items+="Phim Mới ${I_NEW}\n"
    menu_items+="Duyệt Phim ${I_BROWSE}\n"
    menu_items+="Anime ${I_ANIME}\n"
    menu_items+="Lọc Nâng Cao ${I_FILTER}\n"
    menu_items+="Lịch Sử ${I_HIST}\n"
    menu_items+="Yêu Thích ${I_FAV}\n"
    menu_items+="Cài Đặt ${I_SETTINGS}\n"
    menu_items+="Thoát ${I_EXIT}"

    echo -e "$menu_items" | add_menu_numbers | fzf "${FZF_OPTS[@]}" --prompt="MENU > " --height=50%
}


load_settings
check_dependencies
check_player

while true; do
    show_banner
    case "$(main_menu)" in
        *"Tìm Kiếm"*)   search ;;
        *"Phim Mới"*)   new_releases ;;
        *"Duyệt Phim"*) browse ;;
        *"Anime"*)      anime_mode ;;
        *"Lọc Nâng Cao"*) advanced_filter ;;
        *"Lịch Sử"*)    history ;;
        *"Yêu Thích"*)  favorites ;;
        *"Cài Đặt"*)    settings ;;
        *"Thoát"*)      exit 0 ;;
    esac
done
