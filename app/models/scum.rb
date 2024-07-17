class Scum < ApplicationRecord
  belongs_to :game
  store_accessor :game_state
  has_many :players, through: :game
  has_many :users, through: :players
  has_many :decks

  def initialize_state
    self.game_state = {
      turn_order: [game.turn_order],
      current_turn: nil,
      deck: nil,
      hands: {},
      last_play: nil,
      last_played: nil,
      last_played_by: nil,
      last_played_to: nil,
      last_played_cards: nil,
    }
  end
end
