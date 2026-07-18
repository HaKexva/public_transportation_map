# GeoJSON routes

Static route geometry served to the map. The manifest [`routes.json`](routes.json) groups routes by `system_id` (layer id). Path convention:

```text
/geojson/{system_id}/{slug}.geojson
```

Do **not** hand-edit `routes.json` for new lines. Rebuild it with catalogs + rake (see below).

## Systems

| Layer id (`system_id`) | Folder | Notes |
| --- | --- | --- |
| `taipei_metro` | `taipei_metro/` | Taipei Metro lines |
| `new_taipei_metro` | `new_taipei_metro/` | New Taipei LRT / lines; see Circular exception below |
| `taoyuan_metro` | `taoyuan_metro/` | Airport MRT (+ express) |
| `taichung_metro` | `taichung_metro/` | Taichung Metro |
| `kaohsiung_metro` | `kaohsiung_metro/` | Kaohsiung Metro / LRT |
| `hsr` | `hsr/` | Taiwan High Speed Rail |
| `tra` | `tra/` | Taiwan Railway |
| `other` | `other/` | Sugar railways, ropeways, forest railways, etc. |

Station and track geometry primarily come from [OpenStreetMap](https://www.openstreetmap.org/) (© contributors, ODbL), with NLSC / fallback caches under `lib/geojson/fallback_tracks/` when needed.

## Root helper files

| File | Role |
| --- | --- |
| `routes.json` | Runtime route index (id, color, labels, `file` path) |
| `metro_depots.json` | Depot markers + spur track links |
| `out_of_station_transfers.json` | Out-of-station transfer markers |

## Exception: Circular Line (環狀線)

File lives at `taipei_metro/circular.geojson`, but the manifest lists it under `new_taipei_metro`. That split is intentional; do not move the file to “fix” the folder name.

## Rebuild commands

Defined in [`lib/tasks/geojson.rake`](../../lib/tasks/geojson.rake):

```bash
bin/rails geojson:taipei_metro
bin/rails geojson:new_taipei_metro
bin/rails geojson:taoyuan_metro
bin/rails geojson:airport_mrt_express
bin/rails geojson:taichung_metro
bin/rails geojson:kaohsiung_metro
bin/rails geojson:hsr
bin/rails geojson:tra
bin/rails geojson:other
bin/rails geojson:routes_manifest   # rewrite routes.json from on-disk GeoJSON + catalogs
bin/rails geojson:depots            # rewrite metro_depots.json
bin/rails geojson:depot_spurs
bin/rails geojson:refresh_transfer_refs
```

After geometry changes that affect the DB catalog:

```bash
bin/rails transit:sync_catalog
```

## Adding a route

1. Add or update the line definition in the matching catalog under `lib/geojson/` (e.g. `tra_catalog.rb`, `other_transit_catalog.rb`).
2. Run the system’s `geojson:*` rake task (or write the `.geojson` via the importer/builder).
3. Run `bin/rails geojson:routes_manifest` if the importer did not already rewrite `routes.json`.
4. Optionally `bin/rails transit:sync_catalog` so DB routes/stations match the manifest.

Geometry catalogs live in `lib/geojson/`. Timetables for `other` routes use `lib/transit/other_transit_schedule_catalog.rb` (same slugs, different data — do not merge the two).
