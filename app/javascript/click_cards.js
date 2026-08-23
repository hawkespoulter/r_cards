import { showCardModal } from "card_modal"

document.addEventListener("turbo:load", function () {
  // ── Trade exchange "you received" popup (once per round) ───────────────────
  const tradeInfo = document.querySelector("[data-trade-info]");
  if (tradeInfo) {
    const round    = tradeInfo.dataset.round;
    const received = JSON.parse(tradeInfo.dataset.receivedCards || "[]");
    const gameId   = document.querySelector("[data-game-id]")?.dataset.gameId;
    if (received.length && gameId) {
      const key = `r_cards_received_${gameId}_${round}`;
      if (sessionStorage.getItem(key) !== "1") {
        sessionStorage.setItem(key, "1");
        showCardModal({ title: "You received", cards: received });
      }
    }
  }

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

  // Lucky Seven drives the same #play-form / #selected-cards-input from
  // lucky_seven_cards.js — bail out so both don't bind to and reset the
  // shared input.
  if (document.querySelector(".seven-hand-row")) return;

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
    // Give phase: select any individual cards (including splitting a set),
    // total selected must equal giveCount.
    const selectedCards = new Set();

    function refreshGiveSelection() {
      input.value = JSON.stringify(Array.from(selectedCards));
      if (playBtn) playBtn.disabled = selectedCards.size !== giveCount;
    }

    rankGroups.forEach((rankEl) => {
      rankEl.querySelectorAll(".game-card").forEach((cardEl) => {
        cardEl.addEventListener("click", function (e) {
          e.stopPropagation();
          const card = this.dataset.card;

          if (selectedCards.has(card)) {
            selectedCards.delete(card);
            this.classList.remove("selected");
          } else {
            selectedCards.add(card);
            this.classList.add("selected");
          }

          refreshGiveSelection();
        });
      });
    });

    refreshGiveSelection();

  } else {
    // Play phase: select individual cards of a single rank (allows playing
    // fewer cards than the full stack to match what the pile requires).
    const selectedCards = new Set();
    let selectedRankEl  = null;

    function refreshSelection() {
      input.value = JSON.stringify(Array.from(selectedCards));
      if (playBtn) playBtn.disabled = selectedCards.size === 0;
    }

    rankGroups.forEach((rankEl) => {
      const cardEls = rankEl.querySelectorAll(".game-card");

      cardEls.forEach((cardEl) => {
        cardEl.addEventListener("click", function (e) {
          e.stopPropagation();
          const card = this.dataset.card;

          if (selectedRankEl && selectedRankEl !== rankEl) {
            selectedRankEl.querySelectorAll(".game-card.selected").forEach(el => el.classList.remove("selected"));
            selectedCards.clear();
          }
          selectedRankEl = rankEl;

          if (selectedCards.has(card)) {
            selectedCards.delete(card);
            this.classList.remove("selected");
          } else {
            selectedCards.add(card);
            this.classList.add("selected");
          }

          if (selectedCards.size === 0) selectedRankEl = null;
          refreshSelection();
        });
      });
    });

    refreshSelection();
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
