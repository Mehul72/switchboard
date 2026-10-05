#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
export_tmp=$(mktemp -d "$(cd .. && pwd)/.switchboard-brag.XXXXXX")
trap 'rm -rf "$export_tmp"' EXIT

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

ffprobe -v error -show_streams -show_format -of json \
  "$export_tmp/brag.mp4" > "$export_tmp/probe.json"
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
ffmpeg -hide_banner -loglevel error -i "$export_tmp/brag.mp4" -f null -

# Keep the previous delivery intact if rendering, encoding, or validation fails.
mv "$export_tmp/brag.mp4" ../brag.mp4
mv "$export_tmp/brag.jpg" ../brag.jpg
echo 'Verified: ../brag.mp4 and ../brag.jpg (30 seconds, 3840 x 2160, 30 fps).'
