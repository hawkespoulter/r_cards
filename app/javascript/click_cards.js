document.addEventListener("turbo:load", function () {
  // ── Settings panel toggle ──────────────────────────────────────────────────
  const settingsTrigger = document.getElementById("settings-trigger");
  const settingsPanel   = document.getElementById("settings-panel");

  if (settingsTrigger && settingsPanel) {
    settingsTrigger.addEventListener("click", function () {
      const open = settingsPanel.classList.toggle("open");
      this.classList.toggle("active", open);
    });
  }

  // ── Card drag / select ────────────────────────────────────────────────────
  const rankGroups = document.querySelectorAll(".rank");
  const playPile   = document.getElementById("play-pile");
  const input      = document.getElementById("selected-cards-input");
  const playBtn    = document.getElementById("play-cards-btn");
  const playForm   = document.getElementById("play-form");

  if (!input || !playForm) return;

  // Data attribute set on the give form: data-give-count="N"
  const giveCount = parseInt(playForm.dataset.giveCount, 10) || null;
  const isGivePhase = !!giveCount;

  // ── Click-to-select ────────────────────────────────────────────────────────

  if (isGivePhase) {
    // Give phase: multi-select, total selected cards must equal giveCount
    const selectedGroups = new Set();

    rankGroups.forEach((rankEl) => {
      rankEl.addEventListener("click", function () {
        if (selectedGroups.has(this)) {
          selectedGroups.delete(this);
          this.classList.remove("selected");
        } else {
          selectedGroups.add(this);
          this.classList.add("selected");
        }

        const allCards = [];
        selectedGroups.forEach(el => {
          const cards = JSON.parse(el.dataset.cards || "[]");
          allCards.push(...cards);
        });

        input.value = JSON.stringify(allCards);

        if (playBtn) {
          playBtn.disabled = allCards.length !== giveCount;
        }
      });
    });

    if (playBtn) playBtn.disabled = true;

  } else {
    // Play phase: single rank-group select
    let selectedRank = null;

    rankGroups.forEach((rankEl) => {
      rankEl.addEventListener("click", function () {
        if (selectedRank === this) {
          this.classList.remove("selected");
          selectedRank = null;
          input.value  = "[]";
          if (playBtn) playBtn.disabled = true;
          return;
        }
        if (selectedRank) selectedRank.classList.remove("selected");
        this.classList.add("selected");
        selectedRank = this;
        input.value  = this.dataset.cards || "[]";
        if (playBtn) playBtn.disabled = false;
      });
    });

    if (playBtn) playBtn.disabled = true;
  }

  // ── Drag and drop (play phase only) ───────────────────────────────────────

  if (isGivePhase) return; // no drag-to-pile during give phase

  rankGroups.forEach((rankEl) => {
    rankEl.addEventListener("dragstart", function (e) {
      e.dataTransfer.setData("text/plain", this.dataset.cards || "[]");
      e.dataTransfer.effectAllowed = "move";
      setTimeout(() => this.classList.add("dragging"), 0);
    });

    rankEl.addEventListener("dragend", function () {
      this.classList.remove("dragging");
      if (playPile) playPile.classList.remove("drag-over");
    });
  });

  if (!playPile) return;

  playPile.addEventListener("dragover", function (e) {
    if (!document.getElementById("play-form")) return;
    e.preventDefault();
    e.dataTransfer.dropEffect = "move";
    this.classList.add("drag-over");
  });

  playPile.addEventListener("dragleave", function (e) {
    if (!this.contains(e.relatedTarget)) {
      this.classList.remove("drag-over");
    }
  });

  playPile.addEventListener("drop", function (e) {
    e.preventDefault();
    this.classList.remove("drag-over");

    const form      = document.getElementById("play-form");
    const formInput = document.getElementById("selected-cards-input");
    if (!form || !formInput) return;

    const cards = e.dataTransfer.getData("text/plain");
    if (!cards || cards === "[]") return;

    formInput.value = cards;
    form.submit();
  });
});
