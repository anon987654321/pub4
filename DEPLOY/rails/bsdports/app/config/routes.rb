Rails.application.routes.draw do
  resource  :session
  resources :passwords, param: :token

  root "ports#index"

  resources :categories, only: %i[index show]

  resources :ports, only: %i[index show] do
    member do
      post   :watch
      delete :unwatch
    end
    resources :comments, only: %i[create destroy]
  end

  get "up", to: "rails/health#show", as: :rails_health_check
end
