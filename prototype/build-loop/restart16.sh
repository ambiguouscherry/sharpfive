#!/bin/bash
# #16 / #36: save, quit, relaunch Logic from code; dismiss startup alerts; stop at the project chooser.
T=/Users/margot/.claude/jobs/4c72d7fa/tmp
OLD=$(pgrep -x 'Logic Pro')
echo "$(date +%T) old Logic pid $OLD"
date +%s > $T/t16_restart_start
echo "$(date +%T) File > Save"; $T/ui menu "File" "Save"; sleep 3
$T/axdump windows | tr '\n' ' '; echo
echo "$(date +%T) Logic Pro > Quit Logic Pro"; $T/ui menu "Logic Pro" "Quit Logic Pro"
for i in $(seq 1 45); do
  sleep 2
  if ! pgrep -x 'Logic Pro' | grep -q "$OLD"; then echo "$(date +%T) old Logic gone"; break; fi
  w=$($T/axdump windows 2>/dev/null | tr '\n' ' ')
  echo "$(date +%T) still alive: $w"
  if [ $i -ge 3 ]; then
    $T/axdump focused 2>/dev/null | grep -E "AXButton|AXStaticText" | head -8
    $T/axdump press "Save" 2>/dev/null
  fi
done
date +%s > $T/t16_quit
echo "$(date +%T) open -a Logic Pro"; open -a "Logic Pro"
until pgrep -x 'Logic Pro' > /dev/null; do sleep 1; done
NEW=$(pgrep -x 'Logic Pro'); echo "$(date +%T) new Logic pid $NEW"; date +%s > $T/t16_launch
# startup alerts: poll the focused window, press known buttons
for i in $(seq 1 90); do
  sleep 2
  w=$($T/axdump windows 2>/dev/null | tr '\n' ' ')
  f=$($T/axdump focused 2>/dev/null | head -40)
  title=$(echo "$f" | head -1)
  btns=$(echo "$f" | grep -o "AXButton t='[^']*'" | sed "s/AXButton t=//" | tr '\n' ' ')
  texts=$(echo "$f" | grep -o "AXStaticText t='' d='' v='[^']*'" | sed "s/.*v=//" | head -3 | tr '\n' ' ')
  echo "$(date +%T) [$i] $w | $title | buttons: $btns | $texts"
  if echo "$btns" | grep -q "'OK'"; then $T/axdump press "OK"; continue; fi
  if echo "$btns" | grep -q "'Ignore'"; then $T/axdump press "Ignore"; continue; fi
  if echo "$btns" | grep -q "'Start Plug-In Manager'"; then $T/axdump press "Start Plug-In Manager"; sleep 4; $T/axdump press "Done"; continue; fi
  if echo "$w" | grep -q "Tracks"; then echo "$(date +%T) project window up"; break; fi
  if echo "$w$title" | grep -qiE "Choose|Project|New|Open|Templates|Untitled"; then echo "$(date +%T) at the project chooser"; break; fi
done
date +%s > $T/t16_alerts_done
echo "$(date +%T) quit took $(( $(cat $T/t16_quit) - $(cat $T/t16_restart_start) )) s; launch+alerts took $(( $(cat $T/t16_alerts_done) - $(cat $T/t16_quit) )) s"
