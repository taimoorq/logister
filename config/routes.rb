Rails.application.routes.draw do
  docs_base_url = ENV.fetch("LOGISTER_DOCS_URL", "https://docs.logister.org").chomp("/")

  devise_for :users, controllers: {
    sessions: "users/sessions",
    registrations: "users/registrations",
    passwords: "users/passwords",
    confirmations: "users/confirmations"
  }
  root "home#show"
  get "docs", to: redirect("#{docs_base_url}/", status: 301)
  get "docs/getting-started", to: redirect("#{docs_base_url}/getting-started/", status: 301)
  get "docs/product", to: redirect("#{docs_base_url}/product/", status: 301)
  get "docs/self-hosting", to: redirect("#{docs_base_url}/self-hosting/", status: 301)
  get "docs/local-development", to: redirect("#{docs_base_url}/local-development/", status: 301)
  get "docs/deployment", to: redirect("#{docs_base_url}/deployment/", status: 301)
  get "docs/clickhouse", to: redirect("#{docs_base_url}/clickhouse/", status: 301)
  get "docs/http-api", to: redirect("#{docs_base_url}/http-api/", status: 301)
  get "docs/integrations/ruby", to: redirect("#{docs_base_url}/integrations/ruby/", status: 301)
  get "docs/integrations/javascript", to: redirect("#{docs_base_url}/integrations/javascript/", status: 301)
  get "docs/integrations/cfml", to: redirect("#{docs_base_url}/integrations/cfml/", status: 301)
  get "docs/integrations/python", to: redirect("#{docs_base_url}/integrations/python/", status: 301)
  get "docs/integrations/dotnet", to: redirect("#{docs_base_url}/integrations/dotnet/", status: 301)
  get "sitemap.xml", to: "home#sitemap", defaults: { format: :xml }
  get "about", to: "home#about"
  get "privacy", to: "home#privacy"
  get "cookies", to: "home#cookies"
  get "terms", to: "home#terms"

  get "dashboard", to: "dashboard#index"
  get "health/clickhouse", to: "health#clickhouse"
  resource :profile, only: [ :show, :edit, :update ], controller: "users/profiles"
  get "account/security", to: redirect("/users/edit"), as: :account_security

  namespace :admin do
    resources :users, only: [ :index, :show, :destroy ], param: :uuid do
      member do
        patch :confirm
        post :resend_confirmation
      end
    end
  end

  resources :projects, only: [ :index, :show, :new, :create, :edit, :update, :destroy ], param: :uuid do
    member do
      get :settings, to: "project_settings#show"
      get :performance, to: "project_performance#show"
      get :monitors, to: "project_monitors#show"
      get :activity, to: "project_activity#show"
    end
    resources :api_keys, only: [ :create, :destroy ], param: :uuid
    resources :project_memberships, only: [ :create, :destroy ], param: :uuid
    resources :events, only: [ :index, :show ], controller: "project_events", param: :uuid

    resources :error_groups, only: [], param: :uuid do
      member do
        patch :resolve
        patch :ignore
        patch :archive
        patch :reopen
      end
    end
  end

  namespace :api do
    namespace :v1 do
      resources :ingest_events, only: :create
      resources :check_ins, only: :create
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
