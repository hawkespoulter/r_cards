Rails.application.routes.draw do
  devise_for :users, controllers: {
    registrations: 'users/registrations'
  }
  resources :games

  resources :games do
    member do
      post 'join'
      post 'start'
      post 'take_turn'
    end
  end  

  get "up" => "rails/health#show", as: :rails_health_check

  root "games#index"
end
