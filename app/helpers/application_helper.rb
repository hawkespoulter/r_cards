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
end
