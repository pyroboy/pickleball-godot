#!/bin/sh
# Rebuilds docs/PICKLEBALL_2.5D_PROPOSAL.pdf: the original 31 pages (kept on branch
# archive/main-wip-2026-11) followed by Part 2 (part2.py).
# Needs Python with reportlab and pypdf:  PY=/path/to/python docs/proposal_pdf/build.sh
set -e
cd "$(dirname "$0")"
PY="${PY:-python3}"
TMP="$(mktemp -d)"
git show archive/main-wip-2026-11:docs/PICKLEBALL_2.5D_PROPOSAL.pdf > "$TMP/part1.pdf"
"$PY" part2.py "$TMP/part2.pdf"
"$PY" - "$TMP/part1.pdf" "$TMP/part2.pdf" ../PICKLEBALL_2.5D_PROPOSAL.pdf <<'EOF'
import sys
from pypdf import PdfReader, PdfWriter
w = PdfWriter()
for path in sys.argv[1:3]:
    for p in PdfReader(path).pages:
        w.add_page(p)
w.add_metadata({"/Title": "Pickleball 2.5D - Graphics, Performance, Physics & Mechanics Proposal"})
w.write(sys.argv[3])
print("wrote", sys.argv[3], len(w.pages), "pages")
EOF
rm -r "$TMP"
