class Game < ApplicationRecord
  has_many :players, dependent: :destroy
  has_many :decks, dependent: :destroy
  has_one :scum, dependent: :destroy
  has_many :users, through: :players

  enum game_type: { scum: 0, canasta: 1, lucky_seven: 2 }

  def start_game
    if scum?
      initialize_scum_game_state
      player_ids = players.pluck(:id)

      self.update(turn_order: player_ids.shuffle)

      self.update(current_turn: self.turn_order.first)
      self.players.find(self.current_turn).update(is_turn: true)
    end
  end

  def take_turn
    current_player = players.find(current_turn)
    current_player.update(is_turn: false)

    next_player_index = turn_order.index(current_turn) + 1
    next_player_index = 0 if next_player_index == turn_order.length

    self.update(current_turn: turn_order[next_player_index])
    players.find(current_turn).update(is_turn: true)
  end

  private 

  def initialize_scum_game_state
    Scum.create(game: self)
  end

  def update_current_turn(player_id)
    update(current_turn: player_id)
  end
end
