# GeoJSON routes

Route geometry is stored here as static files loaded by the map. The manifest `routes.json` groups routes by layer id.

## Metro systems

| Layer id | Label | Routes |
| --- | --- | --- |
| `taipei_metro` | 台北捷運 | 8 lines in `taipei_metro/` (see `routes.json`) |
| `new_taipei_metro` | 新北捷運 | (coming soon) |
| `taoyuan_metro` | 桃園捷運 | (coming soon) |
| `taichung_metro` | 台中捷運 | (coming soon) |
| `kaohsiung_metro` | 高雄捷運 | (coming soon) |

Station coordinates are from [OpenStreetMap](https://www.openstreetmap.org/) (© contributors, ODbL).

**Track geometry** comes from OSM route relations (not straight lines between stations). Regenerate all Taipei Metro lines with:

```bash
bin/rails geojson:taipei_metro
```

This imports OSM route relations for 文湖、淡水信義、新北投支線、板南、松山新店、小碧潭支線、中和新蘆、環狀線 and updates `routes.json`.

## Adding a route

1. Add a GeoJSON file under the appropriate folder (e.g. `taipei_metro/my_line.geojson`).
2. Append an entry to the matching array in `routes.json`.
