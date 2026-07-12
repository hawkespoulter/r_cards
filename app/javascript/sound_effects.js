function playFile(url) {
  if (!url) return;
  new Audio(url).play().catch(() => {});
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
  picked.forEach(playFile);
}

export function playYourTurnKnock() {
  playFile(window.YOUR_TURN_KNOCK_URL);
}

export function playTeamPilePickup(isMyTeam) {
  playFile(isMyTeam ? window.YOUR_TEAM_PILE_PICKUP_URL : window.ENEMY_TEAM_PILE_PICKUP_URL);
}

export function playRoundEnded() {
  playFile(window.ROUND_ENDED_URL);
}

export function playCanastaMade() {
  playFile(window.CANASTA_MADE_URL);
}

export function playPeakHandPickup() {
  playFile(window.PEAK_HAND_PICKUP_URL);
}

export function playGameStart() {
  playFile(window.GAME_START_URL);
}
