# tankobundler

Combines individual CBZ + CBR files (chapters, issues, etc.) into a single volume / tankōbon in CBZ format, with ComicInfo.xml metadata.

## Requirements

- `zip`
- `unzip`
- `unrar` (only if working with CBR files)

## Folder Setup

Each volume needs its own folder containing:

1. **Individual CBZ/CBR files** — chapters, issues, or whatever makes up the volume
2. **Cover image(s)** (optional) — any loose image file (jpg, png, webp) in the folder

```
Chainsaw Man v24/
├── cover.png                                      # cover image (placed first)
├── Chainsaw Man 223 (2025) (Digital) (1r0n).cbz   # chapter archives
├── Chainsaw Man 224 (2025) (Digital) (1r0n).cbz
└── Chainsaw Man 225 (2025) (Digital) (1r0n).cbz
```

```
Transmetropolitan v03/
├── cover.jpg                              # cover image (placed first)
├── Transmetropolitan 013.cbr              # issue archives
├── Transmetropolitan 014.cbr
├── Transmetropolitan 015.cbr
├── Transmetropolitan 016.cbr
├── Transmetropolitan 017.cbr
└── Transmetropolitan 018.cbr
```

Archives and images are processed in alphabetical order. Cover images always come before archive contents.

## Usage

```bash
# Single manga volume
./tankobundler.sh --manga "Chainsaw Man v24"

# Multiple volumes
./tankobundler.sh "Transmetropolitan v03" "Transmetropolitan v04"

# All subfolders
./tankobundler.sh --manga */

# Flat mode (sequential page numbering, no chapter subfolders)
./tankobundler.sh --flat --manga "Chainsaw Man v24"
```

The output CBZ is named after the folder, with tags (e.g. `(Digital)`, group name) automatically extracted from the source archive filenames and appended:

```
Chainsaw Man v24/                          # input folder
Chainsaw Man v24 (Digital) (1r0n).cbz      # output file (tags from source archives)
```

## Options

| Flag | Description |
|------|-------------|
| `--manga` | Marks output as manga in ComicInfo.xml (right-to-left reading, black & white) |
| `--flat` | Flattens all pages into sequential numbering (`p000`, `p001`, ...) instead of chapter subfolders |

## Output Format

By default, each source archive becomes a chapter subfolder inside the CBZ, preserving chapter boundaries:

```
Chainsaw Man v24 (Digital) (1r0n).cbz
├── ComicInfo.xml                    # metadata (series, volume, cover, etc.)
├── cover.png                               # cover image
├── Chainsaw Man 223/                # chapter subfolder
│   ├── 01.jpg
│   ├── 02.jpg
│   └── ...
├── Chainsaw Man 224/
│   ├── 01.jpg
│   └── ...
└── Chainsaw Man 225/
    ├── 01.jpg
    └── ...
```

Chapter subfolder names are derived from the source archive filename (minus tags and extension).

### Flat mode (`--flat`)

With `--flat`, all pages are extracted into a single flat sequence:

```
Chainsaw Man v24 - p000.png   # cover
Chainsaw Man v24 - p001.jpg   # first page of first chapter
Chainsaw Man v24 - p002.jpg
...
```

## ComicInfo.xml

Each output CBZ includes a [ComicInfo.xml](https://anansi-project.github.io/docs/comicinfo/intro) with metadata auto-populated from the folder and archive names:

| Field | Source |
|-------|--------|
| `Series` | Parsed from folder name (e.g. "Chainsaw Man" from "Chainsaw Man v24") |
| `Number` | Volume number from folder name |
| `Title` | "Vol. X" |
| `Year` | Year tag from source archive filename, e.g. `(2024)` |
| `PageCount` | Total images in the volume |
| `Manga` | Set when `--manga` flag is used |
| `BlackAndWhite` | Set when `--manga` flag is used |
| `LanguageISO` | `en` |
| `Pages` | Cover marked as `FrontCover` |

This metadata is recognized by readers like Komga, Kavita, Tachiyomi/Mihon, and others.

## Notes

Images are stored uncompressed (zip `-0`) since jpg/png are already compressed. This keeps the file fast to read without inflating its size.
