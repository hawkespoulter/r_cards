document.addEventListener("turbo:load", function () {
  const handRow = document.querySelector(".seven-hand-row");
  const input   = document.getElementById("selected-cards-input");
  const playBtn = document.getElementById("play-cards-btn");
  const playForm = document.getElementById("play-form");
  if (!handRow || !input) return;

  let selected = null;

  function select(wrap) {
    handRow.querySelectorAll(".hand-card-wrap.selected").forEach((el) => el.classList.remove("selected"));

    if (selected === wrap) {
      selected = null;
    } else {
      selected = wrap;
      wrap.classList.add("selected");
    }

    input.value = selected ? JSON.stringify([selected.dataset.card]) : "";
    if (playBtn) playBtn.disabled = !selected;
  }

  // One play per board render. A drop and a click can both reach here, and the
  // board is replaced by the turbo_stream response anyway, so a second submit
  // could only ever be a duplicate of the first.
  let submitted = false;

  function play(card) {
    if (!playForm || submitted) return;
    submitted = true;
    input.value = JSON.stringify([card]);
    playForm.requestSubmit ? playForm.requestSubmit() : playForm.submit();
  }

  handRow.querySelectorAll(".hand-card-wrap.seven-playable").forEach((wrap) => {
    wrap.addEventListener("click", function (e) {
      e.stopPropagation();
      select(this);
    });
  });

  // A blocked card is a dead end this turn — flash it rather than silently
  // ignoring the click, so it's clear the card was seen and rejected.
  handRow.querySelectorAll(".hand-card-wrap.seven-blocked").forEach((wrap) => {
    wrap.addEventListener("click", function () {
      this.classList.remove("seven-nudge");
      void this.offsetWidth;
      this.classList.add("seven-nudge");
    });
  });

  if (playBtn) playBtn.disabled = true;

  // ── Drag to the run ────────────────────────────────────────────────────────
  //
  // Every card has exactly one legal destination (its own suit + rank slot), so
  // the drop targets are that slot and — more forgivingly — anywhere on that
  // suit's track. Dropping anywhere else cancels, which is what gives the drag
  // a way out once started.
  //
  // The dragged card is tracked in a variable rather than read back from
  // dataTransfer because getData() is deliberately blocked during dragover,
  // and dragover is where the target has to decide whether to accept.
  let draggedCard = null;

  function clearDropHints() {
    document.querySelectorAll(".seven-slot.drop-target, .seven-track.drop-active")
      .forEach((el) => el.classList.remove("drop-target", "drop-active"));
  }

  handRow.querySelectorAll(".hand-card-wrap.seven-playable").forEach((wrap) => {
    wrap.addEventListener("dragstart", function (e) {
      draggedCard = this.dataset.card;
      e.dataTransfer.setData("text/plain", draggedCard);
      e.dataTransfer.effectAllowed = "move";
      setTimeout(() => this.classList.add("dragging"), 0);

      // Point at where this card is headed, so the target is obvious the
      // moment the drag starts rather than only on hover.
      const slot = document.querySelector(`.seven-slot[data-slot-card="${draggedCard}"]`);
      if (slot) slot.classList.add("drop-target");
    });

    wrap.addEventListener("dragend", function () {
      this.classList.remove("dragging");
      draggedCard = null;
      clearDropHints();
    });
  });

  function accepts(el) {
    if (!draggedCard) return false;
    if (el.classList.contains("seven-track")) return el.dataset.suit === draggedCard[0];
    return el.dataset.slotCard === draggedCard;
  }

  document.querySelectorAll(".seven-track").forEach((track) => {
    const targets = [track, ...track.querySelectorAll(".seven-slot")];

    targets.forEach((el) => {
      el.addEventListener("dragover", function (e) {
        if (!accepts(this)) return;
        e.preventDefault();
        e.dataTransfer.dropEffect = "move";
        track.classList.add("drop-active");
      });

      el.addEventListener("drop", function (e) {
        if (!accepts(this)) return;
        e.preventDefault();
        e.stopPropagation();
        const card = draggedCard;
        draggedCard = null;
        clearDropHints();
        play(card);
      });
    });

    track.addEventListener("dragleave", function (e) {
      if (!this.contains(e.relatedTarget)) this.classList.remove("drop-active");
    });
  });
});
