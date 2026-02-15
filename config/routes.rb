Rails.application.routes.draw do
  devise_for :users, controllers: {
    sessions: "users/sessions",
    registrations: "users/registrations",
    passwords: "users/passwords",
    confirmations: "users/confirmations"
  }
  root "dashboard#index"

  get "dashboard", to: "dashboard#index"
  get "health/clickhouse", to: "health#clickhouse"

  resources :projects, only: [ :index, :show, :new, :create ], param: :uuid do
    resources :api_keys, only: [ :create, :destroy ], param: :uuid
  end

  namespace :api do
    namespace :v1 do
      resources :ingest_events, only: :create
    end
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
