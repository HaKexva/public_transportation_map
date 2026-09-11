# 如何補「TDX 沒有／不足」的公車資料

你可以用下列任一方式交給我（或直接放進 repo），我會依規格匯入。

## 交付方式（任選）

1. **放進這個 repo**（最省事）  
   - 路線幾何：`inbox/bus_manual/{city_id}/{slug}.geojson`  
   - 官方路線圖：`inbox/bus_manual/{city_id}/maps/{slug}.{jpg|png|pdf|webp}`  
   - 對照表：`inbox/bus_manual/manifest.csv`（見下方欄位）
2. **對話上傳** GeoJSON／圖片／PDF，並註明縣市與路線編號。
3. **外部連結**（Drive／Dropbox／GitHub raw／官網圖資 URL），同樣附上對照表。

## 兩種資料各自是什麼

| 類型 | 用途 | 建議格式 |
| --- | --- | --- |
| **路線檔**（幾何） | 地圖上畫線＋站點 | GeoJSON `FeatureCollection`（見範本） |
| **路線圖檔**（示意圖） | 側欄「官方路線圖」 | 圖檔／PDF，或可公開存取的 URL |

有幾何、沒示意圖 → 地圖仍可顯示，只是官方圖會是缺圖狀態。  
只有示意圖、沒幾何 → 無法上地圖，需另外補線段／站點。

## GeoJSON 最低欄位（路線檔）

對齊現有檔（例如 `public/geojson/bus/miaoli_county_101.geojson`）：

```json
{
  "type": "FeatureCollection",
  "name": "101",
  "properties": {
    "id": "miaoli_county_101",
    "name": "101",
    "name_en": "101",
    "ref": "101",
    "color": "#2563eb",
    "city_id": "MiaoliCounty",
    "source": "manual",
    "official_map_url": "https://… 或先留空，圖檔另交",
    "operator_id": "67",
    "operator": "金牌客運",
    "operator_en": "Champion Bus"
  },
  "features": [
    {
      "type": "Feature",
      "properties": {
        "feature_type": "route",
        "ref": "101",
        "name": "101",
        "color": "#2563eb",
        "direction": 0
      },
      "geometry": {
        "type": "LineString",
        "coordinates": [[120.92, 24.70], [120.93, 24.71]]
      }
    },
    {
      "type": "Feature",
      "properties": {
        "feature_type": "station",
        "ref": "STOP001",
        "name": "示例站",
        "line": "101",
        "color": "#2563eb",
        "direction": 0
      },
      "geometry": {
        "type": "Point",
        "coordinates": [120.92, 24.70]
      }
    }
  ]
}
```

注意：

- 座標為 `[經度, 緯度]`（WGS84）。
- `city_id` 必須是 catalog 內代碼（如 `MiaoliCounty`、`InterCity`、`Kaohsiung`）。
- 若只有 GPX／KML／Shapefile，也可以交，我會轉成上述格式。
- 若只有站序表＋大致走法文字，請標註「需描線」，我無法從純文字自動產精確幾何。

## 對照表 `manifest.csv`

```csv
city_id,ref,name,slug,geometry_file,map_file_or_url,operator,source_note,wikipedia_ref
MiaoliCounty,101A,101A 竹南科－高鐵站,miaoli_county_101a,miaoli_county_101a.geojson,maps/miaoli_county_101a.jpg,金牌客運,官網班表,https://zh.wikipedia.org/wiki/苗栗縣公車
```

`map_file_or_url`：相對路徑或 `https://…` 皆可。

## 請你先對照的「待處理總表」

見同目錄：

| 檔案 | 你要做的事 |
| --- | --- |
| [`CHECKLIST.md`](CHECKLIST.md) | 依優先順序處理的完整清單 |
| [`missing_official_maps.md`](missing_official_maps.md) | 缺官方圖名單（目前 0；有新增再補 URL／圖檔） |
| [`intercity_not_imported_refs.txt`](intercity_not_imported_refs.txt) | 公路客運未匯入編號（目前為空；486 條已匯入） |
| [`tdx_vs_local.md`](tdx_vs_local.md) | TDX 對打明細 |

## 公路客運（InterCity）特別說明

這 486 條**不是** TDX 缺資料；本機已全數匯入。  
若要重跑：

```bash
bin/rails geojson:bus CITY=InterCity
```

只有當某條公路客運 **TDX 也沒 shape**、但 Wikipedia／業者官網有圖時，才走手動交付流程。
