Rails.application.routes.draw do
  resource  :session
  resources :passwords, param: :token

  resources :communities do
    resources :posts, shallow: true do
      resources :comments, shallow: true do
        resources :comments, shallow: true, as: :replies
      end
      resource  :vote, only: [:create], controller: "votes"
    end
  end

  resources :posts do
    resources :comments, shallow: true
    resource  :vote, only: [:create], controller: "votes"
  end

  resources :comments do
    resource  :vote, only: [:create], controller: "votes"
    resources :comments, only: [:create], as: :replies
  end

  resources :users, only: [:show] do
    member do
      post   :follow,   to: "follows#create"
      delete :unfollow, to: "follows#destroy"
    end
    resources :conversations, only: [:create]
  end

  resources :conversations, only: [:index, :show] do
    resources :messages, only: [:create]
  end

  namespace :tv do
    root "home#index"
    resources :channels, param: :slug do
      member { post :subscribe; delete :unsubscribe }
      resources :videos, only: %i[new create]
    end
    resources :videos, only: %i[show destroy]
  end

  namespace :dating do
    root 'home#index'
    resource  :profile,  only: %i[new create edit update show]
    resources :likes,    only: :create
    resources :dislikes, only: :create
    resources :matches,  only: :index
  end

  namespace :playlist do
    root 'playlists#index'
    resources :playlists do
      resources :tracks, only: %i[create destroy]
    end
    resources :listens, only: :create
  end

  namespace :takeaway do
    root 'restaurants#index'
    resources :restaurants do
      resources :menu_items, only: %i[create destroy]
      resources :orders,     only: %i[new create]
    end
    resources :orders, only: %i[index show update]
  end

  namespace :marketplace do
    root 'listings#index'
    resources :listings do
      resources :orders, only: %i[create update]
    end
    resources :categories, only: :show, param: :id
  end

  root "home#index"
  get  "up" => "rails/health#show", as: :rails_health_check
end
