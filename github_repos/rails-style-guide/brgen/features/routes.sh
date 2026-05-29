#!/usr/bin/env sh
set -euo pipefail

readonly APP_DIR="/home/brgen/app"
readonly ROUTES_FILE="${APP_DIR}/config/routes.rb"
# Create temporary file in the same directory to guarantee atomic rename
readonly TMP_FILE="$(mktemp -p "${APP_DIR}" routes.rb.tmp.XXXXXX)"

# Ensure temporary file is removed on any exit
trap 'rm -f "$TMP_FILE"' EXIT

# Verify application directory exists and is writable
if [ ! -d "$APP_DIR" ]; then
  printf 'Error: %s does not exist\n' "$APP_DIR" >&2
  exit 1
fi
if [ ! -w "$APP_DIR" ]; then
  printf 'Error: %s is not writable\n' "$APP_DIR" >&2
  exit 1
fi

printf '==> [routes] Wiring all routes\n'

cat >"$TMP_FILE" <<'RUBY'
Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token

  resources :communities do
    resources :posts, shallow: true do
      resources :comments, shallow: true do
        resources :comments, shallow: true, as: :replies
      end
      resource :vote, only: [:create], controller: "votes"
    end
  end

  resources :posts do
    resources :comments, shallow: true
    resource :vote, only: [:create], controller: "votes"
  end

  resources :comments do
    resource :vote, only: [:create], controller: "votes"
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

# Atomically replace the routes file
mv -f "$TMP_FILE" "$ROUTES_FILE"

printf '==> [routes] done\n'
