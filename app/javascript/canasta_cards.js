import { showCardModal } from "card_modal"

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

document.addEventListener("turbo:load", function () {
  // ── Recolor the whole page background to match "my turn" state ───────────
  const gameContainerEl = document.querySelector(".game-container");
  document.body.classList.toggle("my-turn-bg", !!gameContainerEl?.classList.contains("my-turn"));

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
          const hasRedThree = cards.some((c) => c === "h3" || c === "d3");
          showCardModal({
            title: "You drew these cards",
            cards,
            duration: hasRedThree ? 2800 : 1800
          });
        }
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
          showCardModal({ title: "You picked up the pile!", cards: pickedUpCards, duration: 3000 });
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
        showCardModal({ title: "Canasta!", cards: [rankCard0], confetti: true, confettiCard: rankCard0 });
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

  // ── Round-by-round score popup (click a team score chip to open) ─────────
  const roundHistoryPopup = document.getElementById("round-history-popup");
  if (roundHistoryPopup) {
    document.querySelectorAll(".round-history-trigger").forEach((trigger) => {
      trigger.addEventListener("click", () => roundHistoryPopup.classList.add("open"));
    });

    const closeRoundHistory = () => roundHistoryPopup.classList.remove("open");
    document.getElementById("round-history-close")?.addEventListener("click", closeRoundHistory);
    roundHistoryPopup.addEventListener("click", (e) => {
      if (e.target === roundHistoryPopup) closeRoundHistory();
    });
  }

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

  // ── Clicking anywhere outside the hand deselects all selected cards ──────
  document.addEventListener("click", function (e) {
    if (e.target.closest(".hand-card-wrap")) return;
    if (selected.size === 0) return;
    selected.clear();
    hand.querySelectorAll(".hand-card-wrap.selected").forEach((el) => el.classList.remove("selected"));
    refreshTotal();
  });

  // ── Drag cards from hand — always enabled, since playing a red three isn't
  // gated by whose turn it is (unlike melding/discarding/pickup below). ──────
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

  // ── Drag a red three from hand onto your red-three area, any time ────────
  const redThreeForm = document.getElementById("red-three-form");
  const redThreeInput = document.getElementById("red-three-card-input");
  const redThreeDrop = document.getElementById("red-three-drop");
  if (redThreeForm && redThreeInput && redThreeDrop) {
    redThreeDrop.addEventListener("dragover", function (e) {
      if (dragCards.length !== 1) return;
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
      if (dragCards.length !== 1) return;
      redThreeInput.value = dragCards[0];
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
      discardForm.requestSubmit();
    });
  }
});
