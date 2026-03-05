# tankobundler

Combines individual CBZ + CBR files (chapters, issues, etc.) into a single volume / tankōbon in CBZ format.

## Requirements

- `zip`
- `unzip`
- `unrar` (only if working with CBR files)

## Folder Setup

Each volume needs its own folder containing:

1. **Individual CBZ/CBR files** — chapters, issues, or whatever makes up the volume
2. **Cover image(s)** (optional) — any loose image file (jpg, png, webp) in the folder

```
Chainsaw Man - Volume 24/
├── Volume_24.png                          # cover image (placed first)
├── Chainsaw Man 223 (2025) (Digital).cbz  # chapter archives
├── Chainsaw Man 224 (2025) (Digital).cbz
└── Chainsaw Man 225 (2025) (Digital).cbz
```

```
Transmetropolitan - Volume 03/
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
# Single volume
./tankobundler.sh "Chainsaw Man - Volume 24"

# Multiple volumes
./tankobundler.sh "Transmetropolitan - Volume 03" "Transmetropolitan - Volume 04"

# All subfolders
./tankobundler.sh */
```

The output CBZ is named after the folder and placed alongside it:

```
Transmetropolitan - Volume 03/    # input folder
Transmetropolitan - Volume 03.cbz # output file
```

## Output Format

Pages inside the CBZ are named sequentially:

```
Chainsaw Man - Volume 24 - p000.png   # cover
Chainsaw Man - Volume 24 - p001.jpg   # first page of first chapter/issue
Chainsaw Man - Volume 24 - p002.jpg
...
```

Images are stored uncompressed (zip `-0`) since jpg/png are already compressed. This keeps the file fast to read without inflating its size.
