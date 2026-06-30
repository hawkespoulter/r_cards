let audioCtx = null;

function ctx() {
  if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)();
  if (audioCtx.state === "suspended") audioCtx.resume();
  return audioCtx;
}

function tone(freq, duration, type, gainValue, delay = 0) {
  const c = ctx();
  const osc  = c.createOscillator();
  const gain = c.createGain();
  osc.type = type;
  osc.frequency.value = freq;
  gain.gain.value = gainValue;
  osc.connect(gain);
  gain.connect(c.destination);
  const start = c.currentTime + delay;
  osc.start(start);
  gain.gain.exponentialRampToValueAtTime(0.001, start + duration);
  osc.stop(start + duration);
}

export function playKnock() {
  tone(120, 0.1, "square", 0.25);
  tone(90, 0.12, "square", 0.2, 0.08);
}

export function playCardSound() {
  tone(600, 0.06, "triangle", 0.15);
}

export function playDealSound() {
  for (let i = 0; i < 4; i++) tone(500 + i * 30, 0.05, "triangle", 0.12, i * 0.05);
}
