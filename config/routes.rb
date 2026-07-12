Rails.application.routes.draw do
  devise_for :users, controllers: {
    registrations: 'users/registrations'
  }
  patch 'profile/name', to: 'profiles#update_name', as: :update_name
  patch 'profile/card_back', to: 'profiles#update_card_back', as: :update_card_back
  patch 'profile/high_vis_fronts', to: 'profiles#update_high_vis_fronts', as: :update_high_vis_fronts

  resources :games

  resources :games do
    member do
      post 'join'
      post 'start'
      post 'set_team'
      post 'take_turn'
      post 'play_cards'
      post 'pass'
      patch 'update_settings'
      post 'start_round'
      post 'give_cards'
      post 'draw'
      post 'play_red_three'
      post 'draw_red_three_replacement'
      post 'pickup_discard'
      post 'discard'
      post 'meld'
      post 'undo_meld'
      post 'advance_round'
    end
  end  

  resources :bugs, only: [:index, :create, :update]
  resources :stats, only: [:index]
  resource :sound_settings, only: [:edit, :update]

  get "up" => "rails/health#show", as: :rails_health_check

  root "games#index"
end
