#!/bin/bash

CONF="$HOME/.config/sudachi"
DL="$HOME/Downloads/Sudachi-Downloaded"
HIST="$CONF/history.log"
FAV="$CONF/favorites.log"
PROGRESS="$CONF/progress.log"
CACHE="$CONF/cache"
CONFIG_FILE="$CONF/config"
PLAYER_DEFAULT="mpv"
QUALITY=""
AD_BLOCK=1
LAST_PLAYER_PID=""

mkdir -p "$CONF" "$DL" "$CACHE"
[ ! -f "$HIST" ] && touch "$HIST"
[ ! -f "$FAV" ] && touch "$FAV"

TEMP_FILES=()
[ ! -f "$PROGRESS" ] && touch "$PROGRESS"

API_PHIMAPI="https://phimapi.com"
API_VSMOV="https://vsmov.com/api"
API_NGUONC="https://phim.nguonc.com/api"
SOURCE="vsmov"
SEARCH_SOURCES="vsmov,nguonc,phimapi"
API_BASE="$API_VSMOV"
USER_AGENT="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
HLS_PROXY_PID=""
HLS_PROXY_URL=""
NGUONC_ORIGIN=""
NGUONC_PLAYLIST=""

set_api_base() {
    case "$SOURCE" in
        phimapi) API_BASE="$API_PHIMAPI" ;;
        nguonc)  API_BASE="$API_NGUONC" ;;
        *)       SOURCE="vsmov"; API_BASE="$API_VSMOV" ;;
    esac
}

I_SEARCH="󱇓 "
I_NEW="󰎁 "
I_BROWSE="󰖟 "
I_FILTER="󱄤 "
I_HIST="󰋚 "
I_FAV="󰋑 "
I_SOURCE="󰳏 "
I_SETTINGS="󰒓 "
I_DIR=" "
I_EXIT="󰈆 "
I_ANIME=" "
I_QUA="󱤵 "
I_PLAYER=" "
I_CACHE="󰃢 "

C_G='\033[1;32m'
C_Y='\033[1;33m'
C_C='\033[0;36m'
C_M='\033[1;35m'
C_R='\033[0m'

load_settings() {
    local line key value item list
    local -a srcs=()

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
            AD_BLOCK)
                case "$value" in
                    0) AD_BLOCK=0 ;;
                    *) AD_BLOCK=1 ;;
                esac
                ;;
            SOURCE)
                case "$value" in
                    phimapi|vsmov|nguonc) SOURCE="$value" ;;
                esac
                ;;
            SEARCH_SOURCES)
                list=""
                IFS=',' read -ra srcs <<< "$value"
                for item in "${srcs[@]}"; do
                    item="${item//[[:space:]]/}"
                    case "$item" in
                        phimapi|vsmov|nguonc) ;;
                        *) continue ;;
                    esac
                    [[ ",$list," == *",$item,"* ]] && continue
                    list+="${list:+,}$item"
                done
                [[ -n "$list" ]] && SEARCH_SOURCES="$list"
                ;;
        esac
    done < "$CONFIG_FILE"
}

save_settings() {
    {
        printf 'PLAYER_DEFAULT=%s\n' "$PLAYER_DEFAULT"
        printf 'QUALITY=%s\n' "$QUALITY"
        printf 'AD_BLOCK=%s\n' "$AD_BLOCK"
        printf 'SOURCE=%s\n' "$SOURCE"
        printf 'SEARCH_SOURCES=%s\n' "$SEARCH_SOURCES"
    } > "$CONFIG_FILE"
}

add_menu_numbers() {
    awk '{printf "%d. %s\n", NR, $0}'
}

format_movie_items() {
    awk -F'|' '
    {
        name = $1
        tag = $2
        country = $3
        ep = $4
        slug = $5
        poster = $6
        src = $7

        display_tag = ""
        if (tag != "" && tag != "N/A") {
            display_tag = "  \033[0;34m·\033[0m  \033[0;35m" tag "\033[0m"
        }
        if (ep != "" && ep != "N/A" && ep !~ /^(0|null)$/) {
            display_tag = display_tag "  \033[0;36m[" ep "]\033[0m"
        }

        if (src != "") {
            label = src
            if (src == "phimapi") label = "PhimAPI"
            else if (src == "vsmov") label = "VSMov"
            else if (src == "nguonc") label = "NguonC"
            display_tag = display_tag "  \033[0;32m[" label "]\033[0m"
        }

        display = sprintf("\033[0;33m%2d.\033[0m  \033[1;37m%s\033[0m%s", NR, name, display_tag)
        printf "%s|%s|%s|%s|%s|%s|%s|%s\n", display, name, tag, country, ep, slug, poster, src
    }'
}

FZF_OPTS=(
    "--ansi"
    "--border=rounded"
    "--border-label= 🍙 Sudachi "
    "--border-label-pos=2"
    "--margin=1,2"
    "--padding=0,1"
    "--layout=reverse-list"
    "--info=inline"
    "--preview-window=right:50%:rounded:wrap"
    "--preview-label= 󰟴 Chi tiết "

    "--pointer=❯ "
    "--marker=● "
    "--ellipsis=…"

    "--color=bg:-1,bg+:-1,gutter:-1"
    "--color=fg:7,fg+:15"
    "--color=hl:178,hl+:220"
    "--color=border:239,label:75"
    "--color=prompt:81,pointer:81,marker:149"
    "--color=spinner:114,info:244,header:111"
    "--color=preview-fg:7,preview-border:239,preview-label:75,preview-scrollbar:239"
    "--color=query:15"
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

    # VSMov/NguonC need the local HLS proxy.
    if ! command -v python3 >/dev/null 2>&1; then
        if [[ "$SOURCE" == "vsmov" || "$SOURCE" == "nguonc" ]]; then
            echo -e "${C_Y}Nguồn này cần python3, tạm chuyển sang PhimAPI.${C_R}"
            SOURCE="phimapi"
            set_api_base
        fi
        SEARCH_SOURCES="phimapi"
    fi
}


cleanup() {
    stop_hls_proxy
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

# HLS_AD_PATTERNS -- awk ERE alternation matching standalone video ad URIs.
# Standalone video ads (gambling commercials, slot machine clips) live in
# dedicated paths like /v[0-9]+/<hash>/segment_ or ads*/, promo*/.
# Note: convertv[0-9]+/ segments are NOT video commercials; they are the actual
# movie/anime scenes with a sponsor text watermark re-encoded on top. Dropping
# convertv* cuts real movie dialogue and content, so they must be kept.
# Pattern matches are complemented by structural detection (Tier 2) in
# hls_strip_ads: a #EXT-X-KEY:METHOD=NONE block is dropped until movie content
# in the playlist's own directory appears, so renamed ad paths survive less.
HLS_AD_PATTERNS='(^|/)ads?[0-9]*/|(^|/)promo[0-9]*/|(^|/)v[0-9]+/[0-9a-f]+/segment_'

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
# playlist to stdout. Drops all mid-roll and pre/post-roll ad segments
# matching HLS_AD_PATTERNS, preserves all movie segments and their metadata
# (#EXTINF), and emits a single #EXT-X-DISCONTINUITY at each ad splice point
# so the player resets its PTS timeline correctly. Header normalization:
# strips #EXT-X-DISCONTINUITY-SEQUENCE (its index shifts after ad removal and
# poisons ffmpeg seek tables) and guarantees #EXT-X-PLAYLIST-TYPE:VOD.
# Segments resolving into the playlist's own directory are movie content and
# are never treated as ads, even when they match HLS_AD_PATTERNS.
# Tier 2 structural detection: a #EXT-X-KEY:METHOD=NONE tag opens a candidate
# block; every following segment outside the playlist's own directory is
# treated as an ad until a movie segment appears, so a renamed ad CDN path is
# still removed even when HLS_AD_PATTERNS no longer matches.
# Segment URIs are absolutized directly in awk for high performance, and URI
# attributes of #EXT-X-KEY / #EXT-X-MAP / #EXT-X-MEDIA lines are rewritten the
# same way so the cached local playlist still references remote keys/maps.
hls_strip_ads() {
    local base="$1" basedir basehost
    basedir="${base%/*}"
    basehost=$(printf '%s' "$base" | sed -E 's|^(https?://[^/]+).*|\1|')

    awk -v adpat="$HLS_AD_PATTERNS" -v basedir="$basedir" -v basehost="$basehost" '
        function absolutize(u) {
            if (u ~ /^https?:\/\//) return u
            if (u ~ /^\//) return basehost u
            return basedir "/" u
        }
        function seg_is_movie(u,   abs) {
            abs = absolutize(u)
            sub(/\/[^\/]*$/, "", abs)
            return (abs == basedir)
        }
        function rewrite_uri(s,   head, rest, uri, abs) {
            if (!match(s, /URI="[^"]*"/)) return s
            head = substr(s, 1, RSTART - 1)
            uri = substr(s, RSTART + 5, RLENGTH - 6)
            rest = substr(s, RSTART + RLENGTH)
            abs = uri
            if (uri != "") abs = absolutize(uri)
            return head "URI=\"" abs "\"" rest
        }
        {
            if ($0 ~ /^#EXTM3U/) {
                print
                print "#EXT-X-PLAYLIST-TYPE:VOD"
                next
            }
            if ($0 ~ /^#EXT-X-PLAYLIST-TYPE/) { next }
            if ($0 ~ /^#EXT-X-DISCONTINUITY-SEQUENCE/) { next }

            # Segment URI line (non-comment, non-empty).
            if ($0 !~ /^#/ && $0 != "") {
                # Tier 2 candidate block (opened by METHOD=NONE): any segment
                # outside the playlist directory is an ad until movie content
                # appears. seg_is_movie is checked first so own-dir segments
                # are never dropped and close the block.
                if (cand && !seg_is_movie($0)) {
                    in_ad = 1
                    had_ad = 1
                    pend_n = 0
                    ad_pend_n = 0
                    next
                }
                if ($0 ~ adpat && !seg_is_movie($0)) {
                    in_ad = 1
                    had_ad = 1
                    pend_n = 0
                    ad_pend_n = 0
                    next
                }
                # Movie segment
                if (in_ad) {
                    in_ad = 0
                }
                cand = 0
                if (had_ad) {
                    if (movie_count > 0) {
                        print "#EXT-X-DISCONTINUITY"
                    }
                    had_ad = 0
                }
                if (ad_pend_n > 0) {
                    for (i = 0; i < ad_pend_n; i++) print ad_pend[i]
                    ad_pend_n = 0
                } else {
                    for (i = 0; i < pend_n; i++) print pend[i]
                    pend_n = 0
                }
                print absolutize($0)
                movie_count++
                next
            }

            # ENDLIST must terminate ad block and pass through
            if ($0 ~ /^#EXT-X-ENDLIST/) {
                in_ad = 0
                cand = 0
                pend_n = 0
                ad_pend_n = 0
                print
                next
            }

            # Tag lines inside ad block
            if (in_ad) {
                if ($0 ~ /^#EXT-X-KEY/ && $0 ~ /METHOD=NONE/) { cand = 1 }
                if ($0 ~ /^#EXTINF/) {
                    ad_pend[ad_pend_n++] = $0
                } else if ($0 ~ /^#EXT-X-KEY/ && $0 !~ /METHOD=NONE/) {
                    ad_pend[ad_pend_n++] = rewrite_uri($0)
                }
                next
            }

            # Tag lines before movie segments
            if ($0 ~ /^#EXT-X-DISCONTINUITY$/) {
                pend[pend_n++] = $0
                next
            }
            if ($0 ~ /^#EXT-X-KEY/) {
                if ($0 ~ /METHOD=NONE/) { cand = 1 }
                pend[pend_n++] = rewrite_uri($0)
                next
            }
            if ($0 ~ /^#EXTINF/) {
                pend[pend_n++] = $0
                next
            }

            # Any other line (headers, EXT-X-MAP/MEDIA/...): flush and pass,
            # absolutizing any URI attribute so a cached local playlist still
            # points at remote keys/maps.
            for (i = 0; i < pend_n; i++) print pend[i]
            pend_n = 0
            print rewrite_uri($0)
        }
        END {
            for (i = 0; i < pend_n; i++) print pend[i]
        }
    '
}

# hls_pick_variant <master-playlist> <quality> -- pick the media variant URI
# from a master playlist. Empty/auto quality picks the highest resolution
# (then highest bandwidth); a numeric quality picks the largest height that
# does not exceed it, falling back to the smallest variant. Echoes nothing
# when the master has no usable variant.
hls_pick_variant() {
    awk -v want="$2" '
        /^#EXT-X-STREAM-INF/ {
            bw = 0; h = 0
            if (match($0, /BANDWIDTH=[0-9]+/)) bw = substr($0, RSTART + 10, RLENGTH - 10) + 0
            if (match($0, /RESOLUTION=[0-9]+x[0-9]+/)) {
                split(substr($0, RSTART + 11, RLENGTH - 11), wh, "x")
                h = wh[2] + 0
            }
            uri = ""
            while ((getline line) > 0) {
                if (line !~ /^#/ && line != "") { uri = line; break }
            }
            if (uri != "") { n++; vh[n] = h; vbw[n] = bw; vu[n] = uri }
        }
        END {
            best = 0
            if (want == "" || want == "auto") {
                for (i = 1; i <= n; i++)
                    if (vh[i] > vh[best] || (vh[i] == vh[best] && vbw[i] > vbw[best])) best = i
            } else {
                want += 0
                best = -1
                for (i = 1; i <= n; i++)
                    if (vh[i] > 0 && vh[i] <= want && (best < 0 || vh[i] > vh[best])) best = i
                if (best < 0) {
                    for (i = 1; i <= n; i++)
                        if (vh[i] > 0 && (best < 0 || vh[i] < vh[best])) best = i
                }
                if (best < 0) best = 0
            }
            # No RESOLUTION attribute anywhere: still return a variant instead
            # of nothing, otherwise the caller falls back to the raw master
            # playlist and ads come back.
            if (best < 1 && n > 0) best = 1
            if (best > 0) print vu[best]
        }
    ' <<< "$1"
}

# hls_fallback_url <clean-file> <original-url> -- reuse a recent cleaned
# playlist; segment URLs expire, so a stale cache is worse than the raw URL.
hls_fallback_url() {
    if [[ -s "$1" ]] && is_cache_fresh "$1" 21600; then
        printf '%s' "$1"
    else
        printf '%s' "$2"
    fi
}

# hls_rebase_convertv <in-playlist-file> <out-playlist-file> <base-url> --
# convertv* segments are real movie content (ending scenes + credits) whose
# PTS restarts at ~1.48s; the CDN brackets them with #EXT-X-DISCONTINUITY.
# Seeking into or across such a cluster makes mpv skip past it or reset to
# ~1.5s (looks like a restart from the beginning). This rebases each convertv
# clip onto the movie timeline. Consecutive convertv clips form a cluster;
# each cluster is anchored on the movie segment immediately before it (empty
# anchor at playlist start = cursor 0) and chained from there, so a playlist
# with several clusters separated by movie content keeps every cluster on its
# own timeline. The clip is downloaded (cached under $CACHE/segments/) and
# stream-copied with a constant PTS offset so its first video PTS equals the
# running cursor (anchor end, then the end of each rebased clip in the
# cluster):
#   ffmpeg -loglevel error -nostdin -y -itsoffset <cursor-first_pts> -i <in> \
#          -c copy -copyts -muxdelay 0 -muxpreload 0 -f mpegts <out>
# -itsoffset shifts every packet and -copyts keeps the shifted timestamps
# (without -copyts ffmpeg re-normalizes the output to 0); -muxdelay and
# -muxpreload 0 stop the mpegts muxer from adding its default 0.7s delay.
# Verified against the Frieren s6 CDN: first video PTS lands exactly on the
# cursor and the packet layout (h264 + aac) is unchanged. When the shift would
# be negative (no preceding movie segment, cursor 0) the clip is normalized to
# the cursor with -output_ts_offset instead. Rebased copies are cached as
# $CACHE/segments/<hash>-r.ts and reused when their first PTS still matches
# the cursor; otherwise they are rebuilt from the cached download. Writes
# <out>: convertv URI lines become local rebased paths, every
# #EXT-X-DISCONTINUITY is removed (the timeline is continuous again), EXTINF
# and all other lines are kept as-is. Returns 1 when ffmpeg/ffprobe are
# missing, the playlist has no convertv segment, or any download/probe/rebase
# step fails -- the caller then keeps the un-rebased playlist so playback
# never breaks.
hls_rebase_convertv() {
    local in="$1" out="$2" base="$3"
    local segdir="$CACHE/segments"
    local line prev_uri="" cursor=0
    local abs hash src dst shift out_pts p_first p_last fdur map rc uri dst_first
    local -a clips=() rebased=()

    command -v ffmpeg >/dev/null 2>&1 || return 1
    command -v ffprobe >/dev/null 2>&1 || return 1
    [[ -f "$in" ]] || return 1
    grep -qE 'convertv[0-9]*/' "$in" || return 1

    # Private helpers for this pipeline; "-f mpegts" keeps ffprobe/ffmpeg from
    # parsing a mis-downloaded file as an HLS playlist and touching the network.
    _rebase_fetch() { # <abs-url> <cache-file>; 1 on download failure
        local tmp="$2.part.$$"
        [[ -s "$2" ]] && return 0
        curl -fsS --connect-timeout 10 --max-time 30 "$1" -o "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; return 1; }
        [[ -s "$tmp" ]] || { rm -f "$tmp"; return 1; }
        mv -f "$tmp" "$2" 2>/dev/null || { rm -f "$tmp"; return 1; }
    }
    _rebase_pts() { # <file> -> "first last" video PTS on stdout, 1 when absent
        ffprobe -f mpegts -v error -select_streams v -show_entries packet=pts_time -of csv=p=0 "$1" 2>/dev/null \
            | sed 's/,$//' | grep -E '^-?[0-9]+(\.[0-9]+)?$' | sort -n \
            | awk 'NR==1{f=$0}{l=$0}END{if(f=="")exit 1; print f, l}'
    }
    _rebase_framedur() { # <file> -> video frame duration ("0" when unknown)
        local rate
        rate=$(ffprobe -f mpegts -v error -select_streams v -show_entries stream=avg_frame_rate -of csv=p=0 "$1" 2>/dev/null | head -1)
        [[ "$rate" == */* ]] || rate=$(ffprobe -f mpegts -v error -select_streams v -show_entries stream=r_frame_rate -of csv=p=0 "$1" 2>/dev/null | head -1)
        awk -v r="$rate" 'BEGIN{split(r,a,"/"); if (a[1]+0 > 0 && a[2]+0 > 0) printf "%.6f", a[2]/a[1]; else print "0"}'
    }

    # Convertv clips in playlist order, grouped into clusters: consecutive
    # convertv lines share one anchor, the movie segment immediately before the
    # first clip of the cluster (empty when the cluster starts the playlist).
    local -a cluster_anchor=() cluster_first=()
    local in_cluster=0
    while IFS= read -r line; do
        [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
        if [[ "$line" =~ convertv[0-9]*/ ]]; then
            if [[ $in_cluster -eq 0 ]]; then
                cluster_anchor+=("$prev_uri")
                cluster_first+=("${#clips[@]}")
                in_cluster=1
            fi
            clips+=("$line")
        else
            in_cluster=0
        fi
        prev_uri="$line"
    done < "$in"

    [[ ${#clips[@]} -gt 0 ]] || return 1
    mkdir -p "$segdir" || return 1

    # Resolve every source file first and prefetch the missing ones in
    # parallel batches (4 at a time) so the first play does not wait for seven
    # sequential downloads.
    local -a urls=() hashes=() srcs=() need_urls=() need_files=() anchorsrc=()
    local ci a h
    for ((ci = 0; ci < ${#cluster_anchor[@]}; ci++)); do
        if [[ -z "${cluster_anchor[ci]}" ]]; then
            anchorsrc[ci]=""
            continue
        fi
        a=$(hls_absolutize_url "$base" "${cluster_anchor[ci]}")
        h=$(hash_url "$a")
        anchorsrc[ci]="$segdir/$h.ts"
        [[ -s "${anchorsrc[ci]}" ]] || { need_urls+=("$a"); need_files+=("${anchorsrc[ci]}"); }
    done
    for uri in "${clips[@]}"; do
        a=$(hls_absolutize_url "$base" "$uri")
        h=$(hash_url "$a")
        urls+=("$a"); hashes+=("$h"); srcs+=("$segdir/$h.ts")
        [[ -s "$segdir/$h.ts" ]] || { need_urls+=("$a"); need_files+=("$segdir/$h.ts"); }
    done
    if (( ${#need_urls[@]} > 0 )); then
        printf '  Đang tải %d đoạn cần ghép...\n' "${#need_urls[@]}" >&2
        local i j
        for ((i = 0; i < ${#need_urls[@]}; i += 4)); do
            local -a batch=()
            for ((j = i; j < i + 4 && j < ${#need_urls[@]}; j++)); do
                _rebase_fetch "${need_urls[j]}" "${need_files[j]}" &
                batch+=($!)
            done
            wait "${batch[@]}" || true
        done
        local f
        for f in "${need_files[@]}"; do
            [[ -s "$f" ]] || return 1
        done
    fi

    # Rebase each cluster from its own anchor, in playlist order; rebased[] is
    # appended in playlist order so the i-th convertv line maps to the i-th
    # rebased path in the final rewrite.
    local c idx=0 end
    for c in "${!cluster_anchor[@]}"; do
        if [[ -n "${anchorsrc[c]}" ]]; then
            out_pts=$(_rebase_pts "${anchorsrc[c]}") || return 1
            read -r p_first p_last <<< "$out_pts"
            fdur=$(_rebase_framedur "${anchorsrc[c]}")
            cursor=$(awk -v l="$p_last" -v d="$fdur" 'BEGIN{printf "%.6f", l+d}')
        else
            cursor=0
        fi
        if (( c + 1 < ${#cluster_anchor[@]} )); then
            end=${cluster_first[c + 1]}
        else
            end=${#clips[@]}
        fi
        for ((; idx < end; idx++)); do
            abs="${urls[idx]}"
            hash="${hashes[idx]}"
            src="${srcs[idx]}"
            dst="$segdir/$hash-r.ts"

            # Cached rebased clip is usable only when it still starts at the
            # current cursor (the same URI may be republished in another timeline).
            if [[ -s "$dst" ]]; then
                local dst_pts
                dst_pts=$(_rebase_pts "$dst") || return 1
                read -r dst_first p_last <<< "$dst_pts"
                if awk -v a="$dst_first" -v b="$cursor" 'BEGIN{d=a-b; if(d<0)d=-d; exit !(d<0.5)}'; then
                    rebased+=("$dst")
                    fdur=$(_rebase_framedur "$dst")
                    cursor=$(awk -v l="$p_last" -v d="$fdur" 'BEGIN{printf "%.6f", l+d}')
                    continue
                fi
            fi

            [[ -s "$src" ]] || _rebase_fetch "$abs" "$src" || return 1
            out_pts=$(_rebase_pts "$src") || return 1
            read -r p_first p_last <<< "$out_pts"

            # Write to a temp name so an interrupted rebase can never leave a
            # truncated dst that the cursor check might mistake for a good one.
            printf '  Đang ghép đoạn tài trợ %d/%d...\n' "$((idx + 1))" "${#clips[@]}" >&2
            local dst_tmp="$dst.part.$$"
            shift=$(awk -v c="$cursor" -v f="$p_first" 'BEGIN{printf "%.6f", c-f}')
            if [[ "$shift" == -* ]]; then
                ffmpeg -loglevel error -nostdin -y -i "$src" -c copy -muxdelay 0 -muxpreload 0 \
                    -output_ts_offset "$cursor" -f mpegts "$dst_tmp" 2>/dev/null || { rm -f "$dst_tmp"; return 1; }
            else
                ffmpeg -loglevel error -nostdin -y -itsoffset "$shift" -i "$src" -c copy -copyts \
                    -muxdelay 0 -muxpreload 0 -f mpegts "$dst_tmp" 2>/dev/null || { rm -f "$dst_tmp"; return 1; }
            fi
            [[ -s "$dst_tmp" ]] || { rm -f "$dst_tmp"; return 1; }

            # The stream codecs must survive the stream copy (video + audio).
            local src_codecs dst_codecs
            src_codecs=$(ffprobe -f mpegts -v error -show_entries stream=codec_type -of csv=p=0 "$src" 2>/dev/null | sort -u | tr '\n' ' ')
            dst_codecs=$(ffprobe -f mpegts -v error -show_entries stream=codec_type -of csv=p=0 "$dst_tmp" 2>/dev/null | sort -u | tr '\n' ' ')
            [[ -n "$src_codecs" && "$src_codecs" == "$dst_codecs" ]] || { rm -f "$dst_tmp"; return 1; }

            out_pts=$(_rebase_pts "$dst_tmp") || { rm -f "$dst_tmp"; return 1; }
            read -r dst_first p_last <<< "$out_pts"
            # The stream copy must have landed the clip exactly on the cursor.
            awk -v a="$dst_first" -v b="$cursor" 'BEGIN{d=a-b; if(d<0)d=-d; exit !(d<0.5)}' \
                || { rm -f "$dst_tmp"; return 1; }
            fdur=$(_rebase_framedur "$dst_tmp")
            cursor=$(awk -v l="$p_last" -v d="$fdur" 'BEGIN{printf "%.6f", l+d}')
            mv -f "$dst_tmp" "$dst" 2>/dev/null || { rm -f "$dst_tmp"; return 1; }
            rebased+=("$dst")
        done
    done

    map=$(mktemp "$CACHE/.rebase.XXXXXX" 2>/dev/null) || map="$CACHE/.rebase-$$.map"
    printf '%s\n' "${rebased[@]}" > "$map" || { rm -f "$map"; return 1; }
    awk -v mapfile="$map" '
        BEGIN { n = 0; while ((getline p < mapfile) > 0) paths[++n] = p }
        /^#EXT-X-DISCONTINUITY$/ { next }
        {
            if ($0 !~ /^#/ && $0 != "" && $0 ~ /convertv[0-9]*\//) {
                i++
                if (i <= n) { print paths[i]; next }
            }
            print
        }
    ' "$in" > "$out"
    rc=$?
    rm -f "$map"
    [[ $rc -eq 0 && -s "$out" ]] || return 1
    return 0
}

# hls_fetch_clean <url> [play|dl] -- strip ad segments and cache the cleaned
# playlist as $CACHE/<hash>-clean.m3u8 (or -dl.m3u8). Play mode also rebases
# convertv clips. A fetch failure reuses a recent cache, then the raw URL.
hls_fetch_clean() {
    local url="$1" mode="${2:-play}"
    local master variant media out tmp tmp2 hash clean suffix
    [[ "$mode" == "dl" ]] && suffix="-dl" || suffix="-clean"
    hash=$(hash_url "$url")
    clean="$CACHE/$hash$suffix.m3u8"

    master=$(curl -fsS --connect-timeout 10 --max-time 10 "$url" 2>/dev/null) || {
        hls_fallback_url "$clean" "$url"
        return 0
    }
    if printf '%s' "$master" | grep -q '^#EXT-X-STREAM-INF'; then
        variant=$(hls_pick_variant "$master" "$QUALITY")
        media=$(hls_absolutize_url "$url" "$variant")
    else
        media="$url"
    fi
    [[ -z "$media" ]] && {
        hls_fallback_url "$clean" "$url"
        return 0
    }
    out=$(curl -fsS --connect-timeout 10 --max-time 10 "$media" 2>/dev/null) || {
        hls_fallback_url "$clean" "$url"
        return 0
    }
    [[ -z "$out" ]] && {
        hls_fallback_url "$clean" "$url"
        return 0
    }
    # A 200 may be an HTML/JSON error page; never cache that as a playlist.
    if ! printf '%s\n' "$out" | grep -q '^#EXTM3U'; then
        log_debug "hls_fetch_clean: $media is not an m3u8 playlist — using fallback"
        hls_fallback_url "$clean" "$url"
        return 0
    fi
    # Canary: many DISCONTINUITY tags but zero ad-pattern matches means the
    # CDN likely changed its ad URI layout -- flag it so HLS_AD_PATTERNS can
    # be updated before users just accept the ads returning.
    if [ "$(printf '%s\n' "$out" | grep -c '^#EXT-X-DISCONTINUITY$')" -ge 2 ] && \
       ! printf '%s\n' "$out" | grep -qE "$HLS_AD_PATTERNS"; then
        log_debug "hls_fetch_clean: $media has DISCONTINUITY but no ad-pattern match — HLS_AD_PATTERNS may need updating"
    fi
    tmp=$(mktemp "$CACHE/.clean.XXXXXX.m3u8" 2>/dev/null) || tmp="$CACHE/.tmp-$$.m3u8"
    if printf '%s\n' "$out" | hls_strip_ads "$media" > "$tmp"; then
        # Downloads skip convertv rebasing: yt-dlp handles the remote clips.
        if [[ "$mode" != "dl" ]]; then
            tmp2=$(mktemp "$CACHE/.clean.XXXXXX.m3u8" 2>/dev/null) || tmp2="$CACHE/.tmp2-$$.m3u8"
            if hls_rebase_convertv "$tmp" "$tmp2" "$media"; then
                mv -f "$tmp2" "$tmp" 2>/dev/null || rm -f "$tmp2"
            else
                rm -f "$tmp2"
            fi
        fi
        if [[ -s "$tmp" ]] && mv -f "$tmp" "$clean" 2>/dev/null; then
            echo "$clean"
        else
            rm -f "$tmp"
            hls_fallback_url "$clean" "$url"
            return 0
        fi
    else
        rm -f "$tmp"
        hls_fallback_url "$clean" "$url"
        return 0
    fi
}

# parse_vsmov_player_page -- read a player page on stdin and echo its playlist URL.
parse_vsmov_player_page() {
    local page base hash signed enabled
    page=$(cat)
    base=$(sed -n 's/.*baseUrl[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' <<< "$page" | head -1)
    hash=$(sed -n 's/.*videoHash[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' <<< "$page" | head -1)
    signed=$(sed -n 's/.*signedMasterUrl"*[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' <<< "$page" | head -1)
    enabled=$(sed -n 's/.*enableSignedUrl"*[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p' <<< "$page" | head -1)

    if [[ "$enabled" == "true" && -n "$signed" ]]; then
        printf '%s' "$signed"
    elif [[ -n "$base" && -n "$hash" ]]; then
        printf '%s/stream/%s/master.m3u8' "${base%/}" "$hash"
    fi
}

# resolve_stream_url <url> -- VSMov entries carry a player page; extract its playlist.
resolve_stream_url() {
    local url="$1" page resolved

    case "$url" in
        *.m3u8*) printf '%s' "$url"; return 0 ;;
    esac
    if [[ "$url" != *"streamvsmov.com"* ]]; then
        printf '%s' "$url"
        return 0
    fi

    page=$(curl -fsS -A "$USER_AGENT" -e "https://vsmov.com/" \
        --connect-timeout 10 --max-time 15 "$url" 2>/dev/null) || {
        log_debug "resolve_stream_url: fetch failed for $url"
        printf '%s' "$url"
        return 0
    }
    resolved=$(parse_vsmov_player_page <<< "$page")
    if [[ -z "$resolved" ]]; then
        log_debug "resolve_stream_url: cannot parse $url"
        printf '%s' "$url"
        return 0
    fi
    resolved=$(printf '%s' "$resolved" | sed 's|\\/|/|g')
    if [[ "$resolved" != http* ]]; then
        resolved=$(hls_absolutize_url "$url" "$resolved")
    fi
    printf '%s' "$resolved"
}

# resolve_nguonc_embed <embed-url> -- bootstrap the NguonC player; sets
# NGUONC_PLAYLIST and NGUONC_ORIGIN for the local proxy.
resolve_nguonc_embed() {
    local embed="$1" host hash body playlist turnstile format

    host=$(sed -E 's|^https?://([^/]+).*|\1|' <<< "$embed")
    hash=$(sed -n 's/.*[?&]hash=\([^&]*\).*/\1/p' <<< "$embed")
    [[ -n "$host" && -n "$hash" ]] || return 1

    body=$(curl -fsS -A "$USER_AGENT" -H "Origin: https://$host" -H "Referer: https://$host/" \
        -H 'Content-Type: application/json' \
        -d '{"action":"bootstrap","referrer":"https://phim.nguonc.com/","frame_origins":["https://phim.nguonc.com"],"request_grant":true,"playlist_format":"hls","pretty_url":true,"path_chunks":true,"bootstrap_format":"json"}' \
        "https://$host/embed.php?hash=$hash" 2>/dev/null) || return 1

    turnstile=$(jq -r '.turnstileEnabled // false' <<< "$body" 2>/dev/null)
    playlist=$(jq -r '.preissued.playlist // empty' <<< "$body" 2>/dev/null)
    format=$(jq -r '.preissued.playlistFormat // empty' <<< "$body" 2>/dev/null)
    [[ "$turnstile" == "true" || "$format" != "hls" || -z "$playlist" ]] && return 1

    NGUONC_ORIGIN="https://$host"
    NGUONC_PLAYLIST="$playlist"
    return 0
}

# resolve_saved_url <slug> <ep> [stored-url] -- refresh a history link; never
# resolve a stored URL from the other source because slugs can collide.
resolve_saved_url() {
    local slug="$1" ep="$2" stored="${3:-}" res url expected

    [[ -n "$slug" && -n "$ep" ]] || return 0
    if [[ -n "$stored" ]]; then
        case "$stored" in
            *streamvsmov*) expected="vsmov" ;;
            *streamc.xyz*) expected="nguonc" ;;
            *)             expected="phimapi" ;;
        esac
        [[ "$SOURCE" == "$expected" ]] || return 0
    fi

    if [[ "$SOURCE" == "nguonc" ]]; then
        res=$(call_api "/film/$slug") || return 0
        url=$(jq -r --arg ep "$ep" '
            [.movie.episodes[]?.items[]? | select(.name == $ep)] | .[0] |
            if . == null then empty else .embed end
        ' <<< "$res" 2>/dev/null)
    else
        res=$(call_api "/phim/$slug") || return 0
        url=$(jq -r --arg ep "$ep" '
            [.episodes[]?.server_data[]? | select(.name == $ep)] | .[0] |
            if . == null then empty
            elif (.link_m3u8 // "") != "" then .link_m3u8
            else (.link_embed // "") end
        ' <<< "$res" 2>/dev/null)
    fi
    printf '%s' "$url"
}

# create_hls_proxy_script -- cache the PNG-stripping proxy. VSMov wraps each
# TS segment in a PNG header, which ffmpeg refuses to read.
create_hls_proxy_script() {
    local script="$CACHE/hls-proxy.py" tmp
    if [[ -s "$script" ]] && grep -q '^# hls-proxy v3' "$script"; then
        return 0
    fi
    tmp=$(mktemp "$CACHE/hls-proxy.XXXXXX.py") || return 1
    cat > "$tmp" <<'PY'
#!/usr/bin/env python3
# hls-proxy v3
import base64
import sys
import threading
import urllib.parse
import urllib.request
from collections import OrderedDict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
CACHE = OrderedDict()
CACHE_MAX = 12
CACHE_LOCK = threading.Lock()
ROOT = ""
ORIGIN = ""
REFERER = ""


def fetch(url):
    with CACHE_LOCK:
        body = CACHE.get(url)
        if body is not None:
            CACHE.move_to_end(url)
            return body
    headers = {"User-Agent": UA, "Accept": "*/*"}
    if REFERER:
        headers["Referer"] = REFERER
    if ORIGIN:
        headers["Origin"] = ORIGIN
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=30) as res:
        body = res.read()
    with CACHE_LOCK:
        CACHE[url] = body
        while len(CACHE) > CACHE_MAX:
            CACHE.popitem(last=False)
    return body


def strip_png(body):
    if not body.startswith(b"\x89PNG"):
        return body
    limit = min(len(body), 8192)
    for off in range(limit):
        if (body[off] == 0x47
                and body[off + 188:off + 189] == b"\x47"
                and body[off + 376:off + 377] == b"\x47"):
            return body[off:]
    return body


def enc(url):
    return base64.urlsafe_b64encode(url.encode()).decode().rstrip("=")


def dec(token):
    return base64.urlsafe_b64decode(token + "=" * (-len(token) % 4)).decode()


def rewrite_playlist(text, base, prefix):
    out = []
    for line in text.splitlines():
        if line.startswith("#"):
            out.append(line)
        elif line.strip():
            url = urllib.parse.urljoin(base, line.strip())
            if ".m3u8" in url.lower():
                out.append("%s/playlist/%s.m3u8" % (prefix, enc(url)))
            else:
                out.append("%s/seg/%s.ts" % (prefix, enc(url)))
        else:
            out.append(line)
    return "\n".join(out) + "\n"


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def send_body(self, body, ctype):
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        prefix = "http://127.0.0.1:%d" % self.server.server_address[1]
        path = self.path.split("?", 1)[0]
        try:
            if path.startswith("/seg/"):
                token = path[5:]
                if token.endswith(".ts"):
                    token = token[:-3]
                self.send_body(strip_png(fetch(dec(token))), "video/mp2t")
            elif path.startswith("/playlist/"):
                token = path[10:]
                if token.endswith(".m3u8"):
                    token = token[:-5]
                url = dec(token)
                text = fetch(url).decode("utf-8", "replace")
                self.send_body(rewrite_playlist(text, url, prefix).encode(),
                               "application/vnd.apple.mpegurl")
            else:
                text = fetch(ROOT).decode("utf-8", "replace")
                self.send_body(rewrite_playlist(text, ROOT, prefix).encode(),
                               "application/vnd.apple.mpegurl")
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as exc:
            try:
                self.send_error(502, str(exc))
            except Exception:
                pass


def selftest():
    header = b"\x89PNG\r\n\x1a\n" + b"\x00" * 80 + b"\xff" * 60
    ts = (b"\x47" + b"\x00" * 187) * 3
    out = strip_png(header + ts)
    if not out.startswith(b"\x47") or len(out) != len(ts):
        print("selftest failed", file=sys.stderr)
        return 1
    print("ok")
    return 0


def main():
    global ROOT, ORIGIN, REFERER
    if len(sys.argv) > 1 and sys.argv[1] == "--selftest":
        return selftest()
    if len(sys.argv) < 4:
        print("usage: hls-proxy.py <port> <portfile> <playlist-url> [origin] [referer]", file=sys.stderr)
        return 2
    port = int(sys.argv[1])
    portfile = sys.argv[2]
    ROOT = sys.argv[3]
    ORIGIN = sys.argv[4] if len(sys.argv) > 4 else ""
    REFERER = sys.argv[5] if len(sys.argv) > 5 else "https://v9.streamvsmov.com/"
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    with open(portfile, "w") as handle:
        handle.write(str(server.server_address[1]))
    server.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
    if ! mv -f "$tmp" "$script" 2>/dev/null; then
        rm -f "$tmp"
        return 1
    fi
}

# start_hls_proxy <playlist-url> [origin] [referer] [port-key] -- set
# HLS_PROXY_URL to a local proxy playlist. The port is derived from port-key
# (default: the playlist URL) so mpv resume survives token changes.
start_hls_proxy() {
    local url="$1" origin="${2:-}" referer="${3:-https://v9.streamvsmov.com/}" port_key="${4:-$1}"
    local script portfile port i proxy_url seed attempt

    command -v python3 >/dev/null 2>&1 || { log_debug "hls proxy: python3 missing"; return 1; }
    create_hls_proxy_script || return 1
    stop_hls_proxy
    script="$CACHE/hls-proxy.py"
    portfile=$(mktemp "$CACHE/hls-proxy.XXXXXX.port") || return 1

    seed=$(printf '%s' "$port_key" | cksum | cut -d' ' -f1)
    [[ "$seed" =~ ^[0-9]+$ ]] || seed=0
    port=""
    for attempt in $(seq 0 9); do
        : > "$portfile"
        python3 "$script" "$((17000 + seed % 1000 + attempt))" "$portfile" "$url" "$origin" "$referer" \
            >>"$CACHE/hls-proxy.log" 2>&1 &
        HLS_PROXY_PID=$!
        for i in $(seq 1 50); do
            if [[ -s "$portfile" ]]; then
                port=$(<"$portfile")
                break
            fi
            kill -0 "$HLS_PROXY_PID" 2>/dev/null || break
            sleep 0.1
        done
        [[ -n "$port" ]] && break
        stop_hls_proxy
    done
    rm -f "$portfile"
    if [[ -z "$port" ]]; then
        stop_hls_proxy
        log_debug "hls proxy: no port for $url"
        return 1
    fi

    proxy_url="http://127.0.0.1:$port/master.m3u8"
    for i in 1 2 3 4 5; do
        if curl -fsS --max-time 10 "$proxy_url" -o /dev/null 2>/dev/null; then
            HLS_PROXY_URL="$proxy_url"
            return 0
        fi
        sleep 0.2
    done
    stop_hls_proxy
    log_debug "hls proxy: not ready for $url"
    return 1
}

stop_hls_proxy() {
    if [[ -n "$HLS_PROXY_PID" ]]; then
        kill "$HLS_PROXY_PID" 2>/dev/null
        wait "$HLS_PROXY_PID" 2>/dev/null
        HLS_PROXY_PID=""
    fi
    HLS_PROXY_URL=""
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

call_api() {
    local endpoint="$1"
    local url="${API_BASE}${endpoint}"


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
        if jq -e '(. != null) and (.status != "error") and (.status != false) and (has("error") | not)' <<< "$res" >/dev/null 2>&1; then
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
    local slug="$1" title="$2" url="$3" ep="${4:-}" tmp safe_title safe_url safe_ep
    safe_title=$(sanitize_field "$title")
    safe_url=$(sanitize_field "$url")
    safe_ep=$(sanitize_field "$ep")

    tmp=$(mktemp "$CACHE/history.XXXXXX") || return 1

    if ! awk -F'|' -v s="$slug" '$3 != s' "$HIST" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi

    printf -v now '%(%s)T' -1
    printf '%s|%s|%s|%s|%s\n' "$now" "$safe_title" "$slug" "$safe_url" "$safe_ep" >> "$tmp"
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
    local title="$1" slug="$2" year="$3" poster="$4" src="${5:-}"
    local tmp
    local safe_title safe_year safe_poster safe_src
    safe_title=$(sanitize_field "$title")
    safe_year=$(sanitize_field "$year")
    safe_poster=$(sanitize_field "$poster")
    safe_src=$(sanitize_field "$src")
    printf -v timestamp '%(%s)T' -1

    tmp=$(mktemp "$CACHE/favorites.XXXXXX") || return 1

    if ! awk -F'|' -v s="$slug" '{
        if ($2 == s || $3 == s) next
        print
    }' "$FAV" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi

    printf '%s|%s|%s|%s|%s|%s\n' "$timestamp" "$safe_title" "$slug" "$safe_year" "$safe_poster" "$safe_src" >> "$tmp"
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

    local is_proxy=0
    local proxy_playlist="" proxy_origin="" proxy_referer="" proxy_key=""
    if [[ "$url" == *"streamvsmov.com"* ]]; then
        is_proxy=1
        proxy_key="$url"
        proxy_playlist=$(resolve_stream_url "$url")
        if [[ "$proxy_playlist" != *".m3u8"* ]]; then
            show_error "Không lấy được link tải"
            return 1
        fi
    elif [[ "$url" == *"streamc.xyz"* && "$url" == *"embed.php"* ]]; then
        is_proxy=1
        proxy_key="$url"
        if ! resolve_nguonc_embed "$url"; then
            show_error "Không lấy được link NguonC"
            return 1
        fi
        proxy_playlist="$NGUONC_PLAYLIST"
        proxy_origin="$NGUONC_ORIGIN"
        proxy_referer="$NGUONC_ORIGIN/"
    fi

    # PhimAPI: strip ads from the playlist; yt-dlp handles the remote clips.
    local dl_url="$url" dl_local=0 clean
    if [[ $is_proxy -eq 0 && "$AD_BLOCK" == "1" && "$url" == *".m3u8"* ]]; then
        clean=$(hls_fetch_clean "$url" dl)
        if [[ "$clean" == http* ]]; then
            dl_url="$clean"
        else
            dl_url="file://$clean"
            dl_local=1
        fi
    fi

    local row_title
    row_title=$(sanitize_field "$title")
    local safe_title
    safe_title=$(printf '%s' "$title" | sed 's|[/\\:*?"<>|]| - |g' | tr -s ' ' | sed 's/^ *//;s/ *$//' | tr ' ' '_')
    file="${safe_title:-sudachi_$(date +%s)}.mp4"

    mkdir -p "$CACHE/downloads"
    local log_file
    log_file="$CACHE/downloads/$(date +%s)_${file}.log"

    (
        # The subshell owns its proxy; do not touch a playback proxy.
        HLS_PROXY_PID=""
        HLS_PROXY_URL=""
        trap 'stop_hls_proxy' EXIT
        local rc
        if [[ $is_proxy -eq 1 ]]; then
            if ! start_hls_proxy "$proxy_playlist" "$proxy_origin" "$proxy_referer" "$proxy_key"; then
                echo "Không khởi động được proxy HLS" > "$log_file"
                rc=1
            else
                yt-dlp "$HLS_PROXY_URL" -o "$DL/$file" -N 8 > "$log_file" 2>&1
                rc=$?
                stop_hls_proxy
            fi
        elif [[ $dl_local -eq 1 ]]; then
            yt-dlp --enable-file-urls -N 8 "$dl_url" -o "$DL/$file" > "$log_file" 2>&1
            rc=$?
        elif command -v aria2c >/dev/null 2>&1; then
            yt-dlp "$dl_url" -o "$DL/$file" --downloader aria2c -N 8 > "$log_file" 2>&1
            rc=$?
        else
            yt-dlp "$dl_url" -o "$DL/$file" > "$log_file" 2>&1
            rc=$?
        fi
        printf '%s\n' "$rc" > "$log_file.rc"
        if [[ $rc -eq 0 ]]; then
            command -v notify-send >/dev/null 2>&1 && notify-send "Sudachi" "✅ Tải xong: $title"
        else
            command -v notify-send >/dev/null 2>&1 && notify-send -u critical "Sudachi" "❌ Lỗi khi tải: $title"
        fi
    ) &
    printf '%s|%s|%s\n' "$row_title" "$file" "$log_file" >> "$CACHE/downloads/tasks.log"

    command -v notify-send >/dev/null 2>&1 && notify-send "Sudachi" "⬇ Đang tải: $title"
    echo -e "${C_G}  Đang tải: $title${C_R}"
    echo -e "${C_C}  Lưu tại: $DL/$file${C_R}"
    sleep 1
}

view_downloads() {
    local task_file="$CACHE/downloads/tasks.log"
    [[ ! -s "$task_file" ]] && { show_error "Chưa có lượt tải nào"; return; }

    local list="" f1 f2 f3 f4 row_title file log rc status now mtime
    printf -v now '%(%s)T' -1
    while IFS='|' read -r f1 f2 f3 f4; do
        [[ -z "$f1" ]] && continue
        # Legacy rows were pid|title|file|log; current rows are title|file|log
        # with the exit status in <log>.rc.
        if [[ -n "$f4" ]]; then
            row_title="$f2"; file="$f3"; log="$f4"
        else
            row_title="$f1"; file="$f2"; log="$f3"
        fi
        if [[ -f "$log.rc" ]]; then
            rc=$(<"$log.rc")
            if [[ "$rc" == "0" ]]; then
                status="\033[1;32m[󰄲 Hoàn tất]\033[0m"
            else
                status="\033[1;31m[󰅚 Lỗi]\033[0m"
            fi
        else
            mtime=$(stat -c %Y "$log" 2>/dev/null || stat -f %m "$log" 2>/dev/null || echo 0)
            if (( now - mtime < 600 )); then
                status="\033[1;33m[󰑈 Đang tải]\033[0m"
            else
                status="\033[0;90m[󰅚 Đã dừng]\033[0m"
            fi
        fi
        list="${status} ${row_title}|${log}"$'\n'"$list"
    done < "$task_file"

    [[ -z "$list" ]] && { show_error "Chưa có lượt tải nào"; return; }

    echo -e "$list" | add_menu_numbers | fzf "${FZF_OPTS[@]}" \
        --delimiter='|' --with-nth=1 --prompt="Tải phim > " \
        --header="Di chuyển để xem log · Esc quay lại" \
        --preview='tail -n 25 {2} 2>/dev/null || echo "Không có log"' --preview-window=down:55%:rounded:wrap >/dev/null
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
    local is_vsmov=0 is_nguonc=0
    LAST_PLAYER_PID=""

    if [[ "$url" == *"streamvsmov.com"* ]]; then
        is_vsmov=1
    elif [[ "$url" == *"streamc.xyz"* && "$url" == *"embed.php"* ]]; then
        is_nguonc=1
    fi
    if [[ $is_vsmov -eq 1 ]]; then
        url=$(resolve_stream_url "$url")
        if [[ "$url" != *".m3u8"* ]]; then
            log_debug "play_video: could not resolve VSMov stream"
            show_error "Không lấy được link phát"
            return 1
        fi
        if ! start_hls_proxy "$url"; then
            show_error "Không khởi động được proxy HLS"
            return 1
        fi
        url="$HLS_PROXY_URL"
    elif [[ $is_nguonc -eq 1 ]]; then
        if ! resolve_nguonc_embed "$url"; then
            log_debug "play_video: could not bootstrap NguonC embed"
            show_error "Không lấy được link NguonC"
            return 1
        fi
        if ! start_hls_proxy "$NGUONC_PLAYLIST" "$NGUONC_ORIGIN" "$NGUONC_ORIGIN/" "$url"; then
            show_error "Không khởi động được proxy HLS"
            return 1
        fi
        url="$HLS_PROXY_URL"
    fi

    # PhimAPI HLS: strip ads. VSMov/NguonC are clean behind the local proxy.
    if [[ $is_vsmov -eq 0 && $is_nguonc -eq 0 && "$AD_BLOCK" == "1" ]] && [[ "$url" == *".m3u8"* ]]; then
        url=$(hls_fetch_clean "$url")
    fi

    case "$PLAYER_DEFAULT" in
        vlc)
            # Accurate seek + remote-stream buffering for the cleaned HLS
            # playlist: --no-input-fast-seek makes seeks land on the requested
            # time instead of the previous keyframe, --network-caching=3000
            # rides out CDN hiccups on segment fetches. Both are safe for
            # local/non-HLS playback; --preferred-resolution is kept as-is.
            local vlc_args=("$url" "--meta-title=$title" "--no-video-title-show" \
                "--no-input-fast-seek" "--network-caching=3000" "${extra_args[@]}")
            [[ -n "$QUALITY" ]] && vlc_args+=("--preferred-resolution=$QUALITY")
            vlc "${vlc_args[@]}" >/dev/null 2>&1 &
            LAST_PLAYER_PID=$!
            ;;
        *)
            local mpv_args=("$url" "--title=$title" "--force-window" "--save-position-on-quit" "${extra_args[@]}")
            # Seekable demuxer cache for HLS: enables smooth seek on the
            # cleaned playlist. NOT --force-seekable=yes (breaks HLS, mpv#11990).
            if [[ "$url" == *".m3u8"* ]]; then
                mpv_args+=("--cache=yes")
                # Seekable RAM cache: seeks that land inside the buffered
                # range are served from memory instead of the ffmpeg demuxer,
                # so PTS gaps left by ad removal can never reset playback to
                # the start (0:00).
                mpv_args+=("--demuxer-seekable-cache=yes")
                mpv_args+=("--demuxer-max-bytes=150M")
                mpv_args+=("--demuxer-max-back-bytes=100M")
                mpv_args+=("--hr-seek=default")
                # Prevent mpv from dropping frames at DISCONTINUITY splice
                # points left by ad removal.
                mpv_args+=("--hr-seek-framedrop=no")
                mpv_args+=("--demuxer-readahead-secs=20")
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
            LAST_PLAYER_PID=$!
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
    # v1 list endpoints: switch to the CDN base when the poster is relative.
    jq -r --arg cdn "$2" '.data.items[] |
        (if .quality then " [" + .quality + (if .lang then "-" + .lang else "" end) + "]" else "" end) as $tag |
        "\(.name)|\(.year // "N/A")\($tag)|\(.country[0].name // "N/A")|\(.episode_current // "N/A")|\(.slug)|\(if (.poster_url // "" | test("^https?://")) then .poster_url elif (.thumb_url // "" | test("^https?://")) then .thumb_url else ($cdn + "/" + (.poster_url // .thumb_url // "")) end)"' <<< "$1" 2>/dev/null
}

parse_vsmov_items() {
    # VSMov list items only carry name/year/slug/poster.
    jq -r '.items[] |
        "\(.name)|\(.year // "N/A")|\(.country[0].name? // "N/A")|\(.episode_current // "N/A")|\(.slug)|\(.poster_url // .thumb_url // "")"' <<< "$1" 2>/dev/null
}

parse_nguonc_items() {
    jq -r '.items[] |
        (if .quality then " [" + .quality + (if .language then "-" + .language else "" end) + "]" else "" end) as $tag |
        "\(.name)|\(.year // "N/A")\($tag)|N/A|\(.current_episode // "N/A")|\(.slug)|\(.poster_url // .thumb_url // "")"' <<< "$1" 2>/dev/null
}


create_preview_script() {
    local script
    script=$(mktemp "$CACHE/preview.XXXXXX.sh") || return 1
    register_temp "$script"

    local api_phimapi="$API_PHIMAPI"
    local api_vsmov="$API_VSMOV"
    local api_nguonc="$API_NGUONC"

    cat > "$script" << EOF
#!/bin/bash
$(declare -f hash_url)
IFS='|' read -ra parts <<< "\$1"

if [[ \${#parts[@]} -ge 7 ]]; then
    ten="\${parts[1]}"
    nam="\${parts[2]}"
    quocgia="\${parts[3]}"
    trangthai="\${parts[4]}"
    slug="\${parts[5]}"
    anh="\${parts[6]}"
else
    ten="\${parts[0]}"
    nam="\${parts[1]}"
    quocgia="\${parts[2]}"
    trangthai="\${parts[3]}"
    slug="\${parts[4]}"
    anh="\${parts[5]}"
    ten=\$(echo "\$ten" | sed 's/^[0-9]*\. //')
fi

src="\${parts[7]:-}"
[[ -z "\$src" ]] && src="$SOURCE"
case "\$src" in
    vsmov)  api_base="$api_vsmov"; detail_prefix="/phim/" ;;
    nguonc) api_base="$api_nguonc"; detail_prefix="/film/" ;;
    *)      api_base="$api_phimapi"; detail_prefix="/phim/" ;;
esac

origin_name=""
time_dur=""
cats=""
clean_content=""

if [[ -n "\$slug" && "\$slug" != "null" ]]; then
    desc_cache="$CACHE/desc"
    mkdir -p "\$desc_cache"
    detail_cache="\$desc_cache/\${src}-\${slug}.json"

    if [[ -f "\$detail_cache" ]]; then
        detail_res=\$(cat "\$detail_cache")
    else
        detail_res=\$(curl -fsS --max-time 2 "\${api_base}\${detail_prefix}\${slug}" 2>/dev/null)
        [[ -n "\$detail_res" ]] && printf '%s' "\$detail_res" > "\$detail_cache"
    fi

    if [[ -n "\$detail_res" ]]; then
        origin_name=\$(jq -r '.movie.origin_name // ""' <<< "\$detail_res" 2>/dev/null)
        time_dur=\$(jq -r '.movie.time // ""' <<< "\$detail_res" 2>/dev/null)
        cats=\$(jq -r '[.movie.category[]?.name] | join(", ")' <<< "\$detail_res" 2>/dev/null)
        raw_content=\$(jq -r '.movie.content // .movie.description // ""' <<< "\$detail_res" 2>/dev/null)
        clean_content=\$(printf '%s' "\$raw_content" | sed -E 's/<[^>]+>/ /g' | tr -s ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    fi
fi

# Kích thước khung preview động
cols="\${FZF_PREVIEW_COLUMNS:-80}"
wrap_w=\$(( cols - 6 ))
[[ \$wrap_w -lt 35 ]] && wrap_w=35
div=\$(printf '─%.0s' \$(seq 1 "\$wrap_w"))

poster_h=\$(( cols * 18 / 100 ))
[[ \$poster_h -lt 12 ]] && poster_h=12
[[ \$poster_h -gt 17 ]] && poster_h=17

# 1. Header Thẻ Phim
echo -e "  \033[1;36m󰟴 \${ten}\033[0m"
[[ -n "\$origin_name" && "\$origin_name" != "null" ]] && echo -e "  \033[0;90m󰑈 \${origin_name}\033[0m"

# 2. Poster Image (Căn giữa ngang chính xác trên mọi terminal)
img_url="\$anh"
if [[ "\$img_url" =~ ^https?://[^/]+/(https?://.*) ]]; then
    img_url="\${BASH_REMATCH[1]}"
fi

if [[ -z "\$img_url" || "\$img_url" == "null" ]]; then
    if [[ -n "\$detail_res" ]]; then
        detail_poster=\$(jq -r '.movie.poster_url // .movie.thumb_url // ""' <<< "\$detail_res" 2>/dev/null)
        [[ -n "\$detail_poster" && "\$detail_poster" != "null" ]] && img_url="\$detail_poster"
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
        if [[ -n "\$KITTY_WINDOW_ID" || -n "\$GHOSTTY_RESOURCES_DIR" ]]; then
            chafa_fmt="kitty"
        fi
        echo ""
        [[ "\$chafa_fmt" == "kitty" ]] && printf '\033_Ga=d,d=A\033\\'

        cache_key="\${src}-\${slug:-\$(hash_url "\$img_url")}"
        img_cache="\$desc_cache/\${cache_key}.img"
        if [[ ! -s "\$img_cache" ]]; then
            curl -fsS --max-time 4 "\$img_url" -o "\$img_cache" 2>/dev/null
            [[ ! -s "\$img_cache" ]] && rm -f "\$img_cache"
        fi

        if [[ -s "\$img_cache" ]]; then
            target_cols="\$cols"
            target_px_w=\$(( target_cols * 10 ))
            target_px_h=\$(( poster_h * 20 ))

            if command -v magick &>/dev/null; then
                magick "\$img_cache[0]" -resize "x\${target_px_h}>" -background none -gravity center -extent "\${target_px_w}x\${target_px_h}" png:- 2>/dev/null | chafa -f "\$chafa_fmt" --probe off -s "\${target_cols}x\${poster_h}" - 2>/dev/null &
            elif command -v convert &>/dev/null; then
                convert "\$img_cache[0]" -resize "x\${target_px_h}>" -background none -gravity center -extent "\${target_px_w}x\${target_px_h}" png:- 2>/dev/null | chafa -f "\$chafa_fmt" --probe off -s "\${target_cols}x\${poster_h}" - 2>/dev/null &
            elif command -v ffmpeg &>/dev/null; then
                ffmpeg -loglevel quiet -i "\$img_cache" -vf "scale=-1:\${target_px_h},pad=\${target_px_w}:\${target_px_h}:(ow-iw)/2:(oh-ih)/2:color=black@0" -c:v png -f image2 pipe:1 2>/dev/null | chafa -f "\$chafa_fmt" --probe off -s "\${target_cols}x\${poster_h}" - 2>/dev/null &
            else
                chafa -f "\$chafa_fmt" --probe off -s "\${wrap_w}x\${poster_h}" --align center "\$img_cache" 2>/dev/null &
            fi
            wait

            if [[ "\$chafa_fmt" == "kitty" ]]; then
                for ((i=1; i<poster_h; i++)); do
                    echo ""
                done
            fi
        fi
    fi
fi

# 3. Khối Thông Tin Chi Tiết (Tự động chia 2 cột nếu khung rộng)
echo -e "  \033[0;90m\${div}\033[0m"
if [[ \$cols -ge 65 ]]; then
    printf "  \033[0;33m󰃰 Năm:\033[0m %-26s \033[0;32m󱎫 Thời lượng:\033[0m %s\n" "\${nam:-N/A}" "\${time_dur:-N/A}"
    printf "  \033[0;36m󰇧 Quốc gia:\033[0m %-25s \033[0;35m󱖫 Trạng thái:\033[0m %s\n" "\${quocgia:-N/A}" "\${trangthai:-N/A}"
    [[ -n "\$cats" && "\$cats" != "null" ]] && echo -e "  \033[0;34m󰘯 Thể loại:\033[0m \$cats"
else
    [[ -n "\$nam" && "\$nam" != "null" ]] && echo -e "  \033[0;33m󰃰 Năm:\033[0m \$nam"
    [[ -n "\$quocgia" && "\$quocgia" != "null" ]] && echo -e "  \033[0;36m󰇧 Quốc gia:\033[0m \$quocgia"
    [[ -n "\$time_dur" && "\$time_dur" != "null" ]] && echo -e "  \033[0;32m󱎫 Thời lượng:\033[0m \$time_dur"
    [[ -n "\$trangthai" && "\$trangthai" != "null" ]] && echo -e "  \033[0;35m󱖫 Trạng thái:\033[0m \$trangthai"
    [[ -n "\$cats" && "\$cats" != "null" ]] && echo -e "  \033[0;34m󰘯 Thể loại:\033[0m \$cats"
fi

# 4. Tóm Tắt Nội Dung Phim (Trải rộng toàn bộ khung preview)
if [[ -n "\$clean_content" && "\$clean_content" != "null" ]]; then
    echo -e "  \033[0;90m\${div}\033[0m"
    echo -e "  \033[1;33m󰧭 Nội dung tóm tắt:\033[0m"
    printf '%s\n' "\$clean_content" | fold -s -w "\$wrap_w" | sed 's/^/   /'
fi
EOF
    chmod +x "$script"
    echo "$script"
}


pick_server() {
    local res="$1" episodes_path="$2"
    local idx=0

    local parsed name_list
    parsed=$(jq -r "
        [${episodes_path}[] | .server_name] as \$names
        | (\$names | length) as \$count
        | \"COUNT=\(\$count)\", \$names[]
    " <<< "$res" 2>/dev/null) || return 1

    local count
    IFS= read -r count <<< "$parsed"
    count="${count#COUNT=}"

    if [[ "${count:-0}" -gt 1 ]]; then
        name_list="${parsed#*$'\n'}"
        local name
        name=$(add_menu_numbers <<< "$name_list" | fzf "${FZF_OPTS[@]}" --prompt="Server > " --header="Chọn server" --height=40%)
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

_watch_episode_body() {
    local slug="$1" ten="$2"

    show_loading

    local res ds_tap server_idx episodes_path=".episodes"

    if [[ "$SOURCE" == "nguonc" ]]; then
        episodes_path=".movie.episodes"
        res=$(call_api "/film/$slug")
    else
        res=$(call_api "/phim/$slug")
    fi
    [[ -z "$res" ]] && { show_error "Không lấy được thông tin"; return; }

    server_idx=$(pick_server "$res" "$episodes_path") || return
    if [[ "$SOURCE" == "nguonc" ]]; then
        ds_tap=$(jq -r --argjson idx "$server_idx" '.movie.episodes[$idx].items[] | "\(.name)|\(.embed)"' <<< "$res" 2>/dev/null)
    else
        ds_tap=$(jq -r --argjson idx "$server_idx" '.episodes[$idx].server_data[] | select(((.link_m3u8 // "") != "") or ((.link_embed // "") != "")) | "\(.name)|\(if (.link_m3u8 // "") != "" then .link_m3u8 else (.link_embed // "") end)"' <<< "$res" 2>/dev/null)
    fi

    [[ -z "$ds_tap" ]] && { show_error "Không có tập phim"; return; }


    local last_ep=""
    if [[ -f "$PROGRESS" ]]; then
        last_ep=$(awk -F'|' -v s="$slug" '$1 == s {ep=$2} END {if (ep != "") print ep}' "$PROGRESS")
    fi
    local continue_header=""
    if [[ -n "$last_ep" ]]; then
        local last_ep_label="$last_ep"
        [[ "$last_ep" =~ ^[0-9]+$ ]] && last_ep_label="Tập ${last_ep}"
        continue_header="  ▶ Tiếp: ${last_ep_label}"
    fi

    local chon=""
    local phim=""
    local data=""

    while true; do
        chon=""
        phim=""
        data=""

        chon=$(fzf "${FZF_OPTS[@]}" \
            --header="$ten${continue_header:+  │  }${continue_header}  │  Enter xem  │  Tab tải  │  Ctrl+F yêu thích" \
            --prompt="Chọn tập > " \
            --delimiter='|' --with-nth=1 \
            --expect=enter,tab,ctrl-f <<< "$ds_tap")
        [[ -z "$chon" ]] && break

        IFS= read -r phim <<< "$chon"
        [[ "$chon" == *$'\n'* ]] && data="${chon#*$'\n'}"
        [[ -z "$data" ]] && break

        local tap="${data%%|*}"
        local url="${data#*|}"
        local tieu_de
        if [[ "$tap" =~ ^[0-9]+$ ]]; then
            tieu_de="${ten} - Tập ${tap}"
        else
            tieu_de="${ten} - ${tap}"
        fi

        case "$phim" in
            enter)
                record_history "$slug" "$tieu_de" "$url" "$tap" || show_error "Không ghi được lịch sử"
                record_progress "$slug" "$tap" || show_error "Không ghi được tiến độ"
                local tap_label="$tap"
                [[ "$tap" =~ ^[0-9]+$ ]] && tap_label="Tập ${tap}"
                continue_header="  ▶ Vừa xem: ${tap_label}"

                play_video "$url" "$tieu_de"
                [[ -n "$LAST_PLAYER_PID" ]] && wait "$LAST_PLAYER_PID" 2>/dev/null
                stop_hls_proxy
                ;;
            tab)
                download_episode "$url" "$tieu_de"
                ;;
            ctrl-f)
                add_favorite "$ten" "$slug" "" "" "$SOURCE" || show_error "Không lưu được yêu thích"
                ;;
        esac
    done
}

watch_episode() {
    local src="${3:-$SOURCE}" prev_source="$SOURCE" prev_api="$API_BASE" rc

    if [[ "$src" != "$SOURCE" ]]; then
        SOURCE="$src"
        set_api_base
    fi
    _watch_episode_body "$1" "$2"
    rc=$?
    SOURCE="$prev_source"
    API_BASE="$prev_api"
    return $rc
}

show_list() {
    local items="$1" prompt="$2"
    [[ -z "$items" ]] && { show_error "Không có kết quả"; return; }

    local preview
    preview=$(create_preview_script) || { show_error "Không tạo được preview"; return; }

    local formatted
    formatted=$(format_movie_items <<< "$items")

    local chon
    chon=$(fzf "${FZF_OPTS[@]}" \
        --delimiter='|' --with-nth='{1}' \
        --preview="$preview {}" \
        --header="Enter chọn · Esc quay lại " \
        --prompt="$prompt > " <<< "$formatted")

    rm -f "$preview"

    if [[ -n "$chon" ]]; then
        local arr=()
        IFS='|' read -ra arr <<< "$chon"
        watch_episode "${arr[5]}" "${arr[1]}" "${arr[7]:-}"
    fi
}

show_paginated_list() {
    local prompt="$1"
    local fetch_callback="$2"
    local page=1
    local preview
    preview=$(create_preview_script) || { show_error "Không tạo được preview"; return; }

    while true; do
        local items
        items=$($fetch_callback "$page")

        if [[ -z "$items" ]]; then
            if [[ $page -gt 1 ]]; then
                ((page--))
                continue
            fi
            show_error "Không có kết quả"
            rm -f "$preview"
            return
        fi

        local formatted
        formatted=$(format_movie_items <<< "$items")

        local output
        output=$(fzf "${FZF_OPTS[@]}" \
            --delimiter='|' --with-nth='{1}' \
            --preview="$preview {}" \
            --header="Enter chọn · ←/→ trang $page · Esc quay lại " \
            --prompt="$prompt > " \
            --expect=right,left,enter <<< "$formatted")

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
                    watch_episode "${arr[5]}" "${arr[1]}" "${arr[7]:-}"
                fi
                return
                ;;
        esac
    done
}


fetch_list() {
    local loai="$1" p="$2" extra="${3:-}" res cdn path
    if [[ "$SOURCE" == "nguonc" ]]; then
        case "$loai" in
            phim-moi)  path="/films/phim-moi-cap-nhat" ;;
            phim-bo)   path="/films/danh-sach/phim-bo" ;;
            phim-le)   path="/films/danh-sach/phim-le" ;;
            hoat-hinh) path="/films/the-loai/hoat-hinh" ;;
            *)         path="/films/$loai" ;;
        esac
        res=$(call_api "${path}?page=${p}")
        [[ -z "$res" ]] && return
        parse_nguonc_items "$res"
        return
    fi
    if [[ "$SOURCE" == "vsmov" ]]; then
        res=$(call_api "/danh-sach/${loai}?page=${p}")
        [[ -z "$res" ]] && return
        parse_vsmov_items "$res"
        return
    fi
    if [[ -n "$extra" ]]; then
        res=$(call_api "/v1/api/${loai}?${extra}&page=${p}&limit=30&sort_field=modified.time&sort_type=desc")
    else
        res=$(call_api "/v1/api/${loai}?page=${p}&limit=30&sort_field=modified.time&sort_type=desc")
    fi
    [[ -z "$res" ]] && return
    cdn=$(jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""' <<< "$res")
    parse_v1_items "$res" "$cdn"
}

create_search_script() {
    local script sources="$SEARCH_SOURCES"
    [[ -z "$sources" ]] && sources="$SOURCE"
    script=$(mktemp "$CACHE/search.XXXXXX.sh") || return 1
    register_temp "$script"
    cat > "$script" << EOF
#!/bin/bash
$(declare -f format_movie_items)
$(declare -f parse_v1_items)
$(declare -f parse_vsmov_items)
$(declare -f parse_nguonc_items)

[[ -z "\$1" || \${#1} -lt 2 ]] && exit 0
q=\$(jq -rn --arg q "\$1" '\$q|@uri' 2>/dev/null) || exit 0
for src in ${sources//,/ }; do
    out=""
    case "\$src" in
        phimapi)
            res=\$(curl -fsS --max-time 5 "${API_PHIMAPI}/v1/api/tim-kiem?keyword=\${q}&limit=20" 2>/dev/null)
            if [[ -n "\$res" ]]; then
                cdn=\$(jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""' <<< "\$res")
                out=\$(parse_v1_items "\$res" "\$cdn")
            fi
            ;;
        vsmov)
            res=\$(curl -fsS --max-time 5 "${API_VSMOV}/tim-kiem?keyword=\${q}" 2>/dev/null)
            [[ -n "\$res" ]] && out=\$(parse_vsmov_items "\$res")
            ;;
        nguonc)
            res=\$(curl -fsS --max-time 5 "${API_NGUONC}/films/search?keyword=\${q}" 2>/dev/null)
            [[ -n "\$res" ]] && out=\$(parse_nguonc_items "\$res")
            ;;
    esac
    [[ -z "\$out" ]] && continue
    while IFS= read -r line; do
        printf '%s|%s\n' "\$line" "\$src"
    done <<< "\$out"
done | format_movie_items
EOF
    chmod +x "$script"
    echo "$script"
}


search() {
    local initial_query="$1"
    local search preview
    search=$(create_search_script) || { show_error "Không tạo được script tìm kiếm"; return; }
    preview=$(create_preview_script) || { rm -f "$search"; show_error "Không tạo được preview"; return; }

    local fzf_query_arg=()
    local initial_input=""
    if [[ -n "$initial_query" ]]; then
        fzf_query_arg=(--query="$initial_query")
        initial_input=$("$search" "$initial_query" 2>/dev/null)
    fi

    local chon
    chon=$(printf '%s\n' "$initial_input" | fzf "${FZF_OPTS[@]}" \
        "${fzf_query_arg[@]}" \
        --prompt="Tìm phim > " --header="Enter chọn · gõ để tìm kiếm " --phony \
        --delimiter='|' --with-nth='{1}' \
        --bind "change:reload:sleep 0.2; $search {q} || true" \
        --preview="$preview {}")

    rm -f "$search" "$preview"
    if [[ -n "$chon" ]]; then
        local arr=()
        IFS='|' read -ra arr <<< "$chon"
        watch_episode "${arr[5]}" "${arr[1]}" "${arr[7]:-}"
    fi
}

new_releases() {
    show_loading
    local res
    if [[ "$SOURCE" == "nguonc" ]]; then
        res=$(call_api "/films/phim-moi-cap-nhat?page=1")
        [[ -z "$res" ]] && { show_error "Lỗi kết nối"; return; }
        show_list "$(parse_nguonc_items "$res")" "PHIM MỚI"
        return
    fi
    if [[ "$SOURCE" == "vsmov" ]]; then
        res=$(call_api "/danh-sach/phim-moi?page=1")
        [[ -z "$res" ]] && { show_error "Lỗi kết nối"; return; }
        show_list "$(parse_vsmov_items "$res")" "PHIM MỚI"
        return
    fi
    res=$(call_api "/danh-sach/phim-moi-cap-nhat-v3?page=1")
    [[ -z "$res" ]] && { show_error "Lỗi kết nối"; return; }
    show_list "$(parse_phimapi_v3 "$res")" "PHIM MỚI"
}

browse() {
    local menu
    if [[ "$SOURCE" == "nguonc" || "$SOURCE" == "vsmov" ]]; then
        menu="󰎁  Phim Mới|phim-moi
󰎁  Phim Bộ|phim-bo
󰎁  Phim Lẻ|phim-le
󰎁  Hoạt Hình|hoat-hinh"
    else
        menu="󰎁  Phim Mới|phim-moi
󰎁  Phim Bộ|phim-bo
󰎁  Phim Lẻ|phim-le
󰎁  TV Shows|tv-shows
󰎁  Hoạt Hình|hoat-hinh"
    fi

    local chon
    chon=$(echo -e "$menu" | add_menu_numbers | fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth=1 --prompt="Duyệt > " --height=50%)
    [[ -z "$chon" ]] && return

    local loai="${chon#*|}"
    local ten_raw="${chon%%|*}"
    local ten="${ten_raw#*. }"

    if [[ "$SOURCE" == "nguonc" ]]; then
        fetch_browse() { fetch_list "$loai" "$1"; }
    elif [[ "$SOURCE" == "vsmov" ]]; then
        fetch_browse() {
            local res
            if [[ "$loai" == "hoat-hinh" ]]; then
                res=$(call_api "/the-loai/hoat-hinh?page=$1")
            else
                res=$(call_api "/danh-sach/${loai}?page=$1")
            fi
            [[ -z "$res" ]] && return
            parse_vsmov_items "$res"
        }
    else
        fetch_browse() {
            fetch_list "danh-sach/${loai}" "$1"
        }
    fi

    show_paginated_list "$ten" fetch_browse
}


filter_by_category() {
    local prompt="$1" endpoint="$2" param="$3"
    show_loading
    local res ds

    res=$(call_api "$endpoint")
    [[ -z "$res" ]] && { show_error "Lỗi"; return; }
    ds=$(jq -r '.data.items[] | "\(.name)|\(.slug)"' <<< "$res" 2>/dev/null)

    local chon
    chon=$(echo -e "$ds" | add_menu_numbers | fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth=1 --prompt="$prompt > ")
    [[ -z "$chon" ]] && return

    local slug="${chon#*|}"
    local ten_raw="${chon%%|*}"
    local ten="${ten_raw#*. }"

    fetch_category() {
        if [[ "$SOURCE" == "vsmov" ]]; then
            local res kind="the-loai"
            [[ "$param" == "country" ]] && kind="quoc-gia"
            res=$(call_api "/${kind}/${slug}?page=$1")
            [[ -z "$res" ]] && return
            parse_vsmov_items "$res"
        else
            fetch_list "danh-sach/phim-moi" "$1" "${param}=${slug}"
        fi
    }

    show_paginated_list "$ten" fetch_category
}

filter_by_year() {
    local nam_hien_tai=${CURRENT_YEAR:-$(date +%Y)}
    local ds="" y
    for ((y = nam_hien_tai; y >= 2000; y--)); do
        ds+="$y"$'\n'
    done
    ds="${ds%$'\n'}"

    local chon
    chon=$(echo -e "$ds" | add_menu_numbers | fzf "${FZF_OPTS[@]}" --prompt="Năm > " --height=50%)
    [[ -z "$chon" ]] && return

    local nam_chon="${chon#*. }"


    fetch_year() {
        if [[ "$SOURCE" == "vsmov" ]]; then
            local res
            res=$(call_api "/nam/${nam_chon}?page=$1")
            [[ -z "$res" ]] && return
            parse_vsmov_items "$res"
        else
            fetch_list "nam/${nam_chon}" "$1"
        fi
    }

    show_paginated_list "Năm $nam_chon" fetch_year
}

anime_mode() {

    fetch_anime() {
        local p="$1"
        local res cdn
        if [[ "$SOURCE" == "nguonc" ]]; then
            res=$(call_api "/films/the-loai/hoat-hinh?page=${p}")
            [[ -z "$res" ]] && return
            parse_nguonc_items "$res"
            return
        fi
        if [[ "$SOURCE" == "vsmov" ]]; then
            res=$(call_api "/the-loai/hoat-hinh?page=${p}")
            [[ -z "$res" ]] && return
            parse_vsmov_items "$res"
            return
        fi
        res=$(call_api "/v1/api/danh-sach/hoat-hinh?page=${p}&country=nhat-ban&sort_field=modified.time&sort_type=desc")
        [[ -z "$res" ]] && return
        cdn=$(jq -r '.data.APP_DOMAIN_CDN_IMAGE // ""' <<< "$res")
        parse_v1_items "$res" "$cdn"
    }

    show_paginated_list "Anime" fetch_anime
}

advanced_filter() {
    if [[ "$SOURCE" == "nguonc" ]]; then
        show_error "NguonC chưa hỗ trợ lọc"
        return
    fi
    local menu="  Thể loại|theloai
  Quốc gia|quocgia
  Năm|nam"

    local chon
    chon=$(echo -e "$menu" | add_menu_numbers | fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth=1 --prompt="Lọc > " --height=40%)
    [[ -z "$chon" ]] && return

    case "${chon#*|}" in
        theloai) filter_by_category "Thể loại" "/the-loai" "category" ;;
        quocgia) filter_by_category "Quốc gia" "/quoc-gia" "country" ;;
        nam)     filter_by_year ;;
    esac
}

history() {
    [[ ! -s "$HIST" ]] && { show_error "Chưa có lịch sử"; return; }

    local formatted
    formatted=$(sort -rn "$HIST" | awk -F'|' '{
        display = sprintf("\033[0;33m%2d.\033[0m  \033[1;37m󰎤 %s\033[0m", NR, $2)
        printf "%s|%s|%s|%s|%s|%s\n", display, $1, $2, $3, $4, $5
    }')

    local chon
    chon=$(fzf "${FZF_OPTS[@]}" \
        --delimiter='|' --with-nth=1 \
        --header="Enter xem lại · Esc quay lại " \
        --prompt="Lịch sử > " <<< "$formatted")
    [[ -z "$chon" ]] && return
    local title slug url ep fresh
    IFS='|' read -r _ _ title slug url ep <<< "$chon"
    [[ -z "$url" ]] && return
    fresh=$(resolve_saved_url "$slug" "$ep" "$url")
    [[ -n "$fresh" ]] && url="$fresh"
    play_video "$url" "$title"
    [[ -n "$LAST_PLAYER_PID" ]] && wait "$LAST_PLAYER_PID" 2>/dev/null
    stop_hls_proxy
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

    local chon
    chon=$(fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth=1 \
        --header="Enter xem · Ctrl+D xóa · Esc quay lại " \
        --prompt="Yêu thích > " --expect=enter,ctrl-d <<< "$parsed_favs")

    local phim data
    IFS= read -r phim <<< "$chon"
    [[ "$chon" == *$'\n'* ]] && data="${chon#*$'\n'}"
    [[ -z "$data" ]] && return

    local ten slug year poster src
    IFS='|' read -r ten slug year poster src <<< "$data"

    case "$phim" in
        enter)  watch_episode "$slug" "$ten" "$src" ;;
        ctrl-d)
            remove_favorite "$slug" || show_error "Không xóa được yêu thích"
            ;;
    esac
}

select_player() {
    local mpv_mark="" vlc_mark=""
    local has_mpv=0; command -v mpv &>/dev/null && has_mpv=1
    local has_vlc=0; command -v vlc &>/dev/null && has_vlc=1

    [[ "$PLAYER_DEFAULT" == "mpv" ]] && mpv_mark=" \033[1;32m(đang dùng)\033[0m"
    [[ "$PLAYER_DEFAULT" == "vlc" ]] && vlc_mark=" \033[1;32m(đang dùng)\033[0m"

    local menu=""
    [[ $has_mpv -eq 1 ]] && menu+="  MPV${mpv_mark} (Khuyên dùng)|mpv\n"
    [[ $has_vlc -eq 1 ]] && menu+="  VLC${vlc_mark}|vlc"

    [[ -z "$menu" ]] && { show_error "Không có trình phát"; return; }

    local chon
    chon=$(echo -e "$menu" | add_menu_numbers | fzf "${FZF_OPTS[@]}" \
        --delimiter='|' --with-nth=1 --prompt="Trình phát > " --height=40% \
        --header="Trình phát · Esc quay lại ")
    [[ -z "$chon" ]] && return

    PLAYER_DEFAULT="${chon#*|}"
    save_settings
}


select_quality() {
    local current_mark_1080="" current_mark_720="" current_mark_480="" current_mark_auto=""

    case "$QUALITY" in
        1080) current_mark_1080=" \033[1;32m(đang dùng)\033[0m" ;;
        720)  current_mark_720=" \033[1;32m(đang dùng)\033[0m" ;;
        480)  current_mark_480=" \033[1;32m(đang dùng)\033[0m" ;;
        *)    current_mark_auto=" \033[1;32m(đang dùng)\033[0m" ;;
    esac

    local menu="󰎤  Tự động${current_mark_auto}|auto
󰎤  1080p${current_mark_1080}|1080
󰎤  720p${current_mark_720}|720
󰎤  480p${current_mark_480}|480"

    local chon
    chon=$(echo -e "$menu" | add_menu_numbers | fzf "${FZF_OPTS[@]}" \
        --delimiter='|' --with-nth=1 --prompt="Chất lượng > " --height=40% \
        --header="Chất lượng mặc định · Esc quay lại ")
    [[ -z "$chon" ]] && return

    local selected="${chon#*|}"
    [[ "$selected" == "auto" ]] && QUALITY="" || QUALITY="$selected"

    save_settings
}

purge_api_cache() {
    rm -f "$CACHE"/*.json "$CACHE"/*-clean.m3u8 "$CACHE"/*-dl.m3u8
    rm -f "$CACHE"/hls-proxy.py "$CACHE"/hls-proxy.log "$CACHE"/hls-proxy.*.port
    rm -f "$CACHE"/vsmov-proxy.py "$CACHE"/vsmov-proxy.log "$CACHE"/vsmov-proxy.*.port
    rm -rf "$CACHE/desc" "$CACHE/segments"
}

clear_cache() {
    local count=0 f
    for f in "$CACHE"/*.json "$CACHE"/*-clean.m3u8 "$CACHE"/*-dl.m3u8; do
        [[ -f "$f" ]] && ((count++))
    done
    if [[ -d "$CACHE/desc" ]]; then
        count=$((count + $(find "$CACHE/desc" -type f 2>/dev/null | wc -l)))
    fi
    purge_api_cache
    log_debug "Cache cleared manually: $count files removed"
    echo -e "${C_G}  Đã xóa ${count} file cache.${C_R}"
    sleep 1
}

toggle_ad_block() {
    if [[ "$AD_BLOCK" == "1" ]]; then
        AD_BLOCK=0
        echo -e "${C_Y}  Chặn quảng cáo: TẮT${C_R}"
    else
        AD_BLOCK=1
        echo -e "${C_G}  Chặn quảng cáo: BẬT${C_R}"
    fi
    save_settings
    sleep 1
}

source_name() {
    case "$1" in
        phimapi) printf '%s' "PhimAPI" ;;
        vsmov)   printf '%s' "VSMov" ;;
        nguonc)  printf '%s' "NguonC" ;;
        *)       printf '%s' "$1" ;;
    esac
}

select_search_sources() {
    local menu="PhimAPI|phimapi"
    if command -v python3 >/dev/null 2>&1; then
        menu+="
VSMov|vsmov
NguonC|nguonc"
    fi

    local chon line src out=""
    chon=$(echo -e "$menu" | add_menu_numbers | fzf "${FZF_OPTS[@]}" --multi \
        --delimiter='|' --with-nth=1 --prompt="Nguồn tìm kiếm > " --height=40% \
        --header="Tab chọn nhiều · Enter xác nhận · hiện tại: ${SEARCH_SOURCES}")
    [[ -z "$chon" ]] && return

    while IFS= read -r line; do
        src="${line#*|}"
        out+="${out:+,}$src"
    done <<< "$chon"
    [[ -z "$out" ]] && return

    SEARCH_SOURCES="$out"
    save_settings
}

select_source() {
    local phimapi_mark="" vsmov_mark="" nguonc_mark=""
    [[ "$SOURCE" == "phimapi" ]] && phimapi_mark=" \033[1;32m(đang dùng)\033[0m"
    [[ "$SOURCE" == "vsmov" ]] && vsmov_mark=" \033[1;32m(đang dùng)\033[0m"
    [[ "$SOURCE" == "nguonc" ]] && nguonc_mark=" \033[1;32m(đang dùng)\033[0m"

    local menu="PhimAPI${phimapi_mark}|phimapi
VSMov${vsmov_mark}|vsmov
NguonC${nguonc_mark}|nguonc"

    local chon
    chon=$(echo -e "$menu" | add_menu_numbers | fzf "${FZF_OPTS[@]}" \
        --delimiter='|' --with-nth=1 --prompt="Nguồn duyệt > " --height=40% \
        --header="Nguồn duyệt · Esc quay lại ")
    [[ -z "$chon" ]] && return

    local selected="${chon#*|}"
    if [[ "$selected" == "vsmov" || "$selected" == "nguonc" ]] && ! command -v python3 >/dev/null 2>&1; then
        show_error "Nguồn này cần python3"
        return
    fi
    SOURCE="$selected"
    set_api_base
    save_settings
}

settings() {
    local ad_status source_status search_label="" item
    local -a srcs=()
    [[ "$AD_BLOCK" == "1" ]] && ad_status="\033[1;32m[BẬT]\033[0m" || ad_status="\033[1;31m[TẮT]\033[0m"
    source_status=$(source_name "$SOURCE")
    IFS=',' read -ra srcs <<< "$SEARCH_SOURCES"
    for item in "${srcs[@]}"; do
        search_label+="${search_label:+, }$(source_name "$item")"
    done

    local menu="${I_SOURCE} Nguồn duyệt: ${source_status}|source
${I_SOURCE} Nguồn tìm kiếm: ${search_label}|searchsources
${I_PLAYER} Trình phát|player
${I_QUA} Chất lượng|quality
󰫈  Chặn quảng cáo: ${ad_status}|adblock
󰇚  Tải phim|downloads
${I_DIR} Mở thư mục|folder
${I_CACHE} Xóa cache|cache"

    local chon
    chon=$(echo -e "$menu" | add_menu_numbers | fzf "${FZF_OPTS[@]}" \
        --delimiter='|' --with-nth=1 --prompt="Cài đặt > " --height=45% \
        --header="Cài đặt · Esc quay lại ")
    [[ -z "$chon" ]] && return

    case "${chon#*|}" in
        source)         select_source ;;
        searchsources)  select_search_sources ;;
        player)    select_player ;;
        quality)   select_quality ;;
        adblock)   toggle_ad_block ;;
        downloads) view_downloads ;;
        folder)    thunar "$DL" 2>/dev/null || dolphin "$DL" 2>/dev/null || xdg-open "$DL" ;;
        cache)     clear_cache ;;
    esac
}

show_banner() {
    printf '\033[H\033[2J'
    local nguon_text player_text quality_text
    case "$SOURCE" in
        vsmov)  nguon_text="VSMov" ;;
        nguonc) nguon_text="NguonC" ;;
        *)      nguon_text="PhimAPI" ;;
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
    echo -e "${C_G} ⣠⣾⣿⣿⣿⣿⣶⣶⣤⣤⣤⣤⣤⣤⣶⣾⣿⣿⣿⣿⣿⣿⣿⡇${C_R}     ${C_M}Duyệt: ${nguon_text}${C_R}"
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

    menu_items+="${I_SEARCH} Tìm phim\n"
    menu_items+="${I_NEW} Phim mới\n"
    menu_items+="${I_BROWSE} Duyệt\n"
    menu_items+="${I_ANIME} Anime\n"
    menu_items+="${I_FILTER} Lọc\n"
    menu_items+="${I_HIST} Lịch sử\n"
    menu_items+="${I_FAV} Yêu thích\n"
    menu_items+="${I_SETTINGS} Cài đặt\n"
    menu_items+="${I_EXIT} Thoát"

    echo -e "$menu_items" | add_menu_numbers | fzf "${FZF_OPTS[@]}" \
        --prompt="Menu > " --height=50% \
        --border-label=" 🍙 Sudachi Menu " --border-label-pos=2 \
        --header="Chọn mục · mũi tên hoặc phím số "
}

show_help() {
    echo -e "${C_G}Sudachi — Trình xem phim & anime tiếng Việt trên Terminal${C_R}"
    echo ""
    echo "Cách dùng: sudachi [tùy chọn]"
    echo ""
    echo "Tùy chọn:"
    echo "  -s, --search [TỪ_KHÓA]    Tìm kiếm phim trực tiếp"
    echo "  -c, --continue            Xem tiếp tập phim đang xem dở gần nhất"
    echo "  -l, --latest              Mở danh sách Phim Mới"
    echo "  -a, --anime               Mở danh mục Anime"
    echo "  -d, --downloads           Xem tiến độ và danh sách tải phim"
    echo "  -h, --help                Hiển thị trợ giúp này"
    echo ""
}

handle_cli_args() {
    [[ $# -eq 0 ]] && return 0

    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -s|--search)
            shift
            search "$*"
            exit 0
            ;;
        -c|--continue)
            if [[ -s "$HIST" ]]; then
                local last_line
                last_line=$(sort -rn "$HIST" | head -1)
                local title slug url ep fresh
                IFS='|' read -r _ title slug url ep <<< "$last_line"
                fresh=$(resolve_saved_url "$slug" "$ep" "$url")
                [[ -n "$fresh" ]] && url="$fresh"
                if [[ -n "$url" ]]; then
                    echo -e "${C_G}▶ Tiếp tục xem: $title${C_R}"
                    check_player
                    play_video "$url" "$title"
                    [[ -n "$LAST_PLAYER_PID" ]] && wait "$LAST_PLAYER_PID" 2>/dev/null
                    stop_hls_proxy
                    exit 0
                fi
            fi
            echo -e "${C_Y}Chưa có lịch sử xem phim nào.${C_R}"
            exit 1
            ;;
        -l|--latest)
            new_releases
            exit 0
            ;;
        -a|--anime)
            anime_mode
            exit 0
            ;;
        -d|--downloads)
            view_downloads
            exit 0
            ;;
        *)
            echo -e "${C_Y}Tùy chọn không hợp lệ: $1${C_R}"
            echo "Chạy 'sudachi --help' để xem danh sách tùy chọn."
            exit 1
            ;;
    esac
}


load_settings
set_api_base
# Help must work on a machine without fzf/curl/player.
case "${1:-}" in
    -h|--help) show_help; exit 0 ;;
esac
check_dependencies
handle_cli_args "$@"
check_player

while true; do
    show_banner
    case "$(main_menu)" in
        *"Tìm phim"*)   search ;;
        *"Phim mới"*)   new_releases ;;
        *"Duyệt"*)      browse ;;
        *"Anime"*)      anime_mode ;;
        *"Lọc"*)        advanced_filter ;;
        *"Lịch sử"*)    history ;;
        *"Yêu thích"*)  favorites ;;
        *"Cài đặt"*)    settings ;;
        *"Thoát"*)      exit 0 ;;
    esac
done
