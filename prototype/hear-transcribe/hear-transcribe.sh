#!/bin/sh
# sf hear transcribe <wav> [--bpm B] [--grid-start S] [--out DIR]
# Laptop driver: ship the take to mama, run torchcrepe there, bring the motif back (MIDI + sidecar).
# Prints one JSON object in the spec reply shape with local paths and a timing breakdown.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
WAV=$1; shift
BPM=""; GRID=0; OUT="$HERE/out"
while [ $# -gt 0 ]; do
  case "$1" in
    --bpm) BPM=$2; shift 2;;
    --grid-start) GRID=$2; shift 2;;
    --out) OUT=$2; shift 2;;
    *) echo "{\"status\":\"failed\",\"reason\":\"bad-arg\",\"hint\":\"unknown option $1\"}"; exit 2;;
  esac
done
[ -f "$WAV" ] || { echo "{\"status\":\"failed\",\"reason\":\"no-such-file\",\"hint\":\"$WAV\"}"; exit 1; }
mkdir -p "$OUT"
STEM=$(basename "${WAV%.*}")
# the take is a root motif; make its sidecar if the recorder did not
PARENT=$(python3 - "$WAV" "$BPM" <<'EOP'
import json, os, sys, time, secrets, datetime
wav, bpm = sys.argv[1], sys.argv[2]
sc = wav + ".motif.json"
if not os.path.exists(sc):
    alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"; v = (int(time.time()*1000) << 80) | secrets.randbits(80)
    d = {"id": "".join(alphabet[(v >> (5*i)) & 31] for i in range(25, -1, -1)),
         "name": os.path.splitext(os.path.basename(wav))[0], "kind": "audio",
         "source": {"by": "mic", "device": "default input"}, "parents": [],
         "at": datetime.datetime.fromtimestamp(os.path.getmtime(wav)).astimezone().isoformat(timespec="seconds"),
         "tempo": float(bpm) if bpm else None, "key": None, "bars": None, "text": "", "placed": []}
    json.dump(d, open(sc, "w"), indent=1)
print(json.load(open(sc))["id"])
EOP
)
REMOTE=sharpfive-hear
T0=$(python3 -c 'import time;print(time.time())')

ssh -o BatchMode=yes -o ConnectTimeout=8 mama "mkdir -p ~/$REMOTE/in ~/$REMOTE/out" \
  || { echo "{\"status\":\"failed\",\"reason\":\"mama-unreachable\",\"hint\":\"ssh mama failed; is the Mac mini awake?\"}"; exit 1; }
scp -q "$WAV" "$HERE/transcribe_mama.py" "mama:~/$REMOTE/in/"
T1=$(python3 -c 'import time;print(time.time())')

BPMARG=""; [ -n "$BPM" ] && BPMARG="--bpm $BPM"
REPLY=$(ssh -o BatchMode=yes mama "cd ~/$REMOTE && ~/sharpfive-ml-research/.venv-mir/bin/python in/transcribe_mama.py in/$(basename "$WAV") --out out/$STEM $BPMARG --grid-start $GRID --parent $PARENT --name $STEM --render" 2>"$OUT/$STEM.stderr")
T2=$(python3 -c 'import time;print(time.time())')

scp -q -r "mama:~/$REMOTE/out/$STEM/" "$OUT/" 2>/dev/null || true
T3=$(python3 -c 'import time;print(time.time())')

printf '%s' "$REPLY" | python3 -c "
import json,sys,os
r=json.load(sys.stdin); out=os.path.join(sys.argv[1], sys.argv[2])
def loc(p): return os.path.join(out, os.path.basename(p)) if p else None
if 'motif' in r:
    r['motif']['path']=loc(r['motif']['path'])
    r['motif']['provenance']['source']=os.path.abspath(sys.argv[3])
for k,v in list(r.get('sidecars',{}).items()): r['sidecars'][k]=loc(v)
t=[float(x) for x in sys.argv[4:8]]
r['round_trip_s']={'upload':round(t[1]-t[0],2),'mama':round(t[2]-t[1],2),'download':round(t[3]-t[2],2),'total':round(t[3]-t[0],2)}
print(json.dumps(r))
" "$OUT" "$STEM" "$WAV" "$T0" "$T1" "$T2" "$T3"
