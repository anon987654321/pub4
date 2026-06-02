# frozen_string_literal: true

Rails.application.routes.draw do
  resource :registration, only: %i[new create]

  resource  :session
  resources :passwords, param: :token

  resources :items do
    member do
      post :spark_joy
      post :declutter
      post :wear
    end
    collection do
      post :archive_seasonal
      post :resurface_seasonal
      get :shopping_list
    end
  end

  resources :outfits do
    collection { get :dressing_room }
    member { post :like; patch :reorder; post :share; post :wear }
  end

  resources :planned_outfits, only: %i[index create destroy]

  resources :posts, only: %i[index show new create destroy] do
    member { post :like }
    collection { get :feed }
  end

  resources :users, only: :show do
    member { post :follow; delete :unfollow }
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

  root "home#index"
  get 'manifest' => 'rails/pwa#manifest', as: :pwa_manifest
  get 'service-worker' => 'rails/pwa#service_worker', as: :pwa_service_worker
  get "up", to: "rails/health#show", as: :rails_health_check
end
