class Scum < ApplicationRecord
  belongs_to :game

  CARD_VALUES = {
    "2" => 2, "3" => 3, "4" => 4, "5" => 5, "6" => 6, "7" => 7,
    "8" => 8, "9" => 9, "10" => 10, "j" => 11, "q" => 12,
    "k" => 13, "a" => 14
  }.freeze

  store_accessor :game_state,
    :play_pile,          # Array of cards currently on the table
    :play_pile_count,    # Integer - how many cards must be played to match
    :finished_players,   # Array of player IDs in finishing order
    :passed_this_round,  # Array of player IDs who passed this round
    :last_played_by,     # Player ID who last played cards (or nil)
    :last_played_cards,  # Array of cards last played (or nil)
    :trading_phase,      # true during between-round card exchange
    :pending_givers,     # Player IDs who still need to give cards
    :previous_rankings,  # Rankings from the completed round (string keys)
    :round_number,       # Integer, starts at 1
    :trade_log           # Hash of player_id (string) => { "gave" => [...], "received" => [...] }

  after_create :initialize_state

  # --- Public game actions ---

  def play_cards(player, cards)
    return { error: "Not your turn" } unless game.current_turn == player.id
    return { error: "Game is over" } if game_over?
    return { error: "No cards selected" } if cards.empty?

    flat_hand = player.hand.flatten
    return { error: "Invalid cards" } unless cards.all? { |c| flat_hand.include?(c) }

    ranks = cards.map { |c| card_rank(c) }
    return { error: "Cards must all be the same rank" } unless ranks.uniq.length == 1

    if play_pile.present?
      return { error: "Must play #{play_pile_count} card(s)" } unless cards.length == play_pile_count.to_i
      pile_rank = card_rank(play_pile.first)
      return { error: "Must play a higher rank" } unless ranks.first > pile_rank
    end

    aces_played     = ranks.first == CARD_VALUES["a"]
    new_hand        = remove_cards_from_hand(player.hand, cards)
    player_finished = new_hand.flatten.empty?

    player.update!(hand: new_hand)

    new_finished = player_finished ? finished_player_ids + [player.id] : finished_player_ids

    write_game_state!(
      "play_pile"         => aces_played ? [] : cards,
      "play_pile_count"   => aces_played ? nil : cards.length,
      "last_played_by"    => aces_played ? nil : player.id,
      "last_played_cards" => cards,
      "passed_this_round" => [],
      "finished_players"  => new_finished
    )

    remaining_active = active_player_ids
    if remaining_active.length <= 1
      write_game_state!("finished_players" => finished_player_ids + remaining_active)
      return { game_over: true, rankings: rankings, finished_player_name: player_finished ? player.user.name : nil }
    end

    if aces_played
      player_finished ? advance_turn(from_player_id: player.id) : set_turn(player.id)
      return { success: true, finished_player_name: player_finished ? player.user.name : nil }
    end

    advance_turn(from_player_id: player.id)
    { success: true, finished_player_name: player_finished ? player.user.name : nil }
  end

  def pass_turn(player)
    return { error: "Not your turn" } unless game.current_turn == player.id
    return { error: "Game is over" } if game_over?
    return { error: "Must play a card to lead" } if play_pile.blank?

    current_passed = (passed_this_round || []).map(&:to_i) | [player.id]
    write_game_state!("passed_this_round" => current_passed)

    leader_id  = last_played_by&.to_i
    active_ids = active_player_ids

    if leader_id
      non_leader_active = active_ids.reject { |id| id == leader_id }
      if non_leader_active.all? { |id| current_passed.include?(id) }
        if active_ids.include?(leader_id)
          leader_also_passed = current_passed.include?(leader_id)
          if game.leader_can_continue? && !leader_also_passed
            set_turn(leader_id)
            return { success: true }
          else
            clear_pile
            set_turn(leader_id)
          end
        else
          clear_pile
          advance_turn(from_player_id: leader_id)
        end
        return { success: true, pile_cleared: true }
      end
    end

    advance_turn(from_player_id: player.id)
    { success: true }
  end

  def start_new_round
    return { error: "Game is not over" } unless game_over?

    old_rankings  = rankings
    total_players = old_rankings.length
    old_round     = (round_number || 1).to_i

    pres_id = old_rankings[0][:player_id]
    scum_id = old_rankings[-1][:player_id]
    vp_id   = total_players >= 4 ? old_rankings[1][:player_id]  : nil
    vs_id   = total_players >= 4 ? old_rankings[-2][:player_id] : nil
    give_n  = total_players >= 4 ? 2 : 1

    # Deal fresh hands to all players
    deal_cards

    # Force Scum to give their best cards to President
    scum_player = game.players.find(scum_id)
    pres_player = game.players.find(pres_id)
    best_from_scum = best_cards(scum_player.hand, give_n)
    scum_player.update!(hand: remove_cards_from_hand(scum_player.hand, best_from_scum))
    add_cards_to_hand(pres_player, best_from_scum)

    pending = [pres_id]
    log = {
      scum_id.to_s => { "gave" => best_from_scum, "received" => [] },
      pres_id.to_s => { "gave" => [], "received" => best_from_scum }
    }

    # Force Vice Scum to give their best card to VP (4+ players, distinct roles)
    if vp_id && vs_id && vp_id != vs_id
      vs_player = game.players.find(vs_id)
      vp_player = game.players.find(vp_id)
      best_from_vs = best_cards(vs_player.hand, 1)
      vs_player.update!(hand: remove_cards_from_hand(vs_player.hand, best_from_vs))
      add_cards_to_hand(vp_player, best_from_vs)
      pending << vp_id
      log[vs_id.to_s] = { "gave" => best_from_vs, "received" => [] }
      log[vp_id.to_s] = { "gave" => [], "received" => best_from_vs }
    end

    write_game_state!(
      "play_pile"         => [],
      "play_pile_count"   => nil,
      "finished_players"  => [],
      "passed_this_round" => [],
      "last_played_by"    => nil,
      "last_played_cards" => nil,
      "trading_phase"     => true,
      "pending_givers"    => pending,
      "previous_rankings" => old_rankings.map { |r| r.transform_keys(&:to_s) },
      "round_number"      => old_round + 1,
      "trade_log"         => log
    )

    set_turn(pres_id)
    { success: true }
  end

  def give_cards(player, cards)
    return { error: "Not in trading phase" }           unless trading_phase
    return { error: "Not your turn to give cards" }    unless (pending_givers || []).map(&:to_i).include?(player.id)
    return { error: "No cards selected" }              if cards.empty?

    prev_ranks    = previous_rankings || []
    total_players = prev_ranks.length
    give_n        = total_players >= 4 ? 2 : 1

    my_index = prev_ranks.index { |r| r["player_id"].to_i == player.id }
    return { error: "Could not find your ranking" } if my_index.nil?

    if my_index == 0
      required  = give_n
      target_id = prev_ranks[-1]["player_id"].to_i
    elsif my_index == 1 && total_players >= 4
      required  = 1
      target_id = prev_ranks[-2]["player_id"].to_i
    else
      return { error: "You are not required to give cards" }
    end

    return { error: "Must give exactly #{required} card(s)" } unless cards.length == required

    flat_hand = player.hand.flatten
    return { error: "Invalid cards" } unless cards.all? { |c| flat_hand.include?(c) }

    target_player = game.players.find(target_id)
    player.update!(hand: remove_cards_from_hand(player.hand, cards))
    add_cards_to_hand(target_player, cards)

    new_pending = (pending_givers || []).map(&:to_i).reject { |id| id == player.id }

    log = (trade_log || {}).dup
    log[player.id.to_s] = (log[player.id.to_s] || {}).merge("gave" => cards)
    log[target_id.to_s] = (log[target_id.to_s] || {}).merge("received" => cards)
    write_game_state!("pending_givers" => new_pending, "trade_log" => log)

    if new_pending.empty?
      pres_id = prev_ranks[0]["player_id"].to_i
      write_game_state!("trading_phase" => false)
      set_turn(pres_id)
    else
      set_turn(new_pending.first)
    end

    { success: true }
  end

  def game_over?
    active_player_ids.length <= 1
  end

  def rankings
    total = finished_player_ids.length
    finished_player_ids.each_with_index.map do |pid, i|
      rank  = i + 1
      title = if rank == 1                        then "President"
              elsif rank == total                 then "Scum"
              elsif rank == 2 && total >= 4       then "Vice President"
              elsif rank == total - 1 && total >= 4 then "Vice Scum"
              else "Neutral"
              end
      player = game.players.find(pid)
      { player_id: pid, name: player.user.name, rank: rank, title: title }
    end
  end

  # --- Private ---

  private

  # Merges changes into game_state and saves the full column to avoid
  # JSONB dirty-tracking issues where partial updates are silently dropped.
  def write_game_state!(changes)
    merged = (game_state || {}).merge(changes)
    update!(game_state: merged)
  end

  def initialize_state
    update!(game_state: {
      "play_pile"         => [],
      "play_pile_count"   => nil,
      "finished_players"  => [],
      "passed_this_round" => [],
      "last_played_by"    => nil,
      "last_played_cards" => nil,
      "trading_phase"     => false,
      "pending_givers"    => [],
      "previous_rankings" => [],
      "round_number"      => 1
    })
    deal_cards
  end

  def deal_cards
    deck = Deck.new(game: game)
    deck.initialize_deck
    deck.deal
  end

  def card_rank(card)
    rank = card[1..]
    CARD_VALUES[rank.downcase] || 0
  end

  def finished_player_ids
    (finished_players || []).map(&:to_i)
  end

  def active_player_ids
    finished = finished_player_ids
    game.turn_order.reject { |id| finished.include?(id) }
  end

  def eligible_player_ids
    ids = active_player_ids
    return ids unless game.pass_locks_out?

    passed = (passed_this_round || []).map(&:to_i)
    ids.reject { |id| passed.include?(id) }
  end

  def best_cards(hand, count)
    hand.flatten.sort_by { |c| -card_rank(c) }.first(count)
  end

  def add_cards_to_hand(player, new_cards)
    hand = player.hand || []
    new_cards.each do |card|
      r     = card_rank(card)
      group = hand.find { |g| g.any? && card_rank(g.first) == r }
      if group
        group << card
      else
        hand << [card]
      end
    end
    player.update!(hand: hand.sort_by { |g| card_rank(g.first) })
  end

  def remove_cards_from_hand(hand, cards_to_remove)
    remaining = cards_to_remove.dup
    hand.map do |rank_group|
      rank_group.reject do |card|
        idx = remaining.index(card)
        if idx
          remaining.delete_at(idx)
          true
        end
      end
    end.reject(&:empty?)
  end

  def advance_turn(from_player_id:)
    eligible = eligible_player_ids
    return if eligible.empty?

    order = game.turn_order
    start = order.index(from_player_id) || 0

    order.length.times do |offset|
      candidate = order[(start + offset + 1) % order.length]
      if eligible.include?(candidate)
        set_turn(candidate)
        return
      end
    end
  end

  def set_turn(player_id)
    game.players.update_all(is_turn: false)
    game.update!(current_turn: player_id)
    game.players.find(player_id).update!(is_turn: true)
  end

  def clear_pile
    write_game_state!(
      "play_pile"         => [],
      "play_pile_count"   => nil,
      "passed_this_round" => [],
      "last_played_by"    => nil,
      "last_played_cards" => nil
    )
  end
end
