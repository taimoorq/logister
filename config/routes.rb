Rails.application.routes.draw do
  devise_for :users, controllers: {
    sessions: "users/sessions",
    registrations: "users/registrations",
    passwords: "users/passwords",
    confirmations: "users/confirmations"
  }
  root "home#show"
  get "about", to: "home#about"
  get "privacy", to: "home#privacy"
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

  resources :projects, only: [ :index, :show, :new, :create, :destroy ], param: :uuid do
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
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
