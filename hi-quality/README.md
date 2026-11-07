# hi-quality

Writes a copy of an Ableton Live Set (`.als`) with high-quality mode turned on for
every **Glue Compressor**, **EQ Eight** and **Saturator**, including devices inside racks.
The original file is never modified.

Ruby 3.1+, standard library only.

## Usage

```sh
bin/hi-quality "path/to/Song Project/Song.als"      # writes Song-hq.als alongside it
bin/hi-quality --dry-run ~/Music/Projects           # report only, recursive
bin/hi-quality --devices eq8,sat Song.als           # only some devices
```

| Option | |
|---|---|
| `-n`, `--dry-run` | Report what would change, write nothing |
| `-d`, `--devices LIST` | Any of `glue,eq8,sat` (default: all) |
| `-s`, `--suffix SUFFIX` | Output name suffix (default `-hq`) |
| `-f`, `--force` | Overwrite an existing output file |

Directories are searched recursively. `Backup/` folders and files that already end
in the suffix are skipped. If nothing needs changing, no file is written.

## What it changes

| Device | XML element | Field | Off → On |
|---|---|---|---|
| Glue Compressor | `GlueCompressor` | `Oversample` | `false` → `true` |
| EQ Eight | `Eq8` | `Precision` | `0` → `1` |
| Saturator | `Saturator` | `Oversampling` | `0` → `1` (Live 8–11), `false` → `true` (Live 12) |

Edits are minimal text substitutions. Before writing, the tool checks that the only
lines that differ are the flag lines it meant to change, and it refuses to write otherwise.

## Tests

```sh
rake
```

Tests use made-up XML only and never touch real Live Sets.

## License

Copyright (C) 2026 Ari Russo. Part of `ableton-scripts`.

Free software under the [GNU GPL v3 or later](../LICENSE), with an attribution term
under section 7(b); see [NOTICE](../NOTICE). You can use it for anything. If you
distribute a modified version, you must release its source under the same license
and keep the credit to Ari Russo.
