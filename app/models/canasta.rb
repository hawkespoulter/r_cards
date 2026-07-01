class Canasta < ApplicationRecord
  self.table_name = "canastas"

  belongs_to :game

  RANK_VALUES = Deck::CARD_VALUES

  store_accessor :game_state,
    :draw_pile,       # Array of card codes (stock)
    :discard_pile,    # Array of card codes, last element = top
    :frozen,          # Boolean - whether the discard pile requires a natural pair to pick up
    :melds,           # { "0" => { rank => [cards...] }, "1" => { rank => [cards...] } }
    :turn_phase,       # "draw" or "discard"
    :round_number,
    :team_scores,      # { "0" => Integer, "1" => Integer } cumulative across rounds
    :round_scores,     # { "0" => Integer, "1" => Integer } this round's running tally (display only until scored)
    :red_threes,       # { "0" => [cards...], "1" => [cards...] } collected red 3s per team
    :last_draw,        # { "player_id" => Integer, "cards" => [...], "seq" => Integer } - last draw, for the "you got these cards" popup
    :peak_hands,       # { "player_id" => [cards] } - face-down foot pile; nil once picked up (auto on first canasta)
    :foot_pickups,     # { "player_id" => { "cards" => [...], "seq" => N } } - cleared after client sees it
    :last_canasta      # { "rank" => rank, "seq" => N } - last completed canasta, for acting-player notification

  MELD_THRESHOLDS = [
    [3000, 50],
    [5000, 70],
    [7000, 90],
    [9000, 110],
    [Float::INFINITY, 130]
  ].freeze

  CANASTA_SIZE = 7
  GOAL_SCORE = 10_000

  # --- Setup ---

  def initialize_round
    florida    = game.florida_rules?
    hand_size  = 13
    peak_size  = florida ? 15 : 11
    jokers     = florida ? 3 : 2

    deck = game.decks.create
    deck.initialize_deck(deck_count: 3, joker_count: jokers)
    shoe = deck.cards.dup

    players = game.players.order(:created_at).to_a
    collected_red_threes = { "0" => [], "1" => [] }
    dealt_peak_hands = {}

    players.each do |player|
      hand = deal_n_naturals(shoe, hand_size, collected_red_threes, player.team.to_s)
      peak = deal_n_naturals(shoe, peak_size, collected_red_threes, player.team.to_s)
      player.update!(hand: hand)
      dealt_peak_hands[player.id.to_s] = peak
    end

    discard_top = nil
    loop do
      card = shoe.pop
      if red_three?(card)
        next # set aside, doesn't score - just keeps the deck moving
      end
      discard_top = card
      break
    end

    write_game_state!(
      "draw_pile"      => shoe,
      "discard_pile"   => [discard_top],
      "frozen"         => true,
      "melds"          => { "0" => {}, "1" => {} },
      "turn_phase"     => "draw",
      "round_number"   => (round_number || 0) + 1,
      "team_scores"    => team_scores || { "0" => 0, "1" => 0 },
      "round_scores"   => { "0" => 0, "1" => 0 },
      "red_threes"     => collected_red_threes,
      "peak_hands"     => dealt_peak_hands
    )

    game.players.update_all(is_turn: false)
    starter = players[(round_number.to_i - 1) % players.length]
    game.update!(current_turn: starter.id, turn_order: players.map(&:id))
    starter.update!(is_turn: true)
  end

  # --- Public actions ---

  def draw(player)
    return { error: "Not your turn" } unless game.current_turn == player.id
    return { error: "Game is over" } if game_over?
    return { error: "You must discard before drawing again" } unless turn_phase == "draw"

    pile = draw_pile.dup
    reshuffle_stock!(pile) if pile.empty?
    pile = draw_pile.dup

    hand = player.hand.dup
    drawn_cards = []
    2.times do
      loop do
        if pile.empty?
          reshuffle_stock!(pile)
          pile = draw_pile.dup
        end
        return { error: "No cards left to draw" } if pile.empty?
        card = pile.pop
        if red_three?(card)
          log_red_three!(player.team, card)
          next
        end
        drawn_cards << card
        break
      end
    end

    hand.concat(drawn_cards)
    player.update!(hand: hand)
    next_seq = (last_draw || {})["seq"].to_i + 1
    write_game_state!(
      "draw_pile" => pile,
      "turn_phase" => "discard",
      "last_draw" => { "player_id" => player.id, "cards" => drawn_cards, "seq" => next_seq }
    )
    { success: true, drawn_cards: drawn_cards }
  end

  def pickup_discard(player, meld_cards)
    return { error: "Not your turn" } unless game.current_turn == player.id
    return { error: "Game is over" } if game_over?
    return { error: "You must discard before drawing again" } unless turn_phase == "draw"

    pile = discard_pile.dup
    return { error: "Discard pile is empty" } if pile.empty?

    top = pile.last
    return { error: "Black threes cannot be picked up" } if black_three?(top)

    rank = rank_of(top)
    hand = player.hand.dup
    meld_cards = Array(meld_cards)

    return { error: "Select matching cards from your hand to pick up the pile" } if meld_cards.empty?
    return { error: "Invalid cards selected" } unless meld_cards.all? { |c| hand.include?(c) }
    return { error: "Cards used to pick up must be natural cards matching the pile's rank" } \
      unless meld_cards.all? { |c| !wild?(c) && rank_of(c) == rank }

    team_melds   = (melds[player.team.to_s] || {})
    has_existing = team_melds[rank].present?

    if frozen
      return { error: "The pile is frozen - need 2 matching natural cards to pick it up" } if meld_cards.length < 2
    else
      return { error: "Need a matching card, or an existing meld of that rank, to pick up" } \
        if meld_cards.empty? || (meld_cards.length < 1 && !has_existing)
    end

    remaining_hand = hand.dup
    meld_cards.each { |c| remaining_hand.delete_at(remaining_hand.index(c)) }

    # Only natural cards of the matching rank from the pile go into the meld.
    # Everything else (other ranks, wilds in the pile) goes into the hand.
    pile_for_meld = pile.select { |c| !wild?(c) && rank_of(c) == rank }
    pile_to_hand  = pile.reject { |c| !wild?(c) && rank_of(c) == rank }
    remaining_hand.concat(pile_to_hand)
    player.update!(hand: remaining_hand)

    result = add_to_meld(player.team, rank, meld_cards + pile_for_meld)
    write_game_state!("discard_pile" => [], "turn_phase" => "discard", "frozen" => false)
    result.merge(success: true)
  end

  def meld(player, cards)
    return { error: "Not your turn" } unless game.current_turn == player.id
    return { error: "Game is over" } if game_over?
    return { error: "Draw or pick up a card before melding" } unless turn_phase == "discard"
    return { error: "No cards selected" } if cards.empty?

    hand = player.hand.dup
    return { error: "Invalid cards" } unless cards.all? { |c| hand.include?(c) }

    naturals = cards.reject { |c| wild?(c) }
    wilds    = cards.select { |c| wild?(c) }
    return { error: "Need at least one natural card" } if naturals.empty?
    return { error: "Threes cannot be melded" } if naturals.any? { |c| rank_of(c) == "3" }

    ranks = naturals.map { |c| rank_of(c) }.uniq
    return { error: "All natural cards must be the same rank" } unless ranks.length == 1
    rank = ranks.first

    team_melds = (melds[player.team.to_s] || {}).dup
    existing   = team_melds[rank] || []

    return { error: "Need at least 3 cards to start a new meld" } if existing.empty? && cards.length < 3

    total_wild    = existing.count { |c| wild?(c) } + wilds.length
    total_natural = existing.count { |c| !wild?(c) } + naturals.length
    return { error: "A meld cannot contain more wild cards than natural cards" } if total_wild > total_natural

    team_has_melded = team_melds.values.any?(&:present?)
    unless team_has_melded
      total_points = cards.sum { |c| card_points(c) }
      threshold    = meld_threshold(player.team)
      return { error: "Initial meld must total at least #{threshold} points (selected: #{total_points})" } \
        if total_points < threshold
    end

    remaining_hand = hand.dup
    cards.each { |c| remaining_hand.delete_at(remaining_hand.index(c)) }
    player.update!(hand: remaining_hand)

    result = add_to_meld(player.team, rank, cards)
    result.merge(success: true)
  end

  def discard(player, card)
    return { error: "Not your turn" } unless game.current_turn == player.id
    return { error: "Game is over" } if game_over?
    return { error: "Draw or pick up a card before discarding" } unless turn_phase == "discard"

    hand = player.hand.dup
    return { error: "Card not in hand" } unless hand.include?(card)

    going_out = hand.length == 1
    if going_out && !can_go_out?(player.team)
      return { error: "Cannot go out yet - your team needs at least 5 canastas, including 1 clean" }
    end

    hand.delete_at(hand.index(card))
    player.update!(hand: hand)

    new_frozen = frozen || wild?(card)
    write_game_state!("discard_pile" => discard_pile + [card], "frozen" => new_frozen)

    team_str = player.team.to_s
    team_has_canasta = (melds[team_str] || {}).values.any? { |c| c.length >= CANASTA_SIZE }
    team_peak_pending = (peak_hands || {}).key?(player.id.to_s)
    pickup_peak_hands!(player.team) if team_has_canasta && team_peak_pending

    if going_out
      result = end_round!(going_out_team: player.team)
      { success: true, round_ended: true }.merge(result)
    else
      write_game_state!("turn_phase" => "draw")
      game.take_turn
      { success: true }
    end
  end

  def game_over?
    (team_scores || {}).values.any? { |v| v.to_i >= GOAL_SCORE }
  end

  def winning_team
    return nil unless game_over?
    (team_scores || {}).max_by { |_team, score| score }&.first
  end

  # --- Private ---

  private

  def write_game_state!(changes)
    merged = (game_state || {}).merge(changes)
    update!(game_state: merged)
  end

  def reshuffle_stock!(pile)
    return unless pile.empty?
    keep_top = discard_pile.last
    rest     = discard_pile[0..-2] || []
    return if rest.empty?
    write_game_state!("draw_pile" => rest.shuffle, "discard_pile" => [keep_top].compact)
  end

  def log_red_three!(team, card)
    log = (red_threes || {}).dup
    log[team.to_s] = (log[team.to_s] || []) + [card]
    write_game_state!("red_threes" => log)
  end

  def add_to_meld(team, rank, cards)
    team_melds = (melds[team.to_s] || {}).dup
    team_melds[rank] = (team_melds[rank] || []) + cards

    all_melds = (melds || {}).dup
    all_melds[team.to_s] = team_melds
    write_game_state!("melds" => all_melds)

    completed_canasta = team_melds[rank].length >= CANASTA_SIZE && (team_melds[rank].length - cards.length) < CANASTA_SIZE
    if completed_canasta
      next_seq = (last_canasta || {})["seq"].to_i + 1
      write_game_state!("last_canasta" => { "rank" => rank, "seq" => next_seq })
    end
    { canasta_completed: completed_canasta, canasta_rank: completed_canasta ? rank : nil }
  end

  def meld_threshold(team)
    score = (team_scores || {})[team.to_s].to_i
    MELD_THRESHOLDS.find { |max, _threshold| score < max }.last
  end

  def can_go_out?(team)
    team_melds = melds[team.to_s] || {}
    canastas   = team_melds.values.select { |cards| cards.length >= CANASTA_SIZE }
    canastas.length >= 5 && canastas.any? { |cards| cards.none? { |c| wild?(c) } }
  end

  def end_round!(going_out_team:)
    new_team_scores  = (team_scores || { "0" => 0, "1" => 0 }).dup
    new_round_scores = {}

    %w[0 1].each do |team|
      team_melds   = melds[team] || {}
      meld_points  = team_melds.values.flatten.sum { |c| card_points(c) }
      canasta_bonus = team_melds.values.sum do |cards|
        next 0 unless cards.length >= CANASTA_SIZE
        cards.none? { |c| wild?(c) } ? 500 : 300
      end
      red_three_bonus = (red_threes[team] || []).length * 100
      going_out_bonus = team == going_out_team.to_s ? 100 : 0

      team_player_ids = game.players.where(team: team.to_i).pluck(:id)
      hand_penalty = game.players.where(id: team_player_ids).sum do |p|
        p.hand.sum { |c| card_points(c) }
      end

      round_score = meld_points + canasta_bonus + red_three_bonus + going_out_bonus - hand_penalty
      new_round_scores[team] = round_score
      new_team_scores[team]  = new_team_scores[team].to_i + round_score
    end

    write_game_state!("team_scores" => new_team_scores, "round_scores" => new_round_scores)

    if game_over?
      { game_over: true, winning_team: winning_team }
    else
      initialize_round
      { next_round: true }
    end
  end

  def deal_n_naturals(shoe, n, collected_red_threes, team_str)
    cards = []
    while cards.length < n
      card = shoe.pop
      if red_three?(card)
        collected_red_threes[team_str] << card
        next
      end
      cards << card
    end
    cards
  end

  def pickup_peak_hands!(team)
    current_peak = (peak_hands || {}).dup
    new_foot_pickups = (foot_pickups || {}).dup
    next_seq = new_foot_pickups.values.map { |fp| fp["seq"].to_i }.max.to_i + 1

    game.players.where(team: team.to_i).each do |player|
      foot = current_peak.delete(player.id.to_s)
      next unless foot.present?
      player.update!(hand: (player.hand || []) + foot)
      new_foot_pickups[player.id.to_s] = { "cards" => foot, "seq" => next_seq }
    end
    write_game_state!("peak_hands" => current_peak, "foot_pickups" => new_foot_pickups)
  end

  def wild?(card)
    card == "jo" || rank_of(card) == "2"
  end

  def red_three?(card)
    rank_of(card) == "3" && %w[h d].include?(card[0])
  end

  def black_three?(card)
    rank_of(card) == "3" && %w[s c].include?(card[0])
  end

  def rank_of(card)
    return "jo" if card == "jo"
    card[1..-1].downcase
  end

  def card_points(card)
    return 50 if card == "jo"
    rank = rank_of(card)
    return 20 if %w[2 a].include?(rank)
    rank_value = RANK_VALUES[rank] || 0
    rank_value >= 9 ? 10 : 5
  end
end
