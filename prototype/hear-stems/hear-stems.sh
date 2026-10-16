#!/bin/sh
# sf hear stems <audio> [--model htdemucs|htdemucs_ft] [--shifts N] [--out DIR] [--transfer scp|tar]
# Laptop driver: ship the reference track to mama, run Demucs there, bring four stem motifs back.
# Prints one JSON object in the spec reply shape (`motifs`, a list) with local paths and a timing breakdown.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
AUDIO=$1; shift
MODEL=htdemucs; SHIFTS=0; OUT="$HERE/out"; TRANSFER=scp; TRUTH=""; WIRE=flac
while [ $# -gt 0 ]; do
  case "$1" in
    --model) MODEL=$2; shift 2;;
    --wire) WIRE=$2; shift 2;;       # flac (default) | wav: what crosses the link; the motif is always WAV
    --shifts) SHIFTS=$2; shift 2;;
    --out) OUT=$2; shift 2;;
    --transfer) TRANSFER=$2; shift 2;;
    --truth) TRUTH=$2; shift 2;;     # a dir on mama with ground-truth stems (measurement only)
    *) echo "{\"status\":\"failed\",\"reason\":\"bad-arg\",\"hint\":\"unknown option $1\"}"; exit 2;;
  esac
done
[ -f "$AUDIO" ] || { echo "{\"status\":\"failed\",\"reason\":\"no-such-file\",\"hint\":\"$AUDIO\"}"; exit 1; }
mkdir -p "$OUT"
BASE=$(basename "${AUDIO%.*}")
NAME=$(printf '%s' "$BASE" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9\n' '-' | sed 's/--*/-/g; s/^-//; s/-$//')
# the reference track is a root motif; make its sidecar if nothing did (source: file — it was already on disk)
PARENT=$(python3 - "$AUDIO" "$NAME" <<'EOP'
import json, os, sys, time, secrets, datetime
f, name = sys.argv[1], sys.argv[2]
sc = f + ".motif.json"
if not os.path.exists(sc):
    alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"; v = (int(time.time()*1000) << 80) | secrets.randbits(80)
    d = {"id": "".join(alphabet[(v >> (5*i)) & 31] for i in range(25, -1, -1)),
         "name": name, "kind": "audio",
         "source": {"by": "file", "path": os.path.abspath(f)}, "parents": [],
         "at": datetime.datetime.fromtimestamp(os.path.getmtime(f)).astimezone().isoformat(timespec="seconds"),
         "tempo": None, "key": None, "bars": None, "text": "", "placed": []}
    json.dump(d, open(sc, "w"), indent=1)
print(json.load(open(sc))["id"])
EOP
)
REMOTE=sharpfive-hear
EXT=${AUDIO##*.}
RIN="in/$NAME.$EXT"
now() { python3 -c 'import time;print(time.time())'; }
T0=$(now)
ssh -o BatchMode=yes -o ConnectTimeout=8 mama "mkdir -p ~/$REMOTE/in ~/$REMOTE/out" \
  || { echo "{\"status\":\"failed\",\"reason\":\"mama-unreachable\",\"hint\":\"ssh mama failed; is the Mac mini awake?\"}"; exit 1; }
scp -q "$AUDIO" "mama:~/$REMOTE/$RIN"
scp -q "$HERE/stems_mama.py" "mama:~/$REMOTE/in/"
T1=$(now)
TRUTHARG=""; [ -n "$TRUTH" ] && TRUTHARG="--truth $TRUTH"
REPLY=$(ssh -o BatchMode=yes mama "cd ~/$REMOTE && rm -rf out/${NAME:?} && ~/sharpfive-ml-research/.venv-demucs/bin/python in/stems_mama.py $RIN --out out/$NAME --model $MODEL --shifts $SHIFTS --parent $PARENT --name $NAME --wire $WIRE $TRUTHARG" 2>"$OUT/$NAME.stderr")
T2=$(now)
case "$TRANSFER" in
  scp) scp -q -r "mama:~/$REMOTE/out/$NAME/" "$OUT/";;
  tar) ssh -o BatchMode=yes mama "tar cf - -C ~/$REMOTE/out $NAME" | tar xf - -C "$OUT";;
esac
T3=$(now)
if [ "$WIRE" = flac ]; then       # decode on the laptop: afconvert ships with macOS, no ffmpeg
  for f in "$OUT/$NAME"/*.flac; do
    afconvert -f WAVE -d LEI16 "$f" "${f%.flac}.wav" && rm -f "$f"
  done
fi
T4=$(now)
printf '%s' "$REPLY" | python3 -c "
import json,sys,os
r=json.load(sys.stdin); out=os.path.join(sys.argv[1], sys.argv[2])
def loc(p): return os.path.join(out, os.path.basename(p)) if p else None
for m in r.get('motifs',[]):
    m['path']=loc(m['path']); m['provenance']['source']=os.path.abspath(sys.argv[3])
for k,v in list(r.get('sidecars',{}).items()): r['sidecars'][k]=loc(v)
t=[float(x) for x in sys.argv[4:9]]
r['round_trip_s']={'upload':round(t[1]-t[0],2),'mama':round(t[2]-t[1],2),'download':round(t[3]-t[2],2),'decode':round(t[4]-t[3],2),'total':round(t[4]-t[0],2),'transfer':sys.argv[9],'wire':sys.argv[10]}
print(json.dumps(r))
" "$OUT" "$NAME" "$AUDIO" "$T0" "$T1" "$T2" "$T3" "$T4" "$TRANSFER" "$WIRE"
