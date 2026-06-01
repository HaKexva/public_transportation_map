# Public Transportation Map

An interactive map of Taiwan, Penghu, Kinmen, and Matsu with toggleable public transit layers. No sign-in required — open the app and explore.

**Repository:** [github.com/HaKexva/public_transportation_map](https://github.com/HaKexva/public_transportation_map)

## Features

- Full-screen **road-only** basemap (CARTO light, no labels) centered on Taiwan and outlying islands
- Floating **layer panel** (RubyUI) to toggle transit types:
  - 公車 (bus)
  - 火車 (train)
  - 捷運 (metro)
  - 高鐵 (HSR) — Taiwan High Speed Rail (南港–左營, 12 stations)
  - 渡輪 (ferry) — coming soon
- **Light / dark theme** toggle
- **Reset view** button to fit the default map bounds
- No authentication — the dashboard is public

> Bus, conventional rail (台鐵), and ferry layers are placeholders. Metro, HSR, and other transit lines load GeoJSON from `public/geojson/`.

## Tech stack

| Layer | Tools |
| --- | --- |
| Backend | Ruby 3.4, Rails 8.1 |
| Views | Phlex |
| UI | [RubyUI](https://rubyui.com) + Tailwind CSS 4 |
| Frontend | Hotwire (Turbo + Stimulus), importmap |
| Map | [Leaflet](https://leafletjs.com/) + CARTO / OpenStreetMap tiles |
| Database | SQLite3 |
| Tests | Minitest, Capybara, Selenium |

## Requirements

- Ruby **3.4.8** (see `.ruby-version`)
- Bundler
- [Foreman](https://github.com/ddollar/foreman) (installed automatically by `bin/dev` if missing)
- Chrome/Chromium (for system tests only)

## Setup

```bash
git clone https://github.com/HaKexva/public_transportation_map.git
cd public_transportation_map
bundle install
bin/rails db:prepare
cp .env.example .env   # optional
```

### Rebuild HSR GeoJSON from OpenStreetMap

```bash
bin/rails geojson:hsr
```

## Running locally

Start the web server **and** the Tailwind CSS watcher together:

```bash
bin/dev
```

By default the app listens on [http://127.0.0.1:3000](http://127.0.0.1:3000). To use another port:

```bash
PORT=3000 bin/dev
```

Open the root URL in your browser. If styles or the map look wrong after pulling changes, hard-refresh (Cmd+Shift+R) and confirm `bin/dev` is running (not `bin/rails server` alone — Tailwind must compile `app/assets/builds/tailwind.css`).

### One-off Tailwind build

```bash
bin/rails tailwindcss:build
```

## Environment variables

Copy `.env.example` to `.env`. All variables are optional for local development.

| Variable | Purpose |
| --- | --- |
| `GOOGLE_MAPS_API_KEY` | Reserved for future Google Maps integration. The app uses Leaflet + CARTO/OSM by default. |

## Testing

```bash
bin/rails test
bin/rails test:system
```

System tests expect a headless Chrome browser.

## Project layout

```
app/
  views/dashboards/show.rb    # Main map + layer panel (Phlex)
  javascript/controllers/
    map_controller.js         # Leaflet map, layer toggles, reset view
  components/ruby_ui/         # UI component library
config/routes.rb              # root → dashboards#show
```

## Deployment

The app includes [Kamal](https://kamal-deploy.org/) configuration (`config/deploy.yml`). Run `bin/rails tailwindcss:build` before deploying so compiled CSS is present in `app/assets/builds/`.

Health check: `GET /up`

## Contributing

1. Fork the repository
2. Create a branch for your change
3. Run `bin/rubocop` and `bin/rails test` before opening a pull request

CI runs RuboCop, Brakeman, bundler-audit, importmap audit, unit tests, and system tests on push and pull requests.
