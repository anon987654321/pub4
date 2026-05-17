Rails.application.routes.draw do
  # Vertical subdomains share one app. The Rails module name (Tv:: etc.) is fixed;
  # the public subdomain varies per locale (markedsplass = NO marketplace).
  TV_SUBDOMAINS         = %w[tv].freeze
  DATING_SUBDOMAINS     = %w[dating].freeze
  PLAYLIST_SUBDOMAINS   = %w[playlist].freeze
  TAKEAWAY_SUBDOMAINS   = %w[takeaway].freeze
  MARKETPLACE_SUBDOMAINS = %w[
    markedsplass markadur marknadsplats marktplaats marktplatz
    marche mercato mercado markkinapaikka marketplace
  ].freeze

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

  constraints(subdomain: TV_SUBDOMAINS) do
    scope module: "tv", as: "tv" do
      root "home#index", as: :tv_root
      resources :channels, param: :slug do
        member { post :subscribe; delete :unsubscribe }
        resources :videos, only: %i[new create]
      end
      resources :videos, only: %i[show destroy]
    end
  end

  constraints(subdomain: DATING_SUBDOMAINS) do
    scope module: "dating", as: "dating" do
      root "home#index", as: :dating_root
      resource  :profile,  only: %i[new create edit update show]
      resources :likes,    only: :create
      resources :dislikes, only: :create
      resources :matches,  only: :index
    end
  end

  constraints(subdomain: PLAYLIST_SUBDOMAINS) do
    scope module: "playlist", as: "playlist" do
      root "playlists#index", as: :playlist_root
      resources :playlists do
        resources :tracks, only: %i[create destroy]
      end
      resources :listens, only: :create
    end
  end

  constraints(subdomain: TAKEAWAY_SUBDOMAINS) do
    scope module: "takeaway", as: "takeaway" do
      root "restaurants#index", as: :takeaway_root
      resources :restaurants do
        resources :menu_items, only: %i[create destroy]
        resources :orders,     only: %i[new create]
      end
      resources :orders, only: %i[index show update]
    end
  end

  constraints(subdomain: MARKETPLACE_SUBDOMAINS) do
    scope module: "marketplace", as: "marketplace" do
      root "listings#index", as: :marketplace_root
      resources :listings do
        resources :orders, only: %i[create update]
      end
      resources :categories, only: :show, param: :id
    end
  end

  root "home#index"
  get  "up" => "rails/health#show", as: :rails_health_check
end
