# Sudachi — AGENTS.md

## What this is

A single Bash script (`sudachi.sh`) — Vietnamese-subtitled movie/TV/anime player using `fzf` (UI) and `mpv`/`vlc` (playback).

## Running

```bash
bash sudachi.sh [options]
```

CLI options:
- `-s, --search [KEYWORD]` — search directly
- `-c, --continue` — resume latest watched episode
- `-l, --latest` — open new releases
- `-a, --anime` — open anime mode
- `-d, --downloads` — view downloads progress
- `-h, --help` — show CLI help

No build step. Validate syntax only: `bash -n sudachi.sh`.

## Dependencies

| Required | Purpose |
|----------|---------|
| `fzf` | TUI menus |
| `jq` | JSON parsing |
| `curl` | API calls |
| `mpv` or `vlc` | Video playback |

| Optional | Purpose |
|----------|---------|
| `chafa` | Terminal poster preview |
| `yt-dlp` + `aria2` | Multi-thread downloads |
| `notify-send` | Desktop notifications (download complete) |
| `ffmpeg` + `ffprobe` | Rebase convertv sponsor clips onto the movie timeline (smooth seek); without them playback keeps the CDN's discontinuity marks |
| `python3` | Local PNG-header-stripping proxy for VSMov streams (stdlib only) |

## Runtime config

Auto-created at `~/.config/sudachi/`:
- `config` — `PLAYER_DEFAULT` (mpv/vlc) + `QUALITY` (1080/720/480/auto) + `AD_BLOCK` (1/0) + `SOURCE` (vsmov/phimapi)
- `history.log`, `favorites.log`, `progress.log` — pipe-delimited records
- `cache/` — JSON cache per URL hash (3600s TTL)
- `cache/debug.log` — debug output (appended, never rotated)

## API sources

Two sources, selected with `SOURCE` in `config` (or Cài Đặt → Nguồn phim). `set_api_base`
maps the source to `API_BASE` and every `call_api` endpoint is relative to it.

- **`vsmov`** (default): `https://vsmov.com/api`. Endpoints: `/danh-sach/*`, `/phim/{slug}`,
  `/tim-kiem`, `/the-loai/{slug}`, `/quoc-gia/{slug}`, `/nam/{year}`; list responses are
  root `.items[]` (`parse_vsmov_items`). Episodes carry `link_embed`; `resolve_stream_url`
  reads `baseUrl`/`videoHash` (or `signedMasterUrl`) from the player page. Segments are
  PNG header + TS, so `start_vsmov_proxy` runs an embedded stdlib-only Python proxy that
  strips the header and serves a local playlist (stable port for mpv resume).
- **`phimapi`**: `https://phimapi.com`. `/v1/api/...` returns `.data.items[]`,
  `/danh-sach/phim-moi-cap-nhat-v3` root `.items[]`, `/phim/{slug}`
  `.episodes[].server_data[]`. Parsers: `parse_phimapi_v3`, `parse_v1_items`.

`ophim1.com` is dead. NguonC is Turnstile-guarded at the player, so it is not integrated.
Both live sources are third-party and can disappear.

`create_search_script` and `create_preview_script` bake `API_BASE`/`SOURCE` at creation
time. Helpers are embedded with `declare -f`; keep `parse_v1_items` and
`parse_vsmov_items` self-contained (no globals other than `$1`, `$2`).

## Key bindings (episode picker)

- `Enter` → play
- `Tab` → download
- `Ctrl+F` → favorite
- `Esc` → back / exit

## Menu structure

Main menu (`main_menu()`) shows all items:
- Tìm Kiếm, Phim Mới, Duyệt Phim, Anime, Lọc Nâng Cao, Lịch Sử, Yêu Thích, Cài Đặt, Thoát
- All labels are Vietnamese — `case` in the main loop matches by full text

## Architecture notes

- **No `set -euo pipefail`** — the script runs without strict mode. Guards that check `command -v` or use `&&`/`||` are behavioral, not defensive.
- **FZF_OPTS** global array — all fzf calls reuse it.
- **Cache**: URL → MD5 hash → JSON file. Fresh for 3600s. Cleared manually (`Cài Đặt → Xóa Cache` — removes API JSON, cached posters/descriptions in `cache/desc/`, cleaned `*-clean.m3u8` / `*-dl.m3u8` playlists, `vsmov-proxy.py`/`.log`, and `cache/segments/`; `downloads/` and `debug.log` stay).
- **Temp scripts**: `create_preview_script` / `create_search_script` write standalone shell scripts under `$CACHE/`. Cleaned on exit via `trap cleanup EXIT SIGINT SIGTERM`. **Values must be baked at creation time** — subprocesses have no access to parent shell variables. Helpers are embedded with `declare -f` (`format_movie_items`, `parse_v1_items`, `parse_vsmov_items`, `hash_url`).
- **Preview script** uses `IFS='|' read -r` on the fzf-selected line (7-field pipe-delimited record).
- **Downloads**: `tasks.log` rows are `title|file|log`; the subshell writes the exit status to `<log>.rc` and `view_downloads` keys the status off that file (no more PID or "file exists" guessing). Legacy `pid|title|file|log` rows are still parsed.
- **History**: rows are `timestamp|title|slug|url|ep`; old 4-field rows still parse (ep empty). `history()` and `-c` call `resolve_saved_url` to refresh the stream link from the current source, falling back to the stored URL when the episode cannot be resolved.
- **`sanitize_field`** normalizes newlines, trims, replaces `|` — used for display fields in pipe-delimited records.
- **`log_debug`** appends to `$CACHE/debug.log` (never rotated).
- **`hash_url`** prefers `md5sum`, falls back to `md5`, `sha256sum`, `cksum`.
- **HLS ad-stripping** at `play_video()`: guarded by `AD_BLOCK` config (default 1/on, toggled via Cài Đặt → Chặn Quảng Cáo). Every PhimAPI `.m3u8` URL passes through `hls_fetch_clean` before playback; VSMov playlists are already clean and are served through the local proxy instead (skipping `hls_fetch_clean` avoids rewriting loopback URLs into the cache). A 200 response that is not a playlist (`#EXTM3U` missing, e.g. an HTML error page) is never cached: the cached clean playlist is reused when recent (6h TTL), otherwise the raw URL is played. Mid-roll and pre/post-roll standalone video ad commercial segments are completely dropped; each ad block is replaced by a single `#EXT-X-DISCONTINUITY` at the splice point so the player resets its PTS timeline correctly without PTS gap stalls (that marker is dropped again when `hls_rebase_convertv` rebuilds a continuous timeline). Movie segment metadata (`#EXTINF`) following ad blocks is preserved. Header normalization: `#EXT-X-PLAYLIST-TYPE:VOD` is injected (ffmpeg builds a fixed seek table for VOD, not live) and `#EXT-X-DISCONTINUITY-SEQUENCE` is stripped (its index shifts after ad removal and poisons ffmpeg seek tables). Segments resolving into the playlist's own directory are movie content and are NEVER treated as ads, even if they match `HLS_AD_PATTERNS`. Tier 2 structural detection covers renamed ad paths: a `#EXT-X-KEY:METHOD=NONE` tag (exactly one per real phimapi playlist, right after a `#EXT-X-DISCONTINUITY`) opens a candidate block whose following segments are treated as ads until one resolves into the playlist's own directory; own-directory segments are never dropped and close the block, and the KEY tag itself is dropped with the block or passed through with the movie segments (pattern matching is unchanged and additive). Segment URIs are absolutized directly in awk for high performance, and URI attributes of `#EXT-X-KEY` / `#EXT-X-MAP` / `#EXT-X-MEDIA` lines are rewritten the same way (the cached playlist is local, so relative keys/maps would 404). The cleaned playlist is cached as `<hash>-clean.m3u8` in `cache/`; a fetch/filter failure falls back to the cached cleaned playlist when one exists (a transient refetch error must not silently serve ads) and only then to the raw URL (playback never breaks). `HLS_AD_PATTERNS` (awk ERE, extendable) currently matches standalone video ads: `(^|/)ads?[0-9]*/|(^|/)promo[0-9]*/|(^|/)v[0-9]+/[0-9a-f]+/segment_`. Note: `convertv*` segments contain actual movie content with a 2-line sponsor text watermark overlay re-encoded at scene boundaries; these are preserved as movie content to avoid cutting out 20–30s of dialogue. Their PTS restarts at ~1.48s while the surrounding movie PTS is continuous, so `hls_fetch_clean` additionally passes the stripped playlist through `hls_rebase_convertv`: it groups consecutive convertv lines into clusters and downloads each cluster's clips plus its own anchor (the movie segment immediately before the first clip; cached under `cache/segments/`, missing ones fetched in parallel batches of 4 with a stderr progress line), stream-copies every clip with `ffmpeg -itsoffset <cursor-first_pts> -i <clip> -c copy -copyts -muxdelay 0 -muxpreload 0 -f mpegts <out>` so its first video PTS continues the movie timeline, then replaces the convertv URIs with the local rebased files (in playlist order) and drops all `#EXT-X-DISCONTINUITY` tags. Each cluster is anchored on the movie segment before it, so a playlist with several clusters separated by movie content rebases every cluster from its own anchor. If `ffmpeg`/`ffprobe` are missing or any download/probe/rebase step fails, the stripped playlist is kept unchanged (original URIs + discontinuity tags) so playback never breaks; `cache/segments/` is removed by `purge_api_cache` ("Xóa Cache"). Canary: if a playlist has >=2 DISCONTINUITY tags but zero ad-pattern matches, `hls_fetch_clean` writes a warning to `debug.log` ("HLS_AD_PATTERNS may need updating") so a CDN layout change is noticed instead of silently returning ads. For master playlists the variant matching `QUALITY` is fetched (highest resolution when QUALITY is auto/empty) via `hls_pick_variant`. mpv gets `--cache=yes` + `--demuxer-seekable-cache=yes` + `--demuxer-max-bytes=150M` + `--demuxer-max-back-bytes=100M` + `--hr-seek=default` + `--hr-seek-framedrop=no` + `--demuxer-readahead-secs=20` for HLS (seekable RAM cache serves backward seeks from memory so PTS gaps left by ad removal can never reset playback to the start; never `--force-seekable=yes` — breaks HLS, mpv#11990; default initial audio sync keeps A-V perfectly synchronized across discontinuities; do NOT use `--initial-audio-sync=no` as it causes audio desync); for the local cleaned playlist mpv additionally forces `--demuxer-lavf-format=hls` + a widened `protocol_whitelist` (ffmpeg refuses https segments with the default file,crypto,data list — stalls every few seconds). Do NOT add `--demuxer-lavf-linearize-timestamps=yes` — it rewrites the timeline one-way and breaks backward seek across the PTS jumps left by removed ad segments. VLC gets `--no-input-fast-seek` (seek lands on the requested time, not the previous keyframe) and `--network-caching=3000` (buffers remote segments); `--preferred-resolution` behavior is unchanged. PhimAPI downloads use the stripped `*-dl.m3u8` playlist (no convertv rebase; `yt-dlp --enable-file-urls -N 8`), so mid-roll ads are gone from downloaded files too. VSMov downloads run through the proxy (`yt-dlp -N 8`).
- **All UI text is Vietnamese** (labels, error messages, comments). English only in code comments.
- **Single branch (`main`)**, single contributor. Tests: `bash tests/run_tests.sh` (55 cases). CI runs `bash -n`, `shellcheck -S warning` (both files), and the test suite. No formatter yet.
