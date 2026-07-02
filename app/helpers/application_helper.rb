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
end
