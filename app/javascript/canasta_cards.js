document.addEventListener("turbo:load", function () {
  const hand = document.getElementById("canasta-hand");
  if (!hand) return;

  const totalEl = document.getElementById("meld-running-total");
  const selected = new Set();

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

  hand.querySelectorAll(".game-card").forEach((cardEl) => {
    cardEl.addEventListener("click", function () {
      const card = this.dataset.card;
      if (selected.has(card)) {
        selected.delete(card);
        this.classList.remove("selected");
      } else {
        selected.add(card);
        this.classList.add("selected");
      }
      refreshTotal();
    });
  });

  const pickupForm = document.getElementById("pickup-form");
  const pickupInput = document.getElementById("pickup-cards-input");
  if (pickupForm && pickupInput) {
    pickupForm.addEventListener("submit", function () {
      pickupInput.value = JSON.stringify(Array.from(selected));
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
      meldInput.value = JSON.stringify(Array.from(selected));
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
      discardInput.value = Array.from(selected)[0];
    });
  }
});
