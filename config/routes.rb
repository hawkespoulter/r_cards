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
      post 'play_cards'
      post 'pass'
      patch 'update_settings'
      post 'leave'
      post 'start_round'
      post 'give_cards'
    end
  end  

  get "up" => "rails/health#show", as: :rails_health_check

  root "games#index"
end
