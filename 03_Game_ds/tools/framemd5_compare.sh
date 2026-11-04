#!/usr/bin/env bash
# Compare two videos frame by frame with framemd5.
#
#   bash tools/framemd5_compare.sh output/tmp/a.avi output/tmp/b.avi
#
# Prints one ASCII line with both digests, the frame count and a YES/NO verdict,
# and exits non-zero when the two takes differ (so `render.sh` can gate on it).
#
# The digest is sha256 over the per-frame md5 sequence: comparing 1800 hashes by
# eye is not a deterministic check, comparing one 64-char string is.

set -u -o pipefail

A="${1:-}"
B="${2:-}"

if [ -z "$A" ] || [ -z "$B" ]; then
	echo "[md5] usage: bash tools/framemd5_compare.sh <a.avi> <b.avi>" >&2
	exit 2
fi
for f in "$A" "$B"; do
	if [ ! -s "$f" ]; then
		echo "[md5] FAIL missing or empty file: $f" >&2
		exit 2
	fi
done

TMP_A="$(mktemp)"
TMP_B="$(mktemp)"
cleanup() { rm -f "$TMP_A" "$TMP_B"; }
trap cleanup EXIT

dump() {
	# -map 0:v:0 keeps it to the video stream; '#' lines are container metadata.
	ffmpeg -v error -i "$1" -map 0:v:0 -f framemd5 - 2>/dev/null \
		| grep -v '^#' \
		| sed 's/.*, *//' \
		| tr -d '\r'
}

dump "$A" > "$TMP_A" || { echo "[md5] FAIL framemd5 failed for $A" >&2; exit 2; }
dump "$B" > "$TMP_B" || { echo "[md5] FAIL framemd5 failed for $B" >&2; exit 2; }

COUNT_A="$(wc -l < "$TMP_A" | tr -d ' ')"
COUNT_B="$(wc -l < "$TMP_B" | tr -d ' ')"
DIGEST_A="$(sha256sum < "$TMP_A" | cut -d' ' -f1)"
DIGEST_B="$(sha256sum < "$TMP_B" | cut -d' ' -f1)"

if [ -z "$COUNT_A" ] || [ "$COUNT_A" = "0" ]; then
	echo "[md5] FAIL no frames decoded from $A" >&2
	exit 2
fi

if [ "$DIGEST_A" = "$DIGEST_B" ] && [ "$COUNT_A" = "$COUNT_B" ]; then
	echo "[md5] same=YES frames=$COUNT_A digest=$DIGEST_A"
	echo "[md5] a=$DIGEST_A"
	echo "[md5] b=$DIGEST_B"
	exit 0
fi

FIRST_DIFF="$(diff --old-line-format='%dn' --new-line-format='' --unchanged-line-format='' "$TMP_A" "$TMP_B" | head -1)"
echo "[md5] same=NO frames_a=$COUNT_A frames_b=$COUNT_B first_diff_frame=${FIRST_DIFF:-n/a}"
echo "[md5] a=$DIGEST_A"
echo "[md5] b=$DIGEST_B"
if [ -n "${FIRST_DIFF:-}" ]; then
	echo "[md5] frame_a=$(sed -n "${FIRST_DIFF}p" "$TMP_A")"
	echo "[md5] frame_b=$(sed -n "${FIRST_DIFF}p" "$TMP_B")"
fi
exit 1
