Rails.application.routes.draw do
  docs_base_url = ENV["LOGISTER_DOCS_URL"].to_s.strip
  docs_base_url = "https://docs.logister.org" if docs_base_url.empty?
  docs_base_url = docs_base_url.chomp("/")

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
  get "docs/metrics", to: redirect("#{docs_base_url}/metrics/", status: 301)
  get "docs/self-hosting", to: redirect("#{docs_base_url}/self-hosting/", status: 301)
  get "docs/local-development", to: redirect("#{docs_base_url}/local-development/", status: 301)
  get "docs/deployment", to: redirect("#{docs_base_url}/deployment/", status: 301)
  get "docs/github-app", to: redirect("#{docs_base_url}/github-app/", status: 301)
  get "docs/clickhouse", to: redirect("#{docs_base_url}/clickhouse/", status: 301)
  get "docs/http-api", to: redirect("#{docs_base_url}/http-api/", status: 301)
  get "docs/api-reference", to: redirect("#{docs_base_url}/api-reference/", status: 301)
  get "docs/integrations/ruby", to: redirect("#{docs_base_url}/integrations/ruby/", status: 301)
  get "docs/integrations/javascript", to: redirect("#{docs_base_url}/integrations/javascript/", status: 301)
  get "docs/integrations/cfml", to: redirect("#{docs_base_url}/integrations/cfml/", status: 301)
  get "docs/integrations/python", to: redirect("#{docs_base_url}/integrations/python/", status: 301)
  get "docs/integrations/dotnet", to: redirect("#{docs_base_url}/integrations/dotnet/", status: 301)
  get "robots.txt", to: "home#robots", defaults: { format: :text }
  get "sitemap.xml", to: "home#sitemap", defaults: { format: :xml }
  get "about", to: "home#about"
  get "privacy", to: "home#privacy"
  get "cookies", to: "home#cookies"
  get "terms", to: "home#terms"
  get "notification_preferences/unsubscribe/:token", to: "project_notification_preferences#unsubscribe", as: :unsubscribe_notification_preferences
  post "notification_preferences/unsubscribe/:token", to: "project_notification_preferences#unsubscribe"

  get "dashboard", to: "dashboard#index"
  get "dashboard/explorer", to: "dashboard#explorer", as: :dashboard_explorer
  get "dashboard/events", to: "dashboard_events#index", as: :dashboard_events
  post "notifications/dismiss", to: "notifications#dismiss", as: :dismiss_notification
  get "health/clickhouse", to: "health#clickhouse"
  get "github/setup", to: "github/setup#show", as: :github_setup
  post "github/webhooks", to: "github/webhooks#create", as: :github_webhooks
  resource :profile, only: [ :show, :edit, :update ], controller: "users/profiles"
  get "account/security", to: redirect("/users/edit"), as: :account_security

  match "api/cookie-banner/v1/*proxy_path",
        to: "cookie_banner_proxy#show",
        via: [ :get, :post ],
        format: false,
        as: :cookie_banner_proxy

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
      get :inbox
      patch :archive
      patch :restore
      get :settings, to: "project_settings#show"
      get "insights/data", to: "project_insights#data", as: :insights_data
      get :insights, to: "project_insights#show"
      get :performance, to: "project_performance#show"
      get :monitors, to: "project_monitors#show"
      get :deployments, to: "project_deployments#index"
      get :activity, to: "project_activity#show"
    end
    resources :api_keys, only: [ :create, :destroy ], param: :uuid
    resources :project_memberships, only: [ :create, :destroy ], param: :uuid
    resources :source_repositories, only: [ :create, :update, :destroy ], controller: "project_source_repositories", param: :uuid
    post "github/installations/:uuid/sync", to: "github/installations#sync", as: :github_installation_sync
    resource :integration_setting, only: [ :update ], controller: "project_integration_settings", as: :integration_setting
    resource :notification_preference, only: [ :update ], controller: "project_notification_preferences", as: :notification_preference
    resource :retention_policy, only: [ :update ], controller: "project_retention_policies", as: :retention_policy
    resource :rate_limit, only: [ :update ], controller: "project_rate_limits", as: :rate_limit
    resources :events, only: [ :index, :show ], controller: "project_events", param: :uuid

    resources :error_groups, only: [], param: :uuid do
      resource :assignment, only: [ :update, :destroy ], controller: "error_group_assignments"
      resources :external_links, only: [ :create, :destroy ], controller: "error_group_external_links", param: :uuid
      resource :github_issue, only: :create, controller: "github/issues"

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
      resources :deployments, only: :create
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
