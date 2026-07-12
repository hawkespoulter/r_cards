import { showCardModal } from "card_modal"
import { playCardPlayedSounds, playPeakHandPickup } from "sound_effects"

// These three behaviors bind to `document` itself, which persists across
// Turbo Stream renders (unlike the elements inside #game-container, which
// get replaced wholesale). Re-running the whole turbo:load handler on every
// stream render is otherwise safe (old per-element listeners just vanish
// with their elements), but re-registering document-level listeners every
// time would accumulate one extra copy per action for the life of the page.
// So these get assigned fresh each load, but bound to `document` only once,
// via a stable delegating wrapper.
let handleOutsideClick = null;
let handleMarqueeMouseDown = null;
let handleSuppressedClick = null;
let globalHandlersBound = false;

// Elements that count as "still interacting with the board", not "clicked
// away from it" — shared by handleOutsideClick (don't clear a selection just
// because the draw pile, a settings button, etc. was clicked) and
// handleMarqueeMouseDown (don't start a rubber-band drag from on top of
// them). Buttons in particular matter here: the draw pile, pickup pile, and
// undo-meld are all plain <button>s outside #canasta-hand, so without this
// exclusion, clicking any of them looked like "click outside the hand" and
// wiped out a selection you were still building for later.
const BOARD_INTERACTIVE_SELECTOR =
  ".hand-card-wrap, button, a, input, textarea, select, label, .round-history-modal, .settings-panel, .profile-dropdown, .color-picker-dropdown, .meld-group, .canasta-single, .draw-pile-block, #discard-pile-drop, #red-three-drop, #new-meld-drop";

// Builds an off-screen fanned stack of the given cards to use as a custom
// drag image, so dragging a multi-card selection shows all of it instead of
// just the single card the browser grabbed under the cursor.
function buildDragImage(cards) {
  const el = document.createElement("div");
  el.style.position = "fixed";
  el.style.top = "-9999px";
  el.style.left = "-9999px";
  el.style.display = "flex";
  el.style.pointerEvents = "none";

  cards.forEach((card, i) => {
    const img = document.createElement("img");
    img.src = (window.CARD_ASSET_MAP && window.CARD_ASSET_MAP[card]) || "";
    img.style.width = "60px";
    img.style.borderRadius = "5px";
    img.style.boxShadow = "0 4px 10px rgba(0,0,0,0.5)";
    img.style.marginLeft = i === 0 ? "0" : "-36px";
    el.appendChild(img);
  });

  document.body.appendChild(el);
  return el;
}

// ── Condense hand into single row by overlapping cards ───────────────────
// Re-queries the DOM fresh on every call, so it's safe to invoke repeatedly
// (once per turbo:load) and to bind its resize listener exactly once here
// at module scope rather than re-adding a listener on every render.
function condenseHand() {
  const hand = document.getElementById("canasta-hand");
  if (!hand) return;
  const wraps = Array.from(hand.querySelectorAll(".hand-card-wrap"));
  if (wraps.length === 0) return;

  wraps.forEach(c => c.style.marginLeft = "");
  const cardWidth = wraps[0].getBoundingClientRect().width;
  const gap = 8;
  const naturalWidth = wraps.length * cardWidth + (wraps.length - 1) * gap;
  const available = hand.parentElement.getBoundingClientRect().width - 48;

  if (naturalWidth <= available) {
    wraps.forEach((c, i) => { c.style.marginLeft = i === 0 ? "0" : `${gap}px`; });
  } else {
    const overlap = (naturalWidth - available) / (wraps.length - 1);
    const marginLeft = gap - overlap;
    wraps.forEach((c, i) => { c.style.marginLeft = i === 0 ? "0" : `${marginLeft}px`; });
  }
}
window.addEventListener("resize", condenseHand);

// Extra buffer (in px) subtracted from the measured available width before
// deciding whether the completed-canasta row needs to compress. Tune this
// by hand: raise it if cards can still reach the piles column before
// overlap kicks in, lower it if they're compressing sooner than they need
// to. This exists because the "available" measurement below is a best
// effort at the melds column's real width — if it's ever slightly off, this
// margin is the knob to compensate without having to re-derive the CSS math.
const CANASTA_ROW_SAFETY_MARGIN = 130;

// ── Shrink the overlap between completed-canasta cards instead of wrapping
// to a second row when the row is too narrow. Unlike condenseHand, adjacent
// cards here don't all overlap by the same amount (canasta-canasta pairs,
// red-three-red-three pairs, and the junction between the two groups each
// have their own CSS-defined spacing), so instead of assuming one uniform
// gap, this reads each card's own natural margin-left off the CSS first and
// then subtracts the same extra amount from all of them to close the gap.
// A completed canasta alternates "horizontal"/"vertical" orientation
// (.canasta-horizontal rotates the inner .canasta-rep-card 90deg) — CSS
// transforms don't affect layout, so a rotated card's *own* bounding rect
// correctly reflects its swapped, painted width/height, but the outer
// .canasta-single wrapper's rect does not (a child's transform never
// enlarges its parent's layout box). Falls back to the wrapper's own rect
// for cards with no such child (red threes, or if markup ever changes).
function canastaCardVisualWidth(card) {
  const rep = card.querySelector(".canasta-rep-card");
  return (rep || card).getBoundingClientRect().width;
}

function condenseCanastaRows() {
  document.querySelectorAll(".canasta-completed-row").forEach((row) => {
    const cards = Array.from(row.children);
    if (cards.length < 2) return;

    cards.forEach((c) => c.style.marginLeft = "");
    const naturalMargins = cards.map((c) => parseFloat(getComputedStyle(c).marginLeft) || 0);
    const naturalWidth = cards.reduce(
      (sum, c, i) => sum + canastaCardVisualWidth(c) + (i === 0 ? 0 : naturalMargins[i]),
      0
    );
    // Measured against the melds column, not the row itself: .my-melds-col/
    // .opp-melds-col use align-items: flex-start/flex-end rather than
    // stretch, so the row (and its .canasta-area parent) are free to size
    // to their own natural content width rather than being capped at the
    // column's real flex: 1; min-width: 0 width — meaning the row's own
    // rect can already reflect an overflowed, too-wide size by the time
    // it's measured, letting cards spill into the piles column before
    // compression ever kicks in. The column itself is the one width in
    // this chain that's actually guaranteed to stay put.
    const col = row.closest(".my-melds-col, .opp-melds-col");
    // CANASTA_ROW_SAFETY_MARGIN (top of file) is subtracted here as extra
    // buffer — bump it up if cards still reach the piles column before
    // compressing, or down if they're compressing sooner than necessary.
    const available = (col || row).getBoundingClientRect().width - CANASTA_ROW_SAFETY_MARGIN;
    if (naturalWidth <= available) return;

    const extraOverlap = (naturalWidth - available) / (cards.length - 1);
    cards.forEach((c, i) => {
      if (i === 0) return;
      c.style.marginLeft = `${naturalMargins[i] - extraOverlap}px`;
    });
  });
}
window.addEventListener("resize", condenseCanastaRows);

// ── Size each meld's hover count overlay to fill as much of that meld's
// box as it can without overflowing, shrinking from a generous starting
// size until both dimensions fit. Box sizes don't change on hover itself,
// so this only needs to run on load/resize, not per-hover. ────────────────
function fitMeldCountOverlays() {
  document.querySelectorAll(".meld-hoverable").forEach((container) => {
    const textEl = container.querySelector(".meld-count-text");
    if (!textEl) return;

    const maxWidth = container.clientWidth - 12;
    const maxHeight = container.clientHeight - 12;
    if (maxWidth <= 0 || maxHeight <= 0) return;

    let fontSize = Math.max(10, Math.min(maxWidth, maxHeight));
    textEl.style.fontSize = `${fontSize}px`;

    let guard = 0;
    while ((textEl.scrollWidth > maxWidth || textEl.scrollHeight > maxHeight) && fontSize > 8 && guard < 200) {
      fontSize -= 1;
      textEl.style.fontSize = `${fontSize}px`;
      guard++;
    }
  });
}
window.addEventListener("resize", fitMeldCountOverlays);

// ── Long-press to reveal meld/pile counts on touch devices ─────────────────
// Real :hover (see game.scss) only fires the overlay for a genuine mouse —
// touch instead needs a deliberate sustained press, so an ordinary tap or
// drag doesn't flash it. Called once per render on the (then-fresh)
// .meld-hoverable elements, same as the other per-element bindings below.
const LONG_PRESS_MS = 400;
// Once revealed, stays up for a beat after the finger lifts instead of
// vanishing the instant touch ends, so there's time to actually read it
// (and so it visibly fades out via .meld-count-overlay's opacity transition
// instead of just disappearing).
const RELEASE_DELAY_MS = 1000;

function setupLongPress() {
  document.querySelectorAll(".meld-hoverable").forEach((el) => {
    let pressTimer = null;
    let releaseTimer = null;

    const cancelPress = () => {
      if (pressTimer) {
        clearTimeout(pressTimer);
        pressTimer = null;
      }
    };
    const cancelRelease = () => {
      if (releaseTimer) {
        clearTimeout(releaseTimer);
        releaseTimer = null;
      }
    };

    el.addEventListener("touchstart", () => {
      cancelPress();
      cancelRelease();
      pressTimer = setTimeout(() => {
        pressTimer = null;
        el.classList.add("long-press-active");
      }, LONG_PRESS_MS);
    }, { passive: true });

    const onRelease = () => {
      cancelPress();
      if (!el.classList.contains("long-press-active")) return;
      cancelRelease();
      releaseTimer = setTimeout(() => {
        el.classList.remove("long-press-active");
        releaseTimer = null;
      }, RELEASE_DELAY_MS);
    };
    el.addEventListener("touchend", onRelease);
    el.addEventListener("touchcancel", onRelease);

    // Moving before the hold has activated cancels it (not a deliberate
    // press); moving after it's already showing doesn't hide it early —
    // only lifting the finger starts the release countdown.
    el.addEventListener("touchmove", () => {
      if (!el.classList.contains("long-press-active")) cancelPress();
    });

    // Without this, a sustained press on the card image opens the browser's
    // own long-press context menu (Android's "open/save image", etc.) at the
    // same time as our long-press — the CSS touch-callout/user-select rules
    // in game.scss cover Safari, but Android's menu needs this too.
    el.addEventListener("contextmenu", (e) => e.preventDefault());
  });
}

// Identity of the last #canasta-hand node this handler bound listeners to.
// An error-only Turbo Stream response (e.g. "Not your turn") replaces only
// the flash-error partial, leaving #game-container — and everything in it —
// completely untouched. turbo:load still re-fires for that render (see
// application.js's redispatch hook), so without this guard every per-element
// listener below would get bound a second time to the exact same DOM nodes,
// and the next click would submit the action twice. A real board update
// always produces a brand-new #canasta-hand node, so comparing by identity
// reliably tells the two cases apart.
let lastBoundHand = null;

// Whether the round-by-round score popup should be open — see the
// round-history binding block below for why this needs to persist across
// #game-container re-renders instead of relying on the "open" class alone.
let roundHistoryOpen = false;

// Selected hand cards, keyed by a card-identity string ("<code>#<occurrence>",
// e.g. the second "d10" in hand is "d10#1") rather than DOM position, so a
// selection survives the hand being torn down and re-rendered from under it
// — which now happens on every board sync, not just your own actions. This
// is what makes selecting cards while waiting for your turn stick around
// instead of vanishing the moment anyone else acts. Only an explicit
// deselect (click away, or actually playing the selected cards) clears it.
let persistedSelectionKeys = new Set();

function cardSelectionKey(card, occurrence) {
  return `${card}#${occurrence}`;
}

document.addEventListener("turbo:load", function () {
  // ── Recolor the whole page background to match "my turn" state ───────────
  const gameContainerEl = document.querySelector(".game-container");
  document.body.classList.toggle("my-turn-bg", !!gameContainerEl?.classList.contains("my-turn"));

  // ── Play errors as centred popup ──────────────────────────────────────────
  // Lives outside #game-container (in the layout's flash-error-container),
  // so it must be checked on every render, including the error-only ones the
  // guard below skips past.
  const flashError = document.querySelector("[data-flash-error]");
  if (flashError) {
    showCardModal({ title: flashError.dataset.flashError });
    // Remove it immediately — turbo:load can now fire repeatedly (once per
    // Turbo Stream render, not just full page loads), and without removing
    // this the same stale error would re-pop on every subsequent action.
    flashError.remove();
  }

  // ── Round-by-round score popup (click a team score chip to open) ─────────
  // Needs to work in every canasta phase (pregame, active play, round
  // summary, game over), not just while a hand exists, so this can't live
  // behind the #canasta-hand guard below. Each element tracks its own
  // "already bound" flag directly (rather than comparing a container's
  // identity across renders) so a freshly-replaced element always gets
  // bound exactly once, regardless of how many other regions did or didn't
  // change in the same render.
  //
  // The "open" class itself is purely client-side state, but #round-history-
  // popup lives inside #game-container, which syncBoard() replaces wholesale
  // on every board update — including ones triggered by someone else's
  // action, not just your own. Without persisting the open/closed intent
  // here (roundHistoryOpen, mirroring persistedSelectionKeys above), the
  // freshly-rendered popup always comes back closed, silently kicking
  // whoever had it open the moment anyone at the table played a card.
  document.querySelectorAll(".round-history-trigger").forEach((trigger) => {
    if (trigger.dataset.historyBound) return;
    trigger.dataset.historyBound = "1";
    trigger.addEventListener("click", () => {
      roundHistoryOpen = true;
      document.getElementById("round-history-popup")?.classList.add("open");
    });
  });

  const roundHistoryClose = document.getElementById("round-history-close");
  if (roundHistoryClose && !roundHistoryClose.dataset.historyBound) {
    roundHistoryClose.dataset.historyBound = "1";
    roundHistoryClose.addEventListener("click", () => {
      roundHistoryOpen = false;
      document.getElementById("round-history-popup")?.classList.remove("open");
    });
  }

  const roundHistoryPopup = document.getElementById("round-history-popup");
  if (roundHistoryPopup) {
    if (roundHistoryOpen) roundHistoryPopup.classList.add("open");

    if (!roundHistoryPopup.dataset.historyBound) {
      roundHistoryPopup.dataset.historyBound = "1";
      roundHistoryPopup.addEventListener("click", (e) => {
        if (e.target === roundHistoryPopup) {
          roundHistoryOpen = false;
          roundHistoryPopup.classList.remove("open");
        }
      });
    }
  }

  // ── Pregame team-name inputs (host only) ───────────────────────────────────
  // Runs on the pregame team-setup screen, which has no #canasta-hand, so
  // this has to live up here rather than below the hand guard (the same
  // reason the round-history bindings above do).
  //
  // Only saves on "Start Game" — a save's turbo_stream response replaces the
  // *entire* #game-container, including whichever team-name input the user
  // might be in, so saving on typing or on blur risked destroying/recreating
  // a field out from under the user's cursor while they were still using it.
  // Deferring to the one moment the user is done with the whole panel avoids
  // that entirely.
  document.querySelectorAll(".btn-start").forEach(function (btn) {
    btn.addEventListener("click", function () {
      const forms = document.querySelectorAll(".team-setup-name-form");
      if (!forms.length) return;
      // Both team names have to go in a single request — update_settings
      // does a read-modify-write on the whole settings column (load the
      // record, set one field in memory, save the whole column back), so two
      // separate PATCHes fired close together race: whichever one saves last
      // overwrites the other's change, since neither request's in-memory
      // copy knows about the other's edit. Folding every other form's
      // current value into the first as a hidden field submits everything
      // in one shot instead.
      const primary = forms[0];
      forms.forEach(function (form, i) {
        if (i === 0) return;
        const input = form.querySelector(".team-setup-name-input");
        if (!input) return;
        const hidden = document.createElement("input");
        hidden.type = "hidden";
        hidden.name = input.name;
        hidden.value = input.value;
        primary.appendChild(hidden);
      });
      primary.requestSubmit();
    });
  });

  const hand = document.getElementById("canasta-hand");
  if (hand === lastBoundHand) return;
  lastBoundHand = hand;
  if (!hand) {
    // Scum page, or a canasta phase with no hand (pregame/round-summary/
    // game-over). Drop any persisted selection here rather than carrying it
    // into next round's freshly-dealt hand, where matching "<code>#<n>" keys
    // could coincidentally pre-select an unrelated card.
    persistedSelectionKeys.clear();
    return;
  }

  // ── "You drew these cards" popup (once per draw) ───────────────────────────
  const drawInfo = document.querySelector("[data-last-draw]");
  if (drawInfo) {
    const container = document.querySelector("[data-game-id]");
    const gameId     = container?.dataset.gameId;
    const myPlayerId = container?.dataset.playerId;
    const drawPlayer = drawInfo.dataset.drawPlayer;
    const seq        = drawInfo.dataset.drawSeq;
    const cards      = JSON.parse(drawInfo.dataset.drawCards || "[]");

    if (gameId && myPlayerId && drawPlayer === myPlayerId) {
      const key = `r_cards_canasta_draw_${gameId}_${seq}`;
      if (sessionStorage.getItem(key) !== "1") {
        sessionStorage.setItem(key, "1");
        if (cards.length) {
          playCardPlayedSounds(cards.length);
          showCardModal({ title: "You drew these cards", cards });
        }
      }
    }
  }

  // ── Discard sound (once per discard, actor only) ────────────────────────────
  const discardInfo = document.querySelector("[data-last-discard]");
  if (discardInfo) {
    const container4     = document.querySelector("[data-game-id]");
    const gameId4         = container4?.dataset.gameId;
    const myPlayerId4     = container4?.dataset.playerId;
    const discardPlayer   = discardInfo.dataset.discardPlayer;
    const seq4            = discardInfo.dataset.discardSeq;

    if (gameId4 && myPlayerId4 && discardPlayer === myPlayerId4) {
      const key4 = `r_cards_canasta_discard_${gameId4}_${seq4}`;
      if (sessionStorage.getItem(key4) !== "1") {
        sessionStorage.setItem(key4, "1");
        playCardPlayedSounds(1);
      }
    }
  }

  // ── Red three played sound (once per play, actor only) ──────────────────────
  const redThreePlayInfo = document.querySelector("[data-last-red-three-play]");
  if (redThreePlayInfo) {
    const container5     = document.querySelector("[data-game-id]");
    const gameId5         = container5?.dataset.gameId;
    const myPlayerId5     = container5?.dataset.playerId;
    const redThreePlayer  = redThreePlayInfo.dataset.redThreePlayer;
    const seq5            = redThreePlayInfo.dataset.redThreeSeq;
    const redThreeCount   = parseInt(redThreePlayInfo.dataset.redThreeCount || "0", 10);

    if (gameId5 && myPlayerId5 && redThreePlayer === myPlayerId5) {
      const key5 = `r_cards_canasta_red_three_${gameId5}_${seq5}`;
      if (sessionStorage.getItem(key5) !== "1") {
        sessionStorage.setItem(key5, "1");
        playCardPlayedSounds(redThreeCount);
      }
    }
  }

  // ── "You picked up the pile" popup (once per pickup) ───────────────────────
  const pickupInfo = document.querySelector("[data-last-pickup]");
  if (pickupInfo) {
    const container3    = document.querySelector("[data-game-id]");
    const gameId3        = container3?.dataset.gameId;
    const myPlayerId3    = container3?.dataset.playerId;
    const pickupPlayer   = pickupInfo.dataset.pickupPlayer;
    const seq3           = pickupInfo.dataset.pickupSeq;
    const pickedUpCards  = JSON.parse(pickupInfo.dataset.pickupCards || "[]");

    if (gameId3 && myPlayerId3 && pickupPlayer === myPlayerId3) {
      const key3 = `r_cards_canasta_pickup_${gameId3}_${seq3}`;
      if (sessionStorage.getItem(key3) !== "1") {
        sessionStorage.setItem(key3, "1");
        if (pickedUpCards.length) {
          showCardModal({ title: "You picked up the pile!", cards: pickedUpCards, duration: 3000, autoDismiss: true });
        }
      }
    }
  }

  // ── Apply the signed-in user's chosen card back to all face-down card
  // images — server-rendered per-viewer (see current_user.card_back_key in
  // _canasta_game.html.erb), so this is already correct for whoever's
  // looking regardless of who else is at the table. ─────────────────────────
  const gameContainer = document.querySelector("[data-card-back]");
  if (gameContainer) {
    const backSrc = gameContainer.dataset.cardBack;
    document.querySelectorAll("img.pile-card, .peak-hand-stack img").forEach(img => {
      if (img.src.includes("blank_card") || img.src.includes("/cards/backs/")) img.src = backSrc;
    });
  }

  // ── Canasta completed popup (for the acting player) ───────────────────────
  const canastaInfo = document.querySelector("[data-last-canasta]");
  if (canastaInfo) {
    const container0 = document.querySelector("[data-game-id]");
    const gameId0 = container0?.dataset.gameId;
    const rank0 = canastaInfo.dataset.canastaRank;
    const seq0 = canastaInfo.dataset.canastaSeq;
    if (gameId0 && rank0) {
      const key0 = `r_cards_canasta_made_${gameId0}_${seq0}`;
      if (sessionStorage.getItem(key0) !== "1") {
        sessionStorage.setItem(key0, "1");
        const rankCard0 = rank0 === "jo" ? "jo" : "h" + rank0;
        const canastaCards0 = JSON.parse(canastaInfo.dataset.canastaCards || "[]");
        showCardModal({
          title: "Canasta!",
          cards: canastaCards0.length ? canastaCards0 : [rankCard0],
          confetti: true,
          confettiCard: rankCard0,
          duration: 2800,
          autoDismiss: true
        });
      }
    }
  }

  // ── "Your peak hand" popup on first canasta ───────────────────────────────
  const footInfo = document.querySelector("[data-foot-pickup]");
  if (footInfo) {
    const container2 = document.querySelector("[data-game-id]");
    const gameId2 = container2?.dataset.gameId;
    const seq2 = footInfo.dataset.footSeq;
    const footCards = JSON.parse(footInfo.dataset.footCards || "[]");
    if (gameId2 && footCards.length) {
      const key2 = `r_cards_canasta_foot_${gameId2}_${seq2}`;
      if (sessionStorage.getItem(key2) !== "1") {
        sessionStorage.setItem(key2, "1");
        playPeakHandPickup();
        showCardModal({ title: "Your peak hand — added to your hand!", cards: footCards });
      }
    }
  }

  // ── Card back picker selection highlight ──────────────────────────────────
  document.querySelectorAll(".card-back-option").forEach(opt => {
    opt.addEventListener("click", function () {
      document.querySelectorAll(".card-back-option").forEach(o => o.classList.remove("selected"));
      this.classList.add("selected");
    });
  });

  condenseHand();
  condenseCanastaRows();
  fitMeldCountOverlays();
  setupLongPress();

  const totalEl = document.getElementById("meld-running-total");
  // Points already committed to melds earlier this turn (server-computed,
  // zero unless it's this viewer's own turn — a teammate's in-progress
  // total shouldn't show up on your screen) — the displayed total should
  // track cumulative progress toward the initial-meld threshold, not just
  // whatever's presently selected in hand.
  const turnMeldedPoints = parseInt(hand?.dataset.turnMeldedPoints || "0", 10);
  // Map<cardIndex, cardCode> for this render's DOM — index is unique per DOM
  // position so duplicate ranks (e.g. two "dt" from different decks) are
  // tracked independently. Seeded below from persistedSelectionKeys so a
  // selection made before this render survives into it.
  const selected = new Map();
  // idx -> that card's persistedSelectionKeys key, so toggling by DOM
  // position (clicks, marquee) can keep the persisted set in sync.
  const keyForIndex = [];

  function cardPoints(card) {
    if (card === "jo") return 50;
    const rank = card.slice(1).toLowerCase();
    if (rank === "2" || rank === "a") return 20;
    const rankValues = { "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8, "9": 9, "10": 10, "j": 11, "q": 12, "k": 13, "a": 14 };
    const v = rankValues[rank] || 0;
    return v >= 9 ? 10 : 5;
  }

  function refreshTotal() {
    if (!totalEl) return;
    let total = turnMeldedPoints;
    selected.forEach((card) => { total += cardPoints(card); });
    totalEl.textContent = total;
  }

  function selectedCards() {
    return Array.from(selected.values());
  }

  // Clears the selection outright — used when clicking away, and when the
  // selected cards have actually been played (meld/discard/red-three), so a
  // spent selection doesn't linger and risk matching a different card of the
  // same rank drawn later.
  function clearSelection() {
    if (selected.size === 0) return;
    selected.forEach((_card, idx) => persistedSelectionKeys.delete(keyForIndex[idx]));
    selected.clear();
    hand.querySelectorAll(".hand-card-wrap.selected").forEach((el) => el.classList.remove("selected"));
    refreshTotal();
  }

  const occurrenceCounts = {};
  hand.querySelectorAll(".hand-card-wrap").forEach((wrap, idx) => {
    const card = wrap.dataset.card;
    const occurrence = occurrenceCounts[card] || 0;
    occurrenceCounts[card] = occurrence + 1;
    const key = cardSelectionKey(card, occurrence);
    keyForIndex[idx] = key;

    if (persistedSelectionKeys.has(key)) {
      selected.set(idx, card);
      // Restoring a persisted selection onto a freshly-rendered card, not a
      // user toggling it just now — apply the raised .selected position and
      // its yellow outline instantly instead of letting them animate in.
      // Both .hand-card-wrap (the raise) and its inner .game-card (the
      // box-shadow outline) have their own separate transitions, so both
      // need suppressing — otherwise the outline still visibly fades in
      // even once the position jump itself is fixed. Force a reflow between
      // removing and restoring so the instant jump is actually committed
      // before transitions are re-enabled.
      const img = wrap.querySelector(".game-card");
      wrap.style.transition = "none";
      if (img) img.style.transition = "none";
      wrap.classList.add("selected");
      void wrap.offsetHeight;
      wrap.style.transition = "";
      if (img) img.style.transition = "";
    }

    wrap.addEventListener("click", function () {
      if (selected.has(idx)) {
        selected.delete(idx);
        persistedSelectionKeys.delete(key);
        this.classList.remove("selected");
      } else {
        selected.set(idx, card);
        persistedSelectionKeys.add(key);
        this.classList.add("selected");
      }
      refreshTotal();
    });
  });
  refreshTotal(); // reflect any selection just restored above

  // ── Clicking anywhere outside the hand/board controls deselects all
  // selected cards. Excludes BOARD_INTERACTIVE_SELECTOR so drawing, opening
  // settings, undoing a meld, etc. don't read as "clicked away" — only
  // actual dead space (or a hand card, handled separately below) does. ────
  handleOutsideClick = function (e) {
    if (e.target.closest(BOARD_INTERACTIVE_SELECTOR)) return;
    clearSelection();
  };

  // ── Marquee (rubber-band) selection — click-drag anywhere on the page
  // (not starting on a card or another interactive control, so single-card
  // drag-to-play and buttons/links/inputs still work normally) to select
  // every hand card the box passes over, same effect as clicking each one. ──
  let marqueeBox = null;
  let marqueeActive = false;
  let marqueeStartX = 0;
  let marqueeStartY = 0;
  let marqueeBaseKeys = new Set();
  // Indices the box has covered at any point during the current drag. Once a
  // card is hit it stays flipped for the rest of the gesture even if the box
  // later shrinks away from it (e.g. the cursor's path isn't a perfectly
  // monotonic line to the release point) — otherwise a card briefly swept
  // over mid-drag but no longer under the box at mouseup silently reverts to
  // unselected, which is what caused a couple of cards in a "drag across the
  // whole hand" gesture to end up not selected.
  let marqueeHitKeys = new Set();
  let suppressNextClick = false;

  function rectsIntersect(a, b) {
    return a.left < b.right && a.right > b.left && a.top < b.bottom && a.bottom > b.top;
  }

  function onMarqueeMove(e) {
    const dx = e.clientX - marqueeStartX;
    const dy = e.clientY - marqueeStartY;

    if (!marqueeActive) {
      if (Math.hypot(dx, dy) < 4) return;
      marqueeActive = true;
      marqueeBaseKeys = new Set(selected.keys());
      marqueeHitKeys = new Set();
      marqueeBox = document.createElement("div");
      marqueeBox.className = "marquee-select-box";
      document.body.appendChild(marqueeBox);
    }

    const left = Math.min(e.clientX, marqueeStartX);
    const top = Math.min(e.clientY, marqueeStartY);
    const width = Math.abs(dx);
    const height = Math.abs(dy);
    marqueeBox.style.left = `${left}px`;
    marqueeBox.style.top = `${top}px`;
    marqueeBox.style.width = `${width}px`;
    marqueeBox.style.height = `${height}px`;

    const boxRect = { left, top, right: left + width, bottom: top + height };
    const wraps = hand.querySelectorAll(".hand-card-wrap");

    // Cards ever covered by the box this drag flip from their pre-drag
    // state — so dragging over unselected cards selects them, and dragging
    // over already-selected cards deselects them (both in the same sweep).
    wraps.forEach((wrap, idx) => {
      if (rectsIntersect(wrap.getBoundingClientRect(), boxRect)) {
        marqueeHitKeys.add(idx);
      }
      const wasSelected = marqueeBaseKeys.has(idx);
      const everHit = marqueeHitKeys.has(idx);
      const shouldBeSelected = everHit ? !wasSelected : wasSelected;
      const isSelected = selected.has(idx);
      if (shouldBeSelected && !isSelected) {
        selected.set(idx, wrap.dataset.card);
        persistedSelectionKeys.add(keyForIndex[idx]);
        wrap.classList.add("selected");
      } else if (!shouldBeSelected && isSelected) {
        selected.delete(idx);
        persistedSelectionKeys.delete(keyForIndex[idx]);
        wrap.classList.remove("selected");
      }
    });
    refreshTotal();
  }

  function onMarqueeUp() {
    document.removeEventListener("mousemove", onMarqueeMove);
    if (marqueeBox) {
      marqueeBox.remove();
      marqueeBox = null;
    }
    if (marqueeActive) suppressNextClick = true;
    marqueeActive = false;
  }

  handleMarqueeMouseDown = function (e) {
    if (e.button !== 0) return;
    if (e.target.closest(BOARD_INTERACTIVE_SELECTOR)) return;
    e.preventDefault();
    marqueeStartX = e.clientX;
    marqueeStartY = e.clientY;
    document.addEventListener("mousemove", onMarqueeMove);
    document.addEventListener("mouseup", onMarqueeUp, { once: true });
  };

  // A completed drag-select still ends in a native "click" on whatever the
  // pointer lands on — swallow it so it doesn't also toggle that card or
  // trigger the "click outside" deselect handler above.
  handleSuppressedClick = function (e) {
    if (!suppressNextClick) return;
    suppressNextClick = false;
    e.stopPropagation();
    e.preventDefault();
  };

  if (!globalHandlersBound) {
    globalHandlersBound = true;
    document.addEventListener("click", (e) => handleOutsideClick?.(e));
    document.addEventListener("mousedown", (e) => handleMarqueeMouseDown?.(e));
    document.addEventListener("click", (e) => handleSuppressedClick?.(e), true);
  }

  // ── Drag cards from hand — always enabled, since playing a red three isn't
  // gated by whose turn it is (unlike melding/discarding/pickup below). ──────
  let dragCards = [];
  // Whether the current drag is the selection itself (vs. an ad-hoc single
  // unselected card) — only clear the selection on a successful drop if it
  // was actually what got played, so playing an unrelated card doesn't wipe
  // out a selection you're still building for later.
  let dragFromSelection = false;

  hand.querySelectorAll(".hand-card-wrap").forEach((wrap, idx) => {
    wrap.setAttribute("draggable", "true");

    wrap.addEventListener("dragstart", function (e) {
      const card = this.dataset.card;
      dragFromSelection = selected.has(idx);
      dragCards = dragFromSelection ? selectedCards() : [card];
      e.dataTransfer.clearData();
      e.dataTransfer.effectAllowed = "move";
      e.dataTransfer.setData("text/plain", JSON.stringify(dragCards));
      this.classList.add("dragging");

      if (dragCards.length > 1) {
        const dragImg = buildDragImage(dragCards);
        const totalWidth = 60 + (dragCards.length - 1) * 24;
        e.dataTransfer.setDragImage(dragImg, totalWidth / 2, 42);
        setTimeout(() => dragImg.remove(), 0);
      }
    });

    wrap.addEventListener("dragend", function () {
      this.classList.remove("dragging");
    });
  });

  // ── Click the discard pile to pick it up (no hand selection required) ────
  const pickupForm = document.getElementById("pickup-form");
  const discardPileForPickup = document.getElementById("discard-pile-drop");
  if (pickupForm && discardPileForPickup) {
    discardPileForPickup.classList.add("pile-clickable");
    discardPileForPickup.addEventListener("click", function () {
      pickupForm.requestSubmit();
    });
  }

  // ── Drag one or more red threes from hand onto your red-three area, any
  // time — every dragged card must be a red three, so a mixed selection is
  // rejected rather than silently dropping the non-red-three cards. ────────
  function isRedThree(card) {
    return typeof card === "string" && card.slice(1).toLowerCase() === "3" && (card[0] === "h" || card[0] === "d");
  }

  const redThreeForm = document.getElementById("red-three-form");
  const redThreeInput = document.getElementById("red-three-cards-input");
  const redThreeDrop = document.getElementById("red-three-drop");
  if (redThreeForm && redThreeInput && redThreeDrop) {
    redThreeDrop.addEventListener("dragover", function (e) {
      if (dragCards.length === 0 || !dragCards.every(isRedThree)) return;
      e.preventDefault();
      e.dataTransfer.dropEffect = "move";
      this.classList.add("drag-over");
    });

    redThreeDrop.addEventListener("dragleave", function (e) {
      if (!this.contains(e.relatedTarget)) {
        this.classList.remove("drag-over");
      }
    });

    redThreeDrop.addEventListener("drop", function (e) {
      e.preventDefault();
      this.classList.remove("drag-over");
      if (dragCards.length === 0 || !dragCards.every(isRedThree)) return;
      redThreeInput.value = JSON.stringify(dragCards);
      if (dragFromSelection) clearSelection();
      redThreeForm.requestSubmit();
    });

    // ── Tap-to-play fallback — drag-and-drop doesn't work in mobile Safari,
    // so select card(s) in your hand first, then tap here to play them. ────
    redThreeDrop.addEventListener("click", function () {
      const cards = selectedCards();
      if (cards.length === 0 || !cards.every(isRedThree)) return;
      redThreeInput.value = JSON.stringify(cards);
      clearSelection();
      redThreeForm.requestSubmit();
    });
  }

  const meldForm = document.getElementById("meld-form");
  const meldInput = document.getElementById("meld-cards-input");
  const meldTargetRankInput = document.getElementById("meld-target-rank-input");
  const discardForm = document.getElementById("discard-form");
  const discardInput = document.getElementById("discard-card-input");

  // ── Drag cards from hand onto melds (in-progress or already-completed
  // canastas — you can still add matching cards to a finished canasta) ─────
  if (meldForm && meldInput) {
    document.querySelectorAll(".meld-group[data-meld-rank], .canasta-single[data-meld-rank]").forEach(function (group) {
      group.addEventListener("dragover", function (e) {
        e.preventDefault();
        e.dataTransfer.dropEffect = "move";
        this.classList.add("drag-over");
      });

      group.addEventListener("dragleave", function (e) {
        if (!this.contains(e.relatedTarget)) {
          this.classList.remove("drag-over");
        }
      });

      group.addEventListener("drop", function (e) {
        e.preventDefault();
        this.classList.remove("drag-over");
        meldInput.value = JSON.stringify(dragCards);
        if (meldTargetRankInput) meldTargetRankInput.value = this.dataset.meldRank;
        if (dragFromSelection) clearSelection();
        meldForm.requestSubmit();
      });

      // Tap-to-play fallback (see red-three tap handler above for why).
      group.addEventListener("click", function () {
        const cards = selectedCards();
        if (cards.length === 0) return;
        meldInput.value = JSON.stringify(cards);
        if (meldTargetRankInput) meldTargetRankInput.value = this.dataset.meldRank;
        clearSelection();
        meldForm.requestSubmit();
      });
    });

    // ── Drag cards onto an empty spot to start a brand-new meld ──────────────
    const newMeldDrop = document.getElementById("new-meld-drop");
    if (newMeldDrop) {
      newMeldDrop.classList.add("meld-drop-enabled");

      newMeldDrop.addEventListener("dragover", function (e) {
        e.preventDefault();
        e.dataTransfer.dropEffect = "move";
        this.classList.add("drag-over");
      });

      newMeldDrop.addEventListener("dragleave", function (e) {
        if (!this.contains(e.relatedTarget)) {
          this.classList.remove("drag-over");
        }
      });

      newMeldDrop.addEventListener("drop", function (e) {
        e.preventDefault();
        this.classList.remove("drag-over");
        meldInput.value = JSON.stringify(dragCards);
        if (meldTargetRankInput) meldTargetRankInput.value = "";
        if (dragFromSelection) clearSelection();
        meldForm.requestSubmit();
      });

      // Tap-to-play fallback (see red-three tap handler above for why).
      newMeldDrop.addEventListener("click", function () {
        const cards = selectedCards();
        if (cards.length === 0) return;
        meldInput.value = JSON.stringify(cards);
        if (meldTargetRankInput) meldTargetRankInput.value = "";
        clearSelection();
        meldForm.requestSubmit();
      });
    }
  }

  // ── Drag a single card from hand onto the discard pile ──────────────────
  const discardPileEl = document.getElementById("discard-pile-drop");
  if (discardPileEl && discardForm && discardInput) {
    discardPileEl.addEventListener("dragover", function (e) {
      if (dragCards.length !== 1) return;
      e.preventDefault();
      e.dataTransfer.dropEffect = "move";
      this.classList.add("drag-over");
    });

    discardPileEl.addEventListener("dragleave", function (e) {
      if (!this.contains(e.relatedTarget)) {
        this.classList.remove("drag-over");
      }
    });

    discardPileEl.addEventListener("drop", function (e) {
      e.preventDefault();
      this.classList.remove("drag-over");
      if (dragCards.length !== 1) return;
      discardInput.value = dragCards[0];
      if (dragFromSelection) clearSelection();
      discardForm.requestSubmit();
    });

    // Tap-to-play fallback (see red-three tap handler above for why). Skipped
    // during the draw phase — the discard-pile-drop element doubles as the
    // pickup button there (see pickupForm above), and a click on it should
    // always mean "pick up the pile", never "discard", regardless of hand
    // selection.
    discardPileEl.addEventListener("click", function () {
      if (pickupForm) return;
      const cards = selectedCards();
      if (cards.length !== 1) return;
      discardInput.value = cards[0];
      clearSelection();
      discardForm.requestSubmit();
    });
  }
});
