Rails.application.routes.draw do
  docs_redirect = lambda do |path|
    redirect(status: 301) do |_params, _request|
      "#{InstanceConfiguration.value('general.docs_url').to_s.chomp('/')}#{path}"
    end
  end

  devise_for :users, controllers: {
    sessions: "users/sessions",
    registrations: "users/registrations",
    passwords: "users/passwords",
    confirmations: "users/confirmations"
  }
  root "home#show"
  get "setup", to: "instance_setup#new", as: :instance_setup
  post "setup", to: "instance_setup#create"
  get "docs", to: docs_redirect.call("/")
  get "docs/getting-started", to: docs_redirect.call("/getting-started/")
  get "docs/product", to: docs_redirect.call("/product/")
  get "docs/metrics", to: docs_redirect.call("/metrics/")
  get "docs/self-hosting", to: docs_redirect.call("/self-hosting/")
  get "docs/local-development", to: docs_redirect.call("/local-development/")
  get "docs/deployment", to: docs_redirect.call("/deployment/")
  get "docs/github-app", to: docs_redirect.call("/github-app/")
  get "docs/clickhouse", to: docs_redirect.call("/clickhouse/")
  get "docs/http-api", to: docs_redirect.call("/http-api/")
  get "docs/api-reference", to: docs_redirect.call("/api-reference/")
  get "docs/cli", to: docs_redirect.call("/cli/")
  get "docs/integrations/ruby", to: docs_redirect.call("/integrations/ruby/")
  get "docs/integrations/javascript", to: docs_redirect.call("/integrations/javascript/")
  get "docs/integrations/cfml", to: docs_redirect.call("/integrations/cfml/")
  get "docs/integrations/python", to: docs_redirect.call("/integrations/python/")
  get "docs/integrations/dotnet", to: docs_redirect.call("/integrations/dotnet/")
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
  get "cli/device", to: "cli_device_authorizations#show", as: :cli_device_authorization
  post "cli/device", to: "cli_device_authorizations#update"
  resource :profile, only: [ :show, :edit, :update ], controller: "users/profiles"
  get "account/security", to: redirect("/users/edit"), as: :account_security

  match "api/cookie-banner/v1/*proxy_path",
        to: "cookie_banner_proxy#show",
        via: [ :get, :post ],
        format: false,
        as: :cookie_banner_proxy

  namespace :admin do
    resource :installation, only: :show, controller: "installation" do
      post :complete
    end
    get "installation/:section", to: "installation/settings#show", as: :installation_section
    patch "installation/:section", to: "installation/settings#update"
    match "installation/:section/test", to: "installation/settings#test", via: [ :post, :patch ], as: :test_installation_section
    post "installation/:section/repair", to: "installation/settings#repair", as: :repair_installation_section
    post "installation/:section/skip", to: "installation/settings#skip", as: :skip_installation_section
    patch "installation/self-monitoring/project", to: "installation/self_monitoring#update", as: :installation_self_monitoring

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
      get :setup, to: "project_setup#show"
      get :settings, to: "project_settings#show"
      get "insights/data", to: "project_insights#data", as: :insights_data
      get :insights, to: "project_insights#show"
      get :performance, to: "project_performance#show"
      get "performance/request-breakdown", to: "project_performance#request_breakdown", as: :performance_request_breakdown
      get "performance/database-load", to: "project_performance#database_load", as: :performance_database_load
      get "performance/release-health", to: "project_performance#release_health", as: :performance_release_health
      get "performance/transactions", to: "project_performance#transactions", as: :performance_transactions
      get :monitors, to: "project_monitors#show"
      get :deployments, to: "project_deployments#index"
      get :activity, to: "project_activity#show"
      get :archives, to: "project_archives#show"
    end
    resources :api_keys, only: [ :create, :destroy ], param: :uuid
    resources :project_memberships, only: [ :create, :update, :destroy ], param: :uuid
    resources :source_repositories, only: [ :create, :update, :destroy ], controller: "project_source_repositories", param: :uuid
    post "github/installations/:uuid/sync", to: "github/installations#sync", as: :github_installation_sync
    resources :github_installation_links, only: [ :create, :destroy ], controller: "github/project_installations", param: :uuid
    resource :integration_setting, only: [ :update ], controller: "project_integration_settings", as: :integration_setting
    post "integration_setting/import", to: "project_integration_settings#import", as: :integration_setting_import
    resources :android_mapping_files, only: [ :create, :destroy ], param: :uuid
    resources :apple_symbol_artifacts, only: [ :create, :destroy ], param: :uuid do
      post :process_artifact, on: :member, path: "process"
    end
    resource :notification_preference, only: [ :update ], controller: "project_notification_preferences", as: :notification_preference
    resource :retention_policy, only: [ :update ], controller: "project_retention_policies", as: :retention_policy
    resource :rate_limit, only: [ :update ], controller: "project_rate_limits", as: :rate_limit
    resources :check_in_monitors, only: [ :update ], controller: "project_monitors", path: "monitors"
    resources :events, only: [ :index, :show ], controller: "project_events", param: :uuid

    resources :error_groups, only: [], param: :uuid do
      resource :assignment, only: [ :update, :destroy ], controller: "error_group_assignments"
      resources :external_links, only: [ :create, :destroy ], controller: "error_group_external_links", param: :uuid
      resource :github_issue, only: :create, controller: "github/issues"

      member do
        get :export
        patch :resolve
        patch :ignore
        patch :archive
        patch :reopen
      end
    end
  end

  resources :project_purges, only: [] do
    post :retry, on: :member
  end

  namespace :api do
    namespace :v1 do
      namespace :cli do
        get :capabilities, to: "capabilities#show"
        get :session, to: "sessions#show"
        resources :device_authorizations, only: :create do
          post :token, on: :collection
        end
        resources :projects, only: [ :index, :show ], param: :uuid do
          member do
            get :summary, to: "project_summaries#show"
          end
        end
        get "projects/:project_uuid/events", to: "events#index"
        get "projects/:project_uuid/events/:uuid", to: "events#show"
        get "projects/:project_uuid/traces", to: "traces#index"
        get "projects/:project_uuid/traces/:trace_id", to: "traces#show"
        get "projects/:project_uuid/error_groups", to: "error_groups#index"
        get "projects/:project_uuid/error_groups/:uuid", to: "error_groups#show"
        get "projects/:project_uuid/error_groups/:uuid/export", to: "error_groups#export"
        get "projects/:project_uuid/error_groups/:uuid/context", to: "error_groups#context"
        get "projects/:project_uuid/monitors", to: "monitors#index"
        get "projects/:project_uuid/monitors/:uuid", to: "monitors#show"
        get "projects/:project_uuid/deployments", to: "deployments#index"
        get "projects/:project_uuid/deployments/:uuid", to: "deployments#show"
        get "projects/:project_uuid/insights", to: "insights#show"
        get "projects/:project_uuid/metrics/catalog", to: "metrics#catalog"
        get "projects/:project_uuid/metrics/query", to: "metrics#query"
      end

      resources :ingest_events, only: :create do
        post :batch, on: :collection
      end
      resources :check_ins, only: :create
      resources :deployments, only: :create
      resources :mobile_ingest_tokens, only: :create
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
