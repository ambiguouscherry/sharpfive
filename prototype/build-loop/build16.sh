#!/bin/bash
# #16 rebuild + sign + validate + install (over the live component). Logs timings.
set -o pipefail
B=/Users/margot/Desktop/projects/sharpfive/.claude/worktrees/prototype+midi-write/prototype/build-au
T=/Users/margot/.claude/jobs/4c72d7fa/tmp
PV=/Applications/pluginval.app/Contents/MacOS/pluginval
ART=$B/build/plugins/TapeTilt/TapeTilt_artefacts/Release
cd $B
t0=$(date +%s)
cmake --build build --config Release --target TapeTilt_AU --target TapeTilt_VST3 --parallel > $T/build16.log 2>&1; rc=$?
t1=$(date +%s)
echo "build rc=$rc seconds=$((t1 - t0))"
grep -E 'error|warning: ' $T/build16.log | head -10
grep -cE '^\[' $T/build16.log | sed 's/^/ninja steps: /'
[ $rc -ne 0 ] && exit 1
xattr -cr $ART/VST3/TapeTilt.vst3 $ART/AU/TapeTilt.component
codesign --force --sign - $ART/VST3/TapeTilt.vst3 && codesign --force --sign - $ART/AU/TapeTilt.component
codesign --verify --deep --strict $ART/AU/TapeTilt.component && echo "au signature ok"
t2=$(date +%s)
$PV --strictness-level 5 --validate $ART/VST3/TapeTilt.vst3 > $T/pluginval16.log 2>&1; echo "pluginval rc=$? seconds=$(( $(date +%s) - t2 ))"
grep -E 'FAILED|ALL TESTS PASSED|Finished' $T/pluginval16.log | head -3
t3=$(date +%s)
rm -rf ~/Library/Audio/Plug-Ins/Components/TapeTilt.component
cp -R $ART/AU/TapeTilt.component ~/Library/Audio/Plug-Ins/Components/
echo "installed over the live component at $(date +%T)"
plutil -p ~/Library/Audio/Plug-Ins/Components/TapeTilt.component/Contents/Info.plist | grep -E 'CFBundleShortVersionString|"version"'
auval -v aufx Tptl Shfv > $T/auval16.log 2>&1; echo "auval rc=$? seconds=$(( $(date +%s) - t3 ))"
grep -E 'VALIDATION|version' $T/auval16.log | head -3
pgrep -x 'Logic Pro' > /dev/null && echo "Logic still running pid $(pgrep -x 'Logic Pro')" || echo "LOGIC GONE"
echo "total seconds=$(( $(date +%s) - t0 ))"
