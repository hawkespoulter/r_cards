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
    const redThrees  = JSON.parse(drawInfo.dataset.drawRedThrees || "[]");

    if (gameId && myPlayerId && drawPlayer === myPlayerId) {
      const key = `r_cards_canasta_draw_${gameId}_${seq}`;
      if (sessionStorage.getItem(key) !== "1") {
        sessionStorage.setItem(key, "1");
        if (redThrees.length > 0) {
          // Show red three modal first, then normal draw modal after
          showCardModal({
            title: "🟥 Red three auto-played — replaced!",
            subtitle: redThrees.length > 1 ? `${redThrees.length} red threes collected` : null,
            cards: [...redThrees, ...cards],
            duration: 2800
          });
        } else if (cards.length) {
          showCardModal({ title: "You drew these cards", cards });
        }
      }
    }
  }

  // ── Apply selected card back to all face-down card images ────────────────
  const gameContainer = document.querySelector("[data-card-back]");
  if (gameContainer) {
    const backSrc = localStorage.getItem("r_cards_card_back") || gameContainer.dataset.cardBack;
    document.querySelectorAll("img.pile-card, .peak-hand-stack img").forEach(img => {
      if (img.src.includes("blank_card")) img.src = backSrc;
    });
  }

  // ── Play errors as centred popup ──────────────────────────────────────────
  const flashError = document.querySelector("[data-flash-error]");
  if (flashError) {
    showCardModal({ title: flashError.dataset.flashError, duration: 2400 });
  }

  // ── Canasta completed popup (for the acting player who gets a redirect) ──
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
        showCardModal({ title: "🃏 Canasta!", cards: [rankCard0], confetti: true, confettiCard: rankCard0 });
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

  // ── Card back picker selection highlight ──────────────────────────────────
  document.querySelectorAll(".card-back-option").forEach(opt => {
    opt.addEventListener("click", function () {
      document.querySelectorAll(".card-back-option").forEach(o => o.classList.remove("selected"));
      this.classList.add("selected");
    });
  });

  // ── Condense hand into single row by overlapping cards ───────────────────
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
  condenseHand();
  window.addEventListener("resize", condenseHand);

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

  hand.querySelectorAll(".hand-card-wrap").forEach((wrap, idx) => {
    wrap.addEventListener("click", function () {
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

  // ── Drag cards from hand onto melds ──────────────────────────────────────
  if (meldForm && meldInput) {
    let dragCards = [];

    hand.querySelectorAll(".hand-card-wrap").forEach((wrap, idx) => {
      wrap.setAttribute("draggable", "true");

      wrap.addEventListener("dragstart", function (e) {
        const card = this.dataset.card;
        dragCards = selected.has(idx) ? selectedCards() : [card];
        e.dataTransfer.clearData();
        e.dataTransfer.effectAllowed = "move";
        e.dataTransfer.setData("text/plain", JSON.stringify(dragCards));
        this.classList.add("dragging");
      });

      wrap.addEventListener("dragend", function () {
        this.classList.remove("dragging");
      });
    });

    document.querySelectorAll(".meld-group[data-meld-rank]").forEach(function (group) {
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
        meldForm.requestSubmit();
      });
    });
  }
});
