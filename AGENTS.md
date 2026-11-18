# Sudachi — AGENTS.md

## What this is

A single Bash script (`sudachi.sh`) — Vietnamese-subtitled movie/TV/anime player using `fzf` (UI) and `mpv`/`vlc` (playback). All content comes from the K20 Stremio addons.

## Running

```bash
bash sudachi.sh [options]
```

CLI options:
- `-s, --search [KEYWORD]` — search directly
- `-c, --continue` — replay the latest history entry
- `-l, --latest` — open new releases
- `-a, --anime` — open anime mode
- `-d, --downloads` — view downloads progress
- `-h, --help` — show CLI help

No build step. Validate: `bash -n sudachi.sh`, `shellcheck -S warning sudachi.sh tests/run_tests.sh`, `bash tests/run_tests.sh`.

## Dependencies

Linux only (GNU `stat -c`, `md5sum`, `sort -V`), bash >= 4.3, fzf >= 0.60 (`--with-nth='{1}'` templates; `check_dependencies` refuses older fzf and adds
`--wrap=word` on fzf >= 0.68, `--wrap` below, so long titles wrap instead of ending in "…";
the preview window uses `noinfo` so its scroll counter does not cover the title).

| Required | Purpose |
|----------|---------|
| `fzf` | TUI menus |
| `jq` | JSON parsing |
| `curl` | API calls |
| `mpv` or `vlc` | Video playback; on Arch/CachyOS VLC also needs `vlc-plugin-dvb` (TS demuxer) and `vlc-plugin-ffmpeg` (decoder): `vlc_plays_hls` checks `vlc --list`, `check_player` warns and falls back to mpv |

| Optional | Purpose |
|----------|---------|
| `chafa` (+ `magick`) | Terminal poster preview |
| `yt-dlp` | Downloads (`-N 8` concurrent HLS fragments) |
| `notify-send` | Desktop notifications |
| `python3` | Local proxy for NguonC only (stdlib; see below) |

## Source: K20 addons

Stremio addon protocol, called directly (no plugin system):

- `k20` → `https://sc.k-20.xyz`: KKPhim, VSMov, NguonC, STP, CLBPX catalogs. Search
  queries the KKPhim/VSMov/NguonC series+movie catalogs in parallel, keeps the first row per
  id (series catalogs come first; their meta always lists episodes), then `group_results`
  merges one title found on several providers into one row (same year + any `" / "` part of
  the name, lowercased, without `(Vietsub)`/`(Lồng Tiếng)`/`(Thuyết Minh)` and punctuation).
  `open_choice` asks for the provider when a row has several.
- `k20anime` → `https://anime.k-20.xyz`: AnimeVietsub. Its search ignores the query, it has
  no streams for `kitsu:` ids and its catalogs ignore `skip`. Search therefore reads a local
  index (`k20anime_index` → `$CACHE/anime-index.txt`, rebuilt hourly by `search()`): every
  catalog plain and per genre, fetched in parallel (~250 titles, ~1-2 s; it waits only on its
  own PIDs so a running download does not block it). Index rows whose name holds every query
  word are appended to the results with src `k20anime`; `group_results` never merges rows of
  different src. Its meta has no synopsis (only "Chất lượng • Trạng thái") and its poster CDN
  (`animevietsub.nl`) is DNS/SNI-blocked by some Vietnamese ISPs, so the preview takes cover,
  genres and synopsis (English) from Kitsu (`KITSU_SEARCH`, first hit for the first `" / "`
  part of the name, cached as `desc/<key>.kitsu.json`; a miss is cached as `{}`). Many older titles (e.g. "Anime Trọn
  Bộ") return an empty stream list from K20 itself.

Both answer 404 to curl's default User-Agent: every request sends `-A Sudachi` (`UA`).
K20 strips ads server-side but for KKPhim it also drops the `convertv*` clips (real scenes
under a sponsor text overlay, ~25s per episode). So `stream_url` rebuilds KKPhim playlists
itself (`kkphim_playlist`): it takes the CDN URL from K20's `proxy-playlist.m3u8?url=`,
keeps segments in the playlist's own directory plus `convertv*/`, drops everything else
(standalone ads such as `/v9/<hash>/segment_*.ts`) with their tags, absolutizes URIs and
writes `$CACHE/playlists/kkphim-<md5>.m3u8`. Any failure falls back to K20's playlist, and so
does a rebuild that drops more seconds than it keeps (the CDN moved the movie elsewhere).
convertv clips restart their timestamps, so in a plain playlist mpv's clock reads 0:0x
inside them and a relative seek there lands near the start of the episode. Hence
`kkphim_playlist` also writes `kkphim-<md5>.edl` (mpv's timeline file): one part playlist
per run between `#EXT-X-DISCONTINUITY` tags, each with its EXTINF length, relative ASCII
names (resolved next to the EDL, so the `%bytes%` prefix is exact). mpv plays the EDL
(continuous clock; seeks inside and across convertv verified; opening takes a few seconds
more because mpv opens every part), with `--demuxer-lavf-format=hls` and a widened
`protocol_whitelist` (ffmpeg's file default refuses https segments). Do NOT use
`--demuxer-lavf-linearize-timestamps` instead: it fixes seeks inside convertv but breaks
absolute seeks (3:20 lands at 6:42). VLC plays the `.m3u8` (no EDL support; seeking inside
convertv can misbehave there); yt-dlp gets `file://` + `--enable-file-urls`.
NguonC's CDN and K20's NguonC proxy answer 403 to HTTP/1.1 (all that ffmpeg/mpv and yt-dlp
speak) and its segments are TS named `.png`, which ffmpeg >= 7 refuses
(`allowed_segment_extensions`). `stream_url` therefore starts `nguonc_proxy_start` for
`*/nguonc:*`: an embedded stdlib Python server on 127.0.0.1 (random port) that fetches with
curl (HTTP/2) using the K20 headers, rewrites playlists to `/p.m3u8?u=` and `/s.ts?u=`, and
only serves URLs it wrote itself (no open proxy). play_video stops it after the player; a
download owns it (the parent clears `NGUONC_PROXY_PID`) and stops it after yt-dlp; it ignores
SIGHUP like downloads. Without python3 NguonC shows an error.
`resolve_k20_stream` retries (`--retry 2 --retry-all-errors`): K20 drops requests often.
All sources are third-party and can disappear.

Data flow:
- List rows: `name|year|N/A|provider|<type>/<id>|poster|src[|alternatives]` (`parse_k20_items`
  + `src` tag; search rows add `slug~name^slug~name`). The slug carries the type, so
  `/meta/<slug>.json` needs no extra field. `format_movie_items` prepends the display column
  (9 fields: field 8 = src, field 9 = alternatives); readers must not let field 9 spill into src.
- `k20_catalog <src> <type/id> <page> [genre]` pages with `skip=(page-1)*len(page 1)`; a
  page identical to page 1 means "no next page". Genre options (Danh mục / Thể loại /
  Quốc gia / Năm) come from the manifest and power the Lọc menu.
- `watch_episode` turns `.meta.videos[]` into `title|<base>/stream/<type>/<video-id>.json`;
  movies without videos use the meta id. Those stream URLs are what history stores.
- `resolve_k20_stream` fetches the stream list (fzf when several versions), sets `K20_URL`
  and `K20_HEADERS` from `behaviorHints.proxyHeaders.request`. mpv gets them via
  `--http-header-fields-append` (one header verbatim — UA values contain commas), VLC via
  `--http-referrer`/`--http-user-agent`, yt-dlp via `--add-header`. `stream_url` plays
  `.m3u8` links from older history rows as they are and refuses other old links (player pages).

## Key bindings (episode picker)

- `Enter` → play (blocks until the player exits; Ctrl+C quits the player, not Sudachi)
- `Tab` → download
- `Ctrl+F` → favorite
- `Esc` → back to the list it was opened from (search keeps its query via `--print-query`,
  paginated lists keep their page, Yêu thích / Xem tiếp reload); Esc there goes one level up,
  and Esc in the main menu quits
- The episode list opens with the cursor on the episode after the last one in
  `progress.log` (`--bind load:pos(N)`); the header says `▶ Tiếp` or `✓ Đã xem`

## Menu structure

Main menu (`main_menu()`, under `show_banner`, 50% height; small menus keep compact heights): Tìm phim, Xem tiếp, Khám phá, Yêu thích,
Tải về, Cài đặt. The main loop `case` matches labels by substring; an empty choice (Esc) exits.
- Khám phá (`kham_pha`): "Phim mới cập nhật" (`new_releases`, also `-l`), "Anime mới cập nhật"
  (`anime_mode`, also `-a`), then every catalog of both addons (`browse_catalog`). In a list,
  `show_paginated_list` takes an optional filters callback: Ctrl+G picks one of the catalog's
  genre options (Danh mục / Thể loại / Quốc gia / Năm), passed to the fetch callback as `$2`.
- Xem tiếp (`continue_watching`): history newest first with "N phút/giờ/ngày trước"; Enter opens
  the episode list (name = title without its last `" - <episode>"`, src from the URL host),
  Ctrl+D removes the row; rows from before K20 (slug without `/`) play their URL directly.
- Cài đặt: Trình phát, Mở thư mục tải về, Xóa cache.
- No list shows row numbers; hidden columns carry what a choice needs (e.g. the stream
  index after a tab in `resolve_k20_stream`).

## Runtime config

`~/.config/sudachi/`:
- `config` — `PLAYER_DEFAULT` (mpv/vlc). Keys from older versions are ignored.
- `history.log` (`timestamp|title|slug|url|ep`), `favorites.log` (`timestamp|title|slug|||src`),
  `progress.log` (`slug|ep`) — pipe-delimited; `sanitize_field` cleans display fields.

`${XDG_CACHE_HOME:-~/.cache}/sudachi/`: `call_api` JSON per URL md5 (3600s TTL; error bodies
and `{"meta":null}` are never cached), `desc/` preview meta + posters (deleted at startup after 30 days unused), `downloads/`
(`tasks.log` rows `title|file|log`, exit status in `<log>.rc`; yt-dlp ignores SIGHUP so
closing the terminal keeps it running), `debug.log` (never rotated). Xóa cache empties it,
drops finished/dead downloads (`download_running`) with their logs, and removes the old
`~/.config/sudachi/cache` of earlier versions.

## Architecture notes

- **No `set -euo pipefail`**; `trap cleanup EXIT` removes temp scripts, INT/TERM exit 130.
- **FZF_OPTS** global array — all fzf calls reuse it.
- **Temp scripts**: `create_preview_script` / `create_search_script` write standalone scripts
  under `$CACHE/` with values baked in at creation time; helpers are embedded with
  `declare -f` (`format_movie_items`, `parse_k20_items`) and must stay self-contained.
- **All UI text is Vietnamese**; English only in code comments.
- **Single branch (`main`)**, single contributor. Tests: `bash tests/run_tests.sh` (46 cases,
  stubs via `fake_bin`). CI runs `bash -n`, `shellcheck -S warning` (both files) and the suite.
