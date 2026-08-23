module ApplicationHelper
  CANASTA_SORT_VALUES = Deck::CARD_VALUES.merge("jo" => 100, "2" => 99)

  HIGH_VIS_RANKS = { "10" => "T", "a" => "A", "j" => "J", "q" => "Q", "k" => "K" }.freeze

  # Filename stem (relative to "cards/") for a card code like "h10" or "jo".
  # Normal deck files are keyed suit-first/lowercase (h10.svg, joker_black.svg);
  # the high-vis deck's files are rank-first/uppercase with a single joker
  # (high_vis_cards/TH.svg, high_vis_cards/1J.svg) — hence the reshuffle here
  # rather than just swapping a directory prefix.
  def card_asset(card)
    return card if card == "blank_card"
    return current_user&.high_vis_fronts? ? "high_vis_cards/1J" : "joker_black" if card == "jo"
    return card unless current_user&.high_vis_fronts?

    suit = card[0].upcase
    rank = HIGH_VIS_RANKS[card[1..-1]] || card[1..-1].upcase
    "high_vis_cards/#{rank}#{suit}"
  end

  # Tie-broken by each card's original position in `hand` (not just rank), so
  # a freshly-drawn card sharing a rank with a card already in hand always
  # sorts after it, never before or between existing same-rank cards. That
  # keeps existing cards' left-to-right order stable across a draw — which
  # canasta_cards.js's persisted-selection restore depends on (it identifies
  # a selected card by "<code>#<nth occurrence of that code>", so if drawing
  # reshuffled the occurrence order, the wrong card could end up reselected).
  def canasta_sort(hand)
    (hand || []).each_with_index.sort_by do |card, idx|
      rank = card == "jo" ? "jo" : card[1..-1].downcase
      [CANASTA_SORT_VALUES[rank] || 0, idx]
    end.map(&:first)
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

  SEVEN_RANK_KEYS = LuckySeven::RANK_VALUES.invert.freeze

  # Card code for a slot on a Lucky Seven run, e.g. ("d", 12) => "dq".
  def seven_card_code(suit, value)
    "#{suit}#{SEVEN_RANK_KEYS[value]}"
  end

  def seven_rank_label(value)
    SEVEN_RANK_KEYS[value].upcase
  end

  def build_version
    Rails.application.config.build_version
  end
end
