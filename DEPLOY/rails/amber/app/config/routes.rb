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
  end

  resources :outfits do
    member { post :like }
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
    post "items/:id/analyze", to: "ai#analyze_item",    as: :ai_analyze_item
    post "items/:id/tag",     to: "ai#tag_item",        as: :ai_tag_item
    get  "outfits/suggest",   to: "ai#suggest_outfits", as: :ai_suggest_outfits
    get  "declutter",         to: "ai#declutter_guide", as: :ai_declutter
    get  "capsule",           to: "ai#capsule",         as: :ai_capsule
    get  "palette",           to: "ai#color_palette",   as: :ai_palette
    get  "search",            to: "ai#search",          as: :ai_search
    get  "moodboard",         to: "ai#mood_board",      as: :ai_mood_board
    get  "occasions",         to: "ai#occasion_map",    as: :ai_occasions
  end

  root "home#index"
  get "up", to: "rails/health#show", as: :rails_health_check
end
