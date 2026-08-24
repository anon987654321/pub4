# frozen_string_literal: true

Rails.application.routes.draw do
  get "offline" => "rails/pwa#offline", as: :pwa_offline
  get "internal/status" => "internal#status", as: :internal_status
  get "sso/from_master" => "sso#from_master", as: :sso_from_master

  jobs_constraint = lambda { |request|
    session_id = request.cookie_jar.signed[:session_id]
    session_id.present? && ::Session.exists?(id: session_id)
  }

  resource :session, only: %i[new create destroy] do
    # Passwordless sign-in. The mailer, the token generator and the columns
    # have existed since 20260709120000; the route the link pointed at never
    # did, so nothing could send one and nothing could consume one.
    get  "magic", to: "sessions#magic", as: :magic
    post "magic", to: "sessions#request_magic", as: :request_magic
  end
  instance_eval(File.read(File.expand_path("../../shared/config/routes/legal.rb", __dir__)))
  instance_eval(File.read(File.expand_path("../../shared/config/routes/auth.rb", __dir__)))
  instance_eval(File.read(File.expand_path("../../shared/config/routes/verification.rb", __dir__)))
  # Social stack (notifications/reactions/reports/fingerprint) needs tables bsdports
  # does not have. Opt in with BSDPORTS_SOCIAL=1 only after migrations land.
  if ENV["BSDPORTS_SOCIAL"] == "1"
    instance_eval(File.read(File.expand_path("../../shared/config/routes/social.rb", __dir__)))
  end
  instance_eval(File.read(File.expand_path("../../shared/config/routes/fleet.rb", __dir__)))
  resources :passwords, param: :token, only: %i[new create edit update]

  root "ports#index"
  constraints(jobs_constraint) do
    mount SolidQueue::Engine, at: "/admin/jobs"
  end

  resources :categories, only: %i[index show]
  resources :maintainers, only: %i[index show]

  resources :ports, only: %i[index show] do
    member do
      get :explore
      post :watch
      delete :unwatch
      post :crossref_cves
      post :review
    end
    resources :comments, only: %i[create destroy]
  end

  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "up", to: "rails/health#show", as: :rails_health_check
  get "sitemap.xml" => "sitemaps#index", as: :sitemap
end
