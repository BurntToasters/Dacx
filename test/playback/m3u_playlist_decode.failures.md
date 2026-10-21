# Playlist Decode Failure Inventory

`M3uPlaylist.parseFile` must handle these encodings:

- A Latin-1 / Windows-1252 `.m3u` with accented names throws and the whole import fails.
- A UTF-8 playlist with a byte-order mark keeps the BOM in the first entry.
- A UTF-8 `.pls` playlist with a BOM is not detected as PLS.
- A UTF-8 playlist is decoded as Latin-1, garbling non-ASCII names.
- A file larger than `maxBytes` is read fully before the size check.
- A UTF-16 playlist is silently treated as one garbage entry.
