#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != --preview-only ) ]]; then
  echo 'Usage: bash export.sh [--preview-only]' >&2
  exit 2
fi

cd "$(dirname "$0")"
export_tmp=$(mktemp -d "$(cd .. && pwd)/.switchboard-brag.XXXXXX")
trap 'rm -rf "$export_tmp"' EXIT

source_video=../brag.mp4
if [[ "${1:-}" != --preview-only ]]; then
  npx --yes hyperframes@0.8.127 render \
    --quality delivery --resolution landscape-4k --fps 30 --workers 4 \
    --output "$export_tmp/render.mp4"

  ffmpeg -hide_banner -loglevel error -y -ss 1.5 -i "$export_tmp/render.mp4" \
    -frames:v 1 -q:v 2 "$export_tmp/brag.jpg"

  # A settled product frame serves as the thumbnail without shifting the soundtrack.
  ffmpeg -hide_banner -loglevel error -y \
    -i "$export_tmp/render.mp4" -i "$export_tmp/brag.jpg" \
    -filter_complex "[0:v][1:v]overlay=0:0:enable='eq(n,0)'[v]" \
    -map '[v]' -map '0:a?' -c:v libx264 -crf 16 -preset slow \
    -pix_fmt yuv420p -c:a copy -movflags +faststart "$export_tmp/brag.mp4"
  source_video="$export_tmp/brag.mp4"
fi

ffprobe -v error -show_streams -show_format -of json \
  "$source_video" > "$export_tmp/probe.json"
node --input-type=module - "$export_tmp/probe.json" <<'JS'
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const probe = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const video = probe.streams.find(stream => stream.codec_type === 'video');
const audio = probe.streams.find(stream => stream.codec_type === 'audio');
assert(video && audio, 'Expected both video and audio streams');
assert.equal(video.width, 3840);
assert.equal(video.height, 2160);
assert.equal(video.r_frame_rate, '30/1');
assert.equal(Number(video.nb_frames), 900);
assert(Math.abs(Number(probe.format.duration) - 30) < 0.05);
assert.equal(video.codec_name, 'h264');
assert.equal(audio.codec_name, 'aac');
JS
ffmpeg -hide_banner -loglevel error -i "$source_video" -f null -

# Round upward so frame zero keeps the poster when reducing 30 fps to 12 fps.
preview_filter='fps=12:round=up,scale=960:540:flags=lanczos'
ffmpeg -hide_banner -loglevel error -y -i "$source_video" \
  -vf "$preview_filter,palettegen=max_colors=64:stats_mode=diff" \
  -frames:v 1 -update 1 "$export_tmp/palette.png"
ffmpeg -hide_banner -loglevel error -y -i "$source_video" -i "$export_tmp/palette.png" \
  -filter_complex "[0:v]$preview_filter[preview];[preview][1:v]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
  -an -loop 0 "$export_tmp/brag-preview.gif"

ffprobe -v error -count_frames -show_streams -show_format -of json \
  "$export_tmp/brag-preview.gif" > "$export_tmp/preview-probe.json"
node --input-type=module - "$export_tmp/preview-probe.json" <<'JS'
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';

const probe = JSON.parse(readFileSync(process.argv[2], 'utf8'));
assert.equal(probe.streams.length, 1, 'Expected a silent GIF');
const video = probe.streams[0];
assert.equal(video.codec_name, 'gif');
assert.equal(video.width, 960);
assert.equal(video.height, 540);
assert.equal(Number(video.nb_read_frames), 360);
assert(Math.abs(Number(probe.format.duration) - 30) < 0.05);
assert(Number(probe.format.size) < 10_000_000, `GIF preview is ${probe.format.size} bytes; keep it below 10 MB`);
JS
ffmpeg -hide_banner -loglevel error -i "$export_tmp/brag-preview.gif" -f null -

# Keep the previous delivery intact if rendering, encoding, or validation fails.
if [[ "${1:-}" != --preview-only ]]; then
  mv "$export_tmp/brag.mp4" ../brag.mp4
  mv "$export_tmp/brag.jpg" ../brag.jpg
fi
mv "$export_tmp/brag-preview.gif" ../brag-preview.gif
echo 'Verified: 4K master (30 seconds, 30 fps) and silent GIF preview (960 x 540, 12 fps, below 10 MB).'
