class Deck < ApplicationRecord
  belongs_to :game

  SUITS = ['Hearts', 'Diamonds', 'Clubs', 'Spades']
  RANKS = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A']

  store_accessor :cards

  def initialize_deck(deck_count: 1)
    self.cards = []
    deck_count.times do
      SUITS.each do |suit|
        RANKS.each do |rank|
          self.cards << { suit: suit, rank: rank }
        end
      end
    end
    save
  end

  def shuffle
    self.cards.shuffle!
    save
  end

  def deal
    card = self.cards.pop
    save
    card
  end
end
