class Scum < ApplicationRecord
  belongs_to :game
  store_accessor :game_state, :turn_order, :current_turn, :deck, :hands,
                             :last_played_by, :last_played_cards

  after_initialize :initialize_state

  def initialize_state
    self.game_state = {
      turn_order: [],
      current_turn: nil,
      deck: nil,
      hands: initialize_hands(),
      last_played_by: nil,
      last_played_cards: nil,
    }
  end

  def initialize_hands
    hands = {}
    game.players.each do |player|
      hands[player.id] = initial_hand_for_player(player)
    end
    hands
  end

  def initial_hand_for_player(player)
    # Define your logic here to initialize the initial hand for each player
    # For example, you might generate a random hand or initialize with specific cards
    # Here's a basic example:
    Array.new(5) { generate_random_card }  # Replace generate_random_card with your logic
  end

  def generate_random_card
    # Replace this with your actual logic to generate a random card
    ['Ace', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'Jack', 'Queen', 'King'].sample
  end
end
