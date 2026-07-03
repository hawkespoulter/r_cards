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
    :last_pickup,      # { "player_id" => Integer, "cards" => [...], "seq" => Integer } - last discard pile pickup, for the "you picked up these cards" popup
    :peak_hands,       # { "player_id" => [cards] } - face-down foot pile; nil once picked up (auto on first canasta)
    :foot_pickups,     # { "player_id" => { "cards" => [...], "seq" => N } } - cleared after client sees it
    :last_canasta,     # { "rank" => rank, "seq" => N } - last completed canasta, for acting-player notification
    :pending_red_three_draws, # { "player_id" => Integer } - replacement draws owed for played red threes, not yet claimed
    :turn_meld_log,    # [{ "rank" => rank, "cards" => [...] }, ...] - this turn's meld additions, for undo; reset on draw/pickup/discard
    :round_summary,    # full scoring breakdown for the round that just ended; blocks the table until the host advances (see #advance_round)
    :round_history     # [{ "round_number", "going_out_team", "teams" => { "0"/"1" => { "round_score", "base_score", "card_count", "new_total" } } }, ...] - one compact entry per completed round, for the round-by-round score popup

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
    dealt_peak_hands = {}

    # Red threes deal straight into the hand/peak hand like any other card —
    # they're not auto-collected; the player has to play them manually (same
    # as red threes drawn mid-game) to bank the bonus and draw a replacement.
    players.each do |player|
      hand = Array.new(hand_size) { shoe.pop }
      peak = Array.new(peak_size) { shoe.pop }
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
      "red_threes"     => { "0" => [], "1" => [] },
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
      if pile.empty?
        reshuffle_stock!(pile)
        pile = draw_pile.dup
      end
      return { error: "No cards left to draw" } if pile.empty?
      drawn_cards << pile.pop
    end

    hand.concat(drawn_cards)
    player.update!(hand: hand)
    next_seq = (last_draw || {})["seq"].to_i + 1
    write_game_state!(
      "draw_pile" => pile,
      "turn_phase" => "discard",
      "turn_meld_log" => [],
      "last_draw" => {
        "player_id" => player.id,
        "cards" => drawn_cards,
        "seq" => next_seq
      }
    )
    { success: true, drawn_cards: drawn_cards }
  end

  # Playing a red three from hand is not gated by whose turn it is — a red
  # three can surface in your hand off-turn (e.g. left over from an earlier
  # draw) and you should still be able to play it any time. It queues up a
  # replacement draw rather than drawing immediately — the player has to
  # click the stock pile themselves to claim it (see draw_red_three_replacement).
  def play_red_three(player, card)
    return { error: "Game is over" } if game_over?

    hand = player.hand.dup
    return { error: "Card not in hand" } unless hand.include?(card)
    return { error: "Not a red three" } unless red_three?(card)

    hand.delete_at(hand.index(card))
    player.update!(hand: hand)
    log_red_three!(player.team, card)

    pending = (pending_red_three_draws || {}).dup
    pending[player.id.to_s] = pending[player.id.to_s].to_i + 1
    write_game_state!("pending_red_three_draws" => pending)

    { success: true }
  end

  # Claims one replacement card owed for a previously played red three. Like
  # play_red_three, this is not gated by whose turn it is.
  def draw_red_three_replacement(player)
    return { error: "Game is over" } if game_over?

    owed = (pending_red_three_draws || {})[player.id.to_s].to_i
    return { error: "No red three replacement owed" } if owed <= 0

    pile = draw_pile.dup
    reshuffle_stock!(pile) if pile.empty?
    pile = draw_pile.dup
    return { error: "No cards left to draw" } if pile.empty?

    card = pile.pop
    hand = player.hand.dup << card
    player.update!(hand: hand)

    pending = (pending_red_three_draws || {}).dup
    if owed - 1 <= 0
      pending.delete(player.id.to_s)
    else
      pending[player.id.to_s] = owed - 1
    end

    next_seq = (last_draw || {})["seq"].to_i + 1
    write_game_state!(
      "draw_pile" => pile,
      "pending_red_three_draws" => pending,
      "last_draw" => { "player_id" => player.id, "cards" => [card], "seq" => next_seq }
    )
    { success: true, drawn_card: card }
  end

  def pickup_discard(player)
    return { error: "Not your turn" } unless game.current_turn == player.id
    return { error: "Game is over" } if game_over?
    return { error: "You must discard before drawing again" } unless turn_phase == "draw"

    pile = discard_pile.dup
    return { error: "Discard pile is empty" } if pile.empty?
    return { error: "Your team must make its first meld before picking up the pile" } unless team_melded?(player.team)

    top = pile.last
    return { error: "Black threes cannot be picked up" } if black_three?(top)

    rank = rank_of(top)
    existing_meld = (melds[player.team.to_s] || {})[rank] || []
    return { error: "Your #{rank}s meld already has 5 or more cards — can't pick up the pile for it" } if existing_meld.length >= 5

    hand = player.hand.dup
    natural_count = hand.count { |c| !wild?(c) && rank_of(c) == rank }
    return { error: "Need 2 matching natural cards in hand to pick up the pile" } if natural_count < 2

    player.update!(hand: hand + pile)
    next_seq = (last_pickup || {})["seq"].to_i + 1
    write_game_state!(
      "discard_pile" => [],
      "turn_phase" => "discard",
      "frozen" => false,
      "turn_meld_log" => [],
      "last_pickup" => { "player_id" => player.id, "cards" => pile, "seq" => next_seq }
    )
    { success: true, canasta_completed: false, canasta_rank: nil, pickup_cards: pile, pickup_seq: next_seq }
  end

  def meld(player, cards, target_rank: nil)
    return { error: "Not your turn" } unless game.current_turn == player.id
    return { error: "Game is over" } if game_over?
    return { error: "Draw or pick up a card before melding" } unless turn_phase == "discard"
    return { error: "No cards selected" } if cards.empty?

    hand = player.hand.dup
    return { error: "Invalid cards" } unless cards.all? { |c| hand.include?(c) }

    naturals_all = cards.reject { |c| wild?(c) }
    return { error: "Threes cannot be melded" } if naturals_all.any? { |c| rank_of(c) == "3" }

    team_melds = (melds[player.team.to_s] || {}).dup
    team_has_melded = team_melds.values.any?(&:present?)

    if naturals_all.empty?
      # Pure-wild selection — only valid as an addition to an existing meld,
      # since there's no natural card to infer which rank group it belongs to.
      return { error: "Need at least one natural card" } if target_rank.nil? || (team_melds[target_rank] || []).empty?
      groups = { target_rank => { naturals: [], wilds: cards } }
    else
      # Group cards into melds by rank. Wilds are distributed greedily to each rank group.
      # Strategy: assign each wild card to the rank group it was selected with.
      # Since we can't know which wild belongs to which group from a flat array,
      # we split by rank then distribute wilds proportionally to each group.
      rank_groups = naturals_all.group_by { |c| rank_of(c) }
      wilds_pool  = cards.select { |c| wild?(c) }

      groups = {}
      rank_groups.each do |rank, naturals|
        groups[rank] = { naturals: naturals, wilds: [] }
      end

      # Distribute wilds: first give to groups that need them to reach 3, then round-robin
      remaining_wilds = wilds_pool.dup
      groups.each do |rank, g|
        existing = team_melds[rank] || []
        needed = [3 - existing.length - g[:naturals].length, 0].max
        needed.times { groups[rank][:wilds] << remaining_wilds.shift if remaining_wilds.any? }
      end
      remaining_wilds.each_with_index do |wild, i|
        groups[groups.keys[i % groups.size]][:wilds] << wild
      end
    end

    # Validate each group
    groups.each do |rank, g|
      existing      = team_melds[rank] || []
      group_cards   = g[:naturals] + g[:wilds]
      total_wild    = existing.count { |c| wild?(c) } + g[:wilds].length
      total_natural = existing.count { |c| !wild?(c) } + g[:naturals].length

      return { error: "Need at least 3 cards to start a new meld for #{rank}s" } if existing.empty? && group_cards.length < 3
      return { error: "A meld cannot contain more wild cards than natural cards (#{rank}s)" } if total_wild > total_natural
    end

    unless team_has_melded
      total_points = cards.sum { |c| card_points(c) }
      threshold    = meld_threshold(player.team)
      return { error: "Initial meld must total at least #{threshold} points (selected: #{total_points})" } \
        if total_points < threshold
    end

    remaining_hand = hand.dup
    cards.each { |c| remaining_hand.delete_at(remaining_hand.index(c)) }
    player.update!(hand: remaining_hand)

    last_result = {}
    new_log = (turn_meld_log || []).dup
    groups.each do |rank, g|
      group_cards = g[:naturals] + g[:wilds]
      last_result = add_to_meld(player.team, rank, group_cards)
      new_log << { "rank" => rank, "cards" => group_cards }
    end
    write_game_state!("turn_meld_log" => new_log)

    last_result.merge(success: true)
  end

  # Undoes this player's most recent meld addition this turn, returning those
  # exact cards to hand. Only melds made since the current draw/pickup are
  # undoable — the log resets at the start of each turn.
  def undo_meld(player)
    return { error: "Not your turn" } unless game.current_turn == player.id
    return { error: "Game is over" } if game_over?
    return { error: "Nothing to undo" } if (turn_meld_log || []).empty?

    log = turn_meld_log.dup
    entry = log.pop
    rank = entry["rank"]
    cards = entry["cards"]

    team_melds = (melds[player.team.to_s] || {}).dup
    current = team_melds[rank] || []
    team_melds[rank] = current[0...-cards.length]
    team_melds.delete(rank) if team_melds[rank].blank?

    all_melds = (melds || {}).dup
    all_melds[player.team.to_s] = team_melds

    player.update!(hand: player.hand.dup + cards)
    write_game_state!("melds" => all_melds, "turn_meld_log" => log)

    { success: true }
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
    write_game_state!("discard_pile" => discard_pile + [card], "frozen" => new_frozen, "turn_meld_log" => [])

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

  # Called once the host dismisses the round summary. Deals the next round,
  # unless the round that just ended already won the game.
  def advance_round
    return { error: "No round summary to advance from" } if round_summary.blank?

    game_ending = game_over?
    write_game_state!("round_summary" => nil)

    if game_ending
      { game_over: true, winning_team: winning_team }
    else
      initialize_round
      { next_round: true }
    end
  end

  def game_over?
    (team_scores || {}).values.any? { |v| v.to_i >= GOAL_SCORE }
  end

  def winning_team
    return nil unless game_over?
    (team_scores || {}).max_by { |_team, score| score }&.first
  end

  # Points a team's very first meld must total, based on their cumulative score.
  def meld_threshold(team)
    score = (team_scores || {})[team.to_s].to_i
    MELD_THRESHOLDS.find { |max, _threshold| score < max }.last
  end

  def team_melded?(team)
    ((melds || {})[team.to_s] || {}).values.any?(&:present?)
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
    { canasta_completed: completed_canasta, canasta_rank: completed_canasta ? rank : nil,
      canasta_seq: completed_canasta ? next_seq : nil }
  end

  def can_go_out?(team)
    team_melds = melds[team.to_s] || {}
    canastas   = team_melds.values.select { |cards| cards.length >= CANASTA_SIZE }
    canastas.length >= 5 && canastas.any? { |cards| cards.none? { |c| wild?(c) } }
  end

  # Builds a full, itemized score breakdown for the round that just ended and
  # stores it as `round_summary` instead of immediately dealing the next
  # round. The table stays frozen on a summary screen — see #advance_round —
  # until the host reviews it and explicitly continues.
  def end_round!(going_out_team:)
    new_team_scores  = (team_scores || { "0" => 0, "1" => 0 }).dup
    new_round_scores = {}
    teams_summary    = {}

    %w[0 1].each do |team|
      team_melds = melds[team] || {}

      meld_breakdown = team_melds.keys.sort_by { |r| rank_sort_value(r) }.map do |rank|
        cards      = team_melds[rank]
        is_canasta = cards.length >= CANASTA_SIZE
        clean      = is_canasta ? cards.none? { |c| wild?(c) } : nil
        {
          "rank"    => rank,
          "cards"   => cards,
          "canasta" => is_canasta,
          "clean"   => clean,
          "points"  => cards.sum { |c| card_points(c) }
        }
      end

      meld_points_total = meld_breakdown.sum { |m| m["points"] }
      canasta_bonus     = meld_breakdown.sum { |m| m["canasta"] ? (m["clean"] ? 500 : 300) : 0 }
      red_three_cards   = red_threes[team] || []
      red_three_bonus   = red_three_cards.length * 100
      going_out_bonus   = team == going_out_team.to_s ? 200 : 0
      base_score        = canasta_bonus + red_three_bonus + going_out_bonus

      hand_breakdown = game.players.where(team: team.to_i).map do |p|
        { "player_id" => p.id, "name" => p.user.name, "cards" => p.hand, "points" => p.hand.sum { |c| card_points(c) } }
      end
      hand_penalty = hand_breakdown.sum { |h| h["points"] }

      round_score = base_score + meld_points_total - hand_penalty
      new_round_scores[team] = round_score
      new_team_scores[team]  = new_team_scores[team].to_i + round_score

      teams_summary[team] = {
        "melds"             => meld_breakdown,
        "meld_points_total" => meld_points_total,
        "canasta_bonus"     => canasta_bonus,
        "red_threes"        => red_three_cards,
        "red_three_bonus"   => red_three_bonus,
        "going_out_bonus"   => going_out_bonus,
        "base_score"        => base_score,
        "hands"             => hand_breakdown,
        "hand_penalty"      => hand_penalty,
        "round_score"       => round_score,
        "new_total"         => new_team_scores[team]
      }
    end

    history_entry = {
      "round_number"   => round_number,
      "going_out_team" => going_out_team.to_s,
      "teams" => teams_summary.transform_values { |t|
        {
          "round_score" => t["round_score"],
          "base_score"  => t["base_score"],
          "card_count"  => t["meld_points_total"],
          "new_total"   => t["new_total"]
        }
      }
    }

    write_game_state!(
      "team_scores"   => new_team_scores,
      "round_scores"  => new_round_scores,
      "round_summary" => { "going_out_team" => going_out_team.to_s, "teams" => teams_summary },
      "round_history" => (round_history || []) + [history_entry]
    )

    { round_ended: true }
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

  def rank_sort_value(rank)
    return 100 if rank == "jo"
    return 99 if rank == "2"
    RANK_VALUES[rank] || 0
  end
end
