# 台灣大眾運輸地圖 Public Transportation Map

[中文](#中文) · [English](#english)

程式庫 / Repo：[github.com/HaKexva/public_transportation_map](https://github.com/HaKexva/public_transportation_map)

---

## 中文

這是一份有公車、火車、捷運、高鐵以及其他交通工具的路線圖與時刻表查詢，包含了公車、軌道運輸兩大頁面。

範圍涵蓋台灣本島、澎湖、金門、馬祖，打開就能用，不用登入。

### 可以做什麼

**軌道運輸頁（`/`）**

- 台鐵、高鐵、各地捷運與輕軌（台北、新北、桃園、台中、高雄）、糖鐵、渡輪，還有纜車、林鐵、觀光鐵道這類放在「其他」裡的路線，都可以勾選顯示在地圖上
- 依照時刻表推算列車現在跑到哪，有 TDX 金鑰的話會再疊上即時誤點
- 點車站可以看接下來 60 分鐘的時刻表，點列車可以跟著它跑完全程（也有群車視角）
- 跟隨列車跑完全程可以蒐集「完乘章」，累積公里數和搭過的路線
- 附近列車、平交道、捷運營運異常公告
- 放空模式：什麼都不用按，就看著車在地圖上跑

**公車頁（`/bus`）**

- 各縣市公車和公路客運的路線圖，可以依縣市、客運業者、路線類型、顏色系列篩選
- 站牌到站時間、經過同一站的其他路線

**其他小東西**

- 淺色／深色主題、三種底圖（台灣圖資、簡化地圖、衛星）
- 中英文介面切換
- 分享連結會帶上當下的地圖位置跟時間，別人打開看到的就是同一個畫面

公車路線是從 TDX 匯入的，有些縣市資料不完整，缺的部分我整理在 [`docs/bus_data_gaps/`](docs/bus_data_gaps/)。軌道路線的幾何大多是從 OpenStreetMap 抓下來再整理過，放在 `public/geojson/`。

### 用到的東西

| 項目 | 工具 |
| --- | --- |
| 後端 | Ruby 3.4、Rails 8.1 |
| 資料庫 | PostgreSQL（Solid Cache / Queue / Cable 也放在同一個 DB） |
| 畫面 | Phlex、[RubyUI](https://rubyui.com)、Tailwind CSS 4 |
| 前端 | Hotwire（Turbo + Stimulus）、importmap |
| 地圖 | [Leaflet](https://leafletjs.com/)，底圖用 NLSC、CARTO、衛星圖 |
| 資料來源 | [TDX](https://tdx.transportdata.tw)、台鐵 ODS、OpenStreetMap、NLSC |
| 測試 | Minitest、Capybara、Selenium |

### 在自己電腦上跑起來

需要先裝好：

- Ruby **3.4.8**（版本寫在 `.ruby-version`）
- PostgreSQL
- Chrome / Chromium（只有跑系統測試才需要）

```bash
git clone https://github.com/HaKexva/public_transportation_map.git
cd public_transportation_map
bundle install
cp .env.example .env
bin/rails db:prepare
bin/rails transit:prepare_schedules   # 同步路線目錄＋塞一些範例／固定班表
bin/dev
```

打開 [http://127.0.0.1:3000](http://127.0.0.1:3000) 就可以了，想換 port 就用 `PORT=4000 bin/dev`。

記得要用 `bin/dev`，不要只跑 `bin/rails server`，因為 Tailwind 要一起在背景編譯。如果拉了新的 code 之後畫面怪怪的，先確認 `bin/dev` 有在跑，再 Cmd+Shift+R 強制重新整理。

### 環境變數

本機開發的話全部都可以先不填，只是少了某些功能。

| 變數 | 用途 |
| --- | --- |
| `DATABASE_URL` | 正式環境必填。本機沒設的話會用 `DB_HOST`、`DB_USERNAME` 這些預設值連本機 Postgres |
| `CARTO_API_KEY` | CARTO 底圖用。沒填的話圖磚上會有「API KEY REQUIRED」浮水印，可以去 [CARTO](https://carto.com/basemaps) 免費申請 |
| `TDX_CLIENT_ID` / `TDX_CLIENT_SECRET` | 匯入高鐵、捷運時刻表，還有即時誤點、公車到站都要用。去 [TDX](https://tdx.transportdata.tw) 註冊就有 |
| `SECRET_KEY_BASE` 或 `RAILS_MASTER_KEY` | 正式環境擇一設定，詳細寫在 `.env.example` |
| `GOOGLE_MAPS_API_KEY` | 先留著，目前沒用到 |

### 時刻表

時刻表是存在資料庫裡的：

- 台鐵：抓台鐵 ODS 的每日 JSON（今天起 14 天內），不用金鑰
- 高鐵：TDX 的 `DailyTimetable`
- 捷運：TDX 的站別時刻，再自己拼成一班一班的車次
- 糖鐵、林鐵、纜車這些：直接寫在程式裡的固定班表

```bash
bin/rails transit:import_schedules
```

正式環境每天台北時間凌晨 3:30 會自動跑一次。即時看板的資料不會存進資料庫。

### 更新地圖資料

常用的幾個：

```bash
bin/rails geojson:tra              # 台鐵（從 OSM 重建）
bin/rails geojson:hsr              # 高鐵
bin/rails geojson:taipei_metro     # 台北捷運，其他捷運也是同樣格式
bin/rails geojson:bus CITY=Keelung # 匯入某個縣市的公車
bin/rails geojson:routes_manifest  # 重新產生 routes.json
```

完整清單可以跑 `bin/rails -T geojson` 看。

### 程式放在哪

| 路徑 | 放什麼 |
| --- | --- |
| `app/` | 畫面：Phlex view、Stimulus（主要是 `map_controller.js`）、RubyUI 元件 |
| `app/controllers/api/` | 列車位置、時刻表、站牌到站、營運公告等 JSON API |
| `lib/geojson/` | 產生地圖路線的東西：路線目錄、OSM / NLSC 抓資料、備援快取 |
| `lib/transit/` | 班表相關：台鐵 ODS、TDX client、捷運車次拼接、匯入 |
| `lib/route_catalog.rb` | 讀 `public/geojson/routes.json`，地圖跟班表共用 |
| `public/geojson/` | 給瀏覽器直接讀的路線 GeoJSON |

我自己的原則是：路線幾何放 `lib/geojson/`（產出到 `public/geojson/{system}/`），跟時刻表、TDX、資料庫有關的放 `lib/transit/`，備援用的 JSON / ZIP 放 `lib/geojson/fallback_tracks/`，不要丟進 `public/`。

### 測試

```bash
bin/rails test
bin/rails test:system   # 需要 headless Chrome
```

### 部署

我目前是部署在 Railway，用 repo 裡的 `Dockerfile`；也有留 [Kamal](https://kamal-deploy.org/) 的設定（`config/deploy.yml`）。健康檢查是 `GET /up`。

### 想幫忙的話

歡迎發 PR！開之前先跑一下 `bin/rubocop` 和 `bin/rails test`。CI 會跑 RuboCop、Brakeman、bundler-audit、importmap audit、單元測試跟系統測試。

如果發現哪條路線畫錯、少了或班表不對，直接開 issue 跟我說也很好。

---

## English

This is a route map and timetable lookup for buses, trains, metro, high speed rail, and a bunch of other transit in Taiwan. It has two main pages: one for buses and one for rail.

It covers Taiwan, Penghu, Kinmen, and Matsu. Just open it, no sign-in needed.

### What it does

**Rail page (`/`)**

- Toggle TRA, HSR, every metro and light rail system (Taipei, New Taipei, Taoyuan, Taichung, Kaohsiung), the Taiwan Sugar Railway, ferries, and an "other" group with cable cars, forest railways, and heritage lines
- Trains move on the map based on the timetable, with live delays layered on top if you have a TDX key
- Click a station for the next 60 minutes of departures, or click a train and follow it to the end of its run (there's a group view too)
- Finish following a train and you get a "ride stamp". It keeps track of total distance and which lines you've ridden
- Nearby trains, level crossings, and metro service alerts
- Relax mode: don't click anything, just watch the trains go

**Bus page (`/bus`)**

- City buses and intercity coaches across the country, filterable by city, operator, route type, and color series
- Stop arrival times, plus other routes that serve the same stop

**Small stuff**

- Light / dark theme and three basemaps (NLSC, simplified CARTO, satellite)
- Chinese / English UI
- Share links keep the map position and time, so whoever opens it sees the same view you did

Bus routes come from TDX. Some counties have incomplete data, and I keep notes on the gaps in [`docs/bus_data_gaps/`](docs/bus_data_gaps/). Most rail geometry is pulled from OpenStreetMap and cleaned up, and lives in `public/geojson/`.

### Stack

| What | Tools |
| --- | --- |
| Backend | Ruby 3.4, Rails 8.1 |
| Database | PostgreSQL (Solid Cache / Queue / Cable share the same DB) |
| Views | Phlex, [RubyUI](https://rubyui.com), Tailwind CSS 4 |
| Frontend | Hotwire (Turbo + Stimulus), importmap |
| Map | [Leaflet](https://leafletjs.com/) with NLSC, CARTO, and satellite tiles |
| Data | [TDX](https://tdx.transportdata.tw), TRA ODS, OpenStreetMap, NLSC |
| Tests | Minitest, Capybara, Selenium |

### Running it locally

You'll need:

- Ruby **3.4.8** (see `.ruby-version`)
- PostgreSQL
- Chrome / Chromium (only for system tests)

```bash
git clone https://github.com/HaKexva/public_transportation_map.git
cd public_transportation_map
bundle install
cp .env.example .env
bin/rails db:prepare
bin/rails transit:prepare_schedules   # sync the route catalog + load sample/static schedules
bin/dev
```

Then open [http://127.0.0.1:3000](http://127.0.0.1:3000). Use `PORT=4000 bin/dev` if you want a different port.

Use `bin/dev`, not just `bin/rails server`, because Tailwind has to compile alongside it. If things look broken after pulling, check that `bin/dev` is running and hard-refresh with Cmd+Shift+R.

### Environment variables

You can leave all of these empty for local dev. You'll just be missing some features.

| Variable | What it's for |
| --- | --- |
| `DATABASE_URL` | Required in production. Locally it falls back to `DB_HOST`, `DB_USERNAME`, etc. against your local Postgres |
| `CARTO_API_KEY` | CARTO basemap tiles. Without it you get an "API KEY REQUIRED" watermark. Free at [CARTO](https://carto.com/basemaps) |
| `TDX_CLIENT_ID` / `TDX_CLIENT_SECRET` | Needed for HSR / metro timetables, live delays, and bus arrivals. Sign up at [TDX](https://tdx.transportdata.tw) |
| `SECRET_KEY_BASE` or `RAILS_MASTER_KEY` | Set one of them in production. Details are in `.env.example` |
| `GOOGLE_MAPS_API_KEY` | Reserved, not used right now |

### Timetables

Timetables are stored in the database:

- TRA: daily JSON from TRA ODS (today through 14 days out), no key needed
- HSR: TDX `DailyTimetable`
- Metro: TDX per-station timetables, stitched into individual trips
- Sugar railway, forest railways, cable cars, etc.: static schedules defined in code

```bash
bin/rails transit:import_schedules
```

Production runs this automatically every day at 3:30 AM Taipei time. Live board data isn't saved to the database.

### Refreshing map data

The ones I use most:

```bash
bin/rails geojson:tra              # TRA (rebuilt from OSM)
bin/rails geojson:hsr              # HSR
bin/rails geojson:taipei_metro     # Taipei Metro, other metros follow the same pattern
bin/rails geojson:bus CITY=Keelung # import buses for one city
bin/rails geojson:routes_manifest  # regenerate routes.json
```

Run `bin/rails -T geojson` for the full list.

### Where things live

| Path | What's in it |
| --- | --- |
| `app/` | UI: Phlex views, Stimulus (mostly `map_controller.js`), RubyUI components |
| `app/controllers/api/` | JSON APIs for vehicle positions, schedules, bus arrivals, alerts, etc. |
| `lib/geojson/` | Map geometry pipeline: line catalogs, OSM / NLSC builders, fallback caches |
| `lib/transit/` | Schedules: TRA ODS, TDX client, metro trip stitching, importers |
| `lib/route_catalog.rb` | Reads `public/geojson/routes.json`, shared by the map and schedules |
| `public/geojson/` | Route GeoJSON served straight to the browser |

My rule of thumb: geometry goes in `lib/geojson/` (output to `public/geojson/{system}/`), anything touching timetables, TDX, or the DB goes in `lib/transit/`, and fallback JSON / ZIP files go in `lib/geojson/fallback_tracks/`, never in `public/`.

### Tests

```bash
bin/rails test
bin/rails test:system   # needs headless Chrome
```

### Deploying

I currently deploy on Railway using the `Dockerfile` in the repo. There's also a [Kamal](https://kamal-deploy.org/) config (`config/deploy.yml`) if you'd rather use that. Health check is `GET /up`.

### Contributing

PRs are welcome! Run `bin/rubocop` and `bin/rails test` before opening one. CI runs RuboCop, Brakeman, bundler-audit, importmap audit, unit tests, and system tests.

If you spot a route that's drawn wrong, missing, or has a bad timetable, just open an issue and let me know.
