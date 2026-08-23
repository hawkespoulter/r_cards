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
  const playForm = document.getElementById("play-form");
  if (!handRow || !input) return;

  // One play in flight at a time. The flag lives on the form node rather than in
  // this closure so it still holds if more than one handler set ever reaches
  // here — a closure-local flag is invisible to the other closure, which is what
  // let the duplicate POST through before.
  function play(card) {
    if (!playForm || playForm.dataset.submitting === "1") return;
    playForm.dataset.submitting = "1";
    input.value = JSON.stringify([card]);
    playForm.requestSubmit ? playForm.requestSubmit() : playForm.submit();
  }

  // A rejected play only patches the flash container, leaving this same form on
  // the page — so release the flag or the player would be locked out of retrying.
  playForm?.addEventListener("turbo:submit-end", function () {
    delete this.dataset.submitting;
  });

  // ── Selection ──────────────────────────────────────────────────────────────

  let selectedCard = null;

  function clearSelection() {
    selectedCard = null;
    input.value = "";
    handRow.querySelectorAll(".hand-card-wrap.selected").forEach((el) => el.classList.remove("selected"));
    clearTargets();
  }

  // Marks where the held card can go, so tapping a card shows its destination
  // before the second tap — the touch equivalent of the drag hint.
  function markTargets(card) {
    clearTargets();
    const slot = document.querySelector(`.seven-slot[data-slot-card="${card}"]`);
    if (slot) slot.classList.add("drop-target");
  }

  function clearTargets() {
    document.querySelectorAll(".seven-slot.drop-target, .seven-track.drop-active")
      .forEach((el) => el.classList.remove("drop-target", "drop-active"));
  }

  function selectWrap(wrap) {
    const wasSelected = wrap.classList.contains("selected");
    clearSelection();
    if (wasSelected) return;

    selectedCard = wrap.dataset.card;
    wrap.classList.add("selected");
    input.value = JSON.stringify([selectedCard]);
    markTargets(selectedCard);
  }

  handRow.querySelectorAll(".hand-card-wrap.seven-playable").forEach((wrap) => {
    wrap.addEventListener("click", function (e) {
      e.stopPropagation();
      selectWrap(this);
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

  // ── Playing: drop a dragged card, or tap the destination for a held one ────
  //
  // Every card has exactly one legal destination (its own suit + rank slot), so
  // the targets are that slot and — more forgivingly — anywhere on its suit's
  // track. Anywhere else cancels, which is what gives both a started drag and a
  // held selection a way out.
  //
  // The dragged card is kept in a variable rather than read back from
  // dataTransfer because getData() is blocked during dragover, and dragover is
  // where the target has to decide whether to accept.
  let draggedCard = null;

  function accepts(el, card) {
    if (!card) return false;
    if (el.classList.contains("seven-track")) return el.dataset.suit === card[0];
    return el.dataset.slotCard === card;
  }

  handRow.querySelectorAll(".hand-card-wrap.seven-playable").forEach((wrap) => {
    wrap.addEventListener("dragstart", function (e) {
      draggedCard = this.dataset.card;
      e.dataTransfer.setData("text/plain", draggedCard);
      e.dataTransfer.effectAllowed = "move";
      setTimeout(() => this.classList.add("dragging"), 0);
      markTargets(draggedCard);
    });

    wrap.addEventListener("dragend", function () {
      this.classList.remove("dragging");
      draggedCard = null;
      if (selectedCard) markTargets(selectedCard); else clearTargets();
    });
  });

  document.querySelectorAll(".seven-track").forEach((track) => {
    const targets = [track, ...track.querySelectorAll(".seven-slot")];

    targets.forEach((el) => {
      el.addEventListener("dragover", function (e) {
        if (!accepts(this, draggedCard)) return;
        e.preventDefault();
        e.dataTransfer.dropEffect = "move";
        track.classList.add("drop-active");
      });

      el.addEventListener("drop", function (e) {
        if (!accepts(this, draggedCard)) return;
        e.preventDefault();
        e.stopPropagation();
        const card = draggedCard;
        draggedCard = null;
        clearTargets();
        play(card);
      });

      // Tap-to-play: select a card in hand, then tap where it goes. This is the
      // only route on touch, where HTML5 drag events never fire.
      el.addEventListener("click", function (e) {
        if (!accepts(this, selectedCard)) return;
        e.stopPropagation();
        const card = selectedCard;
        selectedCard = null;
        clearTargets();
        play(card);
      });
    });

    track.addEventListener("dragleave", function (e) {
      if (!this.contains(e.relatedTarget)) this.classList.remove("drop-active");
    });
  });

  // Tapping away drops the selection so a held card isn't left armed. Taps
  // landing anywhere on the runs or the hand still count as using the board,
  // though — otherwise a near-miss on touch would silently disarm the card and
  // the next tap on the right slot would do nothing. Mirrors the exclusion
  // canasta makes with BOARD_INTERACTIVE_SELECTOR.
  const KEEPS_SELECTION = ".seven-table, .seven-hand-row, button, a, input, textarea, select, label";

  document.addEventListener("click", function (e) {
    if (!selectedCard) return;
    if (e.target.closest(KEEPS_SELECTION)) return;
    clearSelection();
  });
});
