document.addEventListener("turbo:load", function () {
  const board = document.getElementById("game-container");
  if (!board) return;

  // turbo:load fires many times per board — Turbo's own event plus the
  // redispatch application.js does after every stream render — and each run
  // would otherwise bind a second set of handlers to the same nodes. Two
  // handlers on one play meant two POSTs, the second landing after the turn had
  // already moved on ("Not your turn" / "card isn't in your hand"). A stream
  // render replaces #game-container outright, so a genuinely new board arrives
  // without this flag and binds exactly once. Same guard pattern as _navbar.
  if (board.dataset.sevenBound === "1") return;
  board.dataset.sevenBound = "1";

  const handRow  = document.querySelector(".seven-hand-row");
  const input    = document.getElementById("selected-cards-input");
  const rowInput = document.getElementById("selected-row-input");
  const playForm = document.getElementById("play-form");
  if (!handRow || !input) return;

  // One play in flight at a time. The flag lives on the form node rather than in
  // this closure so it still holds if more than one handler set ever reaches
  // here — a closure-local flag is invisible to the other closure, which is what
  // let the duplicate POST through before.
  function play(card, rowEl) {
    if (!playForm || playForm.dataset.submitting === "1") return;
    playForm.dataset.submitting = "1";
    input.value = JSON.stringify([card]);
    // Only meaningful when this card is opening its suit — the server ignores it
    // once the suit already has a spot.
    if (rowInput) rowInput.value = rowEl ? rowEl.dataset.row : "";
    playForm.requestSubmit ? playForm.requestSubmit() : playForm.submit();
  }

  // A rejected play only patches the flash container, leaving this same form on
  // the page — so release the flag or the player would be locked out of retrying.
  playForm?.addEventListener("turbo:submit-end", function () {
    delete this.dataset.submitting;
  });

  // ── Where a card is allowed to land ────────────────────────────────────────
  //
  // A card whose suit is already on the table belongs to that suit's row and
  // nowhere else. A seven whose suit hasn't been played yet can open any free
  // row — which spot it takes is the player's choice.
  const isSeven = (card) => card.slice(1).toLowerCase() === "7";

  function accepts(rowEl, card) {
    if (!card) return false;
    if (rowEl.dataset.suit) return rowEl.dataset.suit === card[0];
    return isSeven(card);
  }

  // ── Selection ──────────────────────────────────────────────────────────────

  let selectedCard = null;
  let draggedCard = null;

  function clearTargets() {
    document.querySelectorAll(".seven-row.drop-active")
      .forEach((el) => el.classList.remove("drop-active"));
  }

  function clearSelection() {
    selectedCard = null;
    input.value = "";
    handRow.querySelectorAll(".hand-card-wrap.selected").forEach((el) => el.classList.remove("selected"));
    clearTargets();
  }

  function selectWrap(wrap) {
    const wasSelected = wrap.classList.contains("selected");
    clearSelection();
    if (wasSelected) return;

    selectedCard = wrap.dataset.card;
    wrap.classList.add("selected");
    input.value = JSON.stringify([selectedCard]);
  }

  handRow.querySelectorAll(".hand-card-wrap.seven-playable").forEach((wrap) => {
    wrap.addEventListener("click", function (e) {
      e.stopPropagation();
      selectWrap(this);
    });

    wrap.addEventListener("dragstart", function (e) {
      draggedCard = this.dataset.card;
      e.dataTransfer.setData("text/plain", draggedCard);
      e.dataTransfer.effectAllowed = "move";
      setTimeout(() => this.classList.add("dragging"), 0);
    });

    wrap.addEventListener("dragend", function () {
      this.classList.remove("dragging");
      draggedCard = null;
      clearTargets();
    });
  });

  // A blocked card is a dead end this turn — flash it rather than silently
  // ignoring the tap, so it's clear the card was seen and rejected.
  handRow.querySelectorAll(".hand-card-wrap.seven-blocked").forEach((wrap) => {
    wrap.addEventListener("click", function (e) {
      e.stopPropagation();
      this.classList.remove("seven-nudge");
      void this.offsetWidth;
      this.classList.add("seven-nudge");
    });
  });

  // ── Playing: drop a dragged card, or tap the row for a held one ────────────

  document.querySelectorAll(".seven-row").forEach((rowEl) => {
    rowEl.addEventListener("dragover", function (e) {
      if (!accepts(this, draggedCard)) return;
      e.preventDefault();
      e.dataTransfer.dropEffect = "move";
      this.classList.add("drop-active");
    });

    rowEl.addEventListener("dragleave", function (e) {
      if (!this.contains(e.relatedTarget)) this.classList.remove("drop-active");
    });

    rowEl.addEventListener("drop", function (e) {
      if (!accepts(this, draggedCard)) return;
      e.preventDefault();
      e.stopPropagation();
      const card = draggedCard;
      draggedCard = null;
      clearTargets();
      play(card, this);
    });

    // Tap-to-play: select a card in hand, then tap the row it goes to. This is
    // the only route on touch, where HTML5 drag events never fire.
    rowEl.addEventListener("click", function (e) {
      if (!accepts(this, selectedCard)) return;
      e.stopPropagation();
      const card = selectedCard;
      selectedCard = null;
      clearTargets();
      play(card, this);
    });
  });

  // Tapping away drops the selection so a held card isn't left armed. Taps
  // landing anywhere on the board or the hand still count as using the board,
  // though — otherwise a near-miss on touch would silently disarm the card and
  // the next tap on the right row would do nothing. Mirrors the exclusion
  // canasta makes with BOARD_INTERACTIVE_SELECTOR.
  const KEEPS_SELECTION = ".seven-board, .seven-hand-row, button, a, input, textarea, select, label";

  document.addEventListener("click", function (e) {
    if (!selectedCard) return;
    if (e.target.closest(KEEPS_SELECTION)) return;
    clearSelection();
  });
});
