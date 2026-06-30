class Deck < ApplicationRecord
  belongs_to :game

  DECK = [ 'ha', 'h2', 'h3', 'h4', 'h5', 'h6', 'h7', 'h8', 'h9', 'h10', 'hj', 'hq', 'hk',
           'sa', 's2', 's3', 's4', 's5', 's6', 's7', 's8', 's9', 's10', 'sj', 'sq', 'sk',
           'da', 'd2', 'd3', 'd4', 'd5', 'd6', 'd7', 'd8', 'd9', 'd10', 'dj', 'dq', 'dk',
           'ca', 'c2', 'c3', 'c4', 'c5', 'c6', 'c7', 'c8', 'c9', 'c10', 'cj', 'cq', 'ck' ]

  CARD_VALUES = {
    "2" => 2, "3" => 3, "4" => 4, "5" => 5, "6" => 6, "7" => 7,
    "8" => 8, "9" => 9, "10" => 10, "j" => 11, "q" => 12, "k" => 13, "a" => 14
  }

  before_create :initialize_deck

  def initialize_deck(deck_count: 1, joker_count: 0)
    self.cards = []
    deck_count.times do
      self.cards.concat(DECK)
      joker_count.times { self.cards << "jo" }
    end
    shuffle
  end

  def shuffle
    self.cards.shuffle!
  end

  def deal
    players = game.players.to_a 
    hands = Hash.new { |hash, key| hash[key] = [] } 
    
    while cards.any?
      players.each do |player|
        hands[player.id] << cards.pop if cards.any?
      end
    end
  
    Player.transaction do
      hands.each do |player_id, hand_cards|
        hand_jsonb = sort_cards(hand_cards).to_json
        Player.where(id: player_id).update_all(["hand = ?::jsonb", hand_jsonb])
      end
    end
  end

  def card_rank(card)
    rank = card[1..-1] 
    CARD_VALUES[rank.downcase] || 0 
  end
  
  def sort_cards(cards)
  sorted_cards = cards.sort_by { |card| card_rank(card) }
  grouped_cards = sorted_cards.group_by { |card| card[1] }
  grouped_cards.values
  end
end
