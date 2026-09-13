// Butch: every card on the table is face down, so the board is mostly slots.
// What a tap does is decided server-side (data-butch-mode, from Butch#mode_for);
// this file only routes taps and drags to the matching hidden form, and flips
// cards up for the looks the server has handed this viewer.

// Kept outside the per-board handler so they survive the board being
// re-rendered by someone else's action mid-gesture — arming Match and then
// having another player's move redraw the board shouldn't silently disarm it.
let matchArmedFor = null;      // game id while Match is armed
let queenPick = {};            // { mine: {owner, slot}, theirs: {owner, slot} }
let queenPickFor = null;       // game id the pick belongs to

function flipUp(slotEl, card, className) {
  const img = slotEl.querySelector("img.butch-card-img");
  const src = (window.CARD_ASSET_MAP || {})[card];
  if (!img || !src) return;
  img.src = src;
  slotEl.classList.add("butch-revealed");
  if (className) slotEl.classList.add(className);
}

function flipDown(slotEl) {
  const img = slotEl.querySelector("img.butch-card-img");
  if (img && img.dataset.back) img.src = img.dataset.back;
  slotEl.classList.remove("butch-revealed", "butch-held", "butch-missed");
}

// A look lasts a few seconds from the moment it first reached this tab — not
// from each render — so the board being redrawn by other players' moves
// neither restarts the clock nor cuts it short. Held looks (a 10's target
// while you decide whether to trade) stay up until the server drops them.
function applyReveals(board, gameId) {
  const holder = document.getElementById("butch-reveals");
  if (!holder) return;

  let reveals = [];
  try { reveals = JSON.parse(holder.dataset.reveals || "[]"); } catch (_) { return; }

  reveals.forEach((r) => {
    const el = board.querySelector(`.butch-slot[data-owner="${r.owner}"][data-slot="${r.slot}"]`);
    if (!el) return;

    const isMiss = String(r.key).startsWith("miss");
    if (r.hold) { flipUp(el, r.card, "butch-held"); return; }

    const key = `r_cards_butch_reveal_${gameId}_${r.key}`;
    let started = 0;
    try { started = Number(sessionStorage.getItem(key)) || 0; } catch (_) {}
    if (!started) {
      started = Date.now();
      try { sessionStorage.setItem(key, String(started)); } catch (_) {}
    }

    const left = r.ms - (Date.now() - started);
    if (left <= 0) return;

    flipUp(el, r.card, isMiss ? "butch-missed" : null);
    setTimeout(() => flipDown(el), left);
  });
}

function nudge(el) {
  el.classList.remove("butch-nudge");
  void el.offsetWidth;
  el.classList.add("butch-nudge");
}

document.addEventListener("turbo:load", function () {
  const board = document.getElementById("game-container");
  if (!board || !board.classList.contains("butch-container")) return;

  // Once per board node — an error-only stream render re-fires turbo:load
  // against the same DOM, and binding twice would submit every tap twice.
  // Same guard as lucky_seven_cards.js.
  if (board.dataset.butchBound === "1") return;
  board.dataset.butchBound = "1";

  const gameId   = board.dataset.gameId;
  const mode     = board.dataset.butchMode;
  const matchBtn = document.getElementById("butch-match-toggle");
  const discard  = document.getElementById("butch-discard");
  const canMatch = !!matchBtn && !matchBtn.disabled;

  applyReveals(board, gameId);

  // ── Submitting ────────────────────────────────────────────────────────────

  const formIds = ["butch-peek-form", "butch-swap-form", "butch-power-form", "butch-match-form"];

  // One action in flight at a time; the flag lives on the form node, and is
  // released when a rejected action leaves that same form on the page.
  function submit(formId, fields) {
    const form = document.getElementById(formId);
    if (!form || form.dataset.submitting === "1") return;
    form.dataset.submitting = "1";
    ["slot", "target_player", "target_slot"].forEach((name) => {
      const input = form.querySelector(`input[name="${name}"]`);
      if (input) input.value = fields[name] ?? "";
    });
    form.requestSubmit ? form.requestSubmit() : form.submit();
  }

  formIds.forEach((id) => {
    document.getElementById(id)?.addEventListener("turbo:submit-end", function () {
      delete this.dataset.submitting;
    });
  });

  // ── Match ─────────────────────────────────────────────────────────────────

  function setArmed(on) {
    matchArmedFor = on ? gameId : null;
    board.classList.toggle("butch-match-armed", on);
    matchBtn?.classList.toggle("active", on);
  }

  setArmed(canMatch && matchArmedFor === gameId);

  matchBtn?.addEventListener("click", (e) => {
    e.stopPropagation();
    setArmed(matchArmedFor !== gameId);
  });

  function attemptMatch(slot) {
    setArmed(false);
    submit("butch-match-form", { slot });
  }

  // ── Queen: one of yours plus one of theirs, in either order ───────────────

  if (mode !== "queen" || queenPickFor !== gameId) queenPick = {};
  queenPickFor = gameId;

  function paintQueen() {
    board.querySelectorAll(".butch-slot.selected").forEach((el) => el.classList.remove("selected"));
    Object.values(queenPick).forEach((pick) => {
      board.querySelector(`.butch-slot[data-owner="${pick.owner}"][data-slot="${pick.slot}"]`)?.classList.add("selected");
    });
  }

  function pickForQueen(side, slotEl) {
    const pick = { owner: slotEl.dataset.owner, slot: slotEl.dataset.slot };
    const same = queenPick[side] && queenPick[side].owner === pick.owner && queenPick[side].slot === pick.slot;
    if (same) delete queenPick[side]; else queenPick[side] = pick;
    paintQueen();

    if (queenPick.mine && queenPick.theirs) {
      const { mine, theirs } = queenPick;
      queenPick = {};
      submit("butch-power-form", { slot: mine.slot, target_player: theirs.owner, target_slot: theirs.slot });
    }
  }

  // Drop a pick whose card has since gone (matched away on a re-render).
  Object.keys(queenPick).forEach((side) => {
    const pick = queenPick[side];
    if (!board.querySelector(`.butch-slot-full[data-owner="${pick.owner}"][data-slot="${pick.slot}"]`)) delete queenPick[side];
  });
  paintQueen();

  // ── Taps ──────────────────────────────────────────────────────────────────

  board.querySelectorAll(".butch-slots-mine .butch-slot-full").forEach((slotEl) => {
    slotEl.addEventListener("click", (e) => {
      e.stopPropagation();
      const slot = slotEl.dataset.slot;

      if (matchArmedFor === gameId) return attemptMatch(slot);

      switch (mode) {
        case "peek":     return submit("butch-peek-form", { slot });
        case "swap":     return submit("butch-swap-form", { slot });
        case "jack":
        case "ten_swap": return submit("butch-power-form", { slot });
        case "queen":    return pickForQueen("mine", slotEl);
        default:         return nudge(slotEl);
      }
    });
  });

  board.querySelectorAll(".butch-slots-opp .butch-slot-full").forEach((slotEl) => {
    slotEl.addEventListener("click", (e) => {
      e.stopPropagation();
      const targetable = slotEl.closest(".butch-seat")?.classList.contains("butch-seat-target");

      if (mode === "ten_look" && targetable) {
        return submit("butch-power-form", { target_player: slotEl.dataset.owner, target_slot: slotEl.dataset.slot });
      }
      if (mode === "queen" && targetable) return pickForQueen("theirs", slotEl);
      nudge(slotEl);
    });
  });

  // ── Drag one of your cards onto the discard to match it ───────────────────

  let dragged = null;

  board.querySelectorAll(".butch-slots-mine .butch-slot-full").forEach((slotEl) => {
    slotEl.addEventListener("dragstart", (e) => {
      if (!canMatch) { e.preventDefault(); return; }
      dragged = slotEl.dataset.slot;
      e.dataTransfer.setData("text/plain", dragged);
      e.dataTransfer.effectAllowed = "move";
      setTimeout(() => slotEl.classList.add("dragging"), 0);
    });
    slotEl.addEventListener("dragend", () => {
      slotEl.classList.remove("dragging");
      dragged = null;
    });
  });

  discard?.addEventListener("dragover", (e) => {
    if (dragged == null) return;
    e.preventDefault();
    e.dataTransfer.dropEffect = "move";
  });

  discard?.addEventListener("drop", (e) => {
    if (dragged == null) return;
    e.preventDefault();
    const slot = dragged;
    dragged = null;
    attemptMatch(slot);
  });
});

// Tapping away disarms Match, so a stray tap later doesn't throw a card.
// Bound once at module level rather than per board render.
document.addEventListener("click", (e) => {
  if (!matchArmedFor) return;
  if (e.target.closest(".butch-slot, #butch-match-toggle")) return;
  matchArmedFor = null;
  const board = document.getElementById("game-container");
  board?.classList.remove("butch-match-armed");
  document.getElementById("butch-match-toggle")?.classList.remove("active");
});
