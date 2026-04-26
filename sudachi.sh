#!/bin/bash

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

API_SOURCE="ophim1"
API_PHIMAPI="https://phimapi.com"
API_NGUONC="https://phim.nguonc.com"
API_OPHIM1="https://ophim1.com"
API_ANIMAPPER="https://api.animapper.net/api/v1"

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
            ophim1|phimapi|nguonc|animapper) API_SOURCE="$raw_source" ;;
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

strip_menu_number() {
    sed 's/^[0-9]*\. //'
}

add_list_numbers() {
    awk '{printf "%d. |%s\n", NR, $0}'
}

strip_list_number() {
    sed 's/^[0-9]*\. |//'
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

is_cache_fresh() {
    local file="$1" max_age="$2" now mtime

    now=$(date +%s)

    if mtime=$(stat -c %Y "$file" 2>/dev/null); then
        :
    elif mtime=$(stat -f %m "$file" 2>/dev/null); then
        :
    else
        return 1
    fi

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
        nguonc)    echo "$API_NGUONC" ;;
        phimapi)   echo "$API_PHIMAPI" ;;
        animapper) echo "$API_ANIMAPPER" ;;
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
        if echo "$res" | jq -e . >/dev/null 2>&1 && ! echo "$res" | jq -e '.status == "error" or has("error")' >/dev/null 2>&1; then
            echo "$res" > "$cache_file"
            echo "$res"
            return
        fi
        log_debug "call_api attempt $attempt failed for $url"
        [[ $attempt -lt 3 ]] && sleep 1
    done

    log_debug "call_api all 3 attempts failed for $url — response: $(echo "$res" | head -c 200)"
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

    printf '%s|%s|%s|%s\n' "$(date +%s)" "$safe_title" "$slug" "$safe_url" >> "$tmp"
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
    local timestamp=$(date +%s)

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

    file=$(echo "$title" | sed 's/[[:space:]]\+/_/g; s/[^[:alnum:]_.-]//g').mp4
    [[ -z "$file" || "$file" == ".mp4" ]] && file="sudachi_$(date +%s).mp4"

    if command -v aria2c >/dev/null 2>&1; then
        yt-dlp "$url" -o "$DL/$file" --downloader aria2c -N 8 >/dev/null 2>&1 &
    else
        yt-dlp "$url" -o "$DL/$file" >/dev/null 2>&1 &
    fi

    command -v notify-send >/dev/null 2>&1 && notify-send "Sudachi" " Đang tải: $title"
}

check_player() {
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
    local url="$1" title="$2"
    shift 2
    local extra_args=("$@")

    case "$PLAYER_DEFAULT" in
        vlc)
            local vlc_args=("$url" "--meta-title=$title" "--no-video-title-show" "${extra_args[@]}")
            [[ -n "$QUALITY" ]] && vlc_args+=("--preferred-resolution=$QUALITY")
            vlc "${vlc_args[@]}" >/dev/null 2>&1 &
            ;;
        *)
            local mpv_args=("$url" "--title=$title" "--force-window" "${extra_args[@]}")
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
    echo "$1" | jq -r '.items[] | 
        (if .quality then " [" + .quality + (if .lang then "-" + .lang else "" end) + "]" else "" end) as $tag |
        "\(.name)|\(.year // "N/A")\($tag)|\(.country[0].name // "N/A")|\(.episode_current // "N/A")|\(.slug)|\(.poster_url)"' 2>/dev/null
}

parse_v1_items() {
    # Shared by phimapi and ophim1 — both return the same .data.items[] shape.
    echo "$1" | jq -r --arg cdn "$2" '.data.items[] |
        (if .quality then " [" + .quality + (if .lang then "-" + .lang else "" end) + "]" else "" end) as $tag |
        "\(.name)|\(.year // "N/A")\($tag)|\(.country[0].name // "N/A")|\(.episode_current // "N/A")|\(.slug)|\($cdn)/\(.poster_url)"' 2>/dev/null
}

parse_nguonc() {
    echo "$1" | jq -r '.items[] |
        (if .quality then " [" + .quality + (if .lang then "-" + .lang else "" end) + "]" else "" end) as $tag |
        "\(.name)|\(.year // "N/A")\($tag)|\(.country[0].name // "N/A")|\(.current_episode // "N/A")|\(.slug)|\(.thumb_url)"' 2>/dev/null
}



call_animapper() {
    local endpoint="$1"
    local url="${API_ANIMAPPER}${endpoint}"

    log_debug "call_animapper: URL=$url"

    local cache_key
    cache_key=$(hash_url "$url")
    local cache_file="$CACHE/animapper_${cache_key}.json"

    if [[ -f "$cache_file" ]]; then
        if is_cache_fresh "$cache_file" 3600; then
            log_debug "call_animapper: returning cached result"
            cat "$cache_file"
            return
        else
            rm -f "$cache_file"
        fi
    fi

    local res attempt
    for attempt in 1 2 3; do
        local max_time=30
        if [[ "$endpoint" == *"/stream/episodes"* ]]; then
            max_time=45
        elif [[ "$endpoint" == *"/stream/source"* ]]; then
            max_time=60
        fi

        res=$(curl -fsS --connect-timeout 10 --max-time "$max_time" "$url" 2>/dev/null)
        local curl_exit=$?
        log_debug "call_animapper: attempt $attempt, curl_exit=$curl_exit, response length=${#res}"

        if [[ $curl_exit -ne 0 ]]; then
            log_debug "call_animapper: curl failed with exit code $curl_exit"
            [[ $attempt -lt 3 ]] && sleep 2
            continue
        fi

        if echo "$res" | jq -e '.' >/dev/null 2>&1; then
            if echo "$res" | jq -e '.success == false' >/dev/null 2>&1; then
                log_debug "call_animapper: API returned success=false"
                echo "$res"
                return 1
            fi

            echo "$res" > "$cache_file"
            echo "$res"
            return 0
        fi

        log_debug "call_animapper attempt $attempt failed for $url (invalid JSON)"
        [[ $attempt -lt 3 ]] && sleep 1
    done

    log_debug "call_animapper all 3 attempts failed for $url"
    return 1
}

animapper_search() {
    local res="$1"
    echo "$res" | jq -r '.results[] | 
        (if .status then " [" + .status + "]" else "" end) as $status_tag |
        "\(.titles.vi // .titles.en // .titles.ja // "N/A")|\(.seasonYear // "N/A")\($status_tag)|\(.format // "N/A")|\(.totalUnits // "?")|\(.id)|\(.images.coverLg // "")"' 2>/dev/null
}

animapper_get_metadata() {
    local media_id="$1"
    call_animapper "/metadata?id=${media_id}"
}

animapper_pick_provider() {
    local metadata_res="$1"
    local providers_json
    providers_json=$(echo "$metadata_res" | jq -r '.result.streamingProviders // {}' 2>/dev/null)

    log_debug "animapper_pick_provider: providers_json=$providers_json"

    if [[ "$providers_json" == "{}" || -z "$providers_json" ]]; then
        log_debug "animapper_pick_provider: no providers available"
        return 1
    fi

    local provider_list
    provider_list=$(echo "$providers_json" | jq -r 'keys[]' 2>/dev/null)
    if [[ -z "$provider_list" ]]; then
        log_debug "animapper_pick_provider: empty provider list after parsing"
        return 1
    fi

    log_debug "animapper_pick_provider: available providers: $provider_list"

    local provider_count
    provider_count=$(echo "$provider_list" | wc -l)

    if [[ "$provider_count" -eq 1 ]]; then
        log_debug "animapper_pick_provider: auto-selecting single provider: $provider_list"
        echo "$provider_list"
        return 0
    fi

    local header_text="Chọn provider streaming (ANIMEVIETSUB có thể chậm)"

    local selected
    selected=$(echo "$provider_list" | add_menu_numbers | fzf "${FZF_OPTS[@]}" \
        --prompt="PROVIDER > " --header="$header_text" --height=40%)
    [[ -z "$selected" ]] && return 1

    echo "$selected" | strip_menu_number
}

animapper_get_episodes() {
    local media_id="$1"
    local provider="$2"
    call_animapper "/stream/episodes?id=${media_id}&provider=${provider}&limit=100"
}

animapper_get_source() {
    local episode_data="$1"
    local provider="$2"
    local server="$3"

    local encoded_data
    encoded_data=$(jq -rn --arg d "$episode_data" '$d|@uri' 2>/dev/null) || encoded_data="$episode_data"

    if [[ -n "$server" ]]; then
        call_animapper "/stream/source?episodeData=${encoded_data}&provider=${provider}&server=${server}"
    else
        call_animapper "/stream/source?episodeData=${encoded_data}&provider=${provider}"
    fi
}



watch_episode_animapper() {
    local media_id="$1" ten="$2"
    show_loading

    log_debug "watch_episode_animapper: media_id=$media_id, title=$ten"

    local metadata_res provider_name episodes_res ds_tap

    metadata_res=$(animapper_get_metadata "$media_id")
    [[ -z "$metadata_res" ]] && { show_error "Không lấy được thông tin anime"; return; }

    provider_name=$(animapper_pick_provider "$metadata_res")
    if [[ -z "$provider_name" ]]; then
        local anime_title
        anime_title=$(echo "$metadata_res" | jq -r '.result.titles.vi // .result.titles.en // "Anime"' 2>/dev/null)
        show_error "Anime '${anime_title}' chưa có provider nào được mapping"
        log_debug "watch_episode_animapper: no providers for media_id=$media_id"
        return
    fi

    log_debug "watch_episode_animapper: selected provider=$provider_name"

    echo -e "${C_C} Đang tải danh sách tập từ ${provider_name}...${C_R}"

    episodes_res=$(animapper_get_episodes "$media_id" "$provider_name")
    local episodes_exit=$?

    log_debug "watch_episode_animapper: episodes_res raw length=${#episodes_res}, exit=$episodes_exit"

    if [[ -z "$episodes_res" ]] || [[ $episodes_exit -ne 0 ]]; then
        show_error "Không lấy được danh sách tập từ ${provider_name} (timeout hoặc lỗi)"
        return
    fi

    if echo "$episodes_res" | jq -e '.success == false' >/dev/null 2>&1; then
        local err_msg
        err_msg=$(echo "$episodes_res" | jq -r '.message // "Unknown error"' 2>/dev/null)
        log_debug "watch_episode_animapper: API error: $err_msg"
        show_error "Lỗi API ${provider_name}: $err_msg"
        return
    fi

    local total_episodes
    total_episodes=$(echo "$episodes_res" | jq -r '.total // 0' 2>/dev/null)

    ds_tap=$(echo "$episodes_res" | jq -r '.episodes[] | "\(.episodeNumber)|\(.episodeId)|\(.server)"' 2>/dev/null)

    local has_next_page
    has_next_page=$(echo "$episodes_res" | jq -r '.hasNextPage // false' 2>/dev/null)
    local offset=0

    if [[ "$has_next_page" == "true" ]] && [[ -n "$ds_tap" ]]; then
        log_debug "watch_episode_animapper: more episodes available, fetching with pagination"

        local all_episodes="$ds_tap"
        offset=100

        while [[ "$has_next_page" == "true" ]] && [[ $offset -lt 500 ]]; do
            local more_episodes
            more_episodes=$(call_animapper "/stream/episodes?id=${media_id}&provider=${provider_name}&limit=100&offset=${offset}")

            if [[ -n "$more_episodes" ]]; then
                local page_episodes
                page_episodes=$(echo "$more_episodes" | jq -r '.episodes[] | "\(.episodeNumber)|\(.episodeId)|\(.server)"' 2>/dev/null)
                if [[ -n "$page_episodes" ]]; then
                    all_episodes="$all_episodes
$page_episodes"
                fi
                has_next_page=$(echo "$more_episodes" | jq -r '.hasNextPage // false' 2>/dev/null)
                offset=$((offset + 100))
            else
                break
            fi
        done

        ds_tap="$all_episodes"
    fi

    if [[ -z "$ds_tap" ]]; then
        show_error "Không có tập phim nào từ ${provider_name}"
        return
    fi

    local last_ep=""
    if [[ -f "$PROGRESS" ]]; then
        last_ep=$(awk -F'|' -v s="$media_id" '$1 == s {ep=$2} END {if (ep != "") print ep}' "$PROGRESS")
    fi
    local continue_header=""
    [[ -n "$last_ep" ]] && continue_header="  ▶ Tiếp: Tập ${last_ep}"

    log_debug "watch_episode_animapper: total=$total_episodes, last_ep=$last_ep"

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
        local episode_id=$(echo "$data" | cut -d'|' -f2)

        local tieu_de="${ten} - Tập ${tap}"

        log_debug "watch_episode_animapper: selected tap=$tap, episode_id=$episode_id"

        show_loading
        local source_res source_exit stream_url stream_type
        # Do not pass $server — episodes[].server is the fansub group (e.g. AnimeVsub),
        # not a streaming server name (DU/HDX). Let AniMapper auto-select.
        source_res=$(animapper_get_source "$episode_id" "$provider_name")
        source_exit=$?

        if [[ -z "$source_res" ]] || [[ $source_exit -ne 0 ]]; then
            show_error "Không lấy được nguồn phát (timeout hoặc lỗi kết nối)"
            continue
        fi

        if echo "$source_res" | jq -e '.success == false' >/dev/null 2>&1; then
            local err_msg err_code
            err_msg=$(echo "$source_res" | jq -r '.message // "Unknown error"' 2>/dev/null)
            err_code=$(echo "$source_res" | jq -r '.code // "UNKNOWN"' 2>/dev/null)
            log_debug "watch_episode_animapper: source API error: $err_code - $err_msg"
            show_error "Lỗi nguồn phát ${provider_name}: [$err_code] $err_msg"
            continue
        fi

        stream_url=$(echo "$source_res" | jq -r '.url // empty' 2>/dev/null)
        stream_type=$(echo "$source_res" | jq -r '.type // "HLS"' 2>/dev/null)

        [[ -z "$stream_url" ]] && { show_error "Không có URL phát"; continue; }

        log_debug "watch_episode_animapper: stream_url=$stream_url, type=$stream_type"

        case "$phim" in
            enter)
                record_history "$media_id" "$tieu_de" "$stream_url" || show_error "Không ghi được lịch sử"
                record_progress "$media_id" "$tap" || show_error "Không ghi được tiến độ"
                continue_header="  ▶ Tiếp: Tập ${tap}"

                if [[ "$stream_type" == "HLS" && "$stream_url" == *"/api/v1/stream/source/m3u8/"* ]]; then
                    local proxy_headers
                    proxy_headers=$(echo "$source_res" | jq -r '.proxyHeaders // {}' 2>/dev/null)
                    play_animapper_hls "$stream_url" "$tieu_de" "$proxy_headers"
                else
                    play_video "$stream_url" "$tieu_de"
                fi
                ;;
            tab)
                download_episode "$stream_url" "$tieu_de"
                ;;
            ctrl-f)
                add_favorite "$ten" "$media_id" "" "" || show_error "Không lưu được yêu thích"
                ;;
        esac
    done
}


play_animapper_hls() {
    local stream_url="$1" title="$2" proxy_headers="$3"

    local cache_key real_m3u8_url extra_headers=()
    cache_key=$(basename "$stream_url")
    real_m3u8_url="${API_ANIMAPPER}/stream/source/m3u8/${cache_key}"

    if [[ "$proxy_headers" != "{}" && -n "$proxy_headers" ]]; then
        local referer
        referer=$(echo "$proxy_headers" | jq -r '.Referer // empty' 2>/dev/null)
        [[ -n "$referer" ]] && extra_headers+=("--referrer=$referer")
    fi

    play_video "$real_m3u8_url" "$title" "${extra_headers[@]}"
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

img_url=""
if [[ "\$source" == "ophim1" && -n "\$slug" ]]; then
    img_res=\$(curl -fsS --max-time 3 "$API_OPHIM1/v1/api/phim/\${slug}/images" 2>/dev/null)
    if [[ -n "\$img_res" ]]; then
        img_url=\$(echo "\$img_res" | jq -r '(.data.images[] | select(.type=="poster") | .file_path) // .data.images[0].file_path // ""' 2>/dev/null | head -1)
        [[ -n "\$img_url" && "\$img_url" != "null" ]] && img_url="https://image.tmdb.org/t/p/w500\${img_url}"
    fi
fi

[[ -z "\$img_url" || "\$img_url" == "null" ]] && img_url="\$anh"


if [[ -n "\$img_url" && "\$img_url" != "null" ]]; then
    if command -v chafa &>/dev/null; then
        chafa_fmt="symbols"
        case "\$TERM" in
            st-*|st) chafa_fmt="kitty" ;;
            xterm-kitty|kitty*) chafa_fmt="kitty" ;;
        esac
        curl -fsS --max-time 5 "\$img_url" 2>/dev/null | chafa -f "\$chafa_fmt" -s 35x18 - 2>/dev/null &
        wait
    fi
fi
EOF
    chmod +x "$script"
    echo "$script"
}


# Prompt user to pick a server when multiple are available.
# Arguments: JSON response, jq path to the episodes array.
# Outputs: server index (0-based) to stdout. Returns 1 on cancel.
pick_server() {
    local res="$1" episodes_path="$2"
    local count idx=0

    count=$(echo "$res" | jq "${episodes_path} | length" 2>/dev/null)
    if [[ "${count:-0}" -gt 1 ]]; then
        local list name
        list=$(echo "$res" | jq -r "${episodes_path}[] | .server_name" 2>/dev/null)
        name=$(echo "$list" | add_menu_numbers | fzf "${FZF_OPTS[@]}" --prompt="SERVER > " --header="Chọn server" --height=40%)
        [[ -z "$name" ]] && return 1
        name=$(echo "$name" | strip_menu_number)
        idx=$(echo "$res" | jq -r --arg sn "$name" "[${episodes_path}[].server_name] | to_entries[] | select(.value==\$sn) | .key" 2>/dev/null | head -1)
        [[ -z "$idx" ]] && idx=0
    fi

    printf '%s\n' "$idx"
}

watch_episode() {
    local slug="$1" ten="$2"

    if [[ "$API_SOURCE" == "animapper" ]]; then
        watch_episode_animapper "$slug" "$ten"
        return
    fi

    show_loading

    local res ds_tap server_idx

    case "$API_SOURCE" in
        nguonc)
            res=$(call_api "/api/film/$slug")
            [[ -z "$res" ]] && { show_error "Không lấy được thông tin"; return; }

            server_idx=$(pick_server "$res" '.movie.episodes') || return
            ds_tap=$(echo "$res" | jq -r --argjson idx "$server_idx" '.movie.episodes[$idx].items[] | "\(.name)|\(.embed)"' 2>/dev/null)
            [[ -z "$ds_tap" ]] && ds_tap=$(echo "$res" | jq -r --argjson idx "$server_idx" '.movie.episodes[$idx].items[] | "\(.name)|\(.m3u8)"' 2>/dev/null)
            ds_tap=$(echo "$ds_tap" | awk -F'|' '$2 != "" && $2 != "null"')
            ;;
        phimapi)
            res=$(call_api "/phim/$slug")
            [[ -z "$res" ]] && { show_error "Không lấy được thông tin"; return; }

            server_idx=$(pick_server "$res" '.episodes') || return
            ds_tap=$(echo "$res" | jq -r --argjson idx "$server_idx" '.episodes[$idx].server_data[] | "\(.name)|\(.link_m3u8)"' 2>/dev/null)
            ;;
        *)
            res=$(call_api "/v1/api/phim/$slug")
            [[ -z "$res" ]] && { show_error "Không lấy được thông tin"; return; }

            server_idx=$(pick_server "$res" '.data.item.episodes') || return
            ds_tap=$(echo "$res" | jq -r --argjson idx "$server_idx" '.data.item.episodes[$idx].server_data[] | "\(.name)|\(.link_m3u8)"' 2>/dev/null)
            ;;
    esac
    
    [[ -z "$ds_tap" ]] && { show_error "Không có tập phim"; return; }


    local last_ep=""
    if [[ -f "$PROGRESS" ]]; then
        last_ep=$(awk -F'|' -v s="$slug" '$1 == s {ep=$2} END {if (ep != "") print ep}' "$PROGRESS")
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

    local chon=$(echo "$items" | add_menu_numbers | fzf "${FZF_OPTS[@]}" \
        --delimiter='|' --with-nth=1,2 \
        --preview="$preview {}" --preview-window=right:45%:wrap \
        --prompt="$prompt > ")

    rm -f "$preview"

    if [[ -n "$chon" ]]; then
        watch_episode "$(echo "$chon" | cut -d'|' -f5)" "$(echo "$chon" | cut -d'|' -f1 | strip_menu_number)"
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
        
        local output=$(echo "$items" | add_menu_numbers | fzf "${FZF_OPTS[@]}" \
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
                    watch_episode "$(echo "$chon" | cut -d'|' -f5)" "$(echo "$chon" | cut -d'|' -f1 | strip_menu_number)"
                    return
                else
                    rm -f "$preview"
                    return
                fi
                ;;
        esac
    done
}


fetch_list() {
    local loai="$1" p="$2" res cdn
    case "$API_SOURCE" in
        nguonc)
            res=$(call_api "/api/films/${loai}?page=${p}")
            [[ -z "$res" ]] && return
            parse_nguonc "$res"
            ;;
        phimapi)
            res=$(call_api "/v1/api/${loai}?page=${p}&limit=30&sort_field=modified.time&sort_type=desc")
            [[ -z "$res" ]] && return
            cdn=$(echo "$res" | jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""')
            parse_v1_items "$res" "$cdn"
            ;;
        *)
            res=$(call_api "/v1/api/${loai}?page=${p}&limit=30&sort_field=modified.time&sort_type=desc")
            [[ -z "$res" ]] && return
            cdn=$(echo "$res" | jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""')
            parse_v1_items "$res" "$cdn"
            ;;
    esac
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
    nguonc)
        res=\$(curl -fsS --max-time 5 "$API_NGUONC/api/films/search?keyword=\${q}" 2>/dev/null)
        [[ -z "\$res" ]] && exit 0
        echo "\$res" | jq -r '.items[] | (if .quality then " [" + .quality + (if .lang then "-" + .lang else "" end) + "]" else "" end) as \$tag | "\(.name)|\(.year // "N/A")\(\$tag)|\(.country[0].name // "N/A")|\(.current_episode // "N/A")|\(.slug)|\(.thumb_url)"' 2>/dev/null
        ;;
    phimapi)
        res=\$(curl -fsS --max-time 5 "$API_PHIMAPI/v1/api/tim-kiem?keyword=\${q}&limit=20" 2>/dev/null)
        [[ -z "\$res" ]] && exit 0
        cdn=\$(echo "\$res" | jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""')
        echo "\$res" | jq -r --arg cdn "\$cdn" '.data.items[] | (if .quality then " [" + .quality + (if .lang then "-" + .lang else "" end) + "]" else "" end) as \$tag | "\(.name)|\(.year // "N/A")\(\$tag)|\(.country[0].name // "N/A")|\(.episode_current // "N/A")|\(.slug)|\(\$cdn)/\(.poster_url)"' 2>/dev/null
        ;;
    *)
        res=\$(curl -fsS --max-time 5 "$API_OPHIM1/v1/api/tim-kiem?keyword=\${q}&limit=20" 2>/dev/null)
        [[ -z "\$res" ]] && exit 0
        cdn=\$(echo "\$res" | jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""')
        echo "\$res" | jq -r --arg cdn "\$cdn" '.data.items[] | (if .quality then " [" + .quality + (if .lang then "-" + .lang else "" end) + "]" else "" end) as \$tag | "\(.name)|\(.year // "N/A")\(\$tag)|\(.country[0].name // "N/A")|\(.episode_current // "N/A")|\(.slug)|\(\$cdn)/\(.poster_url)"' 2>/dev/null
        ;;
esac
EOF
    chmod +x "$script"
    echo "$script"
}

create_animapper_search_script() {
    local script
    script=$(mktemp "$CACHE/search_animapper.XXXXXX.sh") || return 1
    register_temp "$script"
    cat > "$script" << EOF
#!/bin/bash
API_ANIMAPPER="$API_ANIMAPPER"
[[ -z "\$1" || \${#1} -lt 2 ]] && exit 0
q=\$(jq -rn --arg q "\$1" '\$q|@uri' 2>/dev/null) || exit 0

res=\$(curl -fsS --max-time 5 "\${API_ANIMAPPER}/search?title=\${q}&mediaType=ANIME&limit=20" 2>/dev/null)
[[ -z "\$res" ]] && exit 0

echo "\$res" | jq -r '.results[] |
    (if .status then " [" + .status + "]" else "" end) as \$status_tag |
    "\(.titles.vi // .titles.en // .titles.ja // "N/A")|\(.seasonYear // "N/A")\(\$status_tag)|\(.format // "N/A")|\(.totalUnits // "?")|\(.id)|\(.images.coverLg // "")"' 2>/dev/null
EOF
    chmod +x "$script"
    echo "$script"
}

search() {
    if [[ "$API_SOURCE" == "animapper" ]]; then
        search_animapper
        return
    fi

    local search preview
    search=$(create_search_script) || { show_error "Không tạo được script tìm kiếm"; return; }
    preview=$(create_preview_script) || { rm -f "$search"; show_error "Không tạo được preview"; return; }

    local chon=$(echo "" | fzf "${FZF_OPTS[@]}" \
        --prompt="󱇒 TÌM > " --header="Nhập từ khóa..." --phony \
        --delimiter='|' --with-nth=1,2 \
        --bind "change:reload:sleep 0.2; $search {q} | awk '{printf \"%d. %s\\n\", NR, \$0}' || true" \
        --preview="$preview {}" --preview-window=right:45%:wrap)

    rm -f "$search" "$preview"
    [[ -n "$chon" ]] && watch_episode "$(echo "$chon" | cut -d'|' -f5)" "$(echo "$chon" | cut -d'|' -f1 | strip_menu_number)"
}

search_animapper() {
    local search_script preview
    search_script=$(create_animapper_search_script) || { show_error "Không tạo được script tìm kiếm"; return; }
    preview=$(create_preview_script) || { rm -f "$search_script"; show_error "Không tạo được preview"; return; }

    local chon=$(echo "" | fzf "${FZF_OPTS[@]}" \
        --prompt="󱇒 TÌM ANIME > " --header="Nhập tên anime..." --phony \
        --delimiter='|' --with-nth=1,2 \
        --bind "change:reload:sleep 0.2; $search_script {q} | awk '{printf \"%d. %s\\n\", NR, \$0}' || true" \
        --preview="$preview {}" --preview-window=right:45%:wrap)

    rm -f "$search_script" "$preview"

    if [[ -n "$chon" ]]; then
        local media_id title
        media_id=$(echo "$chon" | cut -d'|' -f5)
        title=$(echo "$chon" | cut -d'|' -f1 | strip_menu_number)
        watch_episode_animapper "$media_id" "$title"
    fi
}

new_releases() {
    case "$API_SOURCE" in
        nguonc)
            fetch_new_nguonc() {
                local res
                res=$(call_api "/api/films/phim-moi-cap-nhat?page=$1")
                [[ -z "$res" ]] && return
                parse_nguonc "$res"
            }
            show_paginated_list "PHIM MỚI" fetch_new_nguonc
            ;;
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
            res=$(call_api "/v1/api/home")
            [[ -z "$res" ]] && { show_error "Lỗi kết nối"; return; }
            cdn=$(echo "$res" | jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""')
            show_list "$(parse_v1_items "$res" "$cdn")" "PHIM MỚI"
            ;;
    esac
}

browse() {
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
    
    local chon=$(echo -e "$menu" | add_menu_numbers | fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth=1 --prompt="DUYỆT > " --height=50%)
    [[ -z "$chon" ]] && return
    
    local loai=$(echo "$chon" | cut -d'|' -f2)
    local ten=$(echo "$chon" | cut -d'|' -f1 | strip_menu_number | sed 's/󰎁  //')
    
    fetch_browse() {
        fetch_list "danh-sach/${loai}" "$1"
    }
    
    show_paginated_list "$ten" fetch_browse
}


filter_by_genre() {
    show_loading
    local res ds
    
    case "$API_SOURCE" in
        nguonc)
            res=$(curl -fsS --max-time 5 "${API_NGUONC}/api/the-loai" 2>/dev/null)
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
                log_debug "filter_by_genre: nguonc API fallback to hardcoded"
            fi
            ;;
        phimapi)
            res=$(call_api "/the-loai")
            [[ -z "$res" ]] && { show_error "Lỗi"; return; }
            ds=$(echo "$res" | jq -r '.[] | "\(.name)|\(.slug)"' 2>/dev/null)
            ;;
        *)
            res=$(call_api "/v1/api/the-loai")
            [[ -z "$res" ]] && { show_error "Lỗi"; return; }
            ds=$(echo "$res" | jq -r '.data.items[] | "\(.name)|\(.slug)"' 2>/dev/null)
            ;;
    esac
    
    local chon=$(echo -e "$ds" | add_menu_numbers | fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth=1 --prompt="THỂ LOẠI > ")
    [[ -z "$chon" ]] && return
    
    local slug=$(echo "$chon" | cut -d'|' -f2)
    local ten=$(echo "$chon" | cut -d'|' -f1 | strip_menu_number)
    
    fetch_genre() {
        fetch_list "the-loai/${slug}" "$1"
    }
    
    show_paginated_list "$ten" fetch_genre
}

filter_by_country() {
    show_loading
    local res ds
    
    case "$API_SOURCE" in
        nguonc)
            res=$(curl -fsS --max-time 5 "${API_NGUONC}/api/quoc-gia" 2>/dev/null)
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
                log_debug "filter_by_country: nguonc API fallback to hardcoded"
            fi
            ;;
        phimapi)
            res=$(call_api "/quoc-gia")
            [[ -z "$res" ]] && { show_error "Lỗi"; return; }
            ds=$(echo "$res" | jq -r '.[] | "\(.name)|\(.slug)"' 2>/dev/null)
            ;;
        *)
            res=$(call_api "/v1/api/quoc-gia")
            [[ -z "$res" ]] && { show_error "Lỗi"; return; }
            ds=$(echo "$res" | jq -r '.data.items[] | "\(.name)|\(.slug)"' 2>/dev/null)
            ;;
    esac
    
    local chon=$(echo -e "$ds" | add_menu_numbers | fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth=1 --prompt="QUỐC GIA > ")
    [[ -z "$chon" ]] && return
    
    local slug=$(echo "$chon" | cut -d'|' -f2)
    local ten=$(echo "$chon" | cut -d'|' -f1 | strip_menu_number)
    
    fetch_country() {
        fetch_list "quoc-gia/${slug}" "$1"
    }
    
    show_paginated_list "$ten" fetch_country
}

filter_by_year() {
    local nam_hien_tai=$(date +%Y)
    local ds=""
    for ((y=nam_hien_tai; y>=2000; y--)); do ds+="$y\n"; done
    
    local chon=$(echo -e "$ds" | add_menu_numbers | fzf "${FZF_OPTS[@]}" --prompt="NĂM > " --height=50%)
    [[ -z "$chon" ]] && return
    
    local nam_chon=$(echo "$chon" | strip_menu_number)
    

    fetch_year() {
        local p="$1"
        case "$API_SOURCE" in
            nguonc) fetch_list "nam-phat-hanh/${nam_chon}" "$p" ;;
            phimapi)
                local res cdn
                res=$(call_api "/v1/api/nam/${nam_chon}?page=${p}&limit=30&sort_field=modified.time&sort_type=desc")
                [[ -z "$res" ]] && return
                cdn=$(echo "$res" | jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""')
                parse_phimapi_v1 "$res" "$cdn"
                ;;
            *)
                local res cdn
                res=$(call_api "/v1/api/nam-phat-hanh/${nam_chon}?page=${p}&limit=30&sort_field=modified.time&sort_type=desc")
                [[ -z "$res" ]] && return
                cdn=$(echo "$res" | jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""')
                parse_ophim1 "$res" "$cdn"
                ;;
        esac
    }
    
    show_paginated_list "Năm $nam_chon" fetch_year
}

anime_mode() {

    fetch_anime() {
        local p="$1"
        case "$API_SOURCE" in
            nguonc) fetch_list "quoc-gia/nhat-ban" "$p" ;;
            phimapi)
                local res cdn
                res=$(call_api "/v1/api/danh-sach/hoat-hinh?page=${p}&country=nhat-ban&sort_field=modified.time&sort_type=desc")
                [[ -z "$res" ]] && return
                cdn=$(echo "$res" | jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""')
                parse_phimapi_v1 "$res" "$cdn"
                ;;
            *)
                local res cdn
                res=$(call_api "/v1/api/danh-sach/hoat-hinh?page=${p}&country=nhat-ban&sort_field=modified.time&sort_type=desc")
                [[ -z "$res" ]] && return
                cdn=$(echo "$res" | jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""')
                parse_ophim1 "$res" "$cdn"
                ;;
        esac
    }

    show_paginated_list "Anime" fetch_anime
}

advanced_filter() {
    local menu="  Thể Loại|theloai
  Quốc Gia|quocgia
  Năm|nam"
    
    local chon=$(echo -e "$menu" | add_menu_numbers | fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth=1 --prompt="LỌC > " --height=40%)
    [[ -z "$chon" ]] && return
    
    case "$(echo "$chon" | cut -d'|' -f2)" in
        theloai) filter_by_genre ;;
        quocgia) filter_by_country ;;
        nam)     filter_by_year ;;
    esac
}

history() {
    [[ ! -s "$HIST" ]] && { show_error "Chưa có lịch sử"; return; }
    
    local chon=$(sort -rn "$HIST" | add_list_numbers | fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth=1,3 --prompt="LỊCH SỬ > ")
    [[ -z "$chon" ]] && return
    chon=$(echo "$chon" | strip_list_number)
    play_video "$(echo "$chon" | cut -d'|' -f4)" "$(echo "$chon" | cut -d'|' -f2)"
}


favorites() {
    [[ ! -s "$FAV" ]] && { show_error "Chưa có yêu thích"; return; }

    local parsed_favs
    # Old favorites lacked a poster field (4 fields). Skip them silently.
    # Current format has 5 fields: timestamp|title|slug|year|poster.
    parsed_favs=$(awk -F'|' '{
        if (NF == 4) {
        } else if (NF >= 5) {
            print
        }
    }' "$FAV" | sort -t'|' -k1,1rn | cut -d'|' -f2-)

    [[ -z "$parsed_favs" ]] && { show_error "Chưa có yêu thích"; return; }

    local chon=$(echo "$parsed_favs" | fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth=1 \
        --prompt="YÊU THÍCH > " --expect=enter,ctrl-d \
        --preview="echo 'Enter: Xem | Ctrl-D: Xóa'" --preview-window=top:2:wrap)

    local phim=$(head -1 <<< "$chon")
    local data=$(tail -n +2 <<< "$chon")
    [[ -z "$data" ]] && return

    local slug=$(echo "$data" | cut -d'|' -f2)
    local ten=$(echo "$data" | cut -d'|' -f1)

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
    local phimapi_mark="" nguonc_mark="" ophim1_mark="" animapper_mark=""

    case "$API_SOURCE" in
        phimapi)   phimapi_mark=" (đang dùng)" ;;
        nguonc)    nguonc_mark=" (đang dùng)" ;;
        animapper) animapper_mark=" (đang dùng)" ;;
        *)         ophim1_mark=" (đang dùng)" ;;
    esac

    echo -e "${C_C} Kiểm tra kết nối nguồn...${C_R}"
    local st_ophim st_phimapi st_nguonc st_animapper
    st_ophim=$(check_source_status "$API_OPHIM1")
    st_phimapi=$(check_source_status "$API_PHIMAPI")
    st_nguonc=$(check_source_status "$API_NGUONC")
    st_animapper=$(check_source_status "$API_ANIMAPPER")

    local menu="󱃾  Ophim1 ${st_ophim}${ophim1_mark}|ophim1
󱃾  PhimAPI ${st_phimapi}${phimapi_mark}|phimapi
󱃾  Nguonc ${st_nguonc}${nguonc_mark}|nguonc
󱃾  AniMapper ${st_animapper}${animapper_mark}|animapper"
    
    local chon=$(echo -e "$menu" | add_menu_numbers | fzf "${FZF_OPTS[@]}" \
        --delimiter='|' --with-nth=1 --prompt="NGUỒN > " --height=40% \
        --header="Chọn nguồn dữ liệu phim")
    [[ -z "$chon" ]] && return
    
    local new_source=$(echo "$chon" | cut -d'|' -f2)

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
    
    PLAYER_DEFAULT=$(echo "$chon" | cut -d'|' -f2)
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
    
    local selected=$(echo "$chon" | cut -d'|' -f2)
    [[ "$selected" == "auto" ]] && QUALITY="" || QUALITY="$selected"
    
    save_settings
}

clear_cache() {
    local count
    count=$(find "$CACHE" -name '*.json' | wc -l)
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
    
    case "$(echo "$chon" | cut -d'|' -f2)" in
        player)  select_player ;;
        nguon)   select_source ;;
        quality) select_quality ;;
        folder)  thunar "$DL" 2>/dev/null || dolphin "$DL" 2>/dev/null || xdg-open "$DL" ;;
        cache)   clear_cache ;;
    esac
}

show_banner() {
    clear
    local nguon_text player_text quality_text
    case "$API_SOURCE" in
        nguonc)    nguon_text="Nguonc" ;;
        phimapi)   nguon_text="PhimAPI" ;;
        animapper) nguon_text="AniMapper" ;;
        *)         nguon_text="Ophim1" ;;
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

    if [[ "$API_SOURCE" != "animapper" ]]; then
        menu_items+="Phim Mới ${I_NEW}\n"
        menu_items+="Duyệt Phim ${I_BROWSE}\n"
        menu_items+="Anime ${I_ANIME}\n"
    fi

    if [[ "$API_SOURCE" != "animapper" ]]; then
        menu_items+="Lọc Nâng Cao ${I_FILTER}\n"
    fi

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
