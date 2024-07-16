class Game < ApplicationRecord
  has_many :players, dependent: :destroy
  has_many :users, through: :players

  def start_game
    player_ids = players.pluck(:id)

    self.update(turn_order: player_ids.shuffle)

    self.update(current_turn: self.turn_order.first)
    self.players.find(self.current_turn).update(is_turn: true)
  end

  def take_turn
    current_player = players.find(current_turn)
    current_player.update(is_turn: false)

    next_player_index = turn_order.index(current_turn) + 1
    next_player_index = 0 if next_player_index == turn_order.length

    self.update(current_turn: turn_order[next_player_index])
    players.find(current_turn).update(is_turn: true)
  end
end
