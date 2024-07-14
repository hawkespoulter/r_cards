Rails.application.routes.draw do
  devise_for :users
  resources :games

  get "up" => "rails/health#show", as: :rails_health_check

  root "games#index"
end
