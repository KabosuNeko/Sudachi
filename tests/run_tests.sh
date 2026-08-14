#!/usr/bin/env bash
# Regression tests for sudachi.sh — locks observable behavior before slop removal.
# Usage: bash tests/run_tests.sh
# Each test runs in an isolated subshell with a fresh HOME and re-sources the
# (truncated) library, so no test can leak state into another.

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

test_add_list_numbers() {
    assert_eq $'1. |a\n2. |b' "$(printf 'a\nb' | add_list_numbers)" "numbering with pipe" || return 1
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
    assert_eq 0 "$(printf '%s\n' "$out" | grep -c 'convertv8')" "no convertv8 ad lines" || return 1
    assert_eq 0 "$(printf '%s\n' "$out" | grep -c '/v8/')" "no /v8/ ad lines" || return 1
    assert_contains "$out" "#EXT-X-ENDLIST" "endlist kept" || return 1
    assert_contains "$out" "#EXTM3U" "header kept" || return 1
    assert_contains "$out" "https://v7.kkphimplayer7.com/20260807/Dcq1MBiO/3500kb/hls/segment_001.ts" "movie segment kept + absolutized" || return 1
    assert_eq 0 "$(printf '%s\n' "$out" | grep -c '3500kb/hls/3500kb')" "no doubled path" || return 1

    # Clean fixture: no ad patterns -> output must be byte-identical to input.
    out=$(hls_strip_ads "$base" < "$clean_fix")
    printf '%s\n' "$out" | diff -q "$clean_fix" - >/dev/null || {
        echo "clean fixture not byte-identical" >&2
        return 1
    }
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
    save_settings
    assert_eq "PLAYER_DEFAULT=vlc" "$(head -1 "$CONFIG_FILE")" "config player" || return 1
    assert_eq "QUALITY=480" "$(sed -n 2p "$CONFIG_FILE")" "config quality" || return 1
    assert_eq "ophim1" "$(cat "$SOURCE_FILE")" "source file" || return 1
    # Round-trip through load_settings.
    API_SOURCE=phimapi PLAYER_DEFAULT=mpv QUALITY=
    load_settings
    assert_eq "ophim1" "$API_SOURCE" "roundtrip source" || return 1
    assert_eq "vlc" "$PLAYER_DEFAULT" "roundtrip player" || return 1
    assert_eq "480" "$QUALITY" "roundtrip quality" || return 1
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
    assert_eq 0 "$(grep -c 'convertv8' "$clean")" "no convertv8 ad lines" || return 1
    assert_eq 0 "$(grep -c '/v8/' "$clean")" "no /v8/ ad lines" || return 1
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
    PATH="$bin:$curlbin:$PATH" play_video "https://cdn.example/master.m3u8" "Test Title"
    local i=0
    while [[ ! -s "$argsfile" && $i -lt 50 ]]; do sleep 0.05; i=$((i + 1)); done
    local first
    first=$(head -1 "$argsfile")
    assert_contains "$first" "-clean.m3u8" "mpv receives clean playlist" || return 1
    assert_contains "$(cat "$argsfile")" "--cache=yes" "mpv gets --cache=yes" || return 1
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
    PATH="$bin:$curlbin:$PATH" play_video "https://cdn.example/master.m3u8" "Test Title"
    local i=0
    while [[ ! -s "$argsfile" && $i -lt 50 ]]; do sleep 0.05; i=$((i + 1)); done
    local first
    first=$(head -1 "$argsfile")
    assert_eq "https://cdn.example/master.m3u8" "$first" "mpv receives original url" || return 1
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
    add_list_numbers
    get_base_url
    parse_v1_items
    parse_phimapi_v3
    hash_url
    hls_absolutize_url
    hls_strip_ads
    hls_fetch_clean_ok
    hls_fetch_clean_fallback
    play_video_cleans_url
    play_video_fallback_url
    is_cache_fresh
    record_history
    record_progress
    add_favorite
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
