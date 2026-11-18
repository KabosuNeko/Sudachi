#!/bin/bash

CONF="$HOME/.config/sudachi"
DL="$HOME/Downloads/Sudachi-Downloaded"
HIST="$CONF/history.log"
FAV="$CONF/favorites.log"
PROGRESS="$CONF/progress.log"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/sudachi"
CONFIG_FILE="$CONF/config"
PLAYER_DEFAULT="mpv"

# K20 Stremio addons: KKPhim/VSMov/NguonC and AnimeVietsub, ads stripped server-side.
API_K20="https://sc.k-20.xyz"
API_K20_ANIME="https://anime.k-20.xyz"
# K20 answers 404 to curl's default User-Agent.
UA="Sudachi"
# Kitsu (the anime catalog Stremio uses) supplies covers and synopses that K20 Anime lacks.
KITSU_SEARCH="https://anime-kitsu.strem.fun/catalog/anime/kitsu-anime-list"

mkdir -p "$CONF" "$DL" "$CACHE"
ANIME_INDEX="$CACHE/anime-index.txt"
touch "$HIST" "$FAV" "$PROGRESS"
# Preview meta and posters pile up for every title hovered; drop ones unused for 30 days.
find "$CACHE/desc" "$CACHE/playlists" -type f -mtime +30 -delete 2>/dev/null

TEMP_FILES=()

I_SEARCH="󱇓 "
I_NEW="󰎁 "
I_BROWSE="󰖟 "
I_HIST="󰋚 "
I_FAV="󰋑 "
I_SETTINGS="󰒓 "
I_DIR=" "
I_DOWN="󰇚 "
I_ANIME=" "
I_PLAYER=" "
I_CACHE="󰃢 "

C_G='\033[1;32m'
C_Y='\033[1;33m'
C_C='\033[0;36m'
C_M='\033[1;35m'
C_R='\033[0m'

# k20_base <src> -- addon base URL for a source tag.
k20_base() {
    case "$1" in
        k20anime) printf '%s' "$API_K20_ANIME" ;;
        *)        printf '%s' "$API_K20" ;;
    esac
}

load_settings() {
    local line key value

    [[ -f "$CONFIG_FILE" ]] || return

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "${line:0:1}" == "#" || "$line" != *"="* ]] && continue

        key="${line%%=*}"
        value="${line#*=}"
        key="${key//[[:space:]]/}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        value="${value%\"}"
        value="${value#\"}"
        value="${value%\'}"
        value="${value#\'}"

        # Keys from older versions (QUALITY, AD_BLOCK, SOURCE, SEARCH_SOURCES) are ignored.
        [[ "$key" == PLAYER_DEFAULT && ( "$value" == mpv || "$value" == vlc ) ]] && PLAYER_DEFAULT="$value"
    done < "$CONFIG_FILE"
}

save_settings() {
    printf 'PLAYER_DEFAULT=%s\n' "$PLAYER_DEFAULT" > "$CONFIG_FILE"
}

# Input: name|year|country|provider|slug|poster[|src[|alternatives]]. Output prepends the display column.
format_movie_items() {
    awk -F'|' '
    {
        display_tag = ""
        if ($2 != "" && $2 != "N/A") {
            display_tag = "  \033[0;34m·\033[0m  \033[0;35m" $2 "\033[0m"
        }
        if ($4 != "" && $4 != "N/A") {
            display_tag = display_tag "  \033[0;36m[" $4 "]\033[0m"
        }
        display = sprintf("\033[1;37m%s\033[0m%s", $1, display_tag)
        printf "%s|%s|%s|%s|%s|%s|%s|%s|%s\n", display, $1, $2, $3, $4, $5, $6, $7, $8
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
    # noinfo keeps the preview's scroll counter off the end of the title line;
    # list wrapping is added by check_dependencies, which knows the fzf version.
    "--preview-window=right:50%:rounded:wrap:noinfo"
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

    if [[ ${#missing[@]} -eq 0 ]]; then
        local fzf_version
        fzf_version=$(fzf --version | cut -d' ' -f1)
        # --with-nth '{1}' templates need fzf 0.60; Debian 12 ships 0.38.
        if [[ "$(printf '0.60\n%s\n' "$fzf_version" | sort -V | head -1)" != "0.60" ]]; then
            echo -e "${C_Y}⚠ fzf ${fzf_version} quá cũ, Sudachi cần fzf >= 0.60.${C_R}"
            echo -e "${C_C}  Tải bản mới: https://github.com/junegunn/fzf/releases${C_R}"
            exit 1
        fi
        # Long titles wrap instead of ending in "…"; whole words since fzf 0.68.
        if [[ "$(printf '0.68\n%s\n' "$fzf_version" | sort -V | head -1)" == "0.68" ]]; then
            FZF_OPTS+=("--wrap=word")
        else
            FZF_OPTS+=("--wrap")
        fi
        return
    fi
    echo -e "${C_Y}⚠ Thiếu các gói bắt buộc: ${missing[*]}${C_R}"
    echo -e "${C_C}Vui lòng cài đặt trước khi chạy Sudachi.${C_R}"
    echo -e "${C_C}  Arch:   sudo pacman -S ${missing[*]}${C_R}"
    echo -e "${C_C}  Debian: sudo apt install ${missing[*]}${C_R}"
    exit 1
}

cleanup() {
    local f
    nguonc_proxy_stop
    for f in "${TEMP_FILES[@]}"; do
        rm -f "$f"
    done
}

register_temp() {
    TEMP_FILES+=("$1")
}
trap cleanup EXIT
trap 'exit 130' INT TERM


log_debug() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$CACHE/debug.log"
}

hash_url() {
    printf '%s' "$1" | md5sum | cut -d' ' -f1
}

is_cache_fresh() {
    local mtime now
    mtime=$(stat -c %Y "$1" 2>/dev/null) || return 1
    printf -v now '%(%s)T' -1
    (( now - mtime < $2 ))
}

sanitize_field() {
    local value="$1"
    value="${value//$'\n'/ }"
    value="${value//$'\r'/ }"
    value="${value//|/-}"
    printf '%s' "$value"
}

# call_api <url> -- JSON body, cached for an hour; 1 after three failed tries.
call_api() {
    local url="$1" cache_file res attempt
    cache_file="$CACHE/$(hash_url "$url").json"

    if is_cache_fresh "$cache_file" 3600; then
        cat "$cache_file"
        return
    fi
    for attempt in 1 2 3; do
        res=$(curl -fsS -A "$UA" --connect-timeout 10 --max-time 30 "$url" 2>/dev/null)
        # K20 answers unknown ids with HTTP 200 and {"meta":null}.
        if jq -e 'type == "object" and (has("error") | not) and ((has("meta") | not) or .meta != null)' <<< "$res" >/dev/null 2>&1; then
            printf '%s\n' "$res" > "$cache_file"
            printf '%s\n' "$res"
            return
        fi
        log_debug "call_api attempt $attempt failed for $url"
        [[ $attempt -lt 3 ]] && sleep 1
    done

    log_debug "call_api all 3 attempts failed for $url — response: ${res:0:200}"
    return 1
}

# parse_k20_items <json> -- name|year|N/A|provider|<type>/<id>|poster; the
# provider (kkphim, vsmov, ...) fills the episode column shown in brackets.
# The slug carries the type so /meta/<slug>.json needs no extra field.
parse_k20_items() {
    jq -r '.metas[]? |
        "\(.name)|\(.releaseInfo // "N/A")|N/A|\(.id | split(":")[0])|\(.type)/\(.id)|\(.poster // "")"' <<< "$1" 2>/dev/null
}

# group_results -- merge search rows (name|year|N/A|provider|<type>/<id>|poster[|src])
# that are one title on several providers of the same addon (src, default k20).
# Rows match on src and year plus any " / " part of the name, lowercased, without
# audio tags and punctuation. Output keeps src and adds the alternatives
# "slug~name^slug~name" for the source picker.
group_results() {
    local -A group_of=()
    local -a names=() years=() provs=() slugs=() posters=() alts=() srcs=() keys=() words=()
    local name year provider slug poster src rest part key g n=0 i
    while IFS='|' read -r name year _ provider slug poster src; do
        [[ -n "$slug" ]] || continue
        src="${src:-k20}"
        name="${name//[~^]/-}"
        keys=()
        rest="$name / "
        while [[ "$rest" == *" / "* ]]; do
            part="${rest%% / *}"
            rest="${rest#* / }"
            part="${part,,}"
            part="${part//(vietsub)/}"
            part="${part//(lồng tiếng)/}"
            part="${part//(thuyết minh)/}"
            read -ra words <<< "${part//[[:punct:]]/ }"
            [[ ${#words[@]} -gt 0 ]] && keys+=("$src|$year|${words[*]}")
        done
        g=""
        for key in "${keys[@]}"; do
            [[ -n "${group_of[$key]+x}" ]] && { g="${group_of[$key]}"; break; }
        done
        if [[ -z "$g" ]]; then
            g=$n
            n=$((n + 1))
            names[g]="$name"; years[g]="$year"; provs[g]="$provider"; srcs[g]="$src"
            slugs[g]="$slug"; posters[g]="$poster"; alts[g]="$slug~$name"
        else
            [[ ", ${provs[g]}, " == *", $provider, "* ]] || provs[g]+=", $provider"
            [[ -z "${posters[g]}" ]] && posters[g]="$poster"
            alts[g]+="^$slug~$name"
        fi
        for key in "${keys[@]}"; do
            group_of[$key]=$g
        done
    done
    for ((i = 0; i < n; i++)); do
        printf '%s|%s|N/A|%s|%s|%s|%s|%s\n' "${names[i]}" "${years[i]}" "${provs[i]}" "${slugs[i]}" "${posters[i]}" "${srcs[i]}" "${alts[i]}"
    done
}

# k20_catalog <src> <type/catalog-id> <page> [genre] -- one page tagged with src.
k20_catalog() {
    local base extra="" first res n
    base=$(k20_base "$1")
    [[ -n "${4:-}" ]] && extra="genre=$(jq -rn --arg g "$4" '$g | @uri')"
    first=$(call_api "$base/catalog/$2${extra:+/$extra}.json") || return
    res="$first"
    if (( $3 > 1 )); then
        # shortcut: assumes every page is as long as page 1, true for the K20 catalogs seen so far.
        n=$(jq '.metas | length' <<< "$first")
        res=$(call_api "$base/catalog/$2/${extra:+$extra&}skip=$(( ($3 - 1) * n )).json") || return
        # K20 Anime ignores skip; a repeat of page 1 means there is no next page.
        [[ "$res" == "$first" ]] && return
    fi
    parse_k20_items "$res" | sed "s/\$/|$1/"
}

# k20anime_index -- K20 Anime ignores search queries, so search reads a local index
# of every title its catalogs list: each catalog, plain and per genre, fetched in
# parallel (~130 titles). Rebuilt when older than an hour; a failed build keeps
# the previous index.
k20anime_index() {
    local manifest tmp cat genre extra f i=0
    local -a pids=()
    is_cache_fresh "$ANIME_INDEX" 3600 && return 0
    manifest=$(call_api "$API_K20_ANIME/manifest.json") || return 1
    tmp=$(mktemp -d "$CACHE/anime-index.XXXXXX") || return 1
    while IFS='|' read -r cat genre; do
        extra=""
        [[ -n "$genre" ]] && extra="/genre=$(jq -rn --arg g "$genre" '$g | @uri')"
        call_api "$API_K20_ANIME/catalog/$cat$extra.json" > "$tmp/$i" 2>/dev/null &
        pids+=($!)
        i=$((i + 1))
    done < <(jq -r '.catalogs[] | "\(.type)/\(.id)" as $c
        | ($c + "|"), ([.extra[]? | select(.name == "genre") | .options[]?][] | $c + "|" + .)' <<< "$manifest")
    # Only these jobs: a plain wait would also block on a running download.
    (( ${#pids[@]} )) && wait "${pids[@]}"
    for f in "$tmp"/*; do
        parse_k20_items "$(<"$f")"
    # The same id can come back as series and movie from different catalogs.
    done | awk -F'|' '{ id = $5; sub(/^[^\/]*\//, "", id) } !seen[id]++' > "$ANIME_INDEX.tmp"
    if [[ -s "$ANIME_INDEX.tmp" ]]; then
        mv "$ANIME_INDEX.tmp" "$ANIME_INDEX"
    else
        rm -f "$ANIME_INDEX.tmp"
    fi
    rm -rf "$tmp"
}

# k20_catalogs -- name|src|type/id for every movie/series catalog of both addons.
k20_catalogs() {
    local src
    for src in k20 k20anime; do
        call_api "$(k20_base "$src")/manifest.json" | jq -r --arg s "$src" \
            '.catalogs[] | select(.type == "movie" or .type == "series") | "\(.name)|\($s)|\(.type)/\(.id)"'
    done
}

# resolve_k20_stream <stream-json-url> -- set K20_URL/K20_HEADERS; asks via fzf
# when the addon offers several versions (Vietsub, Thuyết minh, ...).
resolve_k20_stream() {
    local json list pick idx=0
    K20_URL=""
    K20_HEADERS=()
    # Not cached like call_api (links should not live an hour), but K20 drops
    # requests often enough that one failure must not end playback.
    json=$(curl -fsS -A "$UA" --connect-timeout 10 --max-time 20 --retry 2 --retry-delay 1 --retry-all-errors "$1" 2>/dev/null) || return 1
    list=$(jq -r '.streams[]? | select(.url) | ("\(.name) · \(.title // "")" | gsub("\n"; " · "))' <<< "$json" 2>/dev/null)
    [[ -n "$list" ]] || return 1
    if (( $(wc -l <<< "$list") > 1 )); then
        # The version index rides in a hidden tab-separated column.
        pick=$(awk '{ printf "%s\t%d\n", $0, NR - 1 }' <<< "$list" | fzf "${FZF_OPTS[@]}" \
            --delimiter=$'\t' --with-nth='{1}' --prompt="Bản phát > " --height=40% --header="Chọn bản phát · Esc quay lại") || return 1
        idx="${pick##*$'\t'}"
    fi
    K20_URL=$(jq -r --argjson i "$idx" '[.streams[]? | select(.url)][$i].url' <<< "$json")
    mapfile -t K20_HEADERS < <(jq -r --argjson i "$idx" \
        '[.streams[]? | select(.url)][$i].behaviorHints.proxyHeaders.request // {} | to_entries[] | "\(.key): \(.value)"' <<< "$json")
    # Addon data is untrusted: a value like "--exec=..." would become a yt-dlp/mpv option.
    [[ "$K20_URL" == http://* || "$K20_URL" == https://* ]]
}

# kkphim_playlist <k20-playlist-url> -- K20 strips KKPhim ads but also its
# convertv clips: real scenes under a sponsor text overlay (~25s per episode).
# Rebuild the playlist from the CDN instead: segments in the playlist's own
# directory and convertv clips stay, anything else (standalone ads) is dropped.
# Prints the local playlist path; 1 on any failure so the caller keeps K20's.
kkphim_playlist() {
    local raw media body dir host out variant
    raw=$(sed -n 's/.*[?&]url=\([^&]*\).*/\1/p' <<< "$1")
    raw=$(printf '%b' "${raw//%/\\x}")
    [[ "$raw" == http://* || "$raw" == https://* ]] || return 1
    body=$(curl -fsS --connect-timeout 10 --max-time 20 "$raw" 2>/dev/null) || return 1
    media="$raw"
    if grep -q '^#EXT-X-STREAM-INF' <<< "$body"; then
        # shortcut: takes the first variant; KKPhim masters carry a single one.
        variant=$(grep -v '^#' <<< "$body" | grep -m1 .)
        case "$variant" in
            http://*|https://*) media="$variant" ;;
            /*) media="$(sed -E 's|^(https?://[^/]+).*|\1|' <<< "$raw")$variant" ;;
            *)  media="${raw%%\?*}"; media="${media%/*}/$variant" ;;
        esac
        body=$(curl -fsS --connect-timeout 10 --max-time 20 "$media" 2>/dev/null) || return 1
    fi
    grep -q '^#EXTM3U' <<< "$body" || return 1

    dir="${media%%\?*}"
    dir="${dir%/*}"
    host=$(sed -E 's|^(https?://[^/]+).*|\1|' <<< "$media")
    mkdir -p "$CACHE/playlists" || return 1
    out="$CACHE/playlists/kkphim-$(hash_url "$raw").m3u8"
    # Header tags print at once; per-segment tags wait for their segment and are
    # dropped with an ad, so the marker after the ad block still splits the timeline.
    awk -v dir="$dir" -v host="$host" '
        function abs(u) {
            if (u ~ /^https?:\/\//) return u
            if (u ~ /^\//) return host u
            return dir "/" u
        }
        /^#EXTM3U|^#EXT-X-(VERSION|TARGETDURATION|MEDIA-SEQUENCE|PLAYLIST-TYPE|ENDLIST|KEY:METHOD=NONE)/ { print; next }
        /^#EXTINF:/ { dur = substr($0, 9) + 0 }
        /^#/ { buf = buf $0 "\n"; next }
        /^[[:space:]]*$/ { next }
        {
            u = abs($0); d = u; sub(/\/[^\/]*$/, "", d)
            if (d == dir || u ~ /\/convertv[0-9]*\//) { printf "%s%s\n", buf, u; kept += dur }
            else dropped += dur
            buf = ""; dur = 0
        }
        # Ads are a minute at most; dropping more than is kept means the CDN moved
        # the movie elsewhere, and the K20 playlist is the safer choice.
        END { exit kept == 0 || dropped > kept }
    ' <<< "$body" > "$out" || { rm -f "$out"; return 1; }

    # For mpv: convertv clips restart their timestamps, so a seek made inside one
    # lands near the start of the episode. An EDL (mpv's timeline file) of parts
    # split at every splice gives one continuous clock. Part names are relative
    # (resolved next to the EDL) and ASCII, so the %byte-length% prefix is exact.
    awk -v base="${out%.m3u8}" '
        function flush(   f, name) {
            if (n == 0) return
            f = sprintf("%s-%03d.m3u8", base, ++k)
            printf "%s%s#EXT-X-ENDLIST\n", hdr, seg > f
            close(f)
            name = f
            sub(/.*\//, "", name)
            printf "%%%d%%%s,length=%.3f\n", length(name), name, len >> edl
            seg = ""; len = 0; n = 0
        }
        BEGIN { edl = base ".edl"; print "# mpv EDL v0" > edl }
        /^#EXTM3U|^#EXT-X-(VERSION|TARGETDURATION|PLAYLIST-TYPE)/ { hdr = hdr $0 "\n"; next }
        /^#EXT-X-DISCONTINUITY$/ { flush(); next }
        /^#EXTINF:/ { inf = $0; d = substr($0, 9) + 0; next }
        /^#/ { next }
        { seg = seg inf "\n" $0 "\n"; len += d; n++ }
        END { flush(); close(edl) }
    ' "$out" || rm -f "${out%.m3u8}.edl"
    printf '%s' "$out"
}

# nguonc_proxy_start -- NguonC's CDN (and K20's proxy for it) answer 403 to
# HTTP/1.1, the only HTTP that ffmpeg (inside mpv) and yt-dlp speak, and ffmpeg
# refuses its .png segment names. A local proxy fetches through curl (HTTP/2)
# and serves .ts names. It only fetches URLs it wrote into a playlist itself, so
# other local programs cannot use it as an open proxy. Points K20_URL at it;
# 1 without python3.
NGUONC_PROXY_PID=""
nguonc_proxy_start() {
    local script="$CACHE/nguonc-proxy.py" portfile port i
    command -v python3 >/dev/null 2>&1 || return 1
    cat > "$script" <<'PROXY'
import subprocess, sys, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

root, headers = sys.argv[1], sys.argv[2:]
allowed = {root}

def fetch(url):
    if not url.startswith(("http://", "https://")):
        return None
    cmd = ["curl", "-fsS", "--retry", "2", "--max-time", "60"]
    for h in headers:
        cmd += ["-H", h]
    r = subprocess.run(cmd + ["--", url], capture_output=True)
    return r.stdout if r.returncode == 0 else None

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        url = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query).get("u", [""])[0]
        if url not in allowed:
            self.send_error(403)
            return
        body = fetch(url)
        if body is None:
            self.send_error(502)
            return
        if body.lstrip().startswith(b"#EXTM3U"):
            body = self.rewrite(body.decode("utf-8", "replace"), url).encode()
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def rewrite(self, text, base):
        prefix = "http://127.0.0.1:%d/" % self.server.server_port
        out = []
        for line in text.splitlines():
            if line.strip() and not line.startswith("#"):
                target = urllib.parse.urljoin(base, line.strip())
                allowed.add(target)
                kind = "p.m3u8" if urllib.parse.urlsplit(target).path.endswith(".m3u8") else "s.ts"
                line = prefix + kind + "?u=" + urllib.parse.quote(target, safe="")
            out.append(line)
        return "\n".join(out) + "\n"

server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
print(server.server_port, flush=True)
server.serve_forever()
PROXY
    portfile=$(mktemp "$CACHE/proxy.XXXXXX") || return 1
    # Ignores SIGHUP like downloads do, so a download through it survives the terminal.
    ( trap '' HUP; exec python3 -I "$script" "$K20_URL" "${K20_HEADERS[@]}" > "$portfile" 2>/dev/null ) &
    NGUONC_PROXY_PID=$!
    for ((i = 0; i < 50; i++)); do
        port=$(head -1 "$portfile" 2>/dev/null)
        [[ -n "$port" ]] && break
        sleep 0.1
    done
    rm -f "$portfile"
    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        nguonc_proxy_stop
        return 1
    fi
    K20_URL="http://127.0.0.1:$port/p.m3u8?u=$(jq -rn --arg u "$K20_URL" '$u | @uri')"
    K20_HEADERS=()
}

nguonc_proxy_stop() {
    [[ -n "$NGUONC_PROXY_PID" ]] && kill "$NGUONC_PROXY_PID" 2>/dev/null
    NGUONC_PROXY_PID=""
}

# stream_url <url> -- resolve K20 stream endpoints; direct playlists saved by
# older versions play as they are, their player pages cannot be played.
stream_url() {
    K20_URL=""
    K20_HEADERS=()
    case "$1" in
        *k-20.xyz/stream/*)
            resolve_k20_stream "$1" || return 1
            if [[ "$1" == */kkphim:* && "$K20_URL" == *proxy-playlist.m3u8*url=* ]]; then
                local playlist
                # On any CDN failure K20's own (ad-free, convertv-less) playlist plays.
                if playlist=$(kkphim_playlist "$K20_URL"); then
                    K20_URL="$playlist"
                    K20_HEADERS=()
                fi
            elif [[ "$1" == */nguonc:* ]] && ! nguonc_proxy_start; then
                show_error "Phát NguonC cần python3 (để chạy proxy cục bộ)"
                return 1
            fi
            ;;
        http*.m3u8*)        K20_URL="$1" ;;
        *)                  return 1 ;;
    esac
}

# rewrite_rows <file> <column> <key> [row] -- drop rows whose column equals key,
# append row, and replace the file. The temp file sits next to the target so
# mv stays an atomic rename even when ~/.cache is another filesystem.
rewrite_rows() {
    local tmp
    tmp=$(mktemp "$1.XXXXXX") || return 1
    if ! awk -F'|' -v c="$2" -v k="$3" '$c != k' "$1" > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    [[ -n "${4:-}" ]] && printf '%s\n' "$4" >> "$tmp"
    mv "$tmp" "$1"
}

# record_history <slug> <title> <url> [ep] -- rows: timestamp|title|slug|url|ep.
record_history() {
    local now
    printf -v now '%(%s)T' -1
    rewrite_rows "$HIST" 3 "$1" "$now|$(sanitize_field "$2")|$1|$(sanitize_field "$3")|$(sanitize_field "${4:-}")"
}

record_progress() {
    rewrite_rows "$PROGRESS" 1 "$1" "$1|$2"
}

# add_favorite <title> <slug> <src> -- rows: timestamp|title|slug|year|poster|src
# (year/poster kept empty for old readers).
add_favorite() {
    local ts
    printf -v ts '%(%s)T' -1
    rewrite_rows "$FAV" 3 "$2" "$ts|$(sanitize_field "$1")|$2|||$3"
}

remove_favorite() {
    rewrite_rows "$FAV" 3 "$1"
}

# download_running <log> -- no exit status yet and the log moved in the last 10 minutes.
download_running() {
    local mtime now
    [[ -f "$1.rc" ]] && return 1
    mtime=$(stat -c %Y "$1" 2>/dev/null) || return 1
    printf -v now '%(%s)T' -1
    (( now - mtime < 600 ))
}

download_episode() {
    local url="$1" title="$2" file safe_title log_file h
    local -a hdr=()

    if ! command -v yt-dlp >/dev/null 2>&1; then
        show_error "Thiếu yt-dlp để tải phim"
        return 1
    fi
    stream_url "$url" || { show_error "Không lấy được link tải"; return 1; }
    for h in "${K20_HEADERS[@]}"; do
        hdr+=(--add-header "$h")
    done
    local src_url="$K20_URL"
    if [[ "$K20_URL" == /* ]]; then
        src_url="file://$K20_URL"
        hdr+=(--enable-file-urls)
    fi

    safe_title=$(printf '%s' "$title" | sed 's|[/\\:*?"<>|]| - |g' | tr -s ' ' | sed 's/^ *//;s/ *$//' | tr ' ' '_')
    file="${safe_title:-sudachi_$(date +%s)}.mp4"
    mkdir -p "$CACHE/downloads"
    log_file="$CACHE/downloads/$(date +%s)_${file}.log"

    (
        # Closing the terminal must not kill the download; yt-dlp inherits this.
        trap '' HUP
        yt-dlp "$src_url" "${hdr[@]}" -N 8 -o "$DL/$file" > "$log_file" 2>&1
        rc=$?
        nguonc_proxy_stop
        printf '%s\n' "$rc" > "$log_file.rc"
        if command -v notify-send >/dev/null 2>&1; then
            if [[ $rc -eq 0 ]]; then
                notify-send "Sudachi" "✅ Tải xong: $title"
            else
                notify-send -u critical "Sudachi" "❌ Lỗi khi tải: $title"
            fi
        fi
    ) &
    # The download owns the NguonC proxy now; this shell must not stop it.
    NGUONC_PROXY_PID=""
    printf '%s|%s|%s\n' "$(sanitize_field "$title")" "$file" "$log_file" >> "$CACHE/downloads/tasks.log"

    command -v notify-send >/dev/null 2>&1 && notify-send "Sudachi" "⬇ Đang tải: $title"
    # Titles come from the API: print them with %s so "\033" or "\c" stay text.
    printf "${C_G}  Đang tải: %s${C_R}\n" "$title"
    printf "${C_C}  Lưu tại: %s${C_R}\n" "$DL/$file"
    sleep 1
}

view_downloads() {
    local task_file="$CACHE/downloads/tasks.log"
    [[ ! -s "$task_file" ]] && { show_error "Chưa có lượt tải nào"; return; }

    local list="" f1 f2 f3 f4 row_title log status
    while IFS='|' read -r f1 f2 f3 f4; do
        [[ -z "$f1" ]] && continue
        # Legacy rows are pid|title|file|log; current rows are title|file|log.
        if [[ -n "$f4" ]]; then
            row_title="$f2"; log="$f4"
        else
            row_title="$f1"; log="$f3"
        fi
        if [[ -f "$log.rc" ]]; then
            if [[ "$(<"$log.rc")" == "0" ]]; then
                status=$'\033[1;32m[󰄲 Hoàn tất]\033[0m'
            else
                status=$'\033[1;31m[󰅚 Lỗi]\033[0m'
            fi
        elif download_running "$log"; then
            status=$'\033[1;33m[󰑈 Đang tải]\033[0m'
        else
            status=$'\033[0;90m[󰅚 Đã dừng]\033[0m'
        fi
        list="${status} ${row_title}|${log}"$'\n'"$list"
    done < "$task_file"

    [[ -z "$list" ]] && { show_error "Chưa có lượt tải nào"; return; }

    printf '%s' "$list" | fzf "${FZF_OPTS[@]}" \
        --delimiter='|' --with-nth='{1}' --prompt="Tải phim > " \
        --header="Di chuyển để xem log · Esc quay lại" \
        --preview='tail -n 25 {2} 2>/dev/null || echo "Không có log"' --preview-window=down:55%:rounded:wrap >/dev/null
}

# vlc_plays_hls -- Arch/CachyOS split VLC into plugin packages; without the TS
# demuxer (vlc-plugin-dvb) and the ffmpeg decoder (vlc-plugin-ffmpeg) it opens
# every stream and silently plays nothing.
vlc_plays_hls() {
    local mods
    mods=$(vlc --list 2>/dev/null)
    grep -qE '^[[:space:]]+ts[[:space:]]' <<< "$mods" && grep -qE '^[[:space:]]+avcodec[[:space:]]' <<< "$mods"
}

vlc_warning() {
    show_error "VLC thiếu plugin phát phim: sudo pacman -S vlc-plugin-dvb vlc-plugin-ffmpeg"
}

check_player() {
    if [[ "$PLAYER_DEFAULT" == vlc ]] && command -v vlc &>/dev/null && ! vlc_plays_hls; then
        vlc_warning
        command -v mpv &>/dev/null && PLAYER_DEFAULT="mpv"
    fi
    command -v "$PLAYER_DEFAULT" &>/dev/null && return 0
    if command -v mpv &>/dev/null; then
        PLAYER_DEFAULT="mpv"
    elif command -v vlc &>/dev/null; then
        PLAYER_DEFAULT="vlc"
    else
        echo -e "${C_Y}⚠ Không tìm thấy MPV hoặc VLC!${C_R}"
        echo -e "${C_C}Vui lòng cài đặt: sudo pacman -S mpv${C_R}"
        exit 1
    fi
}

# play_video <url> <title> -- blocks until the player exits. Ctrl+C reaches
# the player (it quits on its own) but not this script.
play_video() {
    local url="$1" title="$2" h
    local -a args=()

    if ! stream_url "$url"; then
        show_error "Không lấy được link phát"
        return 1
    fi

    case "$PLAYER_DEFAULT" in
        vlc)
            args=("$K20_URL" "--meta-title=$title" "--no-video-title-show" "--no-input-fast-seek" "--network-caching=3000")
            for h in "${K20_HEADERS[@]}"; do
                case "${h%%:*}" in
                    Referer)    args+=("--http-referrer=${h#*: }") ;;
                    User-Agent) args+=("--http-user-agent=${h#*: }") ;;
                esac
            done
            trap '' INT
            vlc "${args[@]}" >/dev/null 2>&1
            ;;
        *)
            # K20 keeps a few discontinuities where ads were cut; the RAM cache
            # serves backward seeks across them.
            local media="$K20_URL"
            # KKPhim rebuilt locally: mpv plays the EDL next to it (see kkphim_playlist).
            [[ "$K20_URL" == /*.m3u8 && -s "${K20_URL%.m3u8}.edl" ]] && media="${K20_URL%.m3u8}.edl"
            args=("$media" "--title=$title" "--force-window" "--save-position-on-quit"
                "--cache=yes" "--demuxer-seekable-cache=yes" "--demuxer-max-bytes=150M" "--demuxer-max-back-bytes=100M")
            for h in "${K20_HEADERS[@]}"; do
                # -append takes one header verbatim; User-Agent values contain commas.
                args+=("--http-header-fields-append=$h")
            done
            # A local playlist with https segments needs the hls demuxer and more
            # protocols than ffmpeg allows for files by default (else it stalls).
            if [[ "$K20_URL" == /* ]]; then
                args+=("--demuxer-lavf-format=hls" '--demuxer-lavf-o=protocol_whitelist="https,http,file,tcp,tls,crypto,data"')
            fi
            trap '' INT
            mpv "${args[@]}" >/dev/null 2>&1
            ;;
    esac
    trap 'exit 130' INT TERM
    nguonc_proxy_stop
}

show_loading() { echo -e "${C_C} Đang tải...${C_R}"; }
show_error() { echo -e "${C_Y}  $1${C_R}"; sleep 2; }


create_preview_script() {
    local script
    script=$(mktemp "$CACHE/preview.XXXXXX.sh") || return 1
    register_temp "$script"

    cat > "$script" << EOF
#!/bin/bash
IFS='|' read -r _ ten nam _ nguon slug anh src _ <<< "\$1"
case "\$src" in
    k20anime) api_base="$API_K20_ANIME" ;;
    *)        api_base="$API_K20" ;;
esac

time_dur=""
cats=""
quocgia=""
poster=""
clean_content=""
detail_res=""
desc_cache="$CACHE/desc"
mkdir -p "\$desc_cache"
# Slugs are "<type>/<id>"; keep the cache file name flat.
cache_key="\${src}-\${slug//\//_}"

if [[ -n "\$slug" ]]; then
    detail_cache="\$desc_cache/\$cache_key.json"
    if [[ -s "\$detail_cache" ]]; then
        detail_res=\$(cat "\$detail_cache")
    else
        detail_res=\$(curl -fsS -A "$UA" --max-time 3 "\${api_base}/meta/\${slug}.json" 2>/dev/null)
        # {"meta":null} is a transient miss; caching it would blank this preview for good.
        jq -e '.meta' <<< "\$detail_res" >/dev/null 2>&1 && printf '%s' "\$detail_res" > "\$detail_cache"
    fi
    if jq -e '.meta' <<< "\$detail_res" >/dev/null 2>&1; then
        { IFS= read -r time_dur; IFS= read -r cats; IFS= read -r quocgia; IFS= read -r poster; IFS= read -r clean_content; } < <(
            jq -r '.meta | (.runtime // ""), ([.genres[]?] | join(", ")),
                (.country // "" | if type == "array" then join(", ") else tostring end), (.poster // ""),
                (.description // "" | gsub("<[^>]+>"; " ") | gsub("[[:space:]]+"; " ") | ltrimstr(" ") | rtrimstr(" "))' <<< "\$detail_res")
        [[ -z "\$anh" ]] && anh="\$poster"
    fi
fi

# K20 Anime has no synopsis and its poster CDN is often blocked by ISPs: take the
# cover, genres and synopsis from Kitsu, matched by the first " / " part of the name.
if [[ "\$src" == k20anime && -n "\$ten" ]]; then
    kitsu_cache="\$desc_cache/\$cache_key.kitsu.json"
    if [[ ! -s "\$kitsu_cache" ]]; then
        q=\$(jq -rn --arg q "\${ten%% / *}" '\$q | @uri')
        # A miss is stored as {} so it is not asked again on every hover; a network
        # failure stores nothing.
        k_res=\$(curl -fsS --max-time 3 "$KITSU_SEARCH/search=\$q.json" 2>/dev/null) \
            && jq -c '.metas[0] // {}' <<< "\$k_res" > "\$kitsu_cache" 2>/dev/null || rm -f "\$kitsu_cache"
    fi
    if [[ -s "\$kitsu_cache" ]]; then
        { IFS= read -r k_poster; IFS= read -r k_genres; IFS= read -r k_desc; } < <(
            jq -r '(.poster // ""), ([.genres[]?] | join(", ")), (.description // "" | gsub("[[:space:]]+"; " "))' "\$kitsu_cache")
        [[ "\$k_poster" == http* ]] && anh="\$k_poster"
        [[ -n "\$k_genres" ]] && cats="\$k_genres"
        [[ -n "\$k_desc" ]] && clean_content="\${clean_content:+\$clean_content — }\$k_desc"
    fi
fi

cols="\${FZF_PREVIEW_COLUMNS:-80}"
wrap_w=\$(( cols - 6 ))
[[ \$wrap_w -lt 35 ]] && wrap_w=35
div=\$(printf '─%.0s' \$(seq 1 "\$wrap_w"))

poster_h=\$(( cols * 18 / 100 ))
[[ \$poster_h -lt 12 ]] && poster_h=12
[[ \$poster_h -gt 17 ]] && poster_h=17

# API values are printed with %s so their backslashes stay text.
printf '  \033[1;36m󰟴 %s\033[0m\n' "\$ten"

# Only http(s) posters: anything else would reach curl as an option.
if [[ "\$anh" == http* ]] && command -v chafa &>/dev/null; then
    chafa_fmt="symbols"
    case "\$TERM" in
        xterm-kitty|kitty*) chafa_fmt="kitty" ;;
        foot*|contour|mlterm*|yaft*) chafa_fmt="sixel" ;;
    esac
    [[ -n "\$KITTY_WINDOW_ID" || -n "\$GHOSTTY_RESOURCES_DIR" ]] && chafa_fmt="kitty"
    echo ""
    [[ "\$chafa_fmt" == "kitty" ]] && printf '\033_Ga=d,d=A\033\\\\'

    img_cache="\$desc_cache/\$cache_key.img"
    if [[ ! -s "\$img_cache" ]]; then
        curl -fsS --max-time 4 "\$anh" -o "\$img_cache" 2>/dev/null
        [[ ! -s "\$img_cache" ]] && rm -f "\$img_cache"
    fi

    if [[ -s "\$img_cache" ]]; then
        im=\$(command -v magick || command -v convert)
        if [[ -n "\$im" ]]; then
            # Pad into a fixed box so every poster is centered at the same size.
            "\$im" "\$img_cache[0]" -resize "x\$(( poster_h * 20 ))>" -background none -gravity center \
                -extent "\$(( cols * 10 ))x\$(( poster_h * 20 ))" png:- 2>/dev/null \
                | chafa -f "\$chafa_fmt" --probe off -s "\${cols}x\${poster_h}" - 2>/dev/null
        else
            chafa -f "\$chafa_fmt" --probe off -s "\${wrap_w}x\${poster_h}" --align center "\$img_cache" 2>/dev/null
        fi
        if [[ "\$chafa_fmt" == "kitty" ]]; then
            for ((i=1; i<poster_h; i++)); do
                echo ""
            done
        fi
    fi
fi

echo -e "  \033[0;90m\${div}\033[0m"
[[ -n "\$nam" && "\$nam" != "N/A" ]] && printf '  \033[0;33m󰃰 Năm:\033[0m %s\n' "\$nam"
[[ -n "\$nguon" ]] && printf '  \033[0;35m󱖫 Nguồn:\033[0m %s\n' "\$nguon"
[[ -n "\$quocgia" ]] && printf '  \033[0;36m󰇧 Quốc gia:\033[0m %s\n' "\$quocgia"
[[ -n "\$time_dur" ]] && printf '  \033[0;32m󱎫 Thời lượng:\033[0m %s\n' "\$time_dur"
[[ -n "\$cats" ]] && printf '  \033[0;34m󰘯 Thể loại:\033[0m %s\n' "\$cats"

if [[ -n "\$clean_content" ]]; then
    echo -e "  \033[0;90m\${div}\033[0m"
    echo -e "  \033[1;33m󰧭 Nội dung tóm tắt:\033[0m"
    printf '%s\n' "\$clean_content" | fold -s -w "\$wrap_w" | sed 's/^/   /'
fi
EOF
    chmod +x "$script"
    echo "$script"
}


# watch_episode <slug> <title> [src]
watch_episode() {
    local slug="$1" ten="$2" src="${3:-k20}" base res ds_tap
    show_loading

    base=$(k20_base "$src")
    res=$(call_api "$base/meta/$slug.json") || { show_error "Không lấy được thông tin"; return; }
    # Episode URL is the addon's stream endpoint; play_video resolves it.
    ds_tap=$(jq -r --arg b "$base" --arg s "$slug" '
        (.meta.videos // []) as $v
        | if ($v | length) == 0 then "Full|\($b)/stream/\($s).json"
          else $v[] | "\(.title // .name // .episode)|\($b)/stream/\($s | split("/")[0])/\(.id).json" end
    ' <<< "$res" 2>/dev/null)
    [[ -z "$ds_tap" ]] && { show_error "Không có tập phim"; return; }

    local chon phim data tap url tieu_de last_ep pos total next continue_header
    total=$(wc -l <<< "$ds_tap")
    while true; do
        # The cursor starts on the episode after the last one watched.
        pos=1
        continue_header=""
        last_ep=$(awk -F'|' -v s="$slug" '$1 == s {ep=$2} END {print ep}' "$PROGRESS")
        if [[ -n "$last_ep" ]]; then
            pos=$(awk -F'|' -v e="$last_ep" '$1 == e {n = NR} END {print n + 0}' <<< "$ds_tap")
            if (( pos == 0 )); then
                # The saved episode name is no longer listed (renamed): no claim.
                pos=1
            else
                if (( pos < total )); then
                    pos=$((pos + 1))
                    next="▶ Tiếp"
                else
                    next="✓ Đã xem"
                fi
                tap=$(sed -n "${pos}p" <<< "$ds_tap")
                tap="${tap%%|*}"
                [[ "$tap" =~ ^[0-9]+$ ]] && tap="Tập $tap"
                continue_header="  │  $next: $tap"
            fi
        fi
        chon=$(fzf "${FZF_OPTS[@]}" \
            --header="$ten$continue_header  │  Enter xem  │  Tab tải  │  Ctrl+F yêu thích" \
            --prompt="Chọn tập > " \
            --delimiter='|' --with-nth='{1}' --bind "load:pos($pos)" \
            --expect=enter,tab,ctrl-f <<< "$ds_tap")
        [[ "$chon" == *$'\n'* ]] || break

        phim="${chon%%$'\n'*}"
        data="${chon#*$'\n'}"
        tap="${data%%|*}"
        url="${data#*|}"
        if [[ "$tap" =~ ^[0-9]+$ ]]; then
            tieu_de="${ten} - Tập ${tap}"
        else
            tieu_de="${ten} - ${tap}"
        fi

        case "$phim" in
            enter)
                play_video "$url" "$tieu_de" || continue
                record_history "$slug" "$tieu_de" "$url" "$tap" || show_error "Không ghi được lịch sử"
                record_progress "$slug" "$tap" || show_error "Không ghi được tiến độ"
                ;;
            tab)
                download_episode "$url" "$tieu_de"
                ;;
            ctrl-f)
                add_favorite "$ten" "$slug" "$src" || show_error "Không lưu được yêu thích"
                ;;
        esac
    done
}

# open_choice <fzf line> -- open the title from a formatted list row; asks for
# the source when search found it on several providers.
open_choice() {
    local -a arr=()
    local slug ten pick
    [[ -n "$1" ]] || return
    IFS='|' read -ra arr <<< "$1"
    slug="${arr[5]}"
    ten="${arr[1]}"
    if [[ "${arr[8]:-}" == *"^"* ]]; then
        pick=$(tr '^' '\n' <<< "${arr[8]}" \
            | awk -F'~' '{ p = $1; sub(/^[^\/]*\//, "", p); sub(/:.*/, "", p); printf "[%s] %s~%s~%s\n", p, $2, $2, $1 }' \
            | fzf "${FZF_OPTS[@]}" --delimiter='~' --with-nth='{1}' \
                --prompt="Nguồn > " --height=40% --header="Chọn nguồn · Esc quay lại") || return
        IFS='~' read -r _ ten slug <<< "$pick"
    fi
    watch_episode "$slug" "$ten" "${arr[7]:-}"
}

# show_paginated_list <prompt> <fetch-callback> [filters-callback] -- the fetch
# callback prints one page for <page> [filter]; with a filters callback (it prints
# the options) Ctrl+G picks a filter. Esc in the episode list comes back here.
show_paginated_list() {
    local prompt="$1" fetch_callback="$2" filters_callback="${3:-}" page=1 filter=""
    local preview items output key chon options expect="right,left,enter" hint=""
    if [[ -n "$filters_callback" ]]; then
        expect+=",ctrl-g"
        hint=" · Ctrl+G lọc"
    fi
    preview=$(create_preview_script) || { show_error "Không tạo được preview"; return; }

    while true; do
        items=$("$fetch_callback" "$page" "$filter")
        if [[ -z "$items" ]]; then
            if [[ $page -gt 1 ]]; then
                ((page--))
                continue
            fi
            if [[ -n "$filter" ]]; then
                show_error "Không có phim nào với bộ lọc này"
                filter=""
                continue
            fi
            show_error "Không có kết quả"
            break
        fi

        output=$(format_movie_items <<< "$items" | fzf "${FZF_OPTS[@]}" \
            --delimiter='|' --with-nth='{1}' \
            --preview="'$preview' {}" \
            --header="Enter chọn · ←/→ trang $page$hint · Esc quay lại " \
            --prompt="$prompt${filter:+ · $filter} > " \
            --expect="$expect")

        key="${output%%$'\n'*}"
        chon=""
        [[ "$output" == *$'\n'* ]] && chon="${output#*$'\n'}"
        case "$key" in
            right) ((page++)) ;;
            left)  [[ $page -gt 1 ]] && ((page--)) ;;
            ctrl-g)
                options=$("$filters_callback")
                if [[ -z "$options" ]]; then
                    show_error "Danh mục này không có bộ lọc"
                    continue
                fi
                options=$(printf '%s\n' "Tất cả" "$options" | fzf "${FZF_OPTS[@]}" \
                    --prompt="Lọc > " --height=50% --header="Danh mục, thể loại, quốc gia, năm · Esc giữ nguyên") || continue
                [[ "$options" == "Tất cả" ]] && filter="" || filter="$options"
                page=1
                ;;
            *)
                [[ -n "$chon" ]] || break
                # Back from the episode list: same page again.
                open_choice "$chon"
                ;;
        esac
    done
    rm -f "$preview"
}


create_search_script() {
    local script
    script=$(mktemp "$CACHE/search.XXXXXX.sh") || return 1
    register_temp "$script"

    cat > "$script" << EOF
#!/bin/bash
$(declare -f format_movie_items)
$(declare -f parse_k20_items)
$(declare -f group_results)

[[ \${#1} -lt 2 ]] && exit 0
q=\$(jq -rn --arg q "\$1" '\$q|@uri' 2>/dev/null) || exit 0
tmp=\$(mktemp -d) || exit 0
# fzf kills this script on every keystroke; stop the curls with it.
trap 'kill \$(jobs -p) 2>/dev/null; rm -rf "\$tmp"' EXIT
trap 'exit 1' TERM INT

# K20 Anime ignores the query (and has no streams for kitsu ids), so only the
# main addon is queried; anime come from the local index (k20anime_index). Movie and series catalogs overlap and may type the same
# id differently; the first row per id wins (series first, whose meta always lists
# the episodes), then one title on several providers becomes one row.
cats="series/kkphim-series movie/kkphim-movie series/vsmov-series movie/vsmov-movie series/nguonc-series movie/nguonc-movie"
i=0
for cat in \$cats; do
    curl -fsS -A "$UA" --max-time 6 "$API_K20/catalog/\$cat/search=\$q.json" -o "\$tmp/\$i" 2>/dev/null &
    i=\$((i + 1))
done
wait
{
    for ((j = 0; j < i; j++)); do
        [[ -s "\$tmp/\$j" ]] && parse_k20_items "\$(<"\$tmp/\$j")"
    done | awk -F'|' '{ id = \$5; sub(/^[^\/]*\//, "", id) } !seen[id]++'
    # Anime index rows whose name holds every query word, case-insensitively.
    read -ra words <<< "\${1,,}"
    if (( \${#words[@]} )) && [[ -s "$ANIME_INDEX" ]]; then
        while IFS= read -r line; do
            name="\${line%%|*}"
            name="\${name,,}"
            for w in "\${words[@]}"; do
                [[ "\$name" == *"\$w"* ]] || continue 2
            done
            printf '%s|k20anime\n' "\$line"
        done < "$ANIME_INDEX"
    fi
} | group_results | format_movie_items
EOF
    chmod +x "$script"
    echo "$script"
}


search() {
    local query="$1" search preview input output chon
    search=$(create_search_script) || { show_error "Không tạo được script tìm kiếm"; return; }
    preview=$(create_preview_script) || { rm -f "$search"; show_error "Không tạo được preview"; return; }
    # Built once an hour (a second or two); search keeps working without it.
    is_cache_fresh "$ANIME_INDEX" 3600 || { show_loading; k20anime_index; }

    # --print-query puts the query on the first line, so coming back from the
    # episode list reopens the same search instead of the main menu.
    while true; do
        input=""
        [[ -n "$query" ]] && input=$("$search" "$query" 2>/dev/null)
        output=$(printf '%s\n' "$input" | fzf "${FZF_OPTS[@]}" \
            --query="$query" --print-query \
            --prompt="Tìm phim > " --header="Enter chọn · gõ để tìm kiếm · Esc quay lại " --phony \
            --delimiter='|' --with-nth='{1}' \
            --bind "change:reload:sleep 0.2; '$search' {q} || true" \
            --preview="'$preview' {}")
        query="${output%%$'\n'*}"
        chon=""
        [[ "$output" == *$'\n'* ]] && chon="${output#*$'\n'}"
        [[ -n "$chon" ]] || break
        open_choice "$chon"
    done
    rm -f "$search" "$preview"
}

new_releases() {
    fetch_new() { k20_catalog k20 movie/kkphim-movie "$1" "Danh mục: Mới Cập Nhật"; }
    show_paginated_list "Phim mới" fetch_new
}

anime_mode() {
    fetch_anime() { k20_catalog k20anime series/animevietsub-latest "$1"; }
    show_paginated_list "Anime" fetch_anime
}

# browse_catalog <name> <src> <type/id> -- one K20 catalog, filterable by the
# genre options its manifest lists (category, genre, country, year).
browse_catalog() {
    local name="$1" src="$2" cat="$3"
    fetch_catalog() { k20_catalog "$src" "$cat" "$1" "${2:-}"; }
    catalog_filters() {
        call_api "$(k20_base "$src")/manifest.json" | jq -r --arg id "${cat#*/}" \
            '.catalogs[] | select(.id == $id) | .extra[]? | select(.name == "genre") | .options[]?'
    }
    show_paginated_list "$name" fetch_catalog catalog_filters
}

# kham_pha -- every way to browse in one place: the two "new" shortcuts, then
# each K20 catalog. Esc in a list comes back here.
kham_pha() {
    local chon name src cat
    while true; do
        chon=$( { printf '%s\n' "${I_NEW} Phim mới cập nhật|new|" "${I_ANIME} Anime mới cập nhật|anime|"; k20_catalogs; } \
            | fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth='{1}' --prompt="Khám phá > " --height=50% \
                --header="Enter mở · Esc quay lại ") || return
        IFS='|' read -r name src cat <<< "$chon"
        case "$src" in
            new)   new_releases ;;
            anime) anime_mode ;;
            *)     browse_catalog "$name" "$src" "$cat" ;;
        esac
    done
}

# continue_watching -- history newest first with episode and age. Enter opens
# the episode list on the next episode; Ctrl+D forgets the title.
continue_watching() {
    local rows chon key data slug title url src now
    while true; do
        [[ -s "$HIST" ]] || { show_error "Chưa có lịch sử"; return; }
        printf -v now '%(%s)T' -1
        rows=$(sort -t'|' -k1,1rn "$HIST" | awk -F'|' -v now="$now" '{
            d = now - $1
            if (d < 3600) ago = int(d / 60) " phút trước"
            else if (d < 86400) ago = int(d / 3600) " giờ trước"
            else ago = int(d / 86400) " ngày trước"
            printf "\033[1;37m%s\033[0m  \033[0;90m%s\033[0m|%s|%s|%s\n", $2, ago, $3, $2, $4
        }')
        chon=$(fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth='{1}' --prompt="Xem tiếp > " \
            --header="Enter mở tập kế · Ctrl+D xóa · Esc quay lại " --expect=enter,ctrl-d <<< "$rows")
        [[ "$chon" == *$'\n'* ]] || return
        key="${chon%%$'\n'*}"
        data="${chon#*$'\n'}"
        IFS='|' read -r _ slug title url <<< "$data"
        case "$key" in
            ctrl-d) rewrite_rows "$HIST" 3 "$slug" || show_error "Không xóa được" ;;
            enter)
                if [[ "$slug" == */* ]]; then
                    src=k20
                    [[ "$url" == *anime.k-20.xyz* ]] && src=k20anime
                    # Titles are "<name> - <episode>".
                    watch_episode "$slug" "${title% - *}" "$src"
                else
                    # Rows from versions before K20 have no meta to list episodes from.
                    play_video "$url" "$title"
                fi
                ;;
        esac
    done
}

favorites() {
    local parsed_favs chon phim data ten slug src
    # Loops so Esc in the episode list (or a Ctrl+D) comes back to this list.
    while true; do
        # Drop the timestamp; rows become title|slug|year|poster|src.
        parsed_favs=$(awk -F'|' 'NF >= 5' "$FAV" | sort -t'|' -k1,1rn | cut -d'|' -f2-)
        [[ -z "$parsed_favs" ]] && { show_error "Chưa có yêu thích"; return; }

        chon=$(fzf "${FZF_OPTS[@]}" --delimiter='|' --with-nth='{1}' \
            --header="Enter xem · Ctrl+D xóa · Esc quay lại " \
            --prompt="Yêu thích > " --expect=enter,ctrl-d <<< "$parsed_favs")
        [[ "$chon" == *$'\n'* ]] || return

        phim="${chon%%$'\n'*}"
        data="${chon#*$'\n'}"
        IFS='|' read -r ten slug _ _ src <<< "$data"
        case "$phim" in
            enter)  watch_episode "$slug" "$ten" "$src" ;;
            ctrl-d) remove_favorite "$slug" || show_error "Không xóa được yêu thích" ;;
        esac
    done
}

select_player() {
    local mpv_mark="" vlc_mark="" menu="" chon
    [[ "$PLAYER_DEFAULT" == "mpv" ]] && mpv_mark=" \033[1;32m(đang dùng)\033[0m"
    [[ "$PLAYER_DEFAULT" == "vlc" ]] && vlc_mark=" \033[1;32m(đang dùng)\033[0m"
    command -v mpv &>/dev/null && menu+="  MPV${mpv_mark} (Khuyên dùng)|mpv\n"
    command -v vlc &>/dev/null && menu+="  VLC${vlc_mark}|vlc"
    [[ -z "$menu" ]] && { show_error "Không có trình phát"; return; }

    chon=$(echo -e "$menu" | fzf "${FZF_OPTS[@]}" \
        --delimiter='|' --with-nth='{1}' --prompt="Trình phát > " --height=40% \
        --header="Trình phát · Esc quay lại ")
    [[ -z "$chon" ]] && return

    PLAYER_DEFAULT="${chon#*|}"
    [[ "$PLAYER_DEFAULT" == vlc ]] && ! vlc_plays_hls && vlc_warning
    save_settings
}

clear_cache() {
    local count
    count=$(find "$CACHE" -maxdepth 1 -name '*.json' | wc -l)
    [[ -d "$CACHE/desc" ]] && count=$((count + $(find "$CACHE/desc" -type f | wc -l)))
    rm -f "$CACHE"/*.json
    rm -rf "$CACHE/desc" "$CACHE/playlists"
    # Older versions kept their cache (and ad-filter segments) under the config dir.
    rm -rf "$CONF/cache"

    # Finished or dead downloads leave the list together with their logs.
    local task_file="$CACHE/downloads/tasks.log" row log tmp
    if [[ -s "$task_file" ]] && tmp=$(mktemp "$CACHE/tasks.XXXXXX"); then
        while IFS= read -r row; do
            log="${row##*|}"
            if download_running "$log"; then
                printf '%s\n' "$row" >> "$tmp"
            else
                rm -f "$log" "$log.rc"
            fi
        done < "$task_file"
        mv "$tmp" "$task_file"
    fi
    log_debug "Cache cleared manually: $count files removed"
    echo -e "${C_G}  Đã xóa ${count} file cache.${C_R}"
    sleep 1
}

settings() {
    local chon
    local menu="${I_PLAYER} Trình phát|player
${I_DIR} Mở thư mục tải về|folder
${I_CACHE} Xóa cache|cache"

    chon=$(echo -e "$menu" | fzf "${FZF_OPTS[@]}" \
        --delimiter='|' --with-nth='{1}' --prompt="Cài đặt > " --height=45% \
        --header="Cài đặt · Esc quay lại ")
    [[ -z "$chon" ]] && return

    case "${chon#*|}" in
        player)        select_player ;;
        folder)        xdg-open "$DL" >/dev/null 2>&1 & ;;
        cache)         clear_cache ;;
    esac
}

show_banner() {
    printf '\033[H\033[2J'
    local player_text="MPV"
    [[ "$PLAYER_DEFAULT" == "vlc" ]] && player_text="VLC"

    echo ""
    echo -e "${C_G}             ⢀⣀⣀⣀⣀⣀⣀⣀⣀⣀${C_R}"
    echo -e "${C_G} ⢀⣀⣠⣤⣴⣶⡶⢿⣿⣿⣿⠿⠿⠿⠿⠟⠛⢋⣁⣤⡴⠂⣠⡆${C_R}"
    echo -e "${C_G} ⠈⠙⠻⢿⣿⣿⣿⣶⣤⣤⣤⣤⣤⣴⣶⣶⣿⣿⣿⡿⠋⣠⣾⣿${C_R}     ${C_Y}Sudachi Player${C_R}"
    echo -e "${C_G} ⢀⣴⣤⣄⡉⠛⠻⠿⠿⣿⣿⣿⣿⡿⠿⠟⠋⣁⣤⣾⣿⣿⣿${C_R}      ${C_C}Git: KabosuNeko${C_R}"
    echo -e "${C_G} ⣠⣾⣿⣿⣿⣿⣶⣶⣤⣤⣤⣤⣤⣤⣶⣾⣿⣿⣿⣿⣿⣿⣿⡇${C_R}     ${C_M}Nguồn: K20${C_R}"
    echo -e "${C_G} ⣰⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇${C_R}    ${C_C}Player: ${player_text}${C_R}"
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
    printf '%s\n' "${I_SEARCH} Tìm phim" "${I_HIST} Xem tiếp" "${I_BROWSE} Khám phá" \
        "${I_FAV} Yêu thích" "${I_DOWN} Tải về" "${I_SETTINGS} Cài đặt" \
        | fzf "${FZF_OPTS[@]}" --prompt="Menu > " --height=50% \
            --border-label=" 🍙 Sudachi Menu " --border-label-pos=2 \
            --header="Enter chọn · Esc thoát "
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
            local title url
            IFS='|' read -r _ title _ url _ < <(sort -rn "$HIST" | head -1)
            if [[ -n "$url" ]]; then
                printf "${C_G}▶ Tiếp tục xem: %s${C_R}\n" "$title"
                play_video "$url" "$title"
                exit 0
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
# Help must work on a machine without fzf/curl/player.
case "${1:-}" in
    -h|--help) show_help; exit 0 ;;
esac
check_dependencies
check_player
handle_cli_args "$@"

while true; do
    show_banner
    case "$(main_menu)" in
        "")             exit 0 ;;
        *"Tìm phim"*)   search ;;
        *"Xem tiếp"*)   continue_watching ;;
        *"Khám phá"*)   kham_pha ;;
        *"Yêu thích"*)  favorites ;;
        *"Tải về"*)     view_downloads ;;
        *"Cài đặt"*)    settings ;;
    esac
done
