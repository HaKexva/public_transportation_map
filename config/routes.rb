Rails.application.routes.draw do
  # Chrome DevTools requests this when open; not part of the app.
  get "/.well-known/appspecific/com.chrome.devtools.json", to: proc { [ 204, {}, [] ] }

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Flat bus GeoJSON paths used by pre-reorganize manifests → nested city folders.
  get "/geojson/bus/:slug", to: "bus_geojson_redirects#show",
      constraints: { slug: /[^\/]+\.geojson/ },
      format: false

  root "dashboards#show", defaults: { transport_mode: "rail" }
  get "bus", to: "dashboards#show", defaults: { transport_mode: "bus" }, as: :bus_map
  get "rail", to: redirect("/")

  resources :routes, only: [ :show ], param: :id

  namespace :api do
    resources :vehicles, only: [ :index ]
    resources :schedules, only: [ :index ]
    resources :station_boards, only: [ :index ]
    resources :station_infos, only: [ :index ]
    resources :bus_arrivals, only: [ :index ]
    resources :bus_through_routes, only: [ :index ]
    resources :alerts, only: [ :index ]
  end
end
