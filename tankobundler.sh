#!/bin/bash
# Combines individual CBZ/CBR files + an optional cover image into a single volume CBZ.
#
# Usage: ./tankobundler.sh [--flat] <folder> [folder...]
#
# Each folder should contain:
#   - Individual CBZ and/or CBR files (chapters, issues, etc.)
#   - Optionally, a cover image (jpg/png/webp) — any loose image file in the folder
#     is treated as the cover and placed first
#
# By default, each source archive becomes a subfolder inside the output CBZ,
# preserving chapter boundaries. Use --flat for sequential page numbering instead.
#
# The output CBZ is named after the folder, with tags extracted from the source
# archive filenames (e.g. Digital, group name) appended automatically.
#
# Examples:
#   ./tankobundler.sh "Chainsaw Man v24"
#   ./tankobundler.sh --flat "Transmetropolitan v03"
#   ./tankobundler.sh */   # all subfolders

set -e

FLAT=0
if [[ "$1" == "--flat" ]]; then
    FLAT=1
    shift
fi

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 [--flat] <folder> [folder...]"
    echo "Combines CBZ/CBR files in each folder into a single volume CBZ."
    echo ""
    echo "Options:"
    echo "  --flat    Flatten all pages into sequential numbering (p000, p001, ...)"
    echo "           Default: preserve chapter subfolders"
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

# Extract parenthesized tags from a filename, skipping year-only tags
extract_tags() {
    local filename="$1"
    basename "$filename" | grep -oP '\([^)]+\)' | while read -r tag; do
        # Skip pure year tags like (2024)
        if [[ ! "$tag" =~ ^\([0-9]{4}\)$ ]]; then
            printf "%s " "$tag"
        fi
    done | sed 's/ $//'
}

# Derive a chapter folder name from an archive filename
# e.g. "Chainsaw Man 223 (2025) (Digital) (1r0n).cbz" -> "Chainsaw Man 223"
chapter_name() {
    local filename
    filename="$(basename "$1")"
    # Strip extension
    filename="${filename%.*}"
    # Strip parenthesized tags
    filename="$(echo "$filename" | sed 's/ *([^)]*)//g')"
    # Trim trailing whitespace
    echo "$filename" | sed 's/ *$//'
}

for VOLDIR_ARG in "$@"; do
    # Strip trailing slash and resolve to absolute path
    VOLDIR="$(cd "$(dirname "${VOLDIR_ARG%/}")" && pwd)/$(basename "${VOLDIR_ARG%/}")"

    if [[ ! -d "$VOLDIR" ]]; then
        echo "ERROR: Not a directory: $VOLDIR"
        continue
    fi

    VOLNAME="$(basename "$VOLDIR")"

    # Extract tags from first source archive
    FIRST_ARCHIVE=$(find "$VOLDIR" -maxdepth 1 -type f \( -iname '*.cbz' -o -iname '*.cbr' \) | sort | head -1)
    TAGS=""
    if [[ -n "$FIRST_ARCHIVE" ]]; then
        TAGS=$(extract_tags "$FIRST_ARCHIVE")
    fi

    # Build output filename with tags
    if [[ -n "$TAGS" ]]; then
        OUTNAME="${VOLNAME} ${TAGS}"
    else
        OUTNAME="${VOLNAME}"
    fi

    OUTFILE="$(cd "$(dirname "$VOLDIR")" && pwd)/${OUTNAME}.cbz"
    WORKDIR="$TMPDIR/$VOLNAME"
    mkdir -p "$WORKDIR"

    PAGE=0
    TOTAL_IMAGES=0

    # Find cover image (loose image files in folder, not inside archives)
    COVERS=()
    while IFS= read -r -d '' IMG; do
        COVERS+=("$IMG")
    done < <(find "$VOLDIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.avif' -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.tiff' \) -print0 | sort -z)

    if [[ ${#COVERS[@]} -gt 0 ]]; then
        for COVER in "${COVERS[@]}"; do
            EXT="${COVER##*.}"
            if [[ $FLAT -eq 1 ]]; then
                PNUM=$(printf "%03d" $PAGE)
                cp "$COVER" "$WORKDIR/${VOLNAME} - p${PNUM}.${EXT}"
            else
                # Cover goes at root level of archive
                COVERNAME="$(basename "$COVER")"
                cp "$COVER" "$WORKDIR/${COVERNAME}"
            fi
            PAGE=$((PAGE + 1))
            TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
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

        if [[ $FLAT -eq 1 ]]; then
            # Flat mode: sequential page numbering
            while IFS= read -r IMG; do
                IMGEXT="${IMG##*.}"
                PNUM=$(printf "%03d" $PAGE)
                cp "$IMG" "$WORKDIR/${VOLNAME} - p${PNUM}.${IMGEXT}"
                PAGE=$((PAGE + 1))
                TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
            done < <(find "$CHDIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.avif' -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.tiff' \) | sort)
        else
            # Chapter mode: each archive becomes a subfolder
            CHNAME="$(chapter_name "$ARCHIVE")"
            CHWORKDIR="$WORKDIR/$CHNAME"
            mkdir -p "$CHWORKDIR"

            while IFS= read -r IMG; do
                IMGNAME="$(basename "$IMG")"
                cp "$IMG" "$CHWORKDIR/${IMGNAME}"
                TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
            done < <(find "$CHDIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.avif' -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.tiff' \) | sort)
        fi

        rm -rf "$CHDIR"
        ARCHIVE_COUNT=$((ARCHIVE_COUNT + 1))
    done < <(find "$VOLDIR" -maxdepth 1 -type f \( -iname '*.cbz' -o -iname '*.cbr' \) -print0 | sort -z)

    if [[ $TOTAL_IMAGES -eq 0 ]]; then
        echo "SKIP: No images or archives found in $VOLDIR"
        rm -rf "$WORKDIR"
        continue
    fi

    cd "$WORKDIR"
    find . -type f -print0 | sort -z | xargs -0 zip -q -0 "$OUTFILE"
    cd "$ORIGDIR"

    echo "$VOLNAME: $TOTAL_IMAGES pages from $ARCHIVE_COUNT archives -> $(basename "$OUTFILE")"
    rm -rf "$WORKDIR"
done

echo "Done!"
