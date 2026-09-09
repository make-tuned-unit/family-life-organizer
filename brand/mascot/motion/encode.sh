#!/bin/bash
# encode.sh <nobg.mp4> <outname> <trim-frames>
# Recovers alpha from the black-matted Higgsfield output (soft luma key + unpremultiply),
# trims the head transition, and writes: HEVC-alpha .mov (iOS + Safari) and VP9-alpha .webm (web).
set -e
IN="$1"; NAME="$2"; TRIM="${3:-10}"
V="${V:-$(cd "$(dirname "$0")" && pwd)}"
KEY="format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='clip((max(max(r(X,Y),g(X,Y)),b(X,Y))-4)*255/22,0,255)',unpremultiply=inplace=1"
ffmpeg -v error -y -i "$IN" -vf "select='gte(n\,$TRIM)',setpts=PTS-STARTPTS,$KEY,scale=720:720:flags=lanczos,format=bgra" \
  -c:v hevc_videotoolbox -alpha_quality 0.9 -q:v 70 -tag:v hvc1 -movflags +faststart -an "$V/$NAME.mov"
ffmpeg -v error -y -i "$IN" -vf "select='gte(n\,$TRIM)',setpts=PTS-STARTPTS,$KEY,scale=480:480:flags=lanczos,format=yuva420p" \
  -c:v libvpx-vp9 -pix_fmt yuva420p -b:v 0 -crf 30 -auto-alt-ref 0 -an "$V/$NAME.webm"
# web poster: first kept frame composited transparent (png)
ffmpeg -v error -y -i "$V/$NAME.webm" -c:v libvpx-vp9 -frames:v 1 -vf "select=eq(n\,0)" "$V/$NAME-poster.png" 2>/dev/null || true
echo "$NAME: $(ffprobe -v error -show_entries stream=nb_frames -of csv=p=0 $V/out/$NAME.mov) frames mov=$(du -k $V/out/$NAME.mov | cut -f1)K webm=$(du -k $V/out/$NAME.webm | cut -f1)K"
