Brgen::Application.routes.draw do
  root to: "forem/forums#index"

  # -------------------------------------------------

  get "/auth/facebook/callback", to: "omniauth_callbacks#facebook"
  get "/auth/google_oauth2/callback", to: "omniauth_callbacks#google_oauth2"

  resources :authentications

  # -------------------------------------------------

  resources :likes, only: [:create, :destroy]

  # -------------------------------------------------

  resources :flags, only: [:create, :destroy]

  # -------------------------------------------------

  get "(/:forum_id)/posting/new",
    to: "forem/topics#new",
    as: :new_posting

  post "(/:forum_id)/posting/new",
    to: "forem/topics#create"

  get "/confirm/:id/:key",
    to: "forem/topics#confirm",
    as: :confirm_ad

  get "(/:topic_id)/reply(/:replies)",
    to: "forem/posts#new",
    as: :new_reply

  post "(/:topic_id)/reply(/:replies)",
    to: "forem/posts#create"

  # -------------------------------------------------

  get "/photo/new",
    to: "photos#new",
    as: :new_photo

  # -------------------------------------------------

  get "/search",
    to: "forem/forums#search",
    as: "search"

  # -------------------------------------------------

  get "/user/(:id)",
    to: "users#show",
    as: "forem_user"

  get "/users/avatar/(:id)",
    to: "users#avatar",
    as: "avatar"

  devise_for :users, controllers: { omniauth_callbacks: "omniauth_callbacks" }

  # -------------------------------------------------

  namespace :api, defaults: { format: :json } do
    namespace :scraper do
      namespace :v1 do
        resources :topics, only: [:create, :show]
      end
    end
  end

  # -------------------------------------------------

  # Corresponds to `$.delayedPaperclipPoller`

  get "/check-photo-processing/:id",
    to: "photos#check_photo_processing",
    as: :check_photo_processing

  # -------------------------------------------------

  # Corresponds to `$.affiliateProductsPoller`

  get "affiliate-products-banner",
    to: "affiliate_products#banner"

  get "affiliate-products-jqm-popup",
    to: "affiliate_products#jqm_popup"

  get "affiliate-products-jqm-page",
    to: "affiliate_products#jqm_page"

  # -------------------------------------------------

  get "/intro",
    to: "static_pages#intro"

  get "/safety",
    to: "static_pages#safety"

  get "/rules",
    to: "static_pages#rules"

  get "/privacy",
    to: "static_pages#privacy"

  # -------------------------------------------------

  # Pretty admin URLs

  scope module: "forem" do
    namespace :admin do
      root to: "base#index"
      resources :groups do
        resources :members
      end

      resources :forums do
        resources :moderators
      end

      resources :categories
      resources :topics do
        member do
          put :toggle_hide
          put :toggle_lock
          put :toggle_pin
        end
      end

      get "users/autocomplete", to: "users#autocomplete"
    end
  end

  # Admin routes

  namespace :admin do
    resources :users
    resources :filters
    resources :forum_types
  end

  # -------------------------------------------------

  get "/forums/:forum_id/topics/new", to: redirect { |params, req|
    "/#{params[:forum_id]}/topics/new"
  }

  get "/forums/:forum_id/topics/:id/edit", to: redirect { |params, req|
    "/#{params[:forum_id]}/#{params[:id]}/edit"
  }

  get "/forums/:forum_id/topics/:id", to: redirect { |params, req|
    req.flash.keep
    "/#{params[:forum_id]}/#{params[:id]}"
  }

  get "/forums/:forum_id/topics/:id/subscribe", to: redirect { |params, req|
    "/#{params[:forum_id]}/#{params[:id]}/subscribe"
  }

  get "/forums/:forum_id/topics/:id/unsubscribe", to: redirect { |params, req|
    "/#{params[:forum_id]}/#{params[:id]}/unsubscribe"
  }

  get "/forums/:id", to: redirect { |params, req|
    req.flash.keep
    "/#{params[:id]}"
  }

  get "/forums", to: redirect("/")

  get "/topics/:topic_id/posts/:id/edit", to: redirect { |params, req|
    "/#{params[:topic_id]}/posts/#{params[:id]}/edit"
  }

  get "/topics/:topic_id/posts/new",
    to: "forem/posts#new",
    as: :new_topic_post

  get "/topics/:topic_id/posts/:id", to: redirect { |params, req|
    req.flash.keep
    "/#{params[:topic_id]}/posts/#{params[:id]}"
  }

  get "/:forum_id/:id",
    to: "forem/topics#show",
    as: :forum_topic

  get "/:forum_id/topics/new",
    to: "forem/topics#new",
    as: :new_forum_topic

  get "/:forum_id/:id/edit",
    to: "forem/topics#edit",
    as: :edit_forum_topic

  get "/:forum_id/:id/subscribe",
    to: "forem/topics#subscribe",
    as: :subscribe_forum_topic

  get "/:forum_id/:id/unsubscribe",
    to: "forem/topics#unsubscribe",
    as: :unsubscribe_forum_topic

  put "/:forum_id/:id",
    to: "forem/topics#update"

  delete "delete/topic/:id",
    to: "forem/topics#destroy",
    as: :delete_topic

  get "/:topic_id/posts/:id",
    to: "forem/posts#show",
    as: :topic_post

  get "/:topic_id/posts/:id/edit",
    to: "forem/posts#edit",
    as: :edit_topic_post

  put "/:topic_id/posts/:id",
    to: "forem/posts#update"

  delete "/:topic_id/posts/:id",
    to: "forem/posts#destroy",
    as: :delete_topic_post

  get "/categories/:id", to: redirect("/%{id}")

  # -------------------------------------------------

  # Pretty base URLs

  get "/:id",
    to: "forem/forums#show",
    as: :forum # Was: main_app.forum_path(@forum)

  get "/:id",
    to: "forem/forums#show",
    as: :category # Was: main_app.category_path(@category)

  # -------------------------------------------------

  # Give above routes higher priority

  # Subscriptions (Setup, Realtime Callbacks etc.,)

  resources :subscriptions, only: [:create]

  get 'instagram_callback' => 'realtime#get'
  post 'instagram_callback' => 'realtime#post'
  post 'twitter_stream' => 'realtime#twitter_stream'

  # ------------------------------------------------------------

  mount Forem::Engine, at: "/"
end

