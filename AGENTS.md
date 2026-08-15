# Sudachi — AGENTS.md

## What this is

A single Bash script (`sudachi.sh`, ~1096 lines) — Vietnamese-subtitled movie/TV/anime player using `fzf` (UI) and `mpv`/`vlc` (playback).

## Running

```bash
bash sudachi.sh
```

No arguments, no env vars, no build step. Validate syntax only: `bash -n sudachi.sh`.

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
- `config` — `PLAYER_DEFAULT` (mpv/vlc) + `QUALITY` (1080/720/480/auto) + `AD_BLOCK` (1/0)
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
- **HLS ad-stripping** at `play_video()`: guarded by `AD_BLOCK` config (default 1/on, toggled via Cài Đặt → Chặn Quảng Cáo). `.m3u8` URLs pass through `hls_fetch_clean` before playback. **Safe-filter**: the first ad segment at each ad-block boundary is KEPT (it may share frames with movie content), only consecutive interior ad segments are dropped; a `#EXT-X-DISCONTINUITY` tag is emitted at each splice point so the player resets its PTS timeline correctly. The cleaned playlist is cached as `<hash>-clean.m3u8` in `cache/`; any fetch/filter failure falls back to the raw URL (playback never breaks). `HLS_AD_PATTERNS` (awk ERE, extendable) uses `(^|/)` anchoring on each pattern to match only full path components (preventing false positives on movie URLs containing substrings like 'ad'); currently matches both phimapi CDNs observed: kkphimplayer7 (`convertv8/`, `/v8/<hex>/segment_`) and kkphimplayer6 (`convertv7/`, `/v7/<hex>/segment_`), plus semantic `ads?[0-9]*/` / `promo[0-9]*/`. Canary: if a playlist has >=2 DISCONTINUITY tags but zero ad-pattern matches, `hls_fetch_clean` writes a warning to `debug.log` ("HLS_AD_PATTERNS may need updating") so a CDN layout change is noticed instead of silently returning ads. mpv gets `--cache=yes` + `--hr-seek-framedrop=no` + `--demuxer-readahead-secs=20` + `--initial-audio-sync=no` for HLS (prevents dropping 0.5-1s of movie frames/audio at DISCONTINUITY splice points; never `--force-seekable=yes` — breaks HLS, mpv#11990); for the local cleaned playlist mpv additionally forces `--demuxer-lavf-format=hls` + a widened `protocol_whitelist` (ffmpeg refuses https segments with the default file,crypto,data list — stalls every few seconds). Do NOT add `--demuxer-lavf-linearize-timestamps=yes` — it rewrites the timeline one-way and breaks backward seek across the PTS jumps left by removed ad segments. Downloads keep the raw stream.
- **All UI text is Vietnamese** (labels, error messages, comments). English only in code comments.
- **Single branch (`main`)**, single contributor. No tests, no CI, no formatter.
