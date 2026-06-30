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
      post 'draw'
      post 'pickup_discard'
      post 'discard'
      post 'meld'
    end
  end  

  resources :bugs, only: [:index, :create, :update]

  get "up" => "rails/health#show", as: :rails_health_check

  root "games#index"
end
