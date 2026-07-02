class Game < ApplicationRecord
  has_many :players, dependent: :destroy
  has_many :decks, dependent: :destroy
  has_one :scum, dependent: :destroy
  has_one :canasta, dependent: :destroy
  has_many :users, through: :players

  enum game_type: { scum: 0, canasta: 1, lucky_seven: 2 }

  store_accessor :settings, :pass_locks_out, :leader_can_continue, :florida_rules, :card_back

  CARD_BACKS = {
    "hawkes_sam_blue"  => "Hawkes + Sam Blue",
    "hawkes_sam_red"   => "Hawkes + Sam Red",
    "gabbitas_blue"    => "Gabbitas Blue",
    "gabbitas_green"   => "Gabbitas Green",
    "gabbitas_red"     => "Gabbitas Red",
    "fifes_purple"     => "Fifes Purple",
    "fifes_yellow"     => "Fifes Yellow",
    "dad"              => "Dad",
    "mom"              => "Mom",
    "sicily"           => "Sicily"
  }.freeze

  def card_back_key
    card_back.presence || "hawkes_sam_blue"
  end

  def pass_locks_out?
    pass_locks_out == true || pass_locks_out == "true" || pass_locks_out == "1"
  end

  def leader_can_continue?
    leader_can_continue == true || leader_can_continue == "true" || leader_can_continue == "1"
  end

  def florida_rules?
    florida_rules == true || florida_rules == "true" || florida_rules == "1"
  end

  def start_game
    if scum?
      initialize_scum_game_state
      player_ids = players.pluck(:id)

      self.update(turn_order: player_ids.shuffle)

      self.update(current_turn: self.turn_order.first)
      self.players.find(self.current_turn).update(is_turn: true)
    elsif canasta?
      assign_canasta_teams
      initialize_canasta_game_state
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

  def assign_canasta_teams
    seated = players.order(:created_at).to_a
    seated.each_with_index { |player, i| player.update!(team: i % 2) }
  end

  def initialize_canasta_game_state
    Canasta.create(game: self).initialize_round
  end

  def update_current_turn(player_id)
    update(current_turn: player_id)
  end
end
