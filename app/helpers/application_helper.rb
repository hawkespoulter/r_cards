module ApplicationHelper
  CANASTA_SORT_VALUES = Deck::CARD_VALUES.merge("jo" => 100, "2" => 99)

  def canasta_card_asset(card)
    card == "jo" ? "joker_black" : card
  end

  def canasta_sort(hand)
    (hand || []).sort_by do |card|
      rank = card == "jo" ? "jo" : card[1..-1].downcase
      CANASTA_SORT_VALUES[rank] || 0
    end
  end

  # Single representative card for a completed canasta display.
  # Clean → red-suited natural; Dirty → black-suited natural, else wild.
  def canasta_representative_card(rank, cards)
    wilds    = cards.select { |c| c == "jo" || c[1..-1]&.downcase == "2" }
    naturals = cards - wilds
    if wilds.empty?
      naturals.find { |c| %w[h d].include?(c[0]) } || naturals.first
    else
      naturals.find { |c| %w[s c].include?(c[0]) } || wilds.first
    end
  end

  def canasta_clean?(cards)
    cards.none? { |c| c == "jo" || c[1..-1]&.downcase == "2" }
  end

  def sort_melds(melds)
    melds.sort_by { |rank, _| CANASTA_SORT_VALUES[rank.downcase] || 0 }.to_h
  end

  RANK_DISPLAY = { "a" => "A", "j" => "J", "q" => "Q", "k" => "K" }.freeze

  # Display label for a meld's rank in the hover overlay, e.g. "Q" or "8".
  def meld_rank_display(rank)
    RANK_DISPLAY[rank.to_s.downcase] || rank.to_s.upcase
  end

  # How many wild cards (2s and jokers) are in a meld, for the hover overlay.
  def meld_wild_count(cards)
    cards.count { |c| c == "jo" || c[1..-1]&.downcase == "2" }
  end
end
