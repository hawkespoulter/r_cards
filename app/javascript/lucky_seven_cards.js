document.addEventListener("turbo:load", function () {
  const handRow = document.querySelector(".seven-hand-row");
  const input   = document.getElementById("selected-cards-input");
  const playBtn = document.getElementById("play-cards-btn");
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
});
