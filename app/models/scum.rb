class Scum < ApplicationRecord
  belongs_to :game
  store_accessor :game_state, :deck, :hands, :last_played_by, :last_played_cards

  after_create :initialize_state

  def initialize_state
    self.game_state = {
      deck: deck,
      hands: {},
      last_played_by: nil,
      last_played_cards: nil,
    }

    create_hands
    save!
  end

  def create_hands
    deck = Deck.new(game: game)
    deck.initialize_deck # add deck_count: i if you want to use multiple decks
    deck.deal
  end
end
