#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

typeset -r APP_DIR="/home/brgen/app"

echo "==> [routes] Rails routes"
cd "$APP_DIR"

cat > config/routes.rb << 'RUBY'
Rails.application.routes.draw do
  devise_for :users

  resources :communities, only: [:index, :show] do
    resources :posts, shallow: true
  end

  resources :posts do
    resources :comments, only: [:create, :destroy]

    member do
      post :upvote
      post :downvote
    end
  end

  resources :votes, only: [:create, :destroy]
  root "communities#index"
end
RUBY

echo "==> [routes] done"
