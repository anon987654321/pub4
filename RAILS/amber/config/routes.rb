# frozen_string_literal: true

Rails.application.routes.draw do
  get "offline" => "rails/pwa#offline", as: :pwa_offline
  post "share" => "items#share", as: :share_item

  jobs_constraint = lambda { |request|
    session_id = request.cookie_jar.signed[:session_id]
    session_id.present? && ::Session.exists?(id: session_id)
  }

  resource :registration, only: %i[new create]

  resource :session
  instance_eval(File.read(File.expand_path("../../shared/config/routes/auth.rb", __dir__)))
  instance_eval(File.read(File.expand_path("../../shared/config/routes/social.rb", __dir__)))
  instance_eval(File.read(File.expand_path("../../shared/config/routes/fleet.rb", __dir__)))
  resources :passwords, param: :token

  resources :items do
    member do
      post :spark_joy
      post :declutter
      post :archive
      post :restore
      post :wear
    end
    collection do
      post :archive_seasonal
      post :resurface_seasonal
      get :shopping_list
    end
  end
  patch "drafts/:id", to: "drafts#update", as: :draft

  resources :outfits do
    collection { get :dressing_room; post :generate }
    member { post :like; patch :reorder; post :share; post :wear }
  end

  resources :planned_outfits, only: %i[index create destroy]

  resources :wardrobe_items do
    collection do
      get :analytics
      get :timeline
    end
  end
  resources :connections, only: %i[index create update]
  resources :live_streams, only: %i[index show create update destroy]
  resources :messages, only: %i[index create]

  resources :posts, only: %i[index show new create destroy] do
    resources :comments, only: %i[create destroy]
    member { post :like }
    collection { get :feed }
  end

  resources :users, only: :show do
    member do
      post :follow, to: "follows#create"
      delete :unfollow, to: "follows#destroy"
    end
  end

  get "creators/:handle", to: "creator_profiles#show", as: :creator_profile
  resource :creator_profile, only: %i[new create edit update], as: :my_creator_profile
  scope "creators/:handle", as: :creator_profile do
    resources :wardrobe_items, only: %i[create destroy], controller: "creator_wardrobe_items"
  end

  resources :declutter, only: :index, param: :id do
    member do
      get  :review
      patch :update_review
      post :move
      post :challenge
      post :complete_challenge
      post :outcome
      get  :last_chance
    end
  end

  scope :ai do
    post "items/:id/analyze", to: "ai#analyze_item", as: :ai_analyze_item
    post "items/:id/tag", to: "ai#tag_item", as: :ai_tag_item
    get "outfits/suggest", to: "ai#suggest_outfits", as: :ai_suggest_outfits
    post "outfits/generate", to: "ai#generate_outfit", as: :ai_generate_outfit
    get "declutter", to: "ai#declutter_guide", as: :ai_declutter
    get "capsule", to: "ai#capsule", as: :ai_capsule
    get "palette", to: "ai#color_palette", as: :ai_palette
    get "search", to: "ai#search", as: :ai_search
    get "moodboard", to: "ai#mood_board", as: :ai_mood_board
    get "occasions", to: "ai#occasion_map", as: :ai_occasions
    get "style", to: "ai#style_profile", as: :ai_style_profile
    post "style", to: "ai#style_profile"
    get "pack", to: "ai#packing_list", as: :ai_packing_list
  end

  get "demo", to: "demo_wardrobe#index", as: :demo_wardrobe
  get "demo/items/:id", to: "demo_wardrobe#show", as: :demo_wardrobe_item

  root "home#index"
  constraints(jobs_constraint) do
    mount SolidQueue::Engine, at: "/admin/jobs"
  end
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "up", to: "rails/health#show", as: :rails_health_check
  get "sitemap.xml" => "sitemaps#index", as: :sitemap
end
