function cardImageSrc(card) {
  return (window.CARD_ASSET_MAP && window.CARD_ASSET_MAP[card]) || "";
}

function spawnConfetti(overlay, card = "blank_card") {
  const src = cardImageSrc(card) || cardImageSrc("blank_card");
  for (let i = 0; i < 14; i++) {
    const piece = document.createElement("img");
    piece.src = src;
    piece.className = "confetti-card";
    const angle    = Math.random() * 360;
    const distance = 120 + Math.random() * 140;
    const x = Math.cos(angle * Math.PI / 180) * distance;
    const y = Math.sin(angle * Math.PI / 180) * distance;
    piece.style.setProperty("--x", `${x}px`);
    piece.style.setProperty("--y", `${y}px`);
    piece.style.setProperty("--rot", `${Math.random() * 720 - 360}deg`);
    piece.style.animationDelay = `${Math.random() * 0.15}s`;
    overlay.appendChild(piece);
  }
}

export function showCardModal({ title, subtitle = "", cards = [], confetti = false, confettiCard = "blank_card", duration = 1800 }) {
  const overlay = document.createElement("div");
  overlay.className = "card-modal-overlay";

  const modal = document.createElement("div");
  modal.className = "card-modal";

  const titleEl = document.createElement("p");
  titleEl.className = "card-modal-title";
  titleEl.textContent = title;
  modal.appendChild(titleEl);

  if (subtitle) {
    const subEl = document.createElement("p");
    subEl.className = "card-modal-subtitle";
    subEl.textContent = subtitle;
    modal.appendChild(subEl);
  }

  if (cards.length) {
    const cardsRow = document.createElement("div");
    cardsRow.className = "card-modal-cards";
    cards.forEach((card) => {
      const img = document.createElement("img");
      img.src = cardImageSrc(card);
      img.className = "card-modal-card-img";
      cardsRow.appendChild(img);
    });
    modal.appendChild(cardsRow);
  }

  overlay.appendChild(modal);
  if (confetti) spawnConfetti(overlay, confettiCard);
  document.body.appendChild(overlay);

  requestAnimationFrame(() => overlay.classList.add("show"));

  setTimeout(() => {
    overlay.classList.remove("show");
    setTimeout(() => overlay.remove(), 300);
  }, duration);
}
