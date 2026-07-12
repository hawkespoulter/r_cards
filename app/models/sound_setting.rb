# Singleton — one row holds every sound's volume multiplier, editable from
# the admin sound-settings page (see SoundSettingsController) and applied
# globally to every player's game session (rendered into the layout as
# window.SOUND_VOLUMES, read by app/javascript/sound_effects.js). Not a
# per-user preference — there's exactly one live mix for the whole app.
class SoundSetting < ApplicationRecord
  # Every adjustable sound, with its default multiplier — the source of
  # truth for which keys the admin page renders a slider for, and what a
  # missing/never-saved key falls back to.
  KEYS = {
    "cardPlayed"          => 1.0,
    "yourTurnKnock"       => 1.0,
    "yourTeamPilePickup"  => 1.0,
    "enemyTeamPilePickup" => 1.0,
    "roundEnded"          => 1.0,
    "canastaMade"         => 1.0,
    "peakHandPickup"      => 1.0,
    "gameStart"           => 1.0
  }.freeze

  def self.current
    first_or_create!
  end

  # Volumes merged with defaults, so a fresh row (or one missing a key added
  # after it was created) still reports a full, sensible set.
  def volumes_with_defaults
    KEYS.merge(volumes || {})
  end
end
