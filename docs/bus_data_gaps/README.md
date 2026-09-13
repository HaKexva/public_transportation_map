# Bus data gaps

Generated reports from `bin/rails geojson:bus_gaps_export` and `bin/rails geojson:bus_coverage`.

| File | Contents |
| --- | --- |
| [`WORKFLOW.md`](WORKFLOW.md) | **一次補齊：步驟 + 流程圖（先看這個）** |
| [`HOW_TO_SUPPLY.md`](HOW_TO_SUPPLY.md) | 如何把 TDX 沒有的路線檔／路線圖交給專案 |
| [`CHECKLIST.md`](CHECKLIST.md) | 待處理總表（含 Wikipedia 對照） |
| [`summary.md`](summary.md) | Counts for local gaps + optional TDX vs local table |
| [`missing_official_maps.md`](missing_official_maps.md) | Full list of routes with geometry but no official schematic URL |
| [`intercity_not_imported_refs.txt`](intercity_not_imported_refs.txt) | InterCity TDX refs not on disk (currently empty) |
| [`tdx_vs_local.md`](tdx_vs_local.md) | TDX Route/Shape vs on-disk GeoJSON |
| [`tdx_vs_local.json`](tdx_vs_local.json) | Machine-readable TDX diff |

Manual drops go in [`inbox/bus_manual/`](../../inbox/bus_manual/).

## Commands

```bash
bin/rails geojson:bus_gaps_export
bin/rails geojson:bus_coverage CITY=MiaoliCounty,InterCity OUT=docs/bus_data_gaps
bin/rails geojson:bus CITY=InterCity
```
