// Per-sound volume multipliers (0.0–1.0), admin-configurable at
// /sound_settings/edit and applied globally to every player's session —
// window.SOUND_VOLUMES is rendered in the layout from SoundSetting.current,
// keyed the same as SoundSetting::KEYS on the Rails side. The 1.0 fallback
// only matters if that global ever isn't set (e.g. a stale cached page).
function volume(key) {
  return (window.SOUND_VOLUMES || {})[key] ?? 1.0;
}

function playFile(url, volumeKey) {
  if (!url) return;
  const audio = new Audio(url);
  audio.volume = volume(volumeKey);
  audio.play().catch(() => {});
}

// Picks `n` distinct URLs out of the pool without replacement (falls back to
// fewer than `n` if the pool is smaller), so a simultaneous "chord" doesn't
// risk landing the same sample on top of itself at the exact same instant.
function pickRandomDistinct(arr, n) {
  const pool = [...arr];
  const picked = [];
  for (let i = 0; i < n && pool.length; i++) {
    const idx = Math.floor(Math.random() * pool.length);
    picked.push(pool.splice(idx, 1)[0]);
  }
  return picked;
}

// `count` simultaneous samples from the "card played" set — one per card
// drawn or melded (2 for a normal draw, 1-3 for red-three replacements,
// however many cards a meld drop contains). Distinct as long as there are
// enough sounds to go around; once count exceeds the pool size, the
// overflow falls back to random repeats rather than refusing to play
// anything for the extra cards. (window.CARD_PLAYED_SOUND_URLS is set in
// the layout via asset_path, since Sprockets fingerprints these files and
// importmap JS can't compute that path itself.)
export function playCardPlayedSounds(count) {
  const urls = window.CARD_PLAYED_SOUND_URLS || [];
  if (!urls.length || !count) return;
  const picked = pickRandomDistinct(urls, count);
  while (picked.length < count) {
    picked.push(urls[Math.floor(Math.random() * urls.length)]);
  }
  picked.forEach((url) => playFile(url, "cardPlayed"));
}

export function playYourTurnKnock() {
  playFile(window.YOUR_TURN_KNOCK_URL, "yourTurnKnock");
}

export function playTeamPilePickup(isMyTeam) {
  if (isMyTeam) {
    playFile(window.YOUR_TEAM_PILE_PICKUP_URL, "yourTeamPilePickup");
  } else {
    playFile(window.ENEMY_TEAM_PILE_PICKUP_URL, "enemyTeamPilePickup");
  }
}

export function playRoundEnded() {
  playFile(window.ROUND_ENDED_URL, "roundEnded");
}

export function playCanastaMade() {
  playFile(window.CANASTA_MADE_URL, "canastaMade");
}

export function playPeakHandPickup() {
  playFile(window.PEAK_HAND_PICKUP_URL, "peakHandPickup");
}

export function playGameStart() {
  playFile(window.GAME_START_URL, "gameStart");
}
