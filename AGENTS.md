# Sudachi — AGENTS.md

## What this is

A single Bash script (`sudachi.sh`, ~1096 lines) — Vietnamese-subtitled movie/TV/anime player using `fzf` (UI) and `mpv`/`vlc` (playback).

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

## Runtime config

Auto-created at `~/.config/sudachi/`:
- `config` — `PLAYER_DEFAULT` (mpv/vlc) + `QUALITY` (1080/720/480/auto) + `AD_BLOCK` (1/0) + `AUTO_NEXT` (1/0)
- `source.conf` — single line: the API source name (validated against ophim1/phimapi)
- `history.log`, `favorites.log`, `progress.log` — pipe-delimited records
- `cache/` — JSON cache per URL hash (3600s TTL)
- `cache/debug.log` — debug output (appended, never rotated)

## API sources

Source selected at `~/.config/sudachi/source.conf`. **Default: `phimapi`** (hardcoded at line 22, overridden by `source.conf` on startup).

| Name | Base URL | Response shape | Endpoint path pattern |
|------|----------|----------------|----------------------|
| `ophim1` | `https://ophim1.com` | `.data.items[]` | `/v1/api/...` |
| `phimapi` | `https://phimapi.com` | `.data.items[]` | `/v1/api/...` |

### Critical: phimAPI/ophim1 merge

Both share `/v1/api/...` paths and `.data.items[]` in most endpoints. **However**:
- `*)` fallback in `get_base_url()` — any unrecognized source name silently falls to ophim1.
- Response parsers must match: `parse_phimapi_v3` (items[]), `parse_v1_items` (data.items[]).

**Rule**: verify JSON path for every source. Do not assume matching response structures even when `call_api` is shared.

## Key bindings (episode picker)

- `Enter` → play
- `Tab` → download
- `Ctrl+F` → favorite
- `Esc` → back / exit

## Menu structure

Main menu (`main_menu()`) always shows all items regardless of `API_SOURCE`:
- Tìm Kiếm, Phim Mới, Duyệt Phim, Anime, Lọc Nâng Cao, Lịch Sử, Yêu Thích, Cài Đặt, Thoát
- All labels are Vietnamese — `case` in the main loop matches by full text

## Architecture notes

- **No `set -euo pipefail`** — the script runs without strict mode. Guards that check `command -v` or use `&&`/`||` are behavioral, not defensive.
- **FZF_OPTS** global array at line 117 — all fzf calls reuse it.
- **Cache**: URL → MD5 hash → JSON file. Fresh for 3600s. Cleared on source switch or manually (`Cài Đặt → Xóa Cache` — only removes `*.json`).
- **Temp scripts**: `create_preview_script` / `create_search_script` write standalone shell scripts under `$CACHE/`. Cleaned on exit via `trap cleanup EXIT SIGINT SIGTERM`. **URLs must be baked at creation time** — subprocesses have no access to parent shell variables.
- **Preview script** uses `IFS='|' read -r` on the fzf-selected line (6-field pipe-delimited record). Ophim1 images fall back to TMDB API (`/v1/api/phim/{slug}/images`).
- **`sanitize_field`** (line 209) normalizes newlines, trims, replaces `|` — used for display fields in pipe-delimited records.
- **`log_debug`** appends to `$CACHE/debug.log` (never rotated).
- **`hash_url`** prefers `md5sum`, falls back to `md5`, `sha256sum`, `cksum`.
- **HLS ad-stripping** at `play_video()`: guarded by `AD_BLOCK` config (default 1/on, toggled via Cài Đặt → Chặn Quảng Cáo). `.m3u8` URLs pass through `hls_fetch_clean` before playback. Mid-roll and pre/post-roll standalone video ad commercial segments are completely dropped; each ad block is replaced by a single `#EXT-X-DISCONTINUITY` at the splice point so the player resets its PTS timeline correctly without PTS gap stalls. Movie segment metadata (`#EXTINF`) following ad blocks is preserved. Header normalization: `#EXT-X-PLAYLIST-TYPE:VOD` is injected (ffmpeg builds a fixed seek table for VOD, not live) and `#EXT-X-DISCONTINUITY-SEQUENCE` is stripped (its index shifts after ad removal and poisons ffmpeg seek tables). Segments resolving into the playlist's own directory are movie content and are NEVER treated as ads, even if they match `HLS_AD_PATTERNS`. Segment URIs are absolutized directly in awk for high performance. The cleaned playlist is cached as `<hash>-clean.m3u8` in `cache/`; any fetch/filter failure falls back to the raw URL (playback never breaks). `HLS_AD_PATTERNS` (awk ERE, extendable) currently matches standalone video ads: `(^|/)ads?[0-9]*/|(^|/)promo[0-9]*/|(^|/)v[0-9]+/[0-9a-f]+/segment_`. Note: `convertv*` segments contain actual movie content with a 2-line sponsor text watermark overlay re-encoded at scene boundaries; these are preserved as movie content to avoid cutting out 20–30s of dialogue. Canary: if a playlist has >=2 DISCONTINUITY tags but zero ad-pattern matches, `hls_fetch_clean` writes a warning to `debug.log` ("HLS_AD_PATTERNS may need updating") so a CDN layout change is noticed instead of silently returning ads. mpv gets `--cache=yes` + `--demuxer-seekable-cache=yes` + `--demuxer-max-bytes=150M` + `--demuxer-max-back-bytes=100M` + `--hr-seek=default` + `--hr-seek-framedrop=no` + `--demuxer-readahead-secs=20` for HLS (seekable RAM cache serves backward seeks from memory so PTS gaps left by ad removal can never reset playback to the start; never `--force-seekable=yes` — breaks HLS, mpv#11990; default initial audio sync keeps A-V perfectly synchronized across discontinuities; do NOT use `--initial-audio-sync=no` as it causes audio desync); for the local cleaned playlist mpv additionally forces `--demuxer-lavf-format=hls` + a widened `protocol_whitelist` (ffmpeg refuses https segments with the default file,crypto,data list — stalls every few seconds). Do NOT add `--demuxer-lavf-linearize-timestamps=yes` — it rewrites the timeline one-way and breaks backward seek across the PTS jumps left by removed ad segments. Downloads keep the raw stream.
- **All UI text is Vietnamese** (labels, error messages, comments). English only in code comments.
- **Single branch (`main`)**, single contributor. No tests, no CI, no formatter.
