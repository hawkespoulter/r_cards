class LuckySeven < ApplicationRecord
  self.table_name = "lucky_sevens"

  belongs_to :game

  # Ace is low here (A-2-…-7-…-K), unlike scum/canasta where it's high — so
  # this can't reuse Deck::CARD_VALUES.
  RANK_VALUES = {
    "a" => 1, "2" => 2, "3" => 3, "4" => 4, "5" => 5, "6" => 6, "7" => 7,
    "8" => 8, "9" => 9, "10" => 10, "j" => 11, "q" => 12, "k" => 13
  }.freeze

  SUITS          = %w[d h s c].freeze
  SUIT_SYMBOLS   = { "d" => "♦", "h" => "♥", "s" => "♠", "c" => "♣" }.freeze
  ANCHOR         = 7
  STARTING_CARD  = "d7"
  ROWS           = 4

  store_accessor :game_state,
    :layouts,          # { suit => { rank_value_string => copies_played } } — the four fanned runs on the table
    :row_suits,        # [suit|nil] x ROWS — which run sits in which spot on the table; filled as each 7 is played
    :deck_count,       # always 1 for now (see .deck_count_for)
    :finished_players, # Array of player IDs in the order they emptied their hands
    :last_play,        # { "player_id", "card", "seq" } - for the acting player's own card sound
    :knocked,          # Player IDs auto-skipped since the last successful play (see #advance_turn)
    :started,          # false until the 7 of diamonds opens play
    :seq               # Monotonic counter so clients can dedupe repeated broadcasts

  after_create :initialize_state

  # Always one deck. The extra-deck house rule (a second at 6 players, a third
  # at 11) is held back until the table can show a rank holding more than one
  # copy — the runs fan out one card per rank, so duplicates have nowhere to go
  # and the board misreads. Hands just get thinner at a big table instead.
  def self.deck_count_for(_player_count)
    1
  end

  # --- Public game actions ---

  # Seats the player holding the 7 of diamonds, who must open with it.
  def begin_play!
    starter = game.players.reload.find { |p| (p.hand || []).include?(STARTING_CARD) }
    set_turn(starter.id) if starter
  end

  # `row` only matters when the card is opening its suit — the 7 goes into
  # whichever of the four spots the player dropped it on. Once a suit has a
  # spot, everything else in that suit follows it there.
  def play_card(player, card, row: nil)
    return { error: "Not your turn" }             unless game.current_turn == player.id
    return { error: "Game is over" }              if game_over?
    return { error: "No card selected" }          if card.blank?
    return { error: "That card isn't in your hand" } unless (player.hand || []).include?(card)

    unless playable?(card)
      return { error: rejection_error(card) }
    end

    suit       = card_suit(card)
    target_row = row_index_for(suit)

    if target_row.nil?
      target_row = row.presence&.to_i
      return { error: "Drop the 7 on one of the open spots" } if target_row.nil?
      return { error: "That spot is already taken" } unless free_row?(target_row)
    end

    new_hand = player.hand.dup
    new_hand.delete_at(new_hand.index(card))
    player.update!(hand: new_hand)

    player_finished = new_hand.empty?
    new_finished    = player_finished ? finished_player_ids + [player.id] : finished_player_ids

    write_game_state!(
      "layouts"          => layouts_with(card),
      "row_suits"        => rows_with(suit, target_row),
      "started"          => true,
      "finished_players" => new_finished,
      "seq"              => seq.to_i + 1,
      "last_play"        => { "player_id" => player.id, "card" => card, "seq" => seq.to_i + 1 }
    )

    # First hand emptied wins and the game stops there — the rest are placed by
    # how many cards they were left holding, which is ordering for the results
    # screen, not scoring.
    if player_finished
      trailing = active_player_ids.sort_by { |id| (game.players.find(id).hand || []).length }
      write_game_state!("finished_players" => [player.id] + trailing, "knocked" => [])
      return { game_over: true, rankings: rankings, winner_name: player.user.name }
    end

    # Capping a run earns another card. It chains — king, then ace, then a
    # plain card — so the turn only moves on once they play something that
    # isn't an end, or run out of legal cards to follow up with.
    if caps_run?(card) && playable_cards(player).any?
      write_game_state!("knocked" => [])
      set_turn(player.id)
      return { success: true, extra_turn: true, capped_card: card }
    end

    skipped = advance_turn(from_player_id: player.id)
    { success: true, knocked_names: skipped.map { |id| game.players.find(id).user.name } }
  end

  # Deals a fresh hand to everyone and starts over with the same table.
  def start_new_game
    return { error: "Game is not over" } unless game_over?

    write_game_state!(
      "layouts"          => {},
      "row_suits"        => Array.new(ROWS),
      "finished_players" => [],
      "knocked"          => [],
      "started"          => false,
      "last_play"        => nil,
      "seq"              => 0
    )
    game.update!(turn_order: game.players.pluck(:id).shuffle)
    # Recomputed rather than carried over, so a game dealt before the one-deck
    # rule doesn't keep redealing itself a shoe the table can't draw.
    decks = self.class.deck_count_for(game.players.count)
    write_game_state!("deck_count" => decks)
    deal_cards(decks)
    begin_play!
    { success: true }
  end

  # The two cards that close off an end of a run: the ace at the bottom and the
  # king at the top (ace is low here).
  def caps_run?(card)
    [1, 13].include?(card_value(card))
  end

  # --- Queries used by the views ---

  # A card extends a run if it sits immediately below or above one of that
  # suit's exposed ends. With more than one deck in play a rank can hold as
  # many copies as there are decks, so duplicates fill the slot that's already
  # on the table rather than being stranded as unplayable dead cards.
  def playable?(card)
    value = card_value(card)
    return false unless value
    return card == STARTING_CARD unless started?

    suit = card_suit(card)
    row  = layout_row(suit)

    # A suit opens with its own 7 — that's always available, whatever state the
    # other runs are in.
    return value == ANCHOR if row.empty?

    # Then that suit owes its 8 and its 6 before it opens up, so no 9 before the
    # 6. This binds only the suit it applies to; the other three stay free.
    needed = suit_required_card(suit)
    return card == needed if needed

    copies = row[value.to_s].to_i
    return copies < deck_count.to_i if copies.positive?

    values = row.keys.map(&:to_i)
    value == values.min - 1 || value == values.max + 1
  end

  def playable_cards(player)
    (player.hand || []).select { |card| playable?(card) }
  end

  # Says which card a rejected play was missing, rather than the generic
  # "doesn't extend a run".
  def rejection_error(card)
    return "The #{SUIT_SYMBOLS['d']}7 opens the game" unless started?

    suit = card_suit(card)
    return "Only a 7 can start a new suit" if layout_row(suit).empty?

    needed = suit_required_card(suit)
    return "#{SUIT_SYMBOLS[suit]}#{seven_rank_label_for(needed)} comes next in that suit" if needed

    "That card doesn't extend a run"
  end

  def seven_rank_label_for(code)
    RANK_VALUES.invert[card_value(code)].to_s.upcase
  end

  # What a suit still owes before it plays freely: its 8, then its 6. Each suit
  # runs this sequence on its own, so one suit waiting never blocks another.
  # Single deck, so each of those cards sits in exactly one hand and the table
  # can always reach whoever holds it.
  def suit_required_card(suit)
    row = layout_row(suit)
    return nil if row.empty?
    return seven_code(suit, ANCHOR + 1) if row[(ANCHOR + 1).to_s].to_i.zero?
    return seven_code(suit, ANCHOR - 1) if row[(ANCHOR - 1).to_s].to_i.zero?

    nil
  end

  def layout_row(suit)
    (layouts || {})[suit] || {}
  end

  # --- Table spots ---

  def rows
    stored = row_suits || []
    Array.new(ROWS) { |i| stored[i] }
  end

  def row_suit(index)
    rows[index]
  end

  def row_index_for(suit)
    rows.index(suit)
  end

  def free_row?(index)
    index.is_a?(Integer) && index.between?(0, ROWS - 1) && rows[index].nil?
  end

  # Cards for one side of a run, nearest-the-7 last so they overlap outward.
  def run_cards(suit, high:)
    range = high ? ((ANCHOR + 1)..13) : (1...ANCHOR)
    range.flat_map do |value|
      copies = copies_played(suit, value)
      copies.positive? ? [[seven_code(suit, value), copies]] : []
    end
  end

  def seven_code(suit, value)
    "#{suit}#{RANK_VALUES.invert[value]}"
  end

  def copies_played(suit, value)
    layout_row(suit)[value.to_s].to_i
  end

  # The first player to empty their hand ends it — everyone else is still
  # holding cards, so there's no play-on-for-places phase.
  def game_over?
    finished_player_ids.any?
  end

  def started?
    started == true
  end

  def knocked_ids
    (knocked || []).map(&:to_i)
  end

  def finished_player_ids
    (finished_players || []).map(&:to_i)
  end

  def rankings
    total = finished_player_ids.length
    finished_player_ids.each_with_index.map do |pid, i|
      rank = i + 1
      { player_id: pid,
        name: game.players.find(pid).user.name,
        rank: rank,
        title: rank == 1 ? "Winner" : (rank == total ? "Rotten Egg" : rank.ordinalize) }
    end
  end

  def card_suit(card)
    card.to_s[0]
  end

  def card_value(card)
    RANK_VALUES[card.to_s[1..].to_s.downcase]
  end

  # --- Private ---

  private

  def initialize_state
    decks = self.class.deck_count_for(game.players.count)
    update!(game_state: {
      "layouts"          => {},
      "row_suits"        => Array.new(ROWS),
      "deck_count"       => decks,
      "finished_players" => [],
      "last_play"        => nil,
      "knocked"          => [],
      "started"          => false,
      "seq"              => 0
    })
    deal_cards(decks)
  end

  def deal_cards(decks)
    deck = game.decks.create
    deck.initialize_deck(deck_count: decks)
    shoe = deck.cards.dup

    players = game.players.order(:created_at).to_a
    hands   = Hash.new { |h, k| h[k] = [] }

    shoe.each_with_index { |card, i| hands[players[i % players.length].id] << card }

    Player.transaction do
      hands.each { |player_id, cards| game.players.find(player_id).update!(hand: sort_hand(cards)) }
    end
  end

  def sort_hand(cards)
    cards.sort_by { |card| [SUITS.index(card_suit(card)) || SUITS.length, card_value(card) || 0] }
  end

  def rows_with(suit, index)
    updated = rows
    updated[index] = suit
    updated
  end

  def layouts_with(card)
    updated = (layouts || {}).each_with_object({}) { |(suit, row), acc| acc[suit] = row.dup }
    row     = updated[card_suit(card)] ||= {}
    key     = card_value(card).to_s
    row[key] = row[key].to_i + 1
    updated
  end

  def active_player_ids
    finished = finished_player_ids
    game.turn_order.reject { |id| finished.include?(id) }
  end

  # Sevens has no optional pass: a player holding a legal card must play it,
  # and a player holding none has no decision to make — so unplayable turns are
  # skipped here instead of stalling on a "knock" button nobody can decline.
  # This always finds someone: every card not yet on the table is in an active
  # player's hand, so at least one of them can extend a run.
  def advance_turn(from_player_id:)
    order  = game.turn_order
    active = active_player_ids
    return [] if active.empty?

    start      = order.index(from_player_id) || 0
    candidates = (1..order.length).map { |i| order[(start + i) % order.length] }
                                 .select { |id| active.include?(id) }
    skipped = []

    candidates.each do |id|
      if playable_cards(game.players.find(id)).any?
        write_game_state!("knocked" => skipped)
        set_turn(id)
        return skipped
      end
      skipped << id
    end

    write_game_state!("knocked" => [])
    set_turn(candidates.first)
    []
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
