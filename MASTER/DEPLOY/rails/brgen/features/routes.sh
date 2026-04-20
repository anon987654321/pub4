#!/usr/bin/env zsh
emulate -L zshsetopt err_return no_unset pipe_fail extended_glob warn_create_global

APP_DIR="/home/brgen/app"
ROUTES_FILE="$APP_DIR/config/routes.rb"

# Fail fast if the app directory is missing
if [[ ! -d "$APP_DIR" ]]; then
  print "Error: $APP_DIR does not exist" >&2
  exit 1
fi

print "==> [routes] Wiring all routes"

# Write routes.rb using a heredoc with literal delimiter
cat > "$ROUTES_FILE" <<'RUBY'
Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token

  resources :communities do    resources :posts, shallow: true do      resources :comments, shallow: true do        resources :comments, shallow: true, as: :replies
      end
      resource :vote, only: [:create], controller: "votes"
    end
  end  resources :posts do
    resources :comments, shallow: true
    resource :vote, only: [:create], controller: "votes"
  end

  resources :comments do    resource :vote, only: [:create], controller: "votes"
    resources :comments, only: [:create], as: :replies
  end

  resources :users, only: [:show] do
    member do
      post :follow, to: "follows#create"
      delete :unfollow, to: "follows#destroy"
    end
    resources :conversations, only: [:create]
  end

  resources :conversations, only: [:index, :show] do
    resources :messages, only: [:create]
  end

  get "playlist", to: "playlist#index"
  root "home#index"
  get "up" => "rails/health#show", as: :rails_health_check
end
RUBY

print "==> [routes] done"