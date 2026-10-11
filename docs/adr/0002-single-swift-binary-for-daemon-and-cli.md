---
status: accepted
date: 2026-10-11
---

# One Swift binary ships the daemon and its CLI

CoreMIDI forces the daemon into Swift. The CLI could be any language, and Margot reads Python best, but a Python CLI would make every future user install a second runtime beside pi's Node, and the CLI is thin (one JSON line out, one in) so the readability gain is small. We ship one Swift binary: `sf daemon` plus verb subcommands, no runtime to install. The socket protocol is language-neutral and documented, so Python scripts against the daemon remain a side door for experiments without being product. This settles the map's "Language per tool" question for the EDIT and WRITE limbs; ML limbs on mama stay Python.
