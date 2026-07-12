class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :players
  has_many :games, through: :players

  # Hardcoded rather than a DB flag so it's true in every environment
  # (dev/prod) without needing a data migration/seed run in each — a fresh
  # prod restore or a new dev DB both grant this immediately.
  ADMIN_EMAILS = %w[hawkespoulter@gmail.com].freeze

  def admin?
    ADMIN_EMAILS.include?(email)
  end

  CARD_BACKS = {
    "hawkes_sam_blue"  => "Hawkes + Sam Blue",
    "hawkes_sam_red"   => "Hawkes + Sam Red",
    "gabbitas_blue"    => "Gabbitas Blue",
    "gabbitas_green"   => "Gabbitas Green",
    "gabbitas_red"     => "Gabbitas Red",
    "fifes_purple"     => "Fifes Purple",
    "fifes_yellow"     => "Fifes Yellow",
    "dad"              => "Dad",
    "mom"              => "Mom",
    "sicily"           => "Sicily",
    "random"           => "Random"
  }.freeze

  # The raw stored preference (what's highlighted in the picker) — as
  # opposed to card_back_key below, which resolves "random" to an actual
  # asset key.
  def card_back_preference
    card_back.presence || "hawkes_sam_blue"
  end

  # Actual asset key to render. A plain preference is returned as-is; a
  # "random" preference is resolved deterministically from the user/game
  # pair, so it stays the same for the whole game (every re-render agrees)
  # but reshuffles to a different look for the next game. Without a game
  # (e.g. no game loaded yet), falls back to a genuinely random pick.
  def card_back_key(game = nil)
    pref = card_back_preference
    return pref unless pref == "random"

    options = CARD_BACKS.keys - ["random"]
    return options.sample if game.nil?

    options[(id.to_i * 1_000_003 + game.id.to_i) % options.length]
  end

  # Lifetime Canasta stat counters, incremented in place as events happen
  # across the app (draws, melds, round/game outcomes, ...) — deliberately
  # not derived from Game/Canasta/Player records, since those are destroyed
  # once a game ends (Game has_one/has_many ... dependent: :destroy) and
  # would erase all history. update_column skips validations/callbacks (this
  # is pure bookkeeping, not a user-facing edit) and matches the same
  # unlocked read-modify-write pattern Canasta#write_game_state! already uses
  # for its own jsonb column — acceptable for a hobby-scale app.
  def bump_canasta_stat!(key, by: 1)
    current = canasta_stats.dup
    current[key.to_s] = current[key.to_s].to_i + by
    update_column(:canasta_stats, current)
  end

  # Records `value` only if it beats the current high score for `key` (e.g.
  # best single-round score) — a no-op otherwise.
  def track_canasta_high!(key, value)
    return if value <= canasta_stats[key.to_s].to_i
    update_column(:canasta_stats, canasta_stats.merge(key.to_s => value))
  end
end
