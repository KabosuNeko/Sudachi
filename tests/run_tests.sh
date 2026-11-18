#!/usr/bin/env bash
# Regression test suite for sudachi.sh
# Usage: bash tests/run_tests.sh
# Each test runs in an isolated subshell with a fresh HOME and re-sources the
# (truncated) library, so no test can leak state into another.
# shellcheck disable=SC1090  # library path is dynamic

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../sudachi.sh"
LIB=""
PASS=0
FAIL=0
FAILED_TESTS=()

TESTS_TMP="$(mktemp -d /tmp/sudachi-tests.XXXXXX)"
trap 'rm -rf "$TESTS_TMP"' EXIT

# Library: everything before the main loop (`load_settings`).
build_lib() {
    local main_start
    main_start=$(grep -n '^load_settings$' "$SCRIPT" | head -1 | cut -d: -f1)
    if [[ -z "$main_start" || "$main_start" -lt 100 ]]; then
        echo "FATAL: cannot find main-loop boundary in $SCRIPT" >&2
        exit 1
    fi
    LIB="$TESTS_TMP/sudachi_lib.sh"
    head -n "$((main_start - 1))" "$SCRIPT" > "$LIB"
}

# run_test NAME — run test_<name> in a fresh HOME.
run_test() {
    local name="$1"
    local home="$TESTS_TMP/home-$name"
    local out rc
    # -c so the test body (defined in the parent) is available after sourcing.
    out=$(export HOME="$home" TEST_HOME="$home"; unset XDG_CACHE_HOME; \
          mkdir -p "$home"; \
          source "$LIB" 2>&1; \
          "test_$name" 2>&1)
    rc=$?
    if [[ $rc -eq 0 ]]; then
        PASS=$((PASS + 1))
        printf '  PASS  %s\n' "$name"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$name")
        printf '  FAIL  %s (rc=%s)\n' "$name" "$rc"
        printf '%s\n' "$out" | sed 's/^/        /'
    fi
}

# assert_eq — compare expected/actual.
assert_eq() {
    local expected="$1" actual="$2" msg="${3:-}"
    if [[ "$expected" != "$actual" ]]; then
        echo "ASSERT_EQ FAIL: $msg" >&2
        echo "  expected: [$expected]" >&2
        echo "  actual:   [$actual]" >&2
        return 1
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" msg="${3:-}"
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "ASSERT_CONTAINS FAIL: $msg" >&2
        echo "  needle:   [$needle]" >&2
        echo "  haystack: [$haystack]" >&2
        return 1
    fi
}


# fake_bin <name> <script body> -- put an executable stub on a private PATH dir.
fake_bin() {
    local dir="$TEST_HOME/bin-$1"
    mkdir -p "$dir"
    printf '#!/bin/bash\n%s\n' "$2" > "$dir/$1"
    chmod +x "$dir/$1"
    printf '%s' "$dir"
}

test_sanitize_field() {
    assert_eq "a b" "$(sanitize_field $'a\nb')" "newline to space" || return 1
    assert_eq "a b" "$(sanitize_field $'a\rb')" "CR to space" || return 1
    assert_eq "a-b" "$(sanitize_field "a|b")" "pipe to dash" || return 1
    assert_eq "" "$(sanitize_field "")" "empty" || return 1
}

test_format_movie_items() {
    local out f1 f2 f3 f6 f8
    out=$(format_movie_items <<< "Phim Test|2026|N/A|kkphim|series/kkphim:x|https://img/p.jpg|k20")
    IFS='|' read -r f1 f2 f3 _ _ f6 _ f8 <<< "$out"
    assert_contains "$f1" "Phim Test" "display has title" || return 1
    assert_contains "$f1" "2026" "display has year" || return 1
    assert_contains "$f1" "[kkphim]" "display has provider" || return 1
    assert_eq "Phim Test" "$f2" "clean title" || return 1
    assert_eq "2026" "$f3" "year" || return 1
    assert_eq "series/kkphim:x" "$f6" "slug" || return 1
    assert_eq "k20" "$f8" "source tag" || return 1
}

test_parse_k20_items() {
    local json='{"metas":[
        {"id":"kkphim:phim-a","type":"series","name":"Phim A","releaseInfo":"2026","poster":"https://img/a.jpg"},
        {"id":"animevietsub:b","type":"movie","name":"Phim B"}
    ]}'
    assert_eq $'Phim A|2026|N/A|kkphim|series/kkphim:phim-a|https://img/a.jpg\nPhim B|N/A|N/A|animevietsub|movie/animevietsub:b|' \
        "$(parse_k20_items "$json")" "item mapping" || return 1
    assert_eq "" "$(parse_k20_items '{"error":"x"}')" "no metas" || return 1
}

test_group_results() {
    local out
    out=$(group_results <<'ROWS'
Trùm Cuối Giá Lâm! / Trùm Cuối Xuất Hiện! (Phần 2)|2026|N/A|kkphim|series/kkphim:tc2|https://img/tc2.jpg
Thám Tử Conan (Vietsub)|1996|N/A|vsmov|series/vsmov:conan-vs|
Trùm Cuối Xuất Hiện! (Phần 2)|2026|N/A|nguonc|series/nguonc:tc2|
Trùm Cuối Xuất Hiện! (Phần 1)|2025|N/A|nguonc|series/nguonc:tc1|
thám tử conan (Lồng Tiếng)|1996|N/A|vsmov|series/vsmov:conan-lt|https://img/c.jpg
Thám Tử Conan|2011|N/A|kkphim|movie/kkphim:conan-2011|
ROWS
)
    assert_eq 4 "$(wc -l <<< "$out")" "same title + year merged, other years kept apart" || return 1
    assert_eq "Trùm Cuối Giá Lâm! / Trùm Cuối Xuất Hiện! (Phần 2)|2026|N/A|kkphim, nguonc|series/kkphim:tc2|https://img/tc2.jpg|k20|series/kkphim:tc2~Trùm Cuối Giá Lâm! / Trùm Cuối Xuất Hiện! (Phần 2)^series/nguonc:tc2~Trùm Cuối Xuất Hiện! (Phần 2)" \
        "$(sed -n 1p <<< "$out")" "matched on a ' / ' part, first row leads" || return 1
    assert_contains "$(sed -n 2p <<< "$out")" "|vsmov|series/vsmov:conan-vs|https://img/c.jpg|k20|series/vsmov:conan-vs~Thám Tử Conan (Vietsub)^series/vsmov:conan-lt~" \
        "case and audio tags ignored, provider listed once, poster filled from a later row" || return 1

    out=$(printf '%s\n' "Psyren|N/A|N/A|kkphim|series/kkphim:p|" "Psyren|N/A|N/A|animevietsub|series/animevietsub:p||k20anime" | group_results)
    assert_eq 2 "$(wc -l <<< "$out")" "rows of different addons never merge" || return 1
    assert_contains "$(sed -n 2p <<< "$out")" "|series/animevietsub:p||k20anime|series/animevietsub:p~Psyren" "src kept" || return 1
}

test_k20anime_index() {
    call_api() {
        case "$1" in
            */manifest.json) echo '{"catalogs":[{"type":"series","id":"latest","extra":[{"name":"genre","options":["Hành Động"]}]},{"type":"movie","id":"film"}]}' ;;
            */series/latest.json) echo '{"metas":[{"id":"animevietsub:a","type":"series","name":"A"}]}' ;;
            */series/latest/genre=H%C3%A0nh%20%C4%90%E1%BB%99ng.json) echo '{"metas":[{"id":"animevietsub:a","type":"series","name":"A"},{"id":"animevietsub:b","type":"series","name":"B"}]}' ;;
            */movie/film.json) echo '{"metas":[{"id":"animevietsub:c","type":"movie","name":"C"},{"id":"animevietsub:a","type":"movie","name":"A"}]}' ;;
        esac
    }
    sleep 30 &
    local bg=$! t0=$SECONDS
    k20anime_index || return 1
    kill "$bg"
    (( SECONDS - t0 < 10 )) || { echo "index build waited on an unrelated background job" >&2; return 1; }
    assert_eq $'A|N/A|N/A|animevietsub|series/animevietsub:a|\nB|N/A|N/A|animevietsub|series/animevietsub:b|\nC|N/A|N/A|animevietsub|movie/animevietsub:c|' \
        "$(sort "$ANIME_INDEX")" "every catalog and genre page, deduplicated by id across types" || return 1

    call_api() { return 1; }
    touch -d "2 hours ago" "$ANIME_INDEX"
    k20anime_index
    assert_eq 3 "$(wc -l < "$ANIME_INDEX")" "failed rebuild keeps the old index" || return 1
}

test_open_choice_source_picker() {
    local got="" row
    watch_episode() { got="$1|$2|$3"; }
    row=$(format_movie_items <<< "Phim|2026|N/A|kkphim, nguonc|series/kkphim:a||k20|series/kkphim:a~Phim A^series/nguonc:b~Phim B")
    fzf() { cat > "$TEST_HOME/picker"; sed -n 2p "$TEST_HOME/picker"; }
    open_choice "$row"
    assert_contains "$(cat "$TEST_HOME/picker")" "[kkphim] Phim A~" "picker shows provider and name" || return 1
    assert_eq "series/nguonc:b|Phim B|k20" "$got" "chosen source opened" || return 1

    got=""
    open_choice "$(format_movie_items <<< "Solo|2026|N/A|kkphim|series/kkphim:s||k20|series/kkphim:s~Solo")"
    assert_eq "series/kkphim:s|Solo|k20" "$got" "single source opens without asking" || return 1
}

test_k20_catalog_paging() {
    local calls="$TEST_HOME/calls"
    call_api() {
        printf '%s\n' "$1" >> "$calls"
        case "$1" in
            *skip=4*) echo '{"metas":[{"id":"kkphim:c","type":"series","name":"C"}]}' ;;
            *) echo '{"metas":[{"id":"kkphim:a","type":"series","name":"A"},{"id":"kkphim:b","type":"series","name":"B"}]}' ;;
        esac
    }
    local out
    out=$(k20_catalog k20anime series/animevietsub-latest 1)
    assert_contains "$out" "A|N/A|N/A|kkphim|series/kkphim:a||k20anime" "rows tagged with source" || return 1
    assert_contains "$(cat "$calls")" "$API_K20_ANIME/catalog/series/animevietsub-latest.json" "anime base" || return 1
    : > "$calls"
    out=$(k20_catalog k20 movie/kkphim-movie 3 "Danh mục: Mới")
    assert_contains "$(cat "$calls")" "$API_K20/catalog/movie/kkphim-movie/genre=Danh%20m%E1%BB%A5c%3A%20M%E1%BB%9Bi&skip=4.json" \
        "genre kept and skip = (page-1) * page size" || return 1
    assert_contains "$out" "|series/kkphim:c|" "page 3 rows" || return 1
    assert_eq "" "$(k20_catalog k20anime series/animevietsub-latest 2)" "page repeating page 1 means no next page" || return 1
}

test_k20_catalogs() {
    call_api() {
        echo '{"catalogs":[{"type":"movie","id":"m","name":"Lẻ"},{"type":"tv","id":"t","name":"TV"},{"type":"series","id":"s","name":"Bộ"}]}'
    }
    assert_eq $'Lẻ|k20|movie/m\nBộ|k20|series/s\nLẻ|k20anime|movie/m\nBộ|k20anime|series/s' "$(k20_catalogs)" "movie/series catalogs of both addons" || return 1
}

test_resolve_k20_stream() {
    local bin
    bin=$(fake_bin curl "cat <<'JSON'
{\"streams\":[{\"name\":\"NguonC\",\"title\":\"Vietsub\\nTập 1\",\"url\":\"https://cdn.test/a.m3u8\",
  \"behaviorHints\":{\"proxyHeaders\":{\"request\":{\"Referer\":\"https://embed.test/\",\"User-Agent\":\"UA, with comma\"}}}},
  {\"name\":\"Rating only\"}]}
JSON")
    PATH="$bin:$PATH" resolve_k20_stream "https://sc.k-20.xyz/stream/series/x.json" || return 1
    assert_eq "https://cdn.test/a.m3u8" "$K20_URL" "single playable stream, no prompt" || return 1
    assert_eq $'Referer: https://embed.test/\nUser-Agent: UA, with comma' "$(printf '%s\n' "${K20_HEADERS[@]}")" "proxy headers" || return 1

    bin=$(fake_bin curl "echo '{\"streams\":[{\"name\":\"A\",\"url\":\"https://a\"},{\"name\":\"B\",\"url\":\"https://b\"}]}'")
    fzf() { sed -n 2p; }
    PATH="$bin:$PATH" resolve_k20_stream "https://sc.k-20.xyz/stream/movie/y.json" || return 1
    assert_eq "https://b" "$K20_URL" "second version picked via fzf" || return 1
    assert_eq 0 "${#K20_HEADERS[@]}" "no headers" || return 1

    bin=$(fake_bin curl "echo '{\"streams\":[{\"name\":\"Evil\",\"url\":\"--exec=touch /tmp/pwned\"}]}'")
    if PATH="$bin:$PATH" resolve_k20_stream "https://sc.k-20.xyz/stream/movie/evil.json"; then
        echo "non-http URL must be refused" >&2; return 1
    fi

    bin=$(fake_bin curl "echo '{\"streams\":[]}'")
    if PATH="$bin:$PATH" resolve_k20_stream "https://sc.k-20.xyz/stream/movie/z.json"; then
        echo "empty stream list must fail" >&2; return 1
    fi
}

# Fake KKPhim CDN: a master pointing at a relative variant, whose playlist opens
# with a pre-roll ad, then movie segments, convertv clips and a mid-roll ad.
kkphim_cdn() {
    fake_bin curl 'url=${@: -1}
case "$url" in
    */hls/index.m3u8) cat <<PL
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:8
#EXTINF:5.0,
/v9/d3b5/segment_0001.ts
#EXT-X-DISCONTINUITY
#EXTINF:6.8,
movie1.ts
#EXT-X-DISCONTINUITY
#EXTINF:3.6,
convertv9/clip1.ts
#EXT-X-DISCONTINUITY
#EXT-X-KEY:METHOD=NONE
#EXTINF:2.7,
/v9/d3b5/segment_0002.ts
#EXT-X-DISCONTINUITY
#EXTINF:4.0,
movie2.ts
#EXT-X-ENDLIST
PL
    ;;
    */index.m3u8) printf "%s\n" "#EXTM3U" "#EXT-X-STREAM-INF:BANDWIDTH=3500000" "3500kb/hls/index.m3u8" ;;
    *) exit 22 ;;
esac'
}

test_kkphim_playlist() {
    local bin out
    bin=$(kkphim_cdn)
    out=$(PATH="$bin:$PATH" kkphim_playlist "https://sc.k-20.xyz/proxy-playlist.m3u8?url=https%3A%2F%2Fcdn.test%2Fep%2Findex.m3u8&referer=x") || return 1
    assert_eq $'#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:8\n#EXT-X-DISCONTINUITY\n#EXTINF:6.8,\nhttps://cdn.test/ep/3500kb/hls/movie1.ts\n#EXT-X-DISCONTINUITY\n#EXTINF:3.6,\nhttps://cdn.test/ep/3500kb/hls/convertv9/clip1.ts\n#EXT-X-KEY:METHOD=NONE\n#EXT-X-DISCONTINUITY\n#EXTINF:4.0,\nhttps://cdn.test/ep/3500kb/hls/movie2.ts\n#EXT-X-ENDLIST' \
        "$(cat "$out")" "ads dropped with their tags, convertv kept, URIs absolute" || return 1

    local base="${out%.m3u8}" name
    name="${base##*/}"
    assert_eq "# mpv EDL v0
%$(( ${#name} + 9 ))%$name-001.m3u8,length=6.800
%$(( ${#name} + 9 ))%$name-002.m3u8,length=3.600
%$(( ${#name} + 9 ))%$name-003.m3u8,length=4.000" "$(cat "$base.edl")" "one EDL part per splice, relative names" || return 1
    assert_eq $'#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:8\n#EXTINF:3.6,\nhttps://cdn.test/ep/3500kb/hls/convertv9/clip1.ts\n#EXT-X-ENDLIST' \
        "$(cat "$base-002.m3u8")" "part playlist is self-contained" || return 1

    # Movie moved to another directory: everything but convertv would be dropped.
    local moved
    moved=$(fake_bin curl 'printf "%s\n" "#EXTM3U" "#EXTINF:6.0," "/elsewhere/movie1.ts" "#EXTINF:6.0," "/elsewhere/movie2.ts" "#EXTINF:3.0," "convertv9/c.ts" "#EXT-X-ENDLIST"')
    if PATH="$moved:$PATH" kkphim_playlist "https://sc.k-20.xyz/proxy-playlist.m3u8?url=https%3A%2F%2Fcdn.test%2Fep%2Fhls%2Findex.m3u8"; then
        echo "a rebuild that drops more than it keeps must fall back to K20" >&2; return 1
    fi

    if PATH="$bin:$PATH" kkphim_playlist "https://sc.k-20.xyz/proxy-playlist.m3u8?url=--exec%3Dx"; then
        echo "non-http upstream URL must be refused" >&2; return 1
    fi
}

test_stream_url_kkphim() {
    local bin
    bin=$(kkphim_cdn)
    resolve_k20_stream() { K20_URL="https://sc.k-20.xyz/proxy-playlist.m3u8?url=https%3A%2F%2Fcdn.test%2Fep%2Findex.m3u8"; K20_HEADERS=("Referer: x"); }
    PATH="$bin:$PATH" stream_url "https://sc.k-20.xyz/stream/series/kkphim:a:tap-1.json" || return 1
    assert_contains "$K20_URL" "$CACHE/playlists/kkphim-" "KKPhim plays the local playlist" || return 1
    assert_eq 0 "${#K20_HEADERS[@]}" "CDN needs no K20 headers" || return 1

    PATH="$bin:$PATH" stream_url "https://sc.k-20.xyz/stream/series/vsmov:a:tap-1.json" || return 1
    assert_contains "$K20_URL" "proxy-playlist.m3u8" "other providers keep K20's playlist" || return 1

    bin=$(fake_bin curl 'exit 7')
    PATH="$bin:$PATH" stream_url "https://sc.k-20.xyz/stream/series/kkphim:a:tap-1.json" || return 1
    assert_contains "$K20_URL" "proxy-playlist.m3u8" "CDN failure falls back to K20" || return 1
}

test_nguonc_proxy() {
    local real_curl bin out seg
    real_curl=$(type -P curl)
    # Upstream as the proxy sees it: a playlist with a .png segment, the segment
    # bytes, and the headers it was given recorded per request.
    bin=$(fake_bin curl 'url=${@: -1}; printf "%s\n" "$*" >> "$HOME/upstream"
case "$url" in
    https://cdn.test/list.m3u8) printf "%s\n" "#EXTM3U" "#EXTINF:5.0," "seg0.png" "#EXT-X-ENDLIST" ;;
    https://cdn.test/seg0.png) printf "TSDATA" ;;
    *) exit 22 ;;
esac')
    K20_URL="https://cdn.test/list.m3u8"
    K20_HEADERS=("Referer: https://embed.test/")
    PATH="$bin:$PATH" nguonc_proxy_start || { echo "proxy did not start" >&2; return 1; }
    assert_contains "$K20_URL" "http://127.0.0.1:" "K20_URL points at the proxy" || { nguonc_proxy_stop; return 1; }
    assert_eq 0 "${#K20_HEADERS[@]}" "headers move into the proxy" || { nguonc_proxy_stop; return 1; }

    out=$("$real_curl" -fsS --max-time 10 "$K20_URL")
    seg=$(grep -v '^#' <<< "$out")
    assert_contains "$seg" "/s.ts?u=https%3A%2F%2Fcdn.test%2Fseg0.png" "segment renamed .ts, served by the proxy" || { nguonc_proxy_stop; return 1; }
    assert_eq "TSDATA" "$("$real_curl" -fsS --max-time 10 "$seg")" "segment bytes passed through" || { nguonc_proxy_stop; return 1; }
    assert_contains "$(cat "$HOME/upstream")" "-H Referer: https://embed.test/" "CDN headers sent upstream" || { nguonc_proxy_stop; return 1; }
    assert_eq 403 "$("$real_curl" -s -o /dev/null -w '%{http_code}' "${K20_URL%%\?*}?u=https%3A%2F%2Fevil.test%2Fx")" \
        "URLs it did not write itself are refused" || { nguonc_proxy_stop; return 1; }

    local pid=$NGUONC_PROXY_PID
    nguonc_proxy_stop
    sleep 0.3
    if kill -0 "$pid" 2>/dev/null; then echo "proxy still running after stop" >&2; return 1; fi
}

test_stream_url_nguonc() {
    resolve_k20_stream() { K20_URL="https://k20.test/nguonc-hls.m3u8"; K20_HEADERS=("Referer: x"); }
    nguonc_proxy_start() { K20_URL="http://127.0.0.1:1/p.m3u8"; K20_HEADERS=(); }
    stream_url "https://sc.k-20.xyz/stream/series/nguonc:a:tap-1.json" || return 1
    assert_eq "http://127.0.0.1:1/p.m3u8" "$K20_URL" "NguonC goes through the local proxy" || return 1

    nguonc_proxy_start() { return 1; }
    show_error() { echo "ERR $1"; }
    local out
    out=$(stream_url "https://sc.k-20.xyz/stream/series/nguonc:a:tap-1.json") && { echo "must fail without the proxy" >&2; return 1; }
    assert_contains "$out" "python3" "user told what is missing" || return 1
}

test_play_video_mpv() {
    local args="$TEST_HOME/mpv-args" bin
    bin=$(fake_bin mpv "printf '%s\n' \"\$@\" > '$args'")
    resolve_k20_stream() { K20_URL="https://k20.test/p.m3u8"; K20_HEADERS=("User-Agent: UA, with comma"); }
    PLAYER_DEFAULT=mpv
    PATH="$bin:$PATH" play_video "https://sc.k-20.xyz/stream/series/x.json" "T" || return 1
    assert_eq "https://k20.test/p.m3u8" "$(head -1 "$args")" "resolved URL first" || return 1
    assert_contains "$(cat "$args")" "--http-header-fields-append=User-Agent: UA, with comma" "header verbatim" || return 1
    assert_contains "$(cat "$args")" "--demuxer-seekable-cache=yes" "seekable cache" || return 1
    [[ "$(cat "$args")" != *protocol_whitelist* ]] || { echo "whitelist only for local playlists" >&2; return 1; }

    resolve_k20_stream() { K20_URL="$CACHE/playlists/kkphim-x.m3u8"; K20_HEADERS=(); }
    PATH="$bin:$PATH" play_video "https://sc.k-20.xyz/stream/series/x.json" "T" || return 1
    assert_contains "$(cat "$args")" '--demuxer-lavf-o=protocol_whitelist="https,http,file,tcp,tls,crypto,data"' "local playlist may load https segments" || return 1
    assert_eq "$CACHE/playlists/kkphim-x.m3u8" "$(head -1 "$args")" "no EDL yet: the playlist plays" || return 1
    mkdir -p "$CACHE/playlists"
    echo "# mpv EDL v0" > "$CACHE/playlists/kkphim-x.edl"
    PATH="$bin:$PATH" play_video "https://sc.k-20.xyz/stream/series/x.json" "T" || return 1
    assert_eq "$CACHE/playlists/kkphim-x.edl" "$(head -1 "$args")" "mpv plays the EDL when present" || return 1
    resolve_k20_stream() { K20_URL="https://k20.test/p.m3u8"; K20_HEADERS=("User-Agent: UA, with comma"); }

    PATH="$bin:$PATH" play_video "https://old.example/ep.m3u8" "Old" || return 1
    assert_eq "https://old.example/ep.m3u8" "$(head -1 "$args")" "legacy playlist link played as is" || return 1
    : > "$args"
    show_error() { :; }
    if PATH="$bin:$PATH" play_video "https://embed11.streamc.xyz/embed.php?hash=x" "Old"; then
        echo "legacy player page must not reach mpv" >&2; return 1
    fi
    assert_eq "" "$(cat "$args")" "mpv not started for a player page" || return 1
    if PATH="$bin:$PATH" play_video "--script=x.m3u8" "Old"; then
        echo "non-http playlist must not reach mpv" >&2; return 1
    fi
}

test_play_video_vlc() {
    local args="$TEST_HOME/vlc-args" bin
    bin=$(fake_bin vlc "printf '%s\n' \"\$@\" > '$args'")
    resolve_k20_stream() { K20_URL="https://k20.test/p.m3u8"; K20_HEADERS=("Referer: https://embed.test/" "Origin: https://embed.test"); }
    PLAYER_DEFAULT=vlc
    PATH="$bin:$PATH" play_video "https://sc.k-20.xyz/stream/series/x.json" "T" || return 1
    assert_contains "$(cat "$args")" "--http-referrer=https://embed.test/" "referrer" || return 1
    assert_contains "$(cat "$args")" "--no-input-fast-seek" "accurate seek" || return 1
    assert_contains "$(cat "$args")" "--network-caching=3000" "network buffer" || return 1
}

test_preview_script() {
    local bin p out row
    bin=$(fake_bin curl 'echo "{\"meta\":{\"runtime\":\"76 phút\",\"genres\":[\"Hài\",\"Nhạc\"],\"description\":\"<p>Dòng một</p>\nDòng hai\"}}"')
    p=$(create_preview_script) || return 1
    # Search rows carry a 9th field (source alternatives) that must not leak into src.
    row=$(format_movie_items <<< "Bocchi|2024|N/A|kkphim|series/kkphim:bocchi||k20|series/kkphim:bocchi~Bocchi^series/nguonc:b~B")
    out=$(PATH="$bin:$PATH" TERM=dumb FZF_PREVIEW_COLUMNS=60 "$p" "$row" | sed 's/\x1b\[[0-9;]*m//g')
    assert_contains "$out" "Năm: 2024" "year" || return 1
    assert_contains "$out" "Nguồn: kkphim" "provider" || return 1
    assert_contains "$out" "Thời lượng: 76 phút" "runtime" || return 1
    assert_contains "$out" "Thể loại: Hài, Nhạc" "genres" || return 1
    assert_contains "$out" "Dòng một Dòng hai" "description without tags" || return 1
    [[ -s "$CACHE/desc/k20-series_kkphim:bocchi.json" ]] || { echo "meta not cached under a flat name" >&2; return 1; }

    bin=$(fake_bin curl 'echo "{\"meta\":null}"')
    row=$(format_movie_items <<< "X|2024|N/A|kkphim|series/kkphim:missing||k20")
    PATH="$bin:$PATH" TERM=dumb "$p" "$row" >/dev/null
    [[ ! -e "$CACHE/desc/k20-series_kkphim:missing.json" ]] || { echo "null meta cached" >&2; return 1; }
}

test_vlc_plugin_check() {
    local bin
    bin=$(fake_bin vlc 'printf "  avcodec  FFmpeg audio/video decoder\n"')
    if PATH="$bin:$PATH" vlc_plays_hls; then
        echo "missing ts demuxer must be detected" >&2; return 1
    fi
    bin=$(fake_bin vlc 'printf "  ts  MPEG Transport Stream demuxer\n  avcodec  FFmpeg audio/video decoder\n"')
    PATH="$bin:$PATH" vlc_plays_hls || { echo "full VLC reported broken" >&2; return 1; }

    local only="$TEST_HOME/vlc-only" both="$TEST_HOME/vlc-mpv"
    mkdir -p "$only" "$both"
    printf '#!/bin/bash\n' > "$only/vlc"; chmod +x "$only/vlc"
    cp "$only/vlc" "$both/vlc"; cp "$only/vlc" "$both/mpv"
    show_error() { echo "WARN $1"; }
    assert_eq "mpv" "$(PLAYER_DEFAULT=vlc; PATH="$both"; check_player >/dev/null; printf '%s' "$PLAYER_DEFAULT")" "broken VLC falls back to mpv" || return 1
    assert_contains "$(PLAYER_DEFAULT=vlc; PATH="$only"; check_player)" "vlc-plugin-dvb vlc-plugin-ffmpeg" "user told which packages to install" || return 1
}

test_watch_episode_records_after_play() {
    call_api() { echo '{"meta":{"videos":[{"id":"kkphim:x:tap-1","title":"1"}]}}'; }
    fzf() {
        local n
        n=$(cat "$TEST_HOME/fzf-calls" 2>/dev/null || echo 0)
        echo $((n + 1)) > "$TEST_HOME/fzf-calls"
        (( n < 2 )) && { printf 'enter\n'; head -1; }
    }
    play_video() { [[ -f "$TEST_HOME/play-ok" ]]; }
    show_error() { :; }
    watch_episode "series/kkphim:x" "X" k20 >/dev/null
    assert_eq "" "$(cat "$HIST")" "failed playback is not recorded" || return 1

    rm -f "$TEST_HOME/fzf-calls"
    touch "$TEST_HOME/play-ok"
    watch_episode "series/kkphim:x" "X" k20 >/dev/null
    assert_contains "$(cat "$HIST")" "|X - Tập 1|series/kkphim:x|" "played episode recorded" || return 1
    assert_eq "series/kkphim:x|1" "$(cat "$PROGRESS")" "progress recorded" || return 1
}

test_paginated_list() {
    local got=""
    # fetch runs in a command substitution, so pages are logged to a file.
    fetch() { printf '%s ' "$1" >> "$TEST_HOME/pages"; [[ "$1" == 1 ]] && echo "A|2024|N/A|kkphim|series/kkphim:a||k20"; }
    fzf() {
        local n
        n=$(cat "$TEST_HOME/fzf-n" 2>/dev/null || echo 0)
        echo $((n + 1)) > "$TEST_HOME/fzf-n"
        case "$n" in
            0) echo right ;;
            1) printf 'enter\n'; head -1 ;;
            *) cat > /dev/null ;;  # Esc
        esac
    }
    watch_episode() { got="$1|$2|$3"; echo opened >> "$TEST_HOME/opened"; }
    show_paginated_list "P" fetch
    assert_eq "1 2 1 1 " "$(cat "$TEST_HOME/pages")" "empty page 2 falls back to page 1, and page 1 shows again after the title" || return 1
    assert_eq "series/kkphim:a|A|k20" "$got" "selection opens the title" || return 1
    assert_eq 3 "$(cat "$TEST_HOME/fzf-n")" "back from the episode list to this list, then Esc leaves" || return 1
}

test_preview_kitsu_for_anime() {
    local bin p out row
    bin=$(fake_bin curl 'case "${*}" in
    *anime-kitsu*) echo "{\"metas\":[{\"name\":\"PSYREN\",\"poster\":\"https://kitsu.test/p.jpg\",\"genres\":[\"Action\"],\"description\":\"A mysterious\nphone card.\"}]}" ;;
    *) echo "{\"meta\":{\"description\":\"Chất lượng: HD\",\"genres\":[\"Anime\"]}}" ;;
esac')
    p=$(create_preview_script) || return 1
    row=$(format_movie_items <<< "Psyren|N/A|N/A|animevietsub|series/animevietsub:p|https://blocked.test/p.jpg|k20anime")
    out=$(PATH="$bin:$PATH" TERM=dumb FZF_PREVIEW_COLUMNS=60 "$p" "$row" | sed 's/\x1b\[[0-9;]*m//g')
    assert_contains "$out" "Thể loại: Action" "genres from Kitsu" || return 1
    assert_contains "$out" "Chất lượng: HD — A mysterious phone card." "K20 status kept, Kitsu synopsis added" || return 1
    [[ -s "$CACHE/desc/k20anime-series_animevietsub:p.kitsu.json" ]] || { echo "Kitsu match not cached" >&2; return 1; }

    row=$(format_movie_items <<< "Phim|2024|N/A|kkphim|series/kkphim:x||k20")
    PATH="$bin:$PATH" TERM=dumb "$p" "$row" >/dev/null
    [[ ! -e "$CACHE/desc/k20-series_kkphim:x.kitsu.json" ]] || { echo "Kitsu must only be asked for K20 Anime" >&2; return 1; }

    bin=$(fake_bin curl 'case "${*}" in *anime-kitsu*) echo kitsu >> "$HOME/kitsu-calls"; echo "{\"metas\":[]}" ;; *) echo "{\"meta\":{}}" ;; esac')
    row=$(format_movie_items <<< "Không Có|N/A|N/A|animevietsub|series/animevietsub:none||k20anime")
    PATH="$bin:$PATH" TERM=dumb "$p" "$row" >/dev/null
    PATH="$bin:$PATH" TERM=dumb "$p" "$row" >/dev/null
    assert_eq 1 "$(wc -l < "$HOME/kitsu-calls")" "a Kitsu miss is remembered, not asked on every hover" || return 1
}

test_download_episode() {
    local args="$TEST_HOME/dl-args" bin
    bin=$(fake_bin yt-dlp "printf '%s\n' \"\$@\" > '$args'")
    resolve_k20_stream() { K20_URL="https://k20.test/p.m3u8"; K20_HEADERS=("Referer: https://embed.test/"); }
    sleep() { :; }
    local shown
    shown=$(PATH="$bin:$PATH" download_episode "https://sc.k-20.xyz/stream/series/x.json" 'Frieren: Pháp Sư (Phần 2) - Tập 01 \c end')
    wait
    assert_contains "$shown" '\c end' "API title printed as text, not as an escape" || return 1
    assert_contains "$(cat "$args")" "Frieren_-_Pháp_Sư_(Phần_2)_-_Tập_01_-_c_end.mp4" "Vietnamese file name kept, backslash replaced" || return 1
    assert_eq $'https://k20.test/p.m3u8\n--add-header\nReferer: https://embed.test/' "$(head -3 "$args")" "URL and header" || return 1
    local log
    IFS='|' read -r _ _ log < "$CACHE/downloads/tasks.log"
    assert_eq "0" "$(cat "$log.rc")" "exit status recorded" || return 1
}

test_download_local_playlist() {
    local args="$TEST_HOME/dl-local" bin
    bin=$(fake_bin yt-dlp "printf '%s\n' \"\$@\" > '$args'")
    resolve_k20_stream() { K20_URL="$CACHE/playlists/kkphim-x.m3u8"; K20_HEADERS=(); }
    sleep() { :; }
    PATH="$bin:$PATH" download_episode "https://sc.k-20.xyz/stream/series/x.json" "Phim" >/dev/null
    wait
    assert_eq "file://$CACHE/playlists/kkphim-x.m3u8" "$(head -1 "$args")" "local playlist as file URL" || return 1
    assert_contains "$(cat "$args")" "--enable-file-urls" "yt-dlp allowed to read it" || return 1
}

test_view_downloads_status() {
    mkdir -p "$CACHE/downloads"
    local log="$CACHE/downloads/1_new.log" legacy="$CACHE/downloads/2_old.log"
    : > "$log"
    : > "$legacy"
    printf '%s|%s|%s\n' "Phim Mới" "new.mp4" "$log" > "$CACHE/downloads/tasks.log"
    printf '%s|%s|%s|%s\n' "99999999" "Phim Cũ" "old.mp4" "$legacy" >> "$CACHE/downloads/tasks.log"
    printf '0\n' > "$log.rc"
    fzf() { cat > "$TEST_HOME/fzf-in"; }
    view_downloads
    assert_contains "$(cat "$TEST_HOME/fzf-in")" "Hoàn tất" "rc=0 is complete" || return 1
    assert_contains "$(cat "$TEST_HOME/fzf-in")" "Phim Cũ" "legacy row parsed" || return 1
}

test_watch_episode_list() {
    call_api() {
        echo '{"meta":{"videos":[{"id":"kkphim:x:tap-1","title":"Tập 1"},{"id":"kkphim:x:tap-2","episode":2}]}}'
    }
    fzf() { cat > "$TEST_HOME/eps"; }
    watch_episode "series/kkphim:x" "X" k20 >/dev/null
    assert_eq $'Tập 1|https://sc.k-20.xyz/stream/series/kkphim:x:tap-1.json\n2|https://sc.k-20.xyz/stream/series/kkphim:x:tap-2.json' \
        "$(cat "$TEST_HOME/eps")" "episodes point at stream endpoints" || return 1

    call_api() { echo '{"meta":{}}'; }
    watch_episode "movie/kkphim:y" "Y" k20 >/dev/null
    assert_eq "Full|https://sc.k-20.xyz/stream/movie/kkphim:y.json" "$(cat "$TEST_HOME/eps")" "movie without videos" || return 1
}

test_search_script() {
    local bin s out
    # Each catalog answers with one row named after itself plus one shared slug.
    bin=$(fake_bin curl 'for a; do case "$a" in */catalog/*) url=$a ;; esac; [[ $prev == -o ]] && out=$a; prev=$a; done
id=${url#*/catalog/}; id=${id%%/search=*}
echo "{\"metas\":[{\"id\":\"p:${id//\//-}\",\"type\":\"series\",\"name\":\"$id\"},{\"id\":\"kkphim:dup\",\"type\":\"series\",\"name\":\"Dup\"}]}" > "$out"')
    printf '%s\n' "Bocchi Anime|N/A|N/A|animevietsub|series/animevietsub:b|" "Other|N/A|N/A|animevietsub|series/animevietsub:o|" > "$ANIME_INDEX"
    s=$(create_search_script) || return 1
    out=$(PATH="$bin:$PATH" "$s" "BOCCHI" | cut -d'|' -f2,6,8)
    assert_eq $'series/kkphim-series|series/p:series-kkphim-series|k20\nDup|series/kkphim:dup|k20' "$(head -2 <<< "$out")" "listed order, tagged" || return 1
    assert_eq 8 "$(wc -l <<< "$out")" "six catalogs, one deduplicated shared row, one anime match" || return 1
    assert_eq "Bocchi Anime|series/animevietsub:b|k20anime" "$(tail -1 <<< "$out")" "anime index matched case-insensitively, tagged k20anime" || return 1
    assert_eq "" "$(PATH="$bin:$PATH" "$s" "b")" "one-letter query ignored" || return 1
    assert_eq 0 "$(PATH="$bin:$PATH" "$s" "  " | grep -c animevietsub)" "blank query lists no anime" || return 1
}

test_handle_cli_args() {
    local out
    out=$(handle_cli_args -h)
    assert_contains "$out" "--search" "help has search" || return 1
    assert_contains "$out" "--continue" "help has continue" || return 1
}

test_continue_plays_latest() {
    printf '%s\n' "100|Old|a|https://old|1" "200|New - Tập 2|b|https://new|2" > "$HIST"
    play_video() { echo "PLAY $1|$2"; }
    assert_contains "$(handle_cli_args -c)" "PLAY https://new|New - Tập 2" "latest row" || return 1
}

test_is_cache_fresh() {
    local f="$TEST_HOME/fresh.json"
    printf '{}' > "$f"
    is_cache_fresh "$f" 3600 || { echo "fresh file reported stale" >&2; return 1; }
    touch -d "10 seconds ago" "$f"
    if is_cache_fresh "$f" 5; then echo "stale file reported fresh" >&2; return 1; fi
    if is_cache_fresh "$TEST_HOME/nope.json" 3600; then echo "missing file reported fresh" >&2; return 1; fi
}

test_record_history() {
    record_history "slug-1" $'Title | weird\nname' "http://url/1" "5" || return 1
    assert_contains "$(cat "$HIST")" "|Title - weird name|slug-1|http://url/1|5" "record shape" || return 1
    record_history "slug-1" "New Title" "http://url/2" "6" || return 1
    assert_eq 1 "$(wc -l < "$HIST")" "dedupe by slug" || return 1
    record_history "slug-2" "Other" "http://url/3" "1" || return 1
    assert_eq 2 "$(wc -l < "$HIST")" "append new slug" || return 1
}

test_continue_watching() {
    local got="" played=""
    watch_episode() { got="$1|$2|$3"; }
    play_video() { played="$1|$2"; }
    printf '%s\n' \
        "1700000000|Frieren - Tập 01|series/kkphim:frieren|https://sc.k-20.xyz/stream/series/kkphim:frieren:tap-01.json|01" \
        "1700000100|Psyren - Tập 02|series/animevietsub:p|https://anime.k-20.xyz/stream/series/animevietsub:p:tap-02.json|02" \
        "1600000000|Cũ - Tập 3|old-slug|https://old.example/ep.m3u8|3" > "$HIST"
    fzf() {
        local n
        n=$(cat "$TEST_HOME/n" 2>/dev/null || echo 0)
        echo $((n + 1)) > "$TEST_HOME/n"
        case "$n" in
            0) cat > "$TEST_HOME/rows"; printf 'enter\n'; sed -n 1p "$TEST_HOME/rows" ;;
            1) printf 'enter\n'; grep 'old-slug' ;;
            2) printf 'ctrl-d\n'; grep 'kkphim:frieren' ;;
            *) return 130 ;;
        esac
    }
    continue_watching
    assert_contains "$(sed -n 1p "$TEST_HOME/rows")" "Psyren - Tập 02" "newest first" || return 1
    assert_contains "$(cat "$TEST_HOME/rows")" "ngày trước" "shows how long ago" || return 1
    assert_eq "series/animevietsub:p|Psyren|k20anime" "$got" "opens the episode list with the name and the anime source" || return 1
    assert_eq "https://old.example/ep.m3u8|Cũ - Tập 3" "$played" "pre-K20 rows still play directly" || return 1
    assert_eq 0 "$(grep -c 'kkphim:frieren' "$HIST")" "Ctrl+D forgets the title" || return 1
}

test_watch_episode_cursor() {
    call_api() { echo '{"meta":{"videos":[{"id":"x:1","title":"1"},{"id":"x:2","title":"2"},{"id":"x:3","title":"3"}]}}'; }
    fzf() { printf '%s\n' "$@" > "$TEST_HOME/fzf-args"; cat > /dev/null; }
    watch_episode "series/kkphim:x" "X" k20 >/dev/null
    assert_contains "$(cat "$TEST_HOME/fzf-args")" "load:pos(1)" "nothing watched: first episode" || return 1

    record_progress "series/kkphim:x" "2"
    watch_episode "series/kkphim:x" "X" k20 >/dev/null
    assert_contains "$(cat "$TEST_HOME/fzf-args")" "load:pos(3)" "cursor on the episode after the last watched" || return 1
    assert_contains "$(cat "$TEST_HOME/fzf-args")" "▶ Tiếp: Tập 3" "header names it" || return 1

    record_progress "series/kkphim:x" "3"
    watch_episode "series/kkphim:x" "X" k20 >/dev/null
    assert_contains "$(cat "$TEST_HOME/fzf-args")" "load:pos(3)" "last episode watched: stays on it" || return 1
    assert_contains "$(cat "$TEST_HOME/fzf-args")" "✓ Đã xem: Tập 3" "header says it was watched" || return 1

    record_progress "series/kkphim:x" "Tập 01"
    watch_episode "series/kkphim:x" "X" k20 >/dev/null
    assert_contains "$(cat "$TEST_HOME/fzf-args")" "load:pos(1)" "unknown saved episode: first episode" || return 1
    if grep -q "Đã xem\|Tiếp:" "$TEST_HOME/fzf-args"; then echo "no claim for an episode that is not listed" >&2; return 1; fi
}

test_paginated_filter() {
    local got=""
    fetch() { printf '%s|%s\n' "$1" "$2" >> "$TEST_HOME/fetches"; echo "A|2024|N/A|kkphim|series/kkphim:a||k20"; }
    filters() { printf '%s\n' "Quốc gia: Hàn Quốc" "Năm: 2024"; }
    fzf() {
        local n
        n=$(cat "$TEST_HOME/fn" 2>/dev/null || echo 0)
        echo $((n + 1)) > "$TEST_HOME/fn"
        case "$n" in
            0) printf '%s\n' "$@" > "$TEST_HOME/list-args"; cat > /dev/null; echo ctrl-g ;;
            1) grep 'Hàn Quốc' ;;
            2) printf '%s\n' "$@" > "$TEST_HOME/list-args"; cat > /dev/null ;;
        esac
    }
    show_paginated_list "KKPhim" fetch filters
    assert_contains "$(cat "$TEST_HOME/fetches")" "1|Quốc gia: Hàn Quốc" "Ctrl+G filter reaches the fetch callback on page 1" || return 1
    assert_contains "$(cat "$TEST_HOME/list-args")" "KKPhim · Quốc gia: Hàn Quốc >" "prompt shows the filter" || return 1
}

test_rewrite_rows_keeps_dir_clean() {
    record_history "a" "A" "http://u" "1" || return 1
    add_favorite "A" "a" k20 || return 1
    remove_favorite "a" || return 1
    assert_eq "" "$(find "$CONF" -name '*.log.*')" "no temp files left next to the logs" || return 1
    assert_eq "" "$(cat "$FAV")" "favorite removed" || return 1
}

test_record_progress() {
    record_progress "slug-1" "5" || return 1
    record_progress "slug-1" "6" || return 1
    assert_eq "slug-1|6" "$(cat "$PROGRESS")" "progress updated" || return 1
    record_progress "slug-2" "1" || return 1
    assert_eq 2 "$(wc -l < "$PROGRESS")" "two slugs" || return 1
}

test_favorites() {
    add_favorite $'Title | X' "series/kkphim:a" k20 || return 1
    assert_contains "$(cat "$FAV")" "|Title - X|series/kkphim:a|||k20" "row shape" || return 1
    add_favorite "Title Y" "series/kkphim:a" k20 || return 1
    assert_eq 1 "$(wc -l < "$FAV")" "dedupe by slug" || return 1
    add_favorite "B" "series/animevietsub:b" k20anime || return 1

    local got=""
    watch_episode() { got="$1|$2|$3"; }
    fzf() {
        [[ -e "$TEST_HOME/fav-shown" ]] && return 130  # Esc on the second visit
        touch "$TEST_HOME/fav-shown"
        printf 'enter\n'; grep 'animevietsub'
    }
    favorites
    assert_eq "series/animevietsub:b|B|k20anime" "$got" "opens with its source, then the list shows again" || return 1

    remove_favorite "series/kkphim:a" || return 1
    assert_eq 1 "$(wc -l < "$FAV")" "removed" || return 1
}

test_load_settings() {
    assert_eq "mpv" "$PLAYER_DEFAULT" "default player" || return 1
    printf '%s\n' 'PLAYER_DEFAULT = "vlc"' '# comment' 'SOURCE=phimapi' 'SEARCH_SOURCES=vsmov' > "$CONFIG_FILE"
    load_settings
    assert_eq "vlc" "$PLAYER_DEFAULT" "quoted player, old keys ignored" || return 1
    printf 'PLAYER_DEFAULT=mplayer\n' > "$CONFIG_FILE"
    load_settings
    assert_eq "vlc" "$PLAYER_DEFAULT" "unknown player ignored" || return 1
}

test_save_settings() {
    PLAYER_DEFAULT=vlc
    save_settings
    assert_eq "PLAYER_DEFAULT=vlc" "$(cat "$CONFIG_FILE")" "config file" || return 1
    PLAYER_DEFAULT=mpv
    load_settings
    assert_eq "vlc" "$PLAYER_DEFAULT" "round trip" || return 1
}

test_clear_cache() {
    mkdir -p "$CACHE/desc" "$CACHE/downloads" "$CONF/cache/segments"
    : > "$CACHE/api.json"
    : > "$CACHE/desc/poster.img"
    local done_log="$CACHE/downloads/1_done.log" live_log="$CACHE/downloads/2_live.log"
    : > "$done_log"
    printf '0\n' > "$done_log.rc"
    : > "$live_log"
    printf '%s\n' "Xong|done.mp4|$done_log" "Đang|live.mp4|$live_log" > "$CACHE/downloads/tasks.log"
    sleep() { :; }
    clear_cache >/dev/null
    [[ ! -e "$CACHE/api.json" && ! -e "$CACHE/desc" ]] || { echo "cache left" >&2; return 1; }
    [[ ! -e "$CONF/cache" ]] || { echo "old cache dir under config left" >&2; return 1; }
    [[ ! -e "$done_log" && ! -e "$done_log.rc" ]] || { echo "finished download log left" >&2; return 1; }
    [[ -f "$live_log" ]] || { echo "running download log removed" >&2; return 1; }
    assert_eq "Đang|live.mp4|$live_log" "$(cat "$CACHE/downloads/tasks.log")" "only the running download stays listed" || return 1
}

test_check_dependencies_fzf_version() {
    local bin
    bin=$(fake_bin fzf 'echo "0.44.1 (debian)"')
    ( PATH="$bin:$PATH"; check_dependencies ) >/dev/null
    assert_eq 1 "$?" "fzf older than 0.60 refused" || return 1
    bin=$(fake_bin fzf 'echo "0.60.0 (abc)"')
    ( PATH="$bin:$PATH"; check_dependencies ) >/dev/null
    assert_eq 0 "$?" "fzf 0.60 accepted" || return 1
    assert_eq "--wrap" "$(PATH="$bin:$PATH"; check_dependencies; printf '%s' "${FZF_OPTS[-1]}")" "0.60 wraps by character" || return 1
    bin=$(fake_bin fzf 'echo "0.75.0 (abc)"')
    assert_eq "--wrap=word" "$(PATH="$bin:$PATH"; check_dependencies; printf '%s' "${FZF_OPTS[-1]}")" "0.68+ wraps whole words" || return 1
}

test_check_dependencies_missing() {
    local minbin="$TEST_HOME/minbin"
    mkdir -p "$minbin"
    ( export PATH="$minbin"; check_dependencies ) >/dev/null
    assert_eq 1 "$?" "exit 1 when deps missing" || return 1
}

test_check_player() {
    local bin="$TEST_HOME/playerbin" empty="$TEST_HOME/emptybin"
    mkdir -p "$bin" "$empty"
    ln -s "$(type -P true)" "$bin/vlc"
    assert_eq "vlc" "$(PLAYER_DEFAULT=mpv; PATH="$bin"; check_player; printf '%s' "$PLAYER_DEFAULT")" "falls back to vlc" || return 1
    ( PATH="$empty"; check_player ) >/dev/null
    assert_eq 1 "$?" "exit 1 when no player" || return 1
}

# fake curl for call_api: counts calls, ok or fail.
make_fake_curl() {
    local counter="$1" mode="$2"
    fake_bin curl "printf x >> '$counter'
[[ '$mode' == fail ]] && exit 1
echo '{\"metas\":[{\"id\":\"kkphim:f\",\"type\":\"movie\",\"name\":\"Fake\"}]}'"
}

test_call_api_cache() {
    local counter="$TEST_HOME/count" bin out1 out2
    : > "$counter"
    bin=$(make_fake_curl "$counter" ok)
    out1=$(PATH="$bin:$PATH" call_api "https://k20.test/catalog/x.json")
    out2=$(PATH="$bin:$PATH" call_api "https://k20.test/catalog/x.json")
    assert_eq "$out1" "$out2" "cache returns same body" || return 1
    assert_contains "$out1" "kkphim:f" "body" || return 1
    assert_eq "x" "$(cat "$counter")" "curl called once" || return 1
}

test_call_api_retry_fails() {
    local counter="$TEST_HOME/count-fail" bin
    : > "$counter"
    bin=$(make_fake_curl "$counter" fail)
    sleep() { :; }
    PATH="$bin:$PATH" call_api "https://k20.test/x.json"
    assert_eq 1 "$?" "returns 1 after retries" || return 1
    assert_eq "xxx" "$(cat "$counter")" "three attempts" || return 1
}

test_call_api_stale_cache_refetch() {
    local counter="$TEST_HOME/count-stale" bin key
    : > "$counter"
    bin=$(make_fake_curl "$counter" ok)
    key=$(hash_url "https://k20.test/stale.json")
    printf '{"stale":true}' > "$CACHE/$key.json"
    touch -d "2 hours ago" "$CACHE/$key.json"
    assert_contains "$(PATH="$bin:$PATH" call_api "https://k20.test/stale.json")" "kkphim:f" "refetched" || return 1
    assert_eq "x" "$(cat "$counter")" "one fetch" || return 1
}

test_call_api_rejects_null_meta() {
    local bin
    bin=$(fake_bin curl "echo '{\"meta\":null}'")
    sleep() { :; }
    PATH="$bin:$PATH" call_api "https://k20.test/meta/series/x.json" >/dev/null
    assert_eq 1 "$?" "null meta is a failure" || return 1
    assert_eq 0 "$(find "$CACHE" -maxdepth 1 -name '*.json' | wc -l)" "null meta not cached" || return 1
}

test_call_api_rejects_error_body() {
    local bin
    bin=$(fake_bin curl "echo '{\"error\":\"Not Found\"}'")
    sleep() { :; }
    PATH="$bin:$PATH" call_api "https://k20.test/missing.json" >/dev/null
    assert_eq 1 "$?" "error body is a failure" || return 1
    assert_eq 0 "$(find "$CACHE" -maxdepth 1 -name '*.json' | wc -l)" "error body not cached" || return 1
}

# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------
build_lib

echo "sudachi.sh regression tests"
echo "  library: $LIB"
echo ""

TESTS=(
    sanitize_field
    format_movie_items
    parse_k20_items
    group_results
    open_choice_source_picker
    k20anime_index
    k20_catalog_paging
    k20_catalogs
    resolve_k20_stream
    kkphim_playlist
    stream_url_kkphim
    nguonc_proxy
    stream_url_nguonc
    play_video_mpv
    play_video_vlc
    preview_script
    preview_kitsu_for_anime
    download_episode
    download_local_playlist
    view_downloads_status
    vlc_plugin_check
    watch_episode_list
    watch_episode_records_after_play
    paginated_list
    search_script
    handle_cli_args
    continue_plays_latest
    is_cache_fresh
    record_history
    continue_watching
    watch_episode_cursor
    paginated_filter
    rewrite_rows_keeps_dir_clean
    record_progress
    favorites
    load_settings
    save_settings
    clear_cache
    check_dependencies_fzf_version
    check_dependencies_missing
    check_player
    call_api_cache
    call_api_retry_fails
    call_api_stale_cache_refetch
    call_api_rejects_null_meta
    call_api_rejects_error_body
)

for t in "${TESTS[@]}"; do
    run_test "$t"
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
    printf 'Failed: %s\n' "${FAILED_TESTS[*]}"
    exit 1
fi
exit 0
