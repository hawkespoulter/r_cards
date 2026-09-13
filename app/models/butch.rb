class Butch < ApplicationRecord
  self.table_name = "butches"

  belongs_to :game

  HAND_SIZE    = 5
  PEEKS        = 2   # cards each player gets to look at when a hand is dealt
  TARGET_SCORE = 100 # the game ends once anyone's running total reaches this
  MIN_PLAYERS  = 2
  MAX_PLAYERS  = 8   # 8 hands of 5 still leaves a dozen cards to draw from
  LOG_LENGTH   = 8
  REVEAL_MS    = 4000
  MISS_MS      = 3500

  # A power fires only when its card is drawn from the deck and discarded
  # straight away. Swapping one out of your hand, or matching one onto the
  # pile, does nothing.
  POWERS = { "10" => "ten", "j" => "jack", "q" => "queen" }.freeze

  POWER_BLURBS = {
    "ten"   => "looks at someone's card and may trade for it",
    "jack"  => "looks at one of their own cards",
    "queen" => "blind-trades with someone"
  }.freeze

  SUIT_SYMBOLS = { "d" => "♦", "h" => "♥", "s" => "♠", "c" => "♣" }.freeze

  # Player IDs are stored as string keys throughout — they come back from
  # jsonb as strings anyway, so keeping them that way avoids mixed lookups.
  store_accessor :game_state,
    :phase,           # "peek" → "play" → "hand_over" → (next hand) … → "game_over"
    :hand_number,
    :draw_pile,
    :discard_pile,
    :discard_seq,     # bumped whenever the top of the discard pile changes
    :peeked,          # { player_id => [slot, ...] } the opening looks taken this hand
    :step,            # current player's step: "draw" → "decide" → ("power") → next turn
    :drawn,           # { "card", "source" } the card the current player is holding
    :power,           # { "type", "target_player", "target_slot" } a 10/J/Q being resolved
    :caller_id,       # who called Butch this hand
    :reveals,         # { player_id => [reveal] } private looks, rendered only for that player
    :public_reveal,   # a missed match, flipped up for the whole table
    :lockouts,        # { player_id => discard_seq } a miss locks you out until the top changes
    :scores,          # { player_id => running total }
    :history,         # [{ "hand", "points" => { player_id => points }, "caller_id" }]
    :hand_end_reason,
    :log,             # recent table talk, newest last
    :seq              # monotonic, keys reveals so clients show each one once

  after_create :initialize_state

  # --- Scoring ---

  def self.rank_of(card)
    card.to_s[1..].to_s.downcase
  end

  # King is worth nothing, jack and queen ten, everything else its face value
  # with the ace low.
  def self.points(card)
    case rank_of(card)
    when "k"      then 0
    when "a"      then 1
    when "j", "q" then 10
    else rank_of(card).to_i
    end
  end

  def self.label(card)
    "#{SUIT_SYMBOLS[card.to_s[0]]}#{rank_of(card).upcase}"
  end

  # --- Public game actions ---
  #
  # Every action runs under a row lock: matching can happen at any moment
  # from anyone at the table, so two requests racing to the discard pile have
  # to be serialized or they'd both read the same top card.

  def peek(player, slot)
    act(player) { |p| peek!(p, slot) }
  end

  def draw(player, source)
    act(player) { |p| draw!(p, source) }
  end

  def swap(player, slot)
    act(player) { |p| swap!(p, slot) }
  end

  def discard_drawn(player)
    act(player) { |p| discard_drawn!(p) }
  end

  def use_power(player, slot: nil, target_player: nil, target_slot: nil)
    act(player) { |p| use_power!(p, slot, target_player, target_slot) }
  end

  def skip_power(player)
    act(player) { |p| skip_power!(p) }
  end

  def call_butch(player)
    act(player) { |p| call_butch!(p) }
  end

  def match(player, slot)
    act(player) { |p| match!(p, slot) }
  end

  def start_next_hand
    with_lock do
      game.reload
      start_next_hand!
    end
  end

  # --- Queries used by the views ---

  def peek_phase?
    phase == "peek"
  end

  def playing?
    phase == "play"
  end

  def hand_over?
    phase == "hand_over"
  end

  def game_over?
    phase == "game_over"
  end

  def between_hands?
    hand_over? || game_over?
  end

  def caller_player_id
    caller_id.presence&.to_i
  end

  def discards
    discard_pile || []
  end

  def draw_count
    (draw_pile || []).length
  end

  def drawn_card
    (drawn || {})["card"]
  end

  def drawn_from_discard?
    (drawn || {})["source"] == "discard"
  end

  def power_type
    (power || {})["type"]
  end

  def score_for(player_id)
    (scores || {})[player_id.to_s].to_i
  end

  def peeks_left(player_id)
    PEEKS - peeked_slots(player_id).length
  end

  def waiting_to_peek
    game.turn_order.select { |pid| peeks_left(pid).positive? }
  end

  def locked_out?(player)
    lockout = (lockouts || {})[player.id.to_s]
    lockout.present? && lockout.to_i == discard_seq.to_i
  end

  def can_match?(player)
    playing? && discards.any? && caller_player_id != player.id && !locked_out?(player) &&
      hand(player).compact.any?
  end

  # Who a 10 or queen can be pointed at: anyone else still holding a card,
  # except whoever called Butch — their hand is frozen once they call.
  def targetable?(player_id, from:)
    player_id.to_i != from.to_i && player_id.to_i != caller_player_id &&
      hand_for_id(player_id).compact.any?
  end

  # What a tap on the board means for this player right now — the JS reads
  # this rather than re-deriving the turn logic.
  def mode_for(player)
    return "none" unless player
    return peeks_left(player.id).positive? ? "peek" : "none" if peek_phase?
    return "none" unless playing? && game.current_turn == player.id

    case step
    when "decide" then "swap"
    when "power"
      case power_type
      when "jack"  then "jack"
      when "queen" then "queen"
      when "ten"   then power["target_player"] ? "ten_swap" : "ten_look"
      end
    else "none"
    end
  end

  # Everyone else, in turn order, starting with whoever plays after `player_id`.
  def seating_after(player_id)
    order = game.turn_order
    start = order.index(player_id)
    return order if start.nil?

    (1...order.length).map { |i| order[(start + i) % order.length] }
  end

  # Only this viewer's own looks plus a missed match everyone saw. Nothing
  # else about a face-down card ever leaves the server.
  def reveal_payload(player_id)
    mine = ((reveals || {})[player_id.to_s] || []).map do |r|
      r.slice("owner", "slot", "card", "hold").merge("key" => r["seq"], "ms" => REVEAL_MS)
    end
    miss = public_reveal && public_reveal.slice("owner", "slot", "card")
                                         .merge("key" => "miss#{public_reveal['seq']}", "ms" => MISS_MS)
    miss ? mine + [miss] : mine
  end

  def hand_points(player_id)
    hand_for_id(player_id).compact.sum { |card| self.class.points(card) }
  end

  def last_hand
    (history || []).last
  end

  def hand_winner_ids
    points = (last_hand || {})["points"] || {}
    return [] if points.empty?

    low = points.values.min
    points.select { |_, pts| pts == low }.keys.map(&:to_i)
  end

  def standings
    game.turn_order.sort_by { |pid| score_for(pid) }
  end

  # Lowest running total takes it; a tie shares the win.
  def winner_ids
    return [] unless game_over?

    low = standings.map { |pid| score_for(pid) }.min
    standings.select { |pid| score_for(pid) == low }
  end

  def log_lines
    (log || []).reverse
  end

  def label(card)
    self.class.label(card)
  end

  # --- Private ---

  private

  def act(player)
    with_lock do
      game.reload
      yield game.players.find(player.id)
    end
  end

  def initialize_state
    update!(game_state: {
      "scores"      => game.turn_order.to_h { |pid| [pid.to_s, 0] },
      "history"     => [],
      "hand_number" => 0,
      "discard_seq" => 0,
      "seq"         => 0
    })
    deal_hand!
  end

  def start_next_hand!
    case phase
    when "hand_over"
      deal_hand!
    when "game_over"
      game.update!(turn_order: game.players.pluck(:id).shuffle)
      write_game_state!(
        "scores"      => game.turn_order.to_h { |pid| [pid.to_s, 0] },
        "history"     => [],
        "hand_number" => 0
      )
      deal_hand!
    else
      return { error: "This hand isn't over yet" }
    end
    { success: true }
  end

  # Five face down each, one card flipped to start the discard pile, and the
  # lead rotates round the table hand by hand.
  def deal_hand!
    order = game.turn_order
    deck  = Deck::DECK.shuffle

    Player.transaction do
      order.each { |pid| game.players.find(pid).update!(hand: deck.shift(HAND_SIZE)) }
    end

    number  = hand_number.to_i + 1
    starter = order[(number - 1) % order.length]
    first   = deck.shift

    write_game_state!(
      "phase"           => "peek",
      "hand_number"     => number,
      "draw_pile"       => deck,
      "discard_pile"    => [first],
      "discard_seq"     => discard_seq.to_i + 1,
      "peeked"          => {},
      "step"            => "draw",
      "drawn"           => nil,
      "power"           => nil,
      "caller_id"       => nil,
      "reveals"         => {},
      "public_reveal"   => nil,
      "lockouts"        => {},
      "hand_end_reason" => nil,
      "log"             => []
    )
    set_turn(starter)
    log!("Hand #{number} dealt — everyone look at #{PEEKS} of your cards")
  end

  def peek!(player, slot)
    return { error: "Everyone's already had their look" } unless peek_phase?

    slot = to_slot(slot)
    return { error: "Pick one of your cards" } unless card_at(player, slot)

    mine = peeked_slots(player.id)
    return { error: "You've already looked at #{PEEKS}" } if mine.length >= PEEKS
    return { error: "You've already looked at that one" } if mine.include?(slot)

    reveal_to!(player.id, player.id, slot)
    write_game_state!("peeked" => (peeked || {}).merge(player.id.to_s => mine + [slot]))

    if waiting_to_peek.empty?
      write_game_state!("phase" => "play")
      log!("Everyone's had a look — #{name_of(game.current_turn)} goes first")
      return { success: true, play_started: true }
    end

    { success: true, silent: true }
  end

  def draw!(player, source)
    error = turn_error(player, "draw")
    return error if error

    clear_reveals!(player.id)

    if source.to_s == "discard"
      card = discards.last
      return { error: "The discard pile is empty" } unless card
      return { error: "You've no cards left to swap it for" } if hand(player).compact.empty?

      write_game_state!("discard_pile" => discards[0...-1], "discard_seq" => discard_seq.to_i + 1)
      log!("#{player.user.name} took the #{label(card)} from the discard pile")
    else
      replenish_draw_pile!
      return finish_hand!("The deck ran out") if (draw_pile || []).empty?

      card = draw_pile.last
      write_game_state!("draw_pile" => draw_pile[0...-1])
      log!("#{player.user.name} drew from the deck")
    end

    write_game_state!(
      "drawn" => { "card" => card, "source" => source.to_s == "discard" ? "discard" : "deck" },
      "step"  => "decide"
    )
    { success: true, sound: true }
  end

  def swap!(player, slot)
    error = turn_error(player, "decide")
    return error if error

    slot = to_slot(slot)
    old  = card_at(player, slot)
    return { error: "Pick one of your cards to replace" } unless old

    new_hand = hand(player).dup
    new_hand[slot] = drawn_card
    player.update!(hand: new_hand)
    forget_slot!(player.id, slot)
    push_discard!(old)

    log!("#{player.user.name} swapped out their card #{slot + 1} — the #{label(old)}")
    end_turn!(player).merge(sound: true)
  end

  def discard_drawn!(player)
    error = turn_error(player, "decide")
    return error if error
    return { error: "You took that from the discard pile — swap it into your hand" } if drawn_from_discard?

    card = drawn_card
    push_discard!(card)
    write_game_state!("drawn" => nil)

    type = POWERS[self.class.rank_of(card)]
    if type && power_usable?(player, type)
      write_game_state!("step" => "power", "power" => { "type" => type })
      log!("#{player.user.name} discarded the #{label(card)} and #{POWER_BLURBS[type]}")
      return { success: true, sound: true }
    end

    log!("#{player.user.name} discarded the #{label(card)}")
    end_turn!(player).merge(sound: true)
  end

  def use_power!(player, slot, target_player_id, target_slot)
    error = turn_error(player, "power")
    return error if error

    name = player.user.name

    case power_type
    when "jack"
      slot = to_slot(slot)
      return { error: "Pick one of your cards to look at" } unless card_at(player, slot)

      reveal_to!(player.id, player.id, slot)
      log!("#{name} looked at their card #{slot + 1}")
      end_turn!(player)

    when "ten"
      if power["target_player"].nil?
        target = target_for(player, target_player_id)
        return { error: "Pick another player's card" } unless target

        tslot = to_slot(target_slot)
        return { error: "Pick one of #{target.user.name}'s cards" } unless card_at(target, tslot)

        # Held face up until the trade decision is made, not flashed.
        reveal_to!(player.id, target.id, tslot, hold: true)
        write_game_state!("power" => power.merge("target_player" => target.id, "target_slot" => tslot))
        log!("#{name} is looking at #{target.user.name}'s card #{tslot + 1}")
        { success: true, silent: true }
      else
        target = game.players.find(power["target_player"])
        tslot  = power["target_slot"].to_i
        slot   = to_slot(slot)
        return { error: "Pick one of your cards to trade" } unless card_at(player, slot)
        return { error: "That card's gone — keep your cards instead" } unless card_at(target, tslot)

        trade!(player, slot, target, tslot)
        log!("#{name} traded their card #{slot + 1} for #{target.user.name}'s card #{tslot + 1}")
        end_turn!(player).merge(sound: true)
      end

    when "queen"
      slot   = to_slot(slot)
      target = target_for(player, target_player_id)
      tslot  = to_slot(target_slot)
      return { error: "Pick one of your cards" } unless card_at(player, slot)
      return { error: "Pick another player's card" } unless target && card_at(target, tslot)

      trade!(player, slot, target, tslot)
      log!("#{name} blind-traded their card #{slot + 1} for #{target.user.name}'s card #{tslot + 1}")
      end_turn!(player).merge(sound: true)

    else
      { error: "No power to use" }
    end
  end

  def skip_power!(player)
    error = turn_error(player, "power")
    return error if error

    verb = power_type == "ten" && power["target_player"] ? "kept their cards" : "passed on the power"
    log!("#{player.user.name} #{verb}")
    end_turn!(player)
  end

  # Called instead of drawing, so the caller's hand is exactly what it was
  # at the start of their turn — and from here it's frozen.
  def call_butch!(player)
    error = turn_error(player, "draw")
    return error if error
    return { error: "#{name_of(caller_player_id)} already called Butch" } if caller_player_id

    write_game_state!("caller_id" => player.id)
    clear_reveals!(player.id)
    log!("#{player.user.name} called BUTCH! Everyone else gets one more turn")
    end_turn!(player).merge(butch_called_by: player.user.name)
  end

  # Throw one of your face-down cards onto the discard pile, any time, if you
  # think it matches the top card's rank. Right, and it's gone from your hand.
  # Wrong, and it's flipped up for everyone, goes back where it was, and you
  # can't try again until a different card lands on top.
  def match!(player, slot)
    return { error: "Wait until everyone's had their look" } if peek_phase?
    return { error: "The hand is over" } unless playing?
    return { error: "You called Butch — your cards are locked" } if caller_player_id == player.id

    top = discards.last
    return { error: "There's nothing on the discard pile to match" } unless top
    return { error: "You already missed on the #{label(top)} — wait for the next discard" } if locked_out?(player)

    slot = to_slot(slot)
    card = card_at(player, slot)
    return { error: "Pick one of your cards" } unless card

    if self.class.rank_of(card) == self.class.rank_of(top)
      new_hand = hand(player).dup
      new_hand[slot] = nil
      player.update!(hand: new_hand)
      forget_slot!(player.id, slot)
      push_discard!(card)
      log!("#{player.user.name} matched the #{label(top)} with their card #{slot + 1}!")
      { success: true, sound: true, matched: true }
    else
      write_game_state!(
        "lockouts"      => (lockouts || {}).merge(player.id.to_s => discard_seq.to_i),
        "public_reveal" => { "owner" => player.id, "slot" => slot, "card" => card, "seq" => next_seq! }
      )
      log!("#{player.user.name} tried to match the #{label(top)} with their #{label(card)} — no good, locked out")
      { success: true, missed: true }
    end
  end

  def end_turn!(player)
    kept = ((reveals || {})[player.id.to_s] || []).reject { |r| r["hold"] }
    write_game_state!(
      "drawn"   => nil,
      "power"   => nil,
      "step"    => "draw",
      "reveals" => (reveals || {}).merge(player.id.to_s => kept)
    )

    upcoming = seating_after(player.id).first
    return finish_hand!(nil) if caller_player_id && upcoming == caller_player_id

    set_turn(upcoming)
    { success: true }
  end

  def finish_hand!(reason)
    order  = game.turn_order
    points = order.to_h { |pid| [pid.to_s, hand_points(pid)] }
    totals = order.to_h { |pid| [pid.to_s, score_for(pid) + points[pid.to_s]] }
    over   = totals.values.max >= TARGET_SCORE

    write_game_state!(
      "scores"          => totals,
      "history"         => (history || []) + [{ "hand" => hand_number, "points" => points, "caller_id" => caller_player_id }],
      "phase"           => over ? "game_over" : "hand_over",
      "step"            => nil,
      "drawn"           => nil,
      "power"           => nil,
      "reveals"         => {},
      "public_reveal"   => nil,
      "hand_end_reason" => reason
    )
    game.players.update_all(is_turn: false)
    { success: true, hand_over: true, game_over: over }
  end

  # --- Helpers ---

  def turn_error(player, needed_step)
    return { error: "Wait until everyone's had their look" } if peek_phase?
    return { error: "The hand is over" } unless playing?
    return { error: "Not your turn" } unless game.current_turn == player.id
    return nil if step == needed_step

    case step
    when "decide" then { error: "Swap the #{label(drawn_card)} into your hand or discard it first" }
    when "power"  then { error: "Use your power or skip it first" }
    else { error: "Draw a card first" }
    end
  end

  def power_usable?(player, type)
    return false if hand(player).compact.empty?
    return true if type == "jack"

    game.turn_order.any? { |pid| targetable?(pid, from: player.id) }
  end

  def target_for(player, target_player_id)
    return nil if target_player_id.blank?
    return nil unless targetable?(target_player_id, from: player.id)

    game.players.find_by(id: target_player_id)
  end

  def trade!(a, a_slot, b, b_slot)
    a_hand = hand(a).dup
    b_hand = hand(b).dup
    a_hand[a_slot], b_hand[b_slot] = b_hand[b_slot], a_hand[a_slot]

    Player.transaction do
      a.update!(hand: a_hand)
      b.update!(hand: b_hand)
    end
    forget_slot!(a.id, a_slot)
    forget_slot!(b.id, b_slot)
  end

  def replenish_draw_pile!
    return if (draw_pile || []).any? || discards.length < 2

    write_game_state!(
      "draw_pile"    => discards[0...-1].shuffle,
      "discard_pile" => [discards.last]
    )
    log!("The deck ran dry — the discard pile was shuffled into a new one")
  end

  def push_discard!(card)
    write_game_state!("discard_pile" => discards + [card], "discard_seq" => discard_seq.to_i + 1)
  end

  def reveal_to!(viewer_id, owner_id, slot, hold: false)
    card  = hand_for_id(owner_id)[slot]
    entry = { "owner" => owner_id, "slot" => slot, "card" => card, "hold" => hold, "seq" => next_seq! }
    list  = ((reveals || {})[viewer_id.to_s] || []) + [entry]
    write_game_state!("reveals" => (reveals || {}).merge(viewer_id.to_s => list))
  end

  def clear_reveals!(player_id)
    write_game_state!("reveals" => (reveals || {}).merge(player_id.to_s => []))
  end

  # A card that's moved or gone can't keep showing a stale face — drop every
  # look (anyone's) still pointing at that spot.
  def forget_slot!(owner_id, slot)
    pruned = (reveals || {}).transform_values do |list|
      list.reject { |r| r["owner"].to_i == owner_id.to_i && r["slot"].to_i == slot }
    end
    miss = public_reveal
    miss = nil if miss && miss["owner"].to_i == owner_id.to_i && miss["slot"].to_i == slot
    write_game_state!("reveals" => pruned, "public_reveal" => miss)
  end

  def peeked_slots(player_id)
    ((peeked || {})[player_id.to_s] || []).map(&:to_i)
  end

  def hand(player)
    player.hand || []
  end

  def hand_for_id(player_id)
    game.players.find(player_id).hand || []
  end

  def card_at(player, slot)
    return nil unless slot.is_a?(Integer) && slot >= 0

    hand(player)[slot]
  end

  def to_slot(value)
    Integer(value.to_s, exception: false)
  end

  def name_of(player_id)
    game.players.find_by(id: player_id)&.user&.name
  end

  def next_seq!
    value = seq.to_i + 1
    write_game_state!("seq" => value)
    value
  end

  def log!(text)
    write_game_state!("log" => ((log || []) + [text]).last(LOG_LENGTH))
  end

  def set_turn(player_id)
    game.players.update_all(is_turn: false)
    game.update!(current_turn: player_id)
    game.players.find(player_id).update!(is_turn: true)
  end

  # Merges changes into game_state and saves the full column to avoid JSONB
  # dirty-tracking issues where partial updates are silently dropped.
  def write_game_state!(changes)
    update!(game_state: (game_state || {}).merge(changes))
  end
end
