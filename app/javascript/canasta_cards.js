import { showCardModal } from "card_modal"

document.addEventListener("turbo:load", function () {
  // ── "You drew these cards" popup (once per draw) ───────────────────────────
  const drawInfo = document.querySelector("[data-last-draw]");
  if (drawInfo) {
    const container = document.querySelector("[data-game-id]");
    const gameId     = container?.dataset.gameId;
    const myPlayerId = container?.dataset.playerId;
    const drawPlayer = drawInfo.dataset.drawPlayer;
    const seq        = drawInfo.dataset.drawSeq;
    const cards      = JSON.parse(drawInfo.dataset.drawCards || "[]");

    if (gameId && myPlayerId && drawPlayer === myPlayerId && cards.length) {
      const key = `r_cards_canasta_draw_${gameId}_${seq}`;
      if (sessionStorage.getItem(key) !== "1") {
        sessionStorage.setItem(key, "1");
        showCardModal({ title: "You drew these cards", cards });
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
        showCardModal({ title: "Your peak hand — added to your hand!", cards: footCards });
      }
    }
  }

  const hand = document.getElementById("canasta-hand");
  if (!hand) return;

  const totalEl = document.getElementById("meld-running-total");
  // Map<cardIndex, cardCode> — index is unique per DOM position so duplicate
  // ranks (e.g. two "dt" from different decks) are tracked independently.
  const selected = new Map();

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
    let total = 0;
    selected.forEach((card) => { total += cardPoints(card); });
    totalEl.textContent = total;
  }

  function selectedCards() {
    return Array.from(selected.values());
  }

  hand.querySelectorAll(".game-card").forEach((cardEl, idx) => {
    cardEl.addEventListener("click", function () {
      const card = this.dataset.card;
      if (selected.has(idx)) {
        selected.delete(idx);
        this.classList.remove("selected");
      } else {
        selected.set(idx, card);
        this.classList.add("selected");
      }
      refreshTotal();
    });
  });

  const pickupForm = document.getElementById("pickup-form");
  const pickupInput = document.getElementById("pickup-cards-input");
  if (pickupForm && pickupInput) {
    pickupForm.addEventListener("submit", function () {
      pickupInput.value = JSON.stringify(selectedCards());
    });
  }

  const meldForm = document.getElementById("meld-form");
  const meldInput = document.getElementById("meld-cards-input");
  if (meldForm && meldInput) {
    meldForm.addEventListener("submit", function (e) {
      if (selected.size === 0) {
        e.preventDefault();
        return;
      }
      meldInput.value = JSON.stringify(selectedCards());
    });
  }

  const discardForm = document.getElementById("discard-form");
  const discardInput = document.getElementById("discard-card-input");
  if (discardForm && discardInput) {
    discardForm.addEventListener("submit", function (e) {
      if (selected.size !== 1) {
        e.preventDefault();
        alert("Select exactly one card to discard.");
        return;
      }
      discardInput.value = selectedCards()[0];
    });
  }
});
