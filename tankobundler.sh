#!/bin/bash
# Combines individual CBZ/CBR files + an optional cover image into a single volume CBZ.
#
# Usage: ./tankobundler.sh [--flat] [--manga] <folder> [folder...]
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
# A ComicInfo.xml is generated with series metadata, page count, and cover marking.
#
# Examples:
#   ./tankobundler.sh --manga "Chainsaw Man v24"
#   ./tankobundler.sh --flat "Transmetropolitan v03"
#   ./tankobundler.sh --manga */   # all subfolders

set -e

FLAT=0
MANGA=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --flat) FLAT=1; shift ;;
        --manga) MANGA=1; shift ;;
        *) break ;;
    esac
done

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 [--flat] [--manga] <folder> [folder...]"
    echo "Combines CBZ/CBR files in each folder into a single volume CBZ."
    echo ""
    echo "Options:"
    echo "  --flat    Flatten all pages into sequential numbering (p000, p001, ...)"
    echo "           Default: preserve chapter subfolders"
    echo "  --manga  Mark as manga in ComicInfo.xml (right-to-left reading order)"
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

# Extract year tag from a filename
extract_year() {
    local filename="$1"
    basename "$filename" | grep -oP '\(\K[0-9]{4}(?=\))' | head -1
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

# Parse series name and volume number from folder name
# e.g. "Chainsaw Man v24" -> SERIES="Chainsaw Man" VOLNUM="24"
parse_volume_info() {
    local volname="$1"
    # Try to match "Series vXX" pattern
    if [[ "$volname" =~ ^(.+)[[:space:]]v([0-9]+) ]]; then
        SERIES="${BASH_REMATCH[1]}"
        VOLNUM="${BASH_REMATCH[2]}"
    else
        SERIES="$volname"
        VOLNUM=""
    fi
}

# Escape special XML characters
xml_escape() {
    local s="$1"
    s="${s//&/&amp;}"
    s="${s//</&lt;}"
    s="${s//>/&gt;}"
    s="${s//\"/&quot;}"
    echo "$s"
}

# Generate ComicInfo.xml
generate_comicinfo() {
    local workdir="$1"
    local series="$2"
    local volnum="$3"
    local year="$4"
    local pagecount="$5"
    local covercount="$6"

    local xml="$workdir/ComicInfo.xml"

    cat > "$xml" <<XMLEOF
<?xml version="1.0" encoding="utf-8"?>
<ComicInfo xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <Series>$(xml_escape "$series")</Series>
XMLEOF

    if [[ -n "$volnum" ]]; then
        # Strip leading zeros for the Number field
        local num=$((10#$volnum))
        echo "  <Title>Vol. $num</Title>" >> "$xml"
        echo "  <Number>$num</Number>" >> "$xml"
    fi

    if [[ -n "$year" ]]; then
        echo "  <Year>$year</Year>" >> "$xml"
    fi

    echo "  <PageCount>$pagecount</PageCount>" >> "$xml"
    echo "  <LanguageISO>en</LanguageISO>" >> "$xml"

    if [[ $MANGA -eq 1 ]]; then
        echo "  <Manga>Yes</Manga>" >> "$xml"
        echo "  <BlackAndWhite>Yes</BlackAndWhite>" >> "$xml"
    fi

    # Page entries
    echo "  <Pages>" >> "$xml"

    local idx=0
    while IFS= read -r -d '' PAGE_FILE; do
        local rel="${PAGE_FILE#$workdir/}"
        # Skip ComicInfo.xml itself
        [[ "$rel" == "ComicInfo.xml" ]] && continue

        if [[ $idx -lt $covercount ]]; then
            echo "    <Page Image=\"$idx\" Type=\"FrontCover\" />" >> "$xml"
        else
            echo "    <Page Image=\"$idx\" />" >> "$xml"
        fi
        idx=$((idx + 1))
    done < <(find "$workdir" -type f -not -name "ComicInfo.xml" -print0 | sort -z)

    echo "  </Pages>" >> "$xml"
    echo "</ComicInfo>" >> "$xml"
}

for VOLDIR_ARG in "$@"; do
    # Strip trailing slash and resolve to absolute path
    VOLDIR="$(cd "$(dirname "${VOLDIR_ARG%/}")" && pwd)/$(basename "${VOLDIR_ARG%/}")"

    if [[ ! -d "$VOLDIR" ]]; then
        echo "ERROR: Not a directory: $VOLDIR"
        continue
    fi

    VOLNAME="$(basename "$VOLDIR")"
    parse_volume_info "$VOLNAME"

    # Extract tags from first source archive
    FIRST_ARCHIVE=$(find "$VOLDIR" -maxdepth 1 -type f \( -iname '*.cbz' -o -iname '*.cbr' \) | sort | head -1)
    TAGS=""
    YEAR=""
    if [[ -n "$FIRST_ARCHIVE" ]]; then
        TAGS=$(extract_tags "$FIRST_ARCHIVE")
        YEAR=$(extract_year "$FIRST_ARCHIVE")
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
    COVER_COUNT=0

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
                # Named to sort before chapter folders
                cp "$COVER" "$WORKDIR/000_cover.${EXT}"
            fi
            PAGE=$((PAGE + 1))
            TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
            COVER_COUNT=$((COVER_COUNT + 1))
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

    # Generate ComicInfo.xml
    generate_comicinfo "$WORKDIR" "$SERIES" "$VOLNUM" "$YEAR" "$TOTAL_IMAGES" "$COVER_COUNT"

    cd "$WORKDIR"
    find . -type f -print0 | sort -z | xargs -0 zip -q -0 "$OUTFILE"
    cd "$ORIGDIR"

    echo "$VOLNAME: $TOTAL_IMAGES pages from $ARCHIVE_COUNT archives -> $(basename "$OUTFILE")"
    rm -rf "$WORKDIR"
done

echo "Done!"
