class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :players
  has_many :games, through: :players

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
end
