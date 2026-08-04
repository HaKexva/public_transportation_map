# 大眾運輸地圖

台灣、澎湖、金門、馬祖的互動地圖，可切換各種大眾運輸圖層。無需登入 —— 開啟即可瀏覽。

**程式庫：** [github.com/HaKexva/public_transportation_map](https://github.com/HaKexva/public_transportation_map)

[English](README.md)

## 功能

- 全螢幕**僅道路**底圖（CARTO light，無標籤），以台灣及離島為中心
- 浮動**圖層面板**（RubyUI）可切換運輸類型：
  - 公車 (bus)
  - 火車 (TRA) — 台鐵幹線與支線
  - 捷運 (metro)
  - 高鐵 (HSR) — 台灣高鐵（南港–左營，12 站）
  - 渡輪 (ferry) — 即將推出
- **淺色 / 深色主題**切換
- **重設視圖**按鈕，回到預設地圖範圍
- 無需驗證 —— 儀表板為公開頁面

> 公車與渡輪圖層目前為佔位。捷運、台鐵、高鐵及其他路線從 `public/geojson/` 載入 GeoJSON。

## 技術棧

| 層級 | 工具 |
| --- | --- |
| 後端 | Ruby 3.4、Rails 8.1 |
| 視圖 | Phlex |
| UI | [RubyUI](https://rubyui.com) + Tailwind CSS 4 |
| 前端 | Hotwire（Turbo + Stimulus）、importmap |
| 地圖 | [Leaflet](https://leafletjs.com/) + CARTO / OpenStreetMap 圖磚 |
| 資料庫 | SQLite3 |
| 測試 | Minitest、Capybara、Selenium |

## 系統需求

- Ruby **3.4.8**（見 `.ruby-version`）
- Bundler
- [Foreman](https://github.com/ddollar/foreman)（若尚未安裝，`bin/dev` 會自動安裝）
- Chrome/Chromium（僅系統測試需要）

## 安裝

```bash
git clone https://github.com/HaKexva/public_transportation_map.git
cd public_transportation_map
bundle install
bin/rails db:prepare
cp .env.example .env   # 可選
```

### 從 OpenStreetMap 重建高鐵 GeoJSON

```bash
bin/rails geojson:hsr
```

### 從 OpenStreetMap 重建台鐵 GeoJSON

```bash
bin/rails geojson:tra
```

## 本機執行

同時啟動網頁伺服器**與** Tailwind CSS 監看程序：

```bash
bin/dev
```

預設監聽 [http://127.0.0.1:3000](http://127.0.0.1:3000)。若要使用其他埠：

```bash
PORT=3000 bin/dev
```

在瀏覽器開啟根網址。若拉取更新後樣式或地圖顯示異常，請強制重新整理（Cmd+Shift+R），並確認執行的是 `bin/dev`（而非單獨的 `bin/rails server` —— Tailwind 必須編譯 `app/assets/builds/tailwind.css`）。

### 單次建置 Tailwind

```bash
bin/rails tailwindcss:build
```

## 環境變數

將 `.env.example` 複製為 `.env`。本機開發時所有變數皆為可選。

| 變數 | 用途 |
| --- | --- |
| `GOOGLE_MAPS_API_KEY` | 保留供未來 Google Maps 整合。目前預設使用 Leaflet + CARTO/OSM。 |

## 測試

```bash
bin/rails test
bin/rails test:system
```

系統測試需要無頭 Chrome 瀏覽器。

## 目錄結構

| 路徑 | 職責 |
| --- | --- |
| `app/` | 精簡 UI：Phlex 視圖、Stimulus（`map_controller.js`）、RubyUI 元件 |
| `lib/geojson/` | 地圖幾何管線：路線目錄、OSM/NLSC 建置器、後備快取 |
| `lib/transit/` | 班表：TDX 客戶端、目錄同步、班表種子／匯入 |
| `lib/route_catalog.rb` | `public/geojson/routes.json` 的執行時讀取器（地圖與運輸共用） |
| `lib/tasks/geojson.rake` | 重建 GeoJSON / `routes.json` / 車廠 |
| `lib/tasks/transit.rake` | 同步資料庫目錄、種子／匯入班表 |
| `public/geojson/` | 提供給瀏覽器的靜態路線 GeoJSON（見該資料夾的 README） |
| `db/seeds.rb` | 僅負責編排；班表邏輯放在 `lib/transit/` |

**放置原則：** 幾何與來源目錄 → `lib/geojson/`（輸出 → `public/geojson/{system}/`）；班表 / TDX / 資料庫同步 → `lib/transit/`；後備 JSON/ZIP → `lib/geojson/fallback_tracks/`（不要放 `public/`）。`other` 路線的幾何在 `OtherTransitCatalog`，營運時間在 `OtherTransitScheduleCatalog`（相同 slug、資料分開）。

```
app/
  views/dashboards/show.rb    # 主地圖 + 圖層面板（Phlex）
  javascript/controllers/
    map_controller.js         # Leaflet 地圖、圖層切換、重設視圖
  components/ruby_ui/         # UI 元件庫
config/routes.rb              # root → dashboards#show
```

## 部署

專案包含 [Kamal](https://kamal-deploy.org/) 設定（`config/deploy.yml`）。部署前請先執行 `bin/rails tailwindcss:build`，確保 `app/assets/builds/` 中有編譯好的 CSS。

健康檢查：`GET /up`

## 貢獻

1. Fork 此程式庫
2. 為你的變更建立分支
3. 開啟 pull request 前執行 `bin/rubocop` 與 `bin/rails test`

CI 會在 push 與 pull request 時執行 RuboCop、Brakeman、bundler-audit、importmap audit、單元測試與系統測試。
