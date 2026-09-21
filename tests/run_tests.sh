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

# ---------------------------------------------------------------------------
# Build a sourceable library: everything in sudachi.sh up to the first
# top-level statement (`load_settings` at the bottom of the file).
# ---------------------------------------------------------------------------
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

# run_test NAME — runs the test body in a subshell with an isolated HOME.
# Body is provided on stdin? No: we pass the function name via $1 and read the
# body from a heredoc at the call site. Simpler: each test is a bash function
# named test_<name>; run_test sources the lib and invokes it.
run_test() {
    local name="$1"
    local home="$TESTS_TMP/home-$name"
    local out rc
    # -c so the test body (defined in the parent) is available after sourcing.
    out=$(export HOME="$home" TEST_HOME="$home"; \
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

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

test_sanitize_field() {
    assert_eq "a b" "$(sanitize_field $'a\nb')" "newline to space" || return 1
    assert_eq "a b" "$(sanitize_field $'a\rb')" "CR to space" || return 1
    assert_eq "a-b" "$(sanitize_field "a|b")" "pipe to dash" || return 1
    assert_eq "plain" "$(sanitize_field "plain")" "passthrough" || return 1
    assert_eq "" "$(sanitize_field "")" "empty" || return 1
}

test_add_menu_numbers() {
    assert_eq $'1. a\n2. b\n3. c' "$(printf 'a\nb\nc' | add_menu_numbers)" "numbering" || return 1
}

test_format_movie_items() {
    local input="Phim Test|2026 [FHD-Vietsub]|Nhật Bản|Tập 10|phim-test|https://img.url/p.jpg"
    local out
    out=$(format_movie_items <<< "$input")
    local field1 field2 field3 field4 field5 field6 field7
    IFS='|' read -r field1 field2 field3 field4 field5 field6 field7 <<< "$out"
    assert_contains "$field1" "Phim Test" "display contains title" || return 1
    assert_contains "$field1" "2026 [FHD-Vietsub]" "display contains tag" || return 1
    assert_contains "$field1" "[Tập 10]" "display contains ep" || return 1
    assert_eq "Phim Test" "$field2" "field 2 is clean title" || return 1
    assert_eq "2026 [FHD-Vietsub]" "$field3" "field 3 is tag" || return 1
    assert_eq "Nhật Bản" "$field4" "field 4 is country" || return 1
    assert_eq "Tập 10" "$field5" "field 5 is ep" || return 1
    assert_eq "phim-test" "$field6" "field 6 is slug" || return 1
    assert_eq "https://img.url/p.jpg" "$field7" "field 7 is poster" || return 1
}

test_get_base_url() {
    API_SOURCE=phimapi
    assert_eq "$API_PHIMAPI" "$(get_base_url)" "phimapi" || return 1
    API_SOURCE=ophim1
    assert_eq "$API_OPHIM1" "$(get_base_url)" "ophim1" || return 1
    API_SOURCE=bogus
    assert_eq "$API_OPHIM1" "$(get_base_url)" "fallback to ophim1" || return 1
}

test_parse_v1_items() {
    local json='{"data":{"items":[
        {"name":"Phim A","year":2024,"quality":"FHD","lang":"Vietsub","country":[{"name":"VN"}],"episode_current":"12/24","slug":"phim-a","poster_url":"/p/a.jpg"},
        {"name":"Phim B","year":null,"quality":null,"lang":null,"country":[],"episode_current":null,"slug":"phim-b","poster_url":"/p/b.jpg"}
    ]}}'
    local out
    out=$(parse_v1_items "$json" "https://cdn.example")
    # NOTE: cdn is prepended as "$cdn/\(.poster_url)"; poster_url starts with
    # '/' so the double slash is current locked behavior.
    assert_eq $'Phim A|2024 [FHD-Vietsub]|VN|12/24|phim-a|https://cdn.example//p/a.jpg\nPhim B|N/A|N/A|N/A|phim-b|https://cdn.example//p/b.jpg' \
        "$out" "item mapping with cdn" || return 1
}

test_parse_phimapi_v3() {
    local json='{"items":[
        {"name":"Phim A","year":2023,"quality":"HD","lang":"TM","country":[{"name":"US"}],"episode_current":"10","slug":"phim-a","poster_url":"/p/a.jpg"}
    ]}'
    local out
    out=$(parse_phimapi_v3 "$json")
    assert_eq $'Phim A|2023 [HD-TM]|US|10|phim-a|/p/a.jpg' "$out" "item mapping" || return 1
}

test_hash_url() {
    local h1 h2
    h1=$(hash_url "https://example.com/a?b=1")
    h2=$(hash_url "https://example.com/a?b=1")
    assert_eq "$h1" "$h2" "deterministic" || return 1
    [[ -n "$h1" ]] || { echo "empty hash" >&2; return 1; }
}

test_hls_absolutize_url() {
    local base="https://cdn/x/a/index.m3u8"
    assert_eq "https://cdn2/other/seg.ts" \
        "$(hls_absolutize_url "$base" "https://cdn2/other/seg.ts")" \
        "absolute passthrough" || return 1
    assert_eq "https://cdn/v8/abc/segment_1.ts" \
        "$(hls_absolutize_url "$base" "/v8/abc/segment_1.ts")" \
        "root-relative" || return 1
    assert_eq "https://cdn/x/a/seg.ts" \
        "$(hls_absolutize_url "$base" "seg.ts")" \
        "relative dir join" || return 1
    assert_eq "" "$(hls_absolutize_url "$base" "")" "empty" || return 1
}

test_hls_strip_ads() {
    local base="https://v7.kkphimplayer7.com/20260807/Dcq1MBiO/3500kb/hls/index.m3u8"
    local ad_fix="$SCRIPT_DIR/fixtures/ad_playlist.m3u8"
    local clean_fix="$SCRIPT_DIR/fixtures/clean_playlist.m3u8"
    local out

    out=$(hls_strip_ads "$base" < "$ad_fix")
    # Standalone video ads are completely dropped; movie segments (including convertv* with watermark) are kept.
    assert_contains "$out" "convertv8" "convertv8 movie segment with text overlay preserved" || return 1
    assert_contains "$out" "convertv7" "convertv7 movie segment with text overlay preserved" || return 1
    assert_eq 0 "$(printf '%s\n' "$out" | grep -c '/v8/')" "all /v8/ video ad lines dropped" || return 1
    assert_eq 0 "$(printf '%s\n' "$out" | grep -c '/v7/')" "all /v7/ video ad lines dropped" || return 1
    assert_eq 0 "$(printf '%s\n' "$out" | grep -c 'ads9/')" "all ads9/ video ad lines dropped" || return 1
    assert_eq 0 "$(printf '%s\n' "$out" | grep -c 'promo7/')" "all promo7/ video ad lines dropped" || return 1
    # Header normalization: VOD injected, DISCONTINUITY-SEQUENCE stripped.
    assert_contains "$out" "#EXT-X-PLAYLIST-TYPE:VOD" "VOD header injected" || return 1
    assert_eq 0 "$(printf '%s\n' "$out" | grep -c 'DISCONTINUITY-SEQUENCE')" "DISCONTINUITY-SEQUENCE stripped" || return 1
    assert_contains "$out" "#EXT-X-ENDLIST" "endlist kept" || return 1
    assert_contains "$out" "#EXTM3U" "header kept" || return 1
    assert_contains "$out" "https://v7.kkphimplayer7.com/20260807/Dcq1MBiO/3500kb/hls/segment_001.ts" "movie segment kept + absolutized" || return 1
    assert_contains "$out" "https://v7.kkphimplayer7.com/20260807/Dcq1MBiO/3500kb/hls/segment_014.ts" "last movie segment kept" || return 1
    assert_eq 0 "$(printf '%s\n' "$out" | grep -c '3500kb/hls/3500kb')" "no doubled path" || return 1

    # Clean fixture: no ad patterns -> all movie segments preserved; VOD is
    # injected so output is NOT byte-identical anymore.
    out=$(hls_strip_ads "$base" < "$clean_fix")
    assert_contains "$out" "#EXT-X-PLAYLIST-TYPE:VOD" "clean fixture gets VOD header" || return 1
    local seg
    for seg in segment_001.ts segment_002.ts segment_003.ts segment_004.ts; do
        assert_contains "$out" "https://v7.kkphimplayer7.com/20260807/Dcq1MBiO/3500kb/hls/$seg" "clean movie segment $seg kept" || return 1
    done
}

test_hls_strip_preroll_postroll() {
    local base="https://v7.kkphimplayer7.com/20260807/Dcq1MBiO/3500kb/hls/index.m3u8"
    local out

    # Test pre-roll ads: standalone ad segments at start must not inject discontinuity between movie segments 1 and 2
    out=$(printf '#EXTM3U\n#EXTINF:5.0,\n/v8/abc/segment_0001.ts\n#EXTINF:10.0,\nseg1.ts\n#EXTINF:10.0,\nseg2.ts\n#EXT-X-ENDLIST\n' | hls_strip_ads "$base")
    assert_eq 0 "$(printf '%s\n' "$out" | grep -c '/v8/')" "preroll ad dropped" || return 1
    assert_eq 0 "$(printf '%s\n' "$out" | grep -c 'DISCONTINUITY')" "no spurious discontinuity after preroll" || return 1
    assert_contains "$out" "seg1.ts" "seg1 kept" || return 1
    assert_contains "$out" "seg2.ts" "seg2 kept" || return 1
    assert_contains "$out" "#EXT-X-ENDLIST" "endlist kept after preroll" || return 1

    # Test post-roll ads: standalone ad segments at end must not swallow EXT-X-ENDLIST
    out=$(printf '#EXTM3U\n#EXTINF:10.0,\nseg1.ts\n#EXTINF:10.0,\nseg2.ts\n#EXTINF:5.0,\n/v8/abc/segment_0002.ts\n#EXT-X-ENDLIST\n' | hls_strip_ads "$base")
    assert_eq 0 "$(printf '%s\n' "$out" | grep -c '/v8/')" "postroll ad dropped" || return 1
    assert_contains "$out" "#EXT-X-ENDLIST" "endlist kept after postroll" || return 1
    assert_contains "$out" "seg1.ts" "seg1 kept" || return 1
    assert_contains "$out" "seg2.ts" "seg2 kept" || return 1
}

test_hls_strip_ads_structural() {
    # Tier 2: an ad block opened by #EXT-X-KEY:METHOD=NONE whose segment URIs
    # do NOT match HLS_AD_PATTERNS (renamed CDN directory, root-relative
    # outside the movie directory) must still be dropped.
    local base="https://s6.kkphimplayer6.com/20260118/C58AUGSC/3500kb/hls/index.m3u8"
    local ad_uri="/newlayout/d61a03b1/segment_0001.ts"
    if printf '%s\n' "$ad_uri" | grep -qE "$HLS_AD_PATTERNS"; then
        echo "fixture URI unexpectedly matches HLS_AD_PATTERNS" >&2
        return 1
    fi

    local out expected
    out=$(printf '#EXTM3U\n#EXTINF:6.0,\nGmydHZmS.ts\n#EXT-X-DISCONTINUITY\n#EXT-X-KEY:METHOD=NONE\n#EXTINF:3.72,\n/newlayout/d61a03b1/segment_0001.ts\n#EXTINF:2.36,\n/newlayout/d61a03b1/segment_0002.ts\n#EXT-X-DISCONTINUITY\n#EXTINF:2.76,\n7pKTYERY.ts\n#EXT-X-ENDLIST\n' | hls_strip_ads "$base")
    expected=$(printf '%s\n' \
        '#EXTM3U' \
        '#EXT-X-PLAYLIST-TYPE:VOD' \
        '#EXTINF:6.0,' \
        'https://s6.kkphimplayer6.com/20260118/C58AUGSC/3500kb/hls/GmydHZmS.ts' \
        '#EXT-X-DISCONTINUITY' \
        '#EXTINF:2.76,' \
        'https://s6.kkphimplayer6.com/20260118/C58AUGSC/3500kb/hls/7pKTYERY.ts' \
        '#EXT-X-ENDLIST')
    assert_eq "$expected" "$out" "pattern-free ad block dropped" || return 1
}

test_hls_strip_ads_structural_control() {
    # METHOD=NONE followed by movie segments in the playlist directory must be
    # untouched: the key tag passes through and nothing is dropped.
    local base="https://cdn/x/a/index.m3u8"
    local out expected
    out=$(printf '#EXTM3U\n#EXT-X-DISCONTINUITY\n#EXT-X-KEY:METHOD=NONE\n#EXTINF:10.0,\nsegment_001.ts\n#EXTINF:10.0,\nsegment_002.ts\n#EXT-X-ENDLIST\n' | hls_strip_ads "$base")
    expected=$(printf '%s\n' \
        '#EXTM3U' \
        '#EXT-X-PLAYLIST-TYPE:VOD' \
        '#EXT-X-DISCONTINUITY' \
        '#EXT-X-KEY:METHOD=NONE' \
        '#EXTINF:10.0,' \
        'https://cdn/x/a/segment_001.ts' \
        '#EXTINF:10.0,' \
        'https://cdn/x/a/segment_002.ts' \
        '#EXT-X-ENDLIST')
    assert_eq "$expected" "$out" "legit METHOD=NONE playlist untouched" || return 1
}

test_hls_pick_variant() {
    local master='#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
360/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720
720/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080
1080/index.m3u8'
    assert_eq "1080/index.m3u8" "$(hls_pick_variant "$master" "")" "auto picks highest" || return 1
    assert_eq "1080/index.m3u8" "$(hls_pick_variant "$master" "auto")" "auto literal picks highest" || return 1
    assert_eq "720/index.m3u8" "$(hls_pick_variant "$master" "720")" "720 picks 720" || return 1
    assert_eq "360/index.m3u8" "$(hls_pick_variant "$master" "480")" "480 falls back to smallest" || return 1
    assert_eq "720/index.m3u8" "$(hls_pick_variant "$master" "900")" "900 picks 720" || return 1
    assert_eq "" "$(hls_pick_variant "#EXTM3U" "")" "no variants echoes nothing" || return 1
}

test_hls_strip_uri_attrs() {
    local base="https://cdn/x/a/index.m3u8"
    local out
    out=$(printf '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n#EXT-X-MAP:URI="/init/map.mp4"\n#EXTINF:10.0,\nseg1.ts\n#EXT-X-ENDLIST\n' | hls_strip_ads "$base")
    assert_contains "$out" 'URI="https://cdn/x/a/key.bin"' "relative key URI absolutized" || return 1
    assert_contains "$out" 'URI="https://cdn/init/map.mp4"' "root-relative map URI absolutized" || return 1
    assert_contains "$out" "https://cdn/x/a/seg1.ts" "segment kept + absolutized" || return 1
}

test_hls_fetch_clean_cache_fallback() {
    # A failed refetch must reuse the cached cleaned playlist instead of the
    # raw ad-carrying URL.
    local curlbin="$TEST_HOME/curlbin-hls-cache"
    mkdir -p "$curlbin"
    cat > "$curlbin/curl" <<'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$curlbin/curl"

    local url="https://cdn.example/master.m3u8"
    local hash clean out
    hash=$(hash_url "$url")
    clean="$CACHE/$hash-clean.m3u8"
    printf '#EXTM3U\n#EXTINF:10,\nhttps://cdn.example/seg.ts\n#EXT-X-ENDLIST\n' > "$clean"

    out=$(PATH="$curlbin:$PATH" hls_fetch_clean "$url")
    assert_eq "$clean" "$out" "refetch failure reuses cached clean playlist" || return 1
}

test_hls_fetch_clean_quality() {
    local curlbin="$TEST_HOME/curlbin-hls-quality"
    mkdir -p "$curlbin"
    cat > "$curlbin/curl" <<EOF
#!/bin/bash
url="\${@: -1}"
printf '%s\n' "\$url" >> "$TEST_HOME/curl-requests.log"
case "\$url" in
    *master*)
        cat <<'MASTER'
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
360/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720
720/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080
1080/index.m3u8
MASTER
        ;;
    *720*|*1080*)
        cat "$SCRIPT_DIR/fixtures/clean_playlist.m3u8"
        ;;
    *)
        echo "WRONG-VARIANT"
        ;;
esac
EOF
    chmod +x "$curlbin/curl"

    local url="https://cdn.example/master.m3u8"
    QUALITY=720
    PATH="$curlbin:$PATH" hls_fetch_clean "$url" >/dev/null
    assert_contains "$(cat "$TEST_HOME/curl-requests.log")" "/720/index.m3u8" "720 variant fetched" || return 1
    assert_eq 0 "$(grep -c 'WRONG-VARIANT' "$TEST_HOME/curl-requests.log" 2>/dev/null || true)" "no other variant fetched" || return 1

    rm -f "$TEST_HOME/curl-requests.log"
    QUALITY=''
    PATH="$curlbin:$PATH" hls_fetch_clean "$url" >/dev/null
    assert_contains "$(cat "$TEST_HOME/curl-requests.log")" "1080/index.m3u8" "auto fetches the highest variant" || return 1
}

test_is_cache_fresh() {
    local f="$TEST_HOME/fresh.json"
    printf '{}' > "$f"
    is_cache_fresh "$f" 3600 || { echo "fresh file reported stale" >&2; return 1; }
    touch -d "10 seconds ago" "$f"
    if is_cache_fresh "$f" 5; then echo "stale file reported fresh" >&2; return 1; fi
    if is_cache_fresh "$TEST_HOME/nope.json" 3600; then echo "missing file reported fresh" >&2; return 1; fi
    return 0
}

test_record_history() {
    record_history "slug-1" $'Title | weird\nname' "http://url/1" || return 1
    local line
    line=$(cat "$HIST")
    assert_contains "$line" "|Title - weird name|slug-1|http://url/1" "record shape" || return 1
    assert_eq 1 "$(wc -l < "$HIST")" "single record" || return 1
    # Re-recording the same slug replaces the old entry.
    record_history "slug-1" "New Title" "http://url/2" || return 1
    assert_eq 1 "$(wc -l < "$HIST")" "dedupe by slug" || return 1
    assert_contains "$(cat "$HIST")" "New Title" "replaced title" || return 1
    # Different slug appends.
    record_history "slug-2" "Other" "http://url/3" || return 1
    assert_eq 2 "$(wc -l < "$HIST")" "append new slug" || return 1
}

test_record_progress() {
    record_progress "slug-1" "5" || return 1
    assert_eq "slug-1|5" "$(cat "$PROGRESS")" "progress record" || return 1
    record_progress "slug-1" "6" || return 1
    assert_eq "slug-1|6" "$(cat "$PROGRESS")" "progress updated" || return 1
    record_progress "slug-2" "1" || return 1
    assert_eq 2 "$(wc -l < "$PROGRESS")" "two slugs" || return 1
}

test_add_favorite() {
    add_favorite $'Title | X' "slug-1" "2024" "/poster.jpg" || return 1
    local line
    line=$(cat "$FAV")
    assert_contains "$line" "|Title - X|slug-1|2024|/poster.jpg" "favorite record" || return 1
    assert_eq 1 "$(wc -l < "$FAV")" "single favorite" || return 1
    # Same slug re-added -> deduped.
    add_favorite "Title Y" "slug-1" "2025" "/p2.jpg" || return 1
    assert_eq 1 "$(wc -l < "$FAV")" "dedupe by slug" || return 1
    add_favorite "Brand New" "slug-2" "2020" "/p4.jpg" || return 1
    assert_eq 2 "$(wc -l < "$FAV")" "append new" || return 1
}

test_remove_favorite() {
    add_favorite "A" "slug-1" "2024" "/p1.jpg" || return 1
    add_favorite "B" "slug-2" "2024" "/p2.jpg" || return 1
    remove_favorite "slug-1" || return 1
    assert_eq 1 "$(wc -l < "$FAV")" "one removed" || return 1
    assert_contains "$(cat "$FAV")" "slug-2" "survivor" || return 1
}

test_load_settings() {
    # Defaults when nothing exists.
    assert_eq "phimapi" "$API_SOURCE" "default source" || return 1
    assert_eq "mpv" "$PLAYER_DEFAULT" "default player" || return 1
    assert_eq "" "$QUALITY" "default quality" || return 1
    assert_eq 1 "$AD_BLOCK" "default ad_block" || return 1

    # With config present: quoted values, whitespace, comments, invalid lines.
    printf 'PLAYER_DEFAULT = "vlc"\n' > "$CONFIG_FILE"
    printf 'QUALITY= 720 \n' >> "$CONFIG_FILE"
    printf '# comment\n' >> "$CONFIG_FILE"
    printf 'BOGUS_KEY=1\n' >> "$CONFIG_FILE"
    printf 'QUALITY=999\n' >> "$CONFIG_FILE"
    printf 'ophim1\n' > "$SOURCE_FILE"
    load_settings
    assert_eq "ophim1" "$API_SOURCE" "source from file" || return 1
    assert_eq "vlc" "$PLAYER_DEFAULT" "quoted player" || return 1
    assert_eq "720" "$QUALITY" "quality" || return 1

    # Invalid QUALITY ignored: with fresh state (QUALITY=""), an invalid value
    # must not set QUALITY.
    printf 'QUALITY=999\n' > "$CONFIG_FILE"
    QUALITY=""
    load_settings
    assert_eq "" "$QUALITY" "invalid quality ignored" || return 1
}

test_save_settings() {
    API_SOURCE=ophim1
    PLAYER_DEFAULT=vlc
    QUALITY=480
    AD_BLOCK=0
    save_settings
    assert_eq "PLAYER_DEFAULT=vlc" "$(head -1 "$CONFIG_FILE")" "config player" || return 1
    assert_eq "QUALITY=480" "$(sed -n 2p "$CONFIG_FILE")" "config quality" || return 1
    assert_eq "AD_BLOCK=0" "$(sed -n 3p "$CONFIG_FILE")" "config ad_block" || return 1
    assert_eq "ophim1" "$(cat "$SOURCE_FILE")" "source file" || return 1
    # Round-trip through load_settings.
    API_SOURCE=phimapi PLAYER_DEFAULT=mpv QUALITY='' AD_BLOCK=1
    load_settings
    assert_eq "ophim1" "$API_SOURCE" "roundtrip source" || return 1
    assert_eq "vlc" "$PLAYER_DEFAULT" "roundtrip player" || return 1
    assert_eq "480" "$QUALITY" "roundtrip quality" || return 1
    assert_eq 0 "$AD_BLOCK" "roundtrip ad_block" || return 1
}

test_clear_cache_removes_all() {
    mkdir -p "$CACHE/desc" "$CACHE/downloads" "$CACHE/segments"
    : > "$CACHE/api.json"
    : > "$CACHE/foo-clean.m3u8"
    : > "$CACHE/desc/poster.img"
    : > "$CACHE/downloads/tasks.log"
    : > "$CACHE/segments/abc-r.ts"

    clear_cache >/dev/null

    [[ ! -f "$CACHE/api.json" ]] || { echo "json cache left" >&2; return 1; }
    [[ ! -f "$CACHE/foo-clean.m3u8" ]] || { echo "clean playlist left" >&2; return 1; }
    [[ ! -e "$CACHE/desc" ]] || { echo "desc dir left" >&2; return 1; }
    [[ ! -e "$CACHE/segments" ]] || { echo "segments dir left" >&2; return 1; }
    [[ -f "$CACHE/downloads/tasks.log" ]] || { echo "downloads must survive" >&2; return 1; }
}

test_download_episode_vietnamese_name() {
    local bin="$TEST_HOME/dlbin"
    mkdir -p "$bin"
    local dl_args="$TEST_HOME/dl_args"
    cat > "$bin/yt-dlp" <<EOF
#!/bin/bash
printf '%s\n' "\$@" > "$dl_args"
EOF
    chmod +x "$bin/yt-dlp"
    sleep() { :; }
    PATH="$bin:$PATH" download_episode "https://example.com/ep.m3u8" "Frieren: Pháp Sư Tiễn Táng (Phần 2) - Tập 01" >/dev/null
    wait
    local recorded
    recorded=$(cat "$dl_args" 2>/dev/null)
    assert_contains "$recorded" "Frieren_-_Pháp_Sư_Tiễn_Táng_(Phần_2)_-_Tập_01.mp4" "preserves Vietnamese name" || return 1
    unset -f sleep
}

test_handle_cli_args() {
    local help_out
    help_out=$(handle_cli_args -h)
    assert_contains "$help_out" "Sudachi" "help output" || return 1
    assert_contains "$help_out" "--search" "help contains search" || return 1
    assert_contains "$help_out" "--continue" "help contains continue" || return 1
}

test_check_dependencies() {
    # Real PATH: all present -> returns normally.
    check_dependencies || { echo "unexpected failure with deps present" >&2; return 1; }
}

test_check_dependencies_missing() {
    # Minimal PATH without fzf/jq/curl -> must exit 1.
    local minbin="$TEST_HOME/minbin"
    mkdir -p "$minbin"
    ln -s "$(command -v mkdir)" "$minbin/mkdir"
    ln -s "$(command -v touch)" "$minbin/touch"
    (
        export PATH="$minbin"
        check_dependencies
    )
    local rc=$?
    assert_eq 1 "$rc" "exit 1 when deps missing" || return 1
}

test_check_player() {
    local bin="$TEST_HOME/bin"
    mkdir -p "$bin"
    ln -s "$(command -v mpv)" "$bin/mpv"
    (
        export PATH="$bin"
        check_player
        printf 'PLAYER=%s' "$PLAYER_DEFAULT"
    ) | assert_contains "$(cat)" "PLAYER=mpv" "mpv detected" || return 1

    local empty="$TEST_HOME/emptybin"
    mkdir -p "$empty"
    (
        export PATH="$empty"
        check_player
    )
    local rc=$?
    assert_eq 1 "$rc" "exit 1 when no player" || return 1
}

test_hls_fetch_clean_ok() {
    # PATH-override curl serves a master playlist (with #EXT-X-STREAM-INF +
    # variant URI) for the master URL and the ad fixture as the media playlist
    # for the variant URL.
    local curlbin="$TEST_HOME/curlbin-hls"
    mkdir -p "$curlbin"
    cat > "$curlbin/curl" <<EOF
#!/bin/bash
url="\${@: -1}"
case "\$url" in
    *master*)
        cat <<'MASTER'
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-STREAM-INF:BANDWIDTH=3500000,RESOLUTION=1920x1080
/20260807/Dcq1MBiO/3500kb/hls/index.m3u8
MASTER
        ;;
    *)
        cat "$SCRIPT_DIR/fixtures/ad_playlist.m3u8"
        ;;
esac
EOF
    chmod +x "$curlbin/curl"

    local url="https://cdn.example/master.m3u8"
    local out hash clean
    out=$(PATH="$curlbin:$PATH" hls_fetch_clean "$url")
    hash=$(hash_url "$url")
    clean="$CACHE/$hash-clean.m3u8"
    assert_eq "$clean" "$out" "echoes clean file path" || return 1
    [[ -f "$clean" ]] || { echo "clean file missing: $clean" >&2; return 1; }
    # Standalone video commercial segments dropped; convertv* movie scenes preserved.
    assert_eq 3 "$(grep -c 'convertv8' "$clean")" "convertv8 movie lines preserved" || return 1
    assert_eq 0 "$(grep -c '/v8/' "$clean")" "/v8/ ad lines dropped" || return 1
    assert_eq 0 "$(grep -c '/v7/' "$clean")" "/v7/ ad lines dropped" || return 1
    assert_eq 0 "$(grep -c 'ads9/' "$clean")" "ads9 ad lines dropped" || return 1
    assert_eq 0 "$(grep -c 'promo7/' "$clean")" "promo7 ad lines dropped" || return 1
    assert_contains "$(cat "$clean")" "#EXT-X-PLAYLIST-TYPE:VOD" "VOD header injected" || return 1
    assert_eq 0 "$(grep -c 'DISCONTINUITY-SEQUENCE' "$clean")" "DISCONTINUITY-SEQUENCE stripped" || return 1
    local bad
    bad=$(grep -v '^#' "$clean" | grep -v '^$' | grep -vc '^http')
    assert_eq 0 "$bad" "all segment lines start with http" || return 1
    assert_contains "$(cat "$clean")" "#EXT-X-ENDLIST" "endlist kept" || return 1
}

test_hls_fetch_clean_fallback() {
    # curl fails -> hls_fetch_clean echoes the original URL and returns 0.
    local curlbin="$TEST_HOME/curlbin-hls-fail"
    mkdir -p "$curlbin"
    cat > "$curlbin/curl" <<'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$curlbin/curl"

    local url="https://cdn.example/master.m3u8"
    local out rc
    out=$(PATH="$curlbin:$PATH" hls_fetch_clean "$url")
    rc=$?
    assert_eq "$url" "$out" "fallback echoes original url" || return 1
    assert_eq 0 "$rc" "fallback returns 0" || return 1
}

test_hls_fetch_clean_canary() {
    # A playlist with DISCONTINUITY but no ad-pattern match must trigger the
    # canary debug log (CDN may have changed its ad URI layout).
    local curlbin="$TEST_HOME/curlbin-hls-canary"
    mkdir -p "$curlbin"
    cat > "$curlbin/curl" <<EOF
#!/bin/bash
url="\${@: -1}"
case "\$url" in
    *master*)
        cat <<'MASTER'
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-STREAM-INF:BANDWIDTH=3500000,RESOLUTION=1920x1080
/20260807/Dcq1MBiO/3500kb/hls/index.m3u8
MASTER
        ;;
    *)
        cat "$SCRIPT_DIR/fixtures/disc_no_ad_playlist.m3u8"
        ;;
esac
EOF
    chmod +x "$curlbin/curl"

    local url="https://cdn.example/master.m3u8"
    PATH="$curlbin:$PATH" hls_fetch_clean "$url" >/dev/null
    assert_contains "$(cat "$CACHE/debug.log" 2>/dev/null)" "HLS_AD_PATTERNS may need updating" "canary flags unmatched ad layout" || return 1
}

test_hls_rebase_convertv_rewrites_playlist() {
    # Fake ffmpeg/ffprobe/curl: every clip reports PTS 1.48..5.44 at 25fps and
    # ffmpeg just writes a marker file, so the rewrite logic is exercised
    # without downloading real segments.
    local shim="$TEST_HOME/rebasebin"
    mkdir -p "$shim"
    cat > "$shim/curl" <<'EOF'
#!/bin/bash
out=""
prev=""
for a in "$@"; do
    [[ "$prev" == "-o" ]] && out="$a"
    prev="$a"
done
[[ -n "$out" ]] && printf 'TS' > "$out"
exit 0
EOF
    cat > "$shim/ffmpeg" <<'EOF'
#!/bin/bash
# Model the real stream copy: output first/last = input first/last + shift,
# recorded in a sidecar the fake ffprobe serves for *-r.ts files.
shift=""
prev=""
for a in "$@"; do
    [[ "$prev" == "-itsoffset" ]] && shift="$a"
    prev="$a"
done
out="${!#}"
[[ -z "$shift" ]] && shift=0
printf 'REBASED' > "$out"
first=$(awk -v s="$shift" 'BEGIN{printf "%.6f", 1.48+s}')
last=$(awk -v s="$shift" 'BEGIN{printf "%.6f", 5.44+s}')
printf '%s,\n%s,\n' "$first" "$last" > "$out.pts"
# The real pipeline writes via a .part temp then renames; publish the sidecar
# under the final name too so the cache-reuse pass finds it.
base="${out%%.part.*}"
[[ "$base" != "$out" ]] && printf '%s,\n%s,\n' "$first" "$last" > "$base.pts"
exit 0
EOF
    cat > "$shim/ffprobe" <<'EOF'
#!/bin/bash
args="$*"
file="${!#}"
if [[ "$args" == *packet=pts_time* && -f "$file.pts" ]]; then
    cat "$file.pts"
    exit 0
fi
case "$args" in
    *packet=pts_time*) printf '1.480000,\n5.440000,\n' ;;
    *avg_frame_rate*|*r_frame_rate*) printf '25/1\n' ;;
    *"-select_streams v"*) printf 'video\n' ;;
    *) printf 'video\naudio\n' ;;
esac
exit 0
EOF
    chmod +x "$shim/curl" "$shim/ffmpeg" "$shim/ffprobe"

    local base="https://cdn.example/hls/index.m3u8"
    local pl="$TEST_HOME/rebase-in.m3u8"
    cat > "$pl" <<'EOF'
#EXTM3U
#EXT-X-PLAYLIST-TYPE:VOD
#EXTINF:4.0,
https://cdn.example/hls/prev.ts
#EXT-X-DISCONTINUITY
#EXTINF:4.0,
https://cdn.example/hls/convertv7/aaa.ts
#EXT-X-DISCONTINUITY
#EXT-X-DISCONTINUITY
#EXTINF:5.4,
https://cdn.example/hls/convertv7/bbb.ts
#EXT-X-DISCONTINUITY
#EXT-X-DISCONTINUITY
#EXT-X-KEY:METHOD=NONE
#EXTINF:3.0,
https://cdn.example/hls/next.ts
#EXT-X-ENDLIST
EOF

    local ha hb hprev out
    ha=$(hash_url "https://cdn.example/hls/convertv7/aaa.ts")
    hb=$(hash_url "https://cdn.example/hls/convertv7/bbb.ts")
    hprev=$(hash_url "https://cdn.example/hls/prev.ts")
    out="$TEST_HOME/rebase-out.m3u8"

    PATH="$shim:$PATH" hls_rebase_convertv "$pl" "$out" "$base" || return 1

    # Exact rewrite: convertv URIs become local rebased paths, every
    # DISCONTINUITY is gone, EXTINF/keys/movie segments are untouched.
    local expected
    expected=$(printf '%s\n' \
        '#EXTM3U' \
        '#EXT-X-PLAYLIST-TYPE:VOD' \
        '#EXTINF:4.0,' \
        'https://cdn.example/hls/prev.ts' \
        '#EXTINF:4.0,' \
        "$CACHE/segments/$ha-r.ts" \
        '#EXTINF:5.4,' \
        "$CACHE/segments/$hb-r.ts" \
        '#EXT-X-KEY:METHOD=NONE' \
        '#EXTINF:3.0,' \
        'https://cdn.example/hls/next.ts' \
        '#EXT-X-ENDLIST')
    assert_eq "$expected" "$(cat "$out")" "playlist rewritten in place" || return 1
    [[ -s "$CACHE/segments/$ha-r.ts" ]] || { echo "rebased clip a missing" >&2; return 1; }
    [[ -s "$CACHE/segments/$hb-r.ts" ]] || { echo "rebased clip b missing" >&2; return 1; }
    [[ -s "$CACHE/segments/$hprev.ts" ]] || { echo "cursor anchor not downloaded" >&2; return 1; }

    # Second pass with a failing ffmpeg: cached rebased clips must be reused
    # (their PTS already matches the cursor), so no download/rebase happens.
    printf '#!/bin/bash\nexit 1\n' > "$shim/ffmpeg"
    chmod +x "$shim/ffmpeg"
    local out2="$TEST_HOME/rebase-out2.m3u8"
    PATH="$shim:$PATH" hls_rebase_convertv "$pl" "$out2" "$base" || return 1
    assert_eq "$expected" "$(cat "$out2")" "cached rebased clips reused" || return 1
}

test_hls_rebase_convertv_multi_cluster() {
    # Two convertv clusters separated by movie content: each cluster must be
    # rebased from its own anchor (the movie segment before it), not chained
    # onto the previous cluster.
    local shim="$TEST_HOME/rebasebin-multi"
    mkdir -p "$shim"
    cat > "$shim/curl" <<'EOF'
#!/bin/bash
out=""
prev=""
for a in "$@"; do
    [[ "$prev" == "-o" ]] && out="$a"
    prev="$a"
done
[[ -n "$out" ]] && printf 'TS' > "$out"
exit 0
EOF
    cat > "$shim/ffmpeg" <<'EOF'
#!/bin/bash
shift=""
prev=""
for a in "$@"; do
    [[ "$prev" == "-itsoffset" ]] && shift="$a"
    prev="$a"
done
out="${!#}"
[[ -z "$shift" ]] && shift=0
printf 'REBASED' > "$out"
first=$(awk -v s="$shift" 'BEGIN{printf "%.6f", 1.48+s}')
last=$(awk -v s="$shift" 'BEGIN{printf "%.6f", 5.44+s}')
printf '%s,\n%s,\n' "$first" "$last" > "$out.pts"
# The real pipeline writes via a .part temp then renames; publish the sidecar
# under the final name too so the cache-reuse pass finds it.
base="${out%%.part.*}"
[[ "$base" != "$out" ]] && printf '%s,\n%s,\n' "$first" "$last" > "$base.pts"
exit 0
EOF
    cat > "$shim/ffprobe" <<'EOF'
#!/bin/bash
args="$*"
file="${!#}"
if [[ "$args" == *packet=pts_time* && -f "$file.pts" ]]; then
    cat "$file.pts"
    exit 0
fi
case "$args" in
    *packet=pts_time*) printf '1.480000,\n5.440000,\n' ;;
    *avg_frame_rate*|*r_frame_rate*) printf '25/1\n' ;;
    *"-select_streams v"*) printf 'video\n' ;;
    *) printf 'video\naudio\n' ;;
esac
exit 0
EOF
    chmod +x "$shim/curl" "$shim/ffmpeg" "$shim/ffprobe"

    local base="https://cdn.example/hls/index.m3u8"
    local pl="$TEST_HOME/rebase-multi-in.m3u8"
    cat > "$pl" <<'EOF'
#EXTM3U
#EXT-X-PLAYLIST-TYPE:VOD
#EXTINF:10.0,
https://cdn.example/hls/movie1.ts
#EXT-X-DISCONTINUITY
#EXTINF:4.0,
https://cdn.example/hls/convertv7/aaa.ts
#EXT-X-DISCONTINUITY
#EXTINF:10.0,
https://cdn.example/hls/movie2.ts
#EXT-X-DISCONTINUITY
#EXTINF:5.4,
https://cdn.example/hls/convertv7/bbb.ts
#EXT-X-ENDLIST
EOF

    # Anchor PTS sidecars at 25fps: movie1 ends at 19.96s (cursor 20.0) and
    # movie2 at 109.96s (cursor 110.0). The second cluster must land on its own
    # cursor instead of continuing after the first cluster.
    local hm1 hm2 ha hb
    hm1=$(hash_url "https://cdn.example/hls/movie1.ts")
    hm2=$(hash_url "https://cdn.example/hls/movie2.ts")
    mkdir -p "$CACHE/segments"
    printf '10.000000,\n19.960000,\n' > "$CACHE/segments/$hm1.ts.pts"
    printf '100.000000,\n109.960000,\n' > "$CACHE/segments/$hm2.ts.pts"

    ha=$(hash_url "https://cdn.example/hls/convertv7/aaa.ts")
    hb=$(hash_url "https://cdn.example/hls/convertv7/bbb.ts")
    local out="$TEST_HOME/rebase-multi-out.m3u8"
    PATH="$shim:$PATH" hls_rebase_convertv "$pl" "$out" "$base" || return 1

    local expected
    expected=$(printf '%s\n' \
        '#EXTM3U' \
        '#EXT-X-PLAYLIST-TYPE:VOD' \
        '#EXTINF:10.0,' \
        'https://cdn.example/hls/movie1.ts' \
        '#EXTINF:4.0,' \
        "$CACHE/segments/$ha-r.ts" \
        '#EXTINF:10.0,' \
        'https://cdn.example/hls/movie2.ts' \
        '#EXTINF:5.4,' \
        "$CACHE/segments/$hb-r.ts" \
        '#EXT-X-ENDLIST')
    assert_eq "$expected" "$(cat "$out")" "both clusters rewritten, discontinuities removed" || return 1
    assert_contains "$(cat "$CACHE/segments/$ha-r.ts.pts")" "20.000000" "first cluster anchored on movie1 cursor" || return 1
    assert_contains "$(cat "$CACHE/segments/$hb-r.ts.pts")" "110.000000" "second cluster anchored on movie2 cursor" || return 1

    # Second pass with a failing ffmpeg: both clusters must be reused from
    # cache because their first PTS still matches each cluster's cursor.
    printf '#!/bin/bash\nexit 1\n' > "$shim/ffmpeg"
    chmod +x "$shim/ffmpeg"
    local out2="$TEST_HOME/rebase-multi-out2.m3u8"
    PATH="$shim:$PATH" hls_rebase_convertv "$pl" "$out2" "$base" || return 1
    assert_eq "$expected" "$(cat "$out2")" "cached rebased clips reused per cluster" || return 1
}

test_hls_fetch_clean_without_ffmpeg_keeps_strip_output() {
    # PATH without ffmpeg/ffprobe: hls_fetch_clean must keep exactly the
    # hls_strip_ads output (convertv URIs + discontinuities), no segment cache.
    local minbin="$TEST_HOME/minbin-noffmpeg"
    mkdir -p "$minbin"
    local tool p
    for tool in awk sed grep cut md5sum mktemp mv rm date sort tr head cat; do
        p=$(command -v "$tool" 2>/dev/null) && ln -sf "$p" "$minbin/$tool"
    done
    cat > "$minbin/curl" <<EOF
#!/bin/bash
cat "$SCRIPT_DIR/fixtures/ad_playlist.m3u8"
EOF
    chmod +x "$minbin/curl"

    local url="https://cdn.example/hls/media.m3u8"
    local expected out hash clean
    expected=$(hls_strip_ads "$url" < "$SCRIPT_DIR/fixtures/ad_playlist.m3u8")

    out=$(PATH="$minbin" hls_fetch_clean "$url") || return 1
    hash=$(hash_url "$url")
    clean="$CACHE/$hash-clean.m3u8"
    assert_eq "$clean" "$out" "clean path echoed" || return 1
    assert_eq "$expected" "$(cat "$clean")" "strip_ads output kept without ffmpeg" || return 1
    assert_contains "$(cat "$clean")" "convertv8" "convertv URIs stay" || return 1
    assert_contains "$(cat "$clean")" "#EXT-X-DISCONTINUITY" "discontinuities stay" || return 1
    [[ ! -e "$CACHE/segments" ]] || { echo "segments cache must not be created" >&2; return 1; }
}

test_play_video_cleans_url() {
    # Fake mpv records its args; fake curl serves master->variant->media
    # fixture. Assert mpv receives the cleaned playlist and --cache=yes.
    local bin="$TEST_HOME/playbin"
    mkdir -p "$bin"
    local argsfile="$TEST_HOME/mpv-args"
    : > "$argsfile"
    cat > "$bin/mpv" <<EOF
#!/bin/bash
printf '%s\n' "\$@" > "$argsfile"
EOF
    chmod +x "$bin/mpv"

    local curlbin="$TEST_HOME/playbin-curl"
    mkdir -p "$curlbin"
    cat > "$curlbin/curl" <<EOF
#!/bin/bash
url="\${@: -1}"
case "\$url" in
    *master*)
        cat <<'MASTER'
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-STREAM-INF:BANDWIDTH=3500000,RESOLUTION=1920x1080
/20260807/Dcq1MBiO/3500kb/hls/index.m3u8
MASTER
        ;;
    *)
        cat "$SCRIPT_DIR/fixtures/ad_playlist.m3u8"
        ;;
esac
EOF
    chmod +x "$curlbin/curl"

    PLAYER_DEFAULT=mpv
    QUALITY=
    PATH="$bin:$curlbin:$PATH" play_video "https://v7.kkphimplayer7.com/master.m3u8" "Test Title"
    local i=0
    while [[ ! -s "$argsfile" && $i -lt 50 ]]; do sleep 0.05; i=$((i + 1)); done
    local first
    first=$(head -1 "$argsfile")
    assert_contains "$first" "-clean.m3u8" "mpv receives clean playlist" || return 1
    assert_contains "$(cat "$argsfile")" "--save-position-on-quit" "mpv saves position on quit" || return 1
    assert_contains "$(cat "$argsfile")" "--cache=yes" "mpv gets --cache=yes" || return 1
    # Local cleaned playlist needs the hls demuxer + widened protocol whitelist
    # (ffmpeg refuses https segments with the default file,crypto,data list).
    assert_contains "$(cat "$argsfile")" "--demuxer-lavf-format=hls" "mpv forces hls demuxer" || return 1
    assert_contains "$(cat "$argsfile")" 'protocol_whitelist="https,http,file,tcp,tls,crypto,data"' "mpv widens segment protocol whitelist" || return 1
    # Anti-framedrop flags for DISCONTINUITY splice points.
    assert_contains "$(cat "$argsfile")" "--hr-seek-framedrop=no" "mpv disables framedrop at seek" || return 1
    assert_contains "$(cat "$argsfile")" "--demuxer-readahead-secs=20" "mpv readahead for smooth splice" || return 1
    # Seekable RAM cache: seeks inside the buffer never hit the demuxer, so
    # PTS gaps left by ad removal cannot reset playback to the start.
    assert_contains "$(cat "$argsfile")" "--demuxer-seekable-cache=yes" "mpv enables seekable cache" || return 1
    assert_contains "$(cat "$argsfile")" "--demuxer-max-bytes=150M" "mpv caps read-ahead buffer" || return 1
    assert_contains "$(cat "$argsfile")" "--demuxer-max-back-bytes=100M" "mpv keeps back-buffer for backward seek" || return 1
    assert_contains "$(cat "$argsfile")" "--hr-seek=default" "mpv hr-seek default" || return 1
    # --demuxer-lavf-linearize-timestamps=yes is deliberately absent: it
    # rewrites the timeline one-way and breaks backward seek across the
    # PTS jumps left by removed ad segments.
}

test_play_video_fallback_url() {
    # curl fails -> play_video must pass the ORIGINAL url to mpv.
    local bin="$TEST_HOME/playbin-fail"
    mkdir -p "$bin"
    local argsfile="$TEST_HOME/mpv-args-fail"
    : > "$argsfile"
    cat > "$bin/mpv" <<EOF
#!/bin/bash
printf '%s\n' "\$@" > "$argsfile"
EOF
    chmod +x "$bin/mpv"

    local curlbin="$TEST_HOME/playbin-curl-fail"
    mkdir -p "$curlbin"
    printf '#!/bin/bash\nexit 1\n' > "$curlbin/curl"
    chmod +x "$curlbin/curl"

    PLAYER_DEFAULT=mpv
    QUALITY=
    PATH="$bin:$curlbin:$PATH" play_video "https://v7.kkphimplayer7.com/master.m3u8" "Test Title"
    local i=0
    while [[ ! -s "$argsfile" && $i -lt 50 ]]; do sleep 0.05; i=$((i + 1)); done
    local first
    first=$(head -1 "$argsfile")
    assert_eq "https://v7.kkphimplayer7.com/master.m3u8" "$first" "mpv receives original url" || return 1
}

test_play_video_vlc_args() {
    # VLC must receive the cleaned playlist plus the accurate-seek and network
    # buffering flags; --preferred-resolution behavior is unchanged.
    local bin="$TEST_HOME/vlcbin"
    mkdir -p "$bin"
    local argsfile="$TEST_HOME/vlc-args"
    : > "$argsfile"
    cat > "$bin/vlc" <<EOF
#!/bin/bash
printf '%s\n' "\$@" > "$argsfile"
EOF
    chmod +x "$bin/vlc"

    local curlbin="$TEST_HOME/vlcbin-curl"
    mkdir -p "$curlbin"
    cat > "$curlbin/curl" <<EOF
#!/bin/bash
cat "$SCRIPT_DIR/fixtures/clean_playlist.m3u8"
EOF
    chmod +x "$curlbin/curl"

    PLAYER_DEFAULT=vlc
    QUALITY=720
    PATH="$bin:$curlbin:$PATH" play_video "https://s6.kkphimplayer6.com/movie/3500kb/hls/index.m3u8" "Test Title"
    local i=0
    while [[ ! -s "$argsfile" && $i -lt 50 ]]; do sleep 0.05; i=$((i + 1)); done
    assert_contains "$(head -1 "$argsfile")" "-clean.m3u8" "vlc receives cleaned playlist" || return 1
    assert_contains "$(cat "$argsfile")" "--no-video-title-show" "vlc title bar disabled" || return 1
    assert_contains "$(cat "$argsfile")" "--no-input-fast-seek" "vlc accurate seek" || return 1
    assert_contains "$(cat "$argsfile")" "--network-caching=3000" "vlc network buffering" || return 1
    assert_contains "$(cat "$argsfile")" "--preferred-resolution=720" "vlc quality flag kept" || return 1
}

test_toggle_ad_block() {
    sleep() { :; }
    AD_BLOCK=1
    toggle_ad_block >/dev/null
    assert_eq 0 "$AD_BLOCK" "ad block toggled to 0" || return 1
    assert_eq "AD_BLOCK=0" "$(sed -n 3p "$CONFIG_FILE")" "config file updated to 0" || return 1
    toggle_ad_block >/dev/null
    assert_eq 1 "$AD_BLOCK" "ad block toggled to 1" || return 1
    assert_eq "AD_BLOCK=1" "$(sed -n 3p "$CONFIG_FILE")" "config file updated to 1" || return 1
    unset -f sleep
}

test_play_video_disabled_ad_block() {
    # When AD_BLOCK=0, play_video must skip hls_fetch_clean and pass raw URL to mpv.
    local bin="$TEST_HOME/playbin-disabled"
    mkdir -p "$bin"
    local argsfile="$TEST_HOME/mpv-args-disabled"
    : > "$argsfile"
    cat > "$bin/mpv" <<EOF
#!/bin/bash
printf '%s\n' "\$@" > "$argsfile"
EOF
    chmod +x "$bin/mpv"

    local curlbin="$TEST_HOME/playbin-curl-disabled"
    mkdir -p "$curlbin"
    cat > "$curlbin/curl" <<EOF
#!/bin/bash
echo "curl should not be called when ad block is off" >&2
exit 1
EOF
    chmod +x "$curlbin/curl"

    AD_BLOCK=0
    PLAYER_DEFAULT=mpv
    QUALITY=
    PATH="$bin:$curlbin:$PATH" play_video "https://v7.kkphimplayer7.com/master.m3u8" "Test Title"
    local i=0
    while [[ ! -s "$argsfile" && $i -lt 50 ]]; do sleep 0.05; i=$((i + 1)); done
    local first
    first=$(head -1 "$argsfile")
    assert_eq "https://v7.kkphimplayer7.com/master.m3u8" "$first" "mpv receives raw url when ad block disabled" || return 1
}

test_history_select() {
    local recorded=""
    play_video() { recorded="$1|$2"; }
    echo "1700000000|Frieren - Tập 01|frieren-slug|https://example.com/stream.m3u8" > "$HIST"
    fzf() { head -1; }
    history
    assert_eq "https://example.com/stream.m3u8|Frieren - Tập 01" "$recorded" "history plays correct url and title" || return 1
}

test_favorites_select() {
    local recorded_slug="" recorded_title=""
    watch_episode() { recorded_slug="$1"; recorded_title="$2"; }
    echo "1700000000|Frieren|frieren-slug|2024|/poster.jpg" > "$FAV"
    fzf() {
        printf 'enter\n'
        head -1
    }
    favorites
    assert_eq "frieren-slug" "$recorded_slug" "favorites extracts clean slug" || return 1
    assert_eq "Frieren" "$recorded_title" "favorites extracts clean title" || return 1
}

# Fake curl for call_api tests: responds with fixture JSON and counts calls.
FAKE_CURL_BIN=""
make_fake_curl() {
    local counter="$1" mode="$2"
    FAKE_CURL_BIN="$TEST_HOME/curlbin-$mode"
    mkdir -p "$FAKE_CURL_BIN"
    cat > "$FAKE_CURL_BIN/curl" <<EOF
#!/bin/bash
printf 'x' >> "$counter"
if [[ "$mode" == "fail" ]]; then
    exit 1
fi
cat <<JSON
{"status":"success","data":{"items":[{"name":"Fake","year":2024,"quality":"HD","lang":"Vietsub","country":[{"name":"VN"}],"episode_current":"1/10","slug":"fake-film","poster_url":"/p/f.jpg"}]}}
JSON
EOF
    chmod +x "$FAKE_CURL_BIN/curl"
}

test_call_api_cache() {
    local counter="$TEST_HOME/curl-count"
    : > "$counter"
    make_fake_curl "$counter" ok
    local out1 out2
    out1=$(PATH="$FAKE_CURL_BIN:$PATH" call_api "/v1/api/x?page=1")
    out2=$(PATH="$FAKE_CURL_BIN:$PATH" call_api "/v1/api/x?page=1")
    assert_eq "$out1" "$out2" "cache returns same body" || return 1
    assert_contains "$out1" "fake-film" "fixture parsed" || return 1
    assert_eq "x" "$(cat "$counter")" "curl called exactly once (cache hit)" || return 1
    local cached
    cached=$(ls "$CACHE"/*.json 2>/dev/null | wc -l)
    assert_eq 1 "$cached" "cache file written" || return 1
}

test_call_api_retry_fails() {
    local counter="$TEST_HOME/curl-count-fail"
    : > "$counter"
    make_fake_curl "$counter" fail
    local rc
    PATH="$FAKE_CURL_BIN:$PATH" call_api "/phim/x"
    rc=$?
    assert_eq 1 "$rc" "call_api returns 1 after retries" || return 1
    assert_eq "xxx" "$(cat "$counter")" "curl attempted 3 times" || return 1
}

test_call_api_stale_cache_refetch() {
    # A stale cache file must be removed and refetched.
    local counter="$TEST_HOME/curl-count-stale"
    : > "$counter"
    make_fake_curl "$counter" ok
    local key
    key=$(hash_url "${API_PHIMAPI}/phim/stale")
    printf '{"stale":true}' > "$CACHE/$key.json"
    touch -d "2 hours ago" "$CACHE/$key.json"
    local out
    out=$(PATH="$FAKE_CURL_BIN:$PATH" call_api "/phim/stale")
    assert_contains "$out" "fake-film" "refetched" || return 1
    assert_eq "x" "$(cat "$counter")" "refetch called curl once" || return 1
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
    add_menu_numbers
    format_movie_items
    get_base_url
    parse_v1_items
    parse_phimapi_v3
    hash_url
    hls_absolutize_url
    hls_strip_ads
    hls_strip_preroll_postroll
    hls_strip_ads_structural
    hls_strip_ads_structural_control
    hls_pick_variant
    hls_strip_uri_attrs
    hls_fetch_clean_ok
    hls_fetch_clean_fallback
    hls_fetch_clean_cache_fallback
    hls_fetch_clean_quality
    hls_fetch_clean_canary
    hls_rebase_convertv_rewrites_playlist
    hls_rebase_convertv_multi_cluster
    hls_fetch_clean_without_ffmpeg_keeps_strip_output
    play_video_cleans_url
    play_video_disabled_ad_block
    play_video_fallback_url
    play_video_vlc_args
    toggle_ad_block
    clear_cache_removes_all
    download_episode_vietnamese_name
    handle_cli_args
    is_cache_fresh
    record_history
    history_select
    record_progress
    add_favorite
    favorites_select
    remove_favorite
    load_settings
    save_settings
    check_dependencies
    check_dependencies_missing
    check_player
    call_api_cache
    call_api_retry_fails
    call_api_stale_cache_refetch
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
