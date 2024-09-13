document.addEventListener("DOMContentLoaded", function () {
  const cards = document.querySelectorAll(".game-card");

  cards.forEach((card) => {
    // Add a click event listener to each card
    card.addEventListener("click", function () {
      const parentRank = this.parentElement; // Get the direct parent element 

      let sameRankCards = [...parentRank.querySelectorAll(".game-card")].map(c => c.dataset.card);
      console.log(sameRankCards);

      // TODO: Perform action here with the sameRankCards
    });
  });
});
