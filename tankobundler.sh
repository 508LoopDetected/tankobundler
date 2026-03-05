#!/bin/bash
# Combines individual CBZ/CBR files + an optional cover image into a single volume CBZ.
#
# Usage: ./tankobundler.sh <folder> [folder...]
#
# Each folder should contain:
#   - Individual CBZ and/or CBR files (chapters, issues, etc.)
#   - Optionally, a cover image (jpg/png/webp) — any lone image file in the folder
#     is treated as the cover and placed first (p000)
#
# The output CBZ is named after the folder and placed alongside it.
# Internal pages are named: {folder name} - p000.ext, p001.ext, ...
#
# Examples:
#   ./tankobundler.sh "Chainsaw Man - Volume 24"
#   ./tankobundler.sh "Transmetropolitan - Volume 03"
#   ./tankobundler.sh */   # all subfolders

set -e

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <folder> [folder...]"
    echo "Combines CBZ/CBR files in each folder into a single volume CBZ."
    exit 1
fi

ORIGDIR="$(pwd)"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

extract_archive() {
    local archive="$1"
    local dest="$2"
    local ext="${archive##*.}"
    case "${ext,,}" in
        cbz|zip) unzip -q -o "$archive" -d "$dest" ;;
        cbr|rar) unrar x -o+ -inul "$archive" "$dest/" ;;
        *) echo "WARNING: Unknown archive type: $archive"; return 1 ;;
    esac
}

for VOLDIR_ARG in "$@"; do
    # Strip trailing slash and resolve to absolute path
    VOLDIR="$(cd "$(dirname "${VOLDIR_ARG%/}")" && pwd)/$(basename "${VOLDIR_ARG%/}")"

    if [[ ! -d "$VOLDIR" ]]; then
        echo "ERROR: Not a directory: $VOLDIR"
        continue
    fi

    VOLNAME="$(basename "$VOLDIR")"
    OUTFILE="$(cd "$(dirname "$VOLDIR")" && pwd)/${VOLNAME}.cbz"
    WORKDIR="$TMPDIR/$VOLNAME"
    mkdir -p "$WORKDIR"

    PAGE=0

    # Find cover image (loose image files in folder, not inside archives)
    COVERS=()
    while IFS= read -r -d '' IMG; do
        COVERS+=("$IMG")
    done < <(find "$VOLDIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -print0 | sort -z)

    if [[ ${#COVERS[@]} -gt 0 ]]; then
        for COVER in "${COVERS[@]}"; do
            EXT="${COVER##*.}"
            PNUM=$(printf "%03d" $PAGE)
            cp "$COVER" "$WORKDIR/${VOLNAME} - p${PNUM}.${EXT}"
            PAGE=$((PAGE + 1))
        done
    fi

    # Find and process all CBZ/CBR files in sorted order
    ARCHIVE_COUNT=0
    while IFS= read -r -d '' ARCHIVE; do
        CHDIR="$TMPDIR/ch_extract"
        mkdir -p "$CHDIR"

        if ! extract_archive "$ARCHIVE" "$CHDIR"; then
            rm -rf "$CHDIR"
            continue
        fi

        while IFS= read -r IMG; do
            IMGEXT="${IMG##*.}"
            PNUM=$(printf "%03d" $PAGE)
            cp "$IMG" "$WORKDIR/${VOLNAME} - p${PNUM}.${IMGEXT}"
            PAGE=$((PAGE + 1))
        done < <(find "$CHDIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) | sort)

        rm -rf "$CHDIR"
        ARCHIVE_COUNT=$((ARCHIVE_COUNT + 1))
    done < <(find "$VOLDIR" -maxdepth 1 -type f \( -iname '*.cbz' -o -iname '*.cbr' \) -print0 | sort -z)

    if [[ $PAGE -eq 0 ]]; then
        echo "SKIP: No images or archives found in $VOLDIR"
        rm -rf "$WORKDIR"
        continue
    fi

    cd "$WORKDIR"
    find . -maxdepth 1 -type f -print0 | sort -z | xargs -0 zip -q -0 "$OUTFILE"
    cd "$ORIGDIR"

    echo "$VOLNAME: $PAGE pages from $ARCHIVE_COUNT archives -> $(basename "$OUTFILE")"
    rm -rf "$WORKDIR"
done

echo "Done!"
