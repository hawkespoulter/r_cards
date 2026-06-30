import consumer from "channels/consumer"
import { playKnock, playCardSound } from "sound_effects"
import { showCardModal } from "card_modal"

let currentSubscription = null;
let currentGameId = null;

document.addEventListener("turbo:load", function () {
  const container = document.querySelector("[data-game-id]");
  const gameId    = container?.dataset.gameId;

  if (container && container.classList.contains("my-turn")) {
    const key = `r_cards_knock_${gameId}`;
    if (sessionStorage.getItem(key) !== "1") {
      sessionStorage.setItem(key, "1");
      playKnock();
    }
  } else if (gameId) {
    sessionStorage.removeItem(`r_cards_knock_${gameId}`);
  }

  // Already subscribed to this game — nothing to do
  if (gameId && gameId === currentGameId && currentSubscription) return;

  // Clean up previous subscription if switching games or leaving the page
  if (currentSubscription) {
    currentSubscription.unsubscribe();
    currentSubscription = null;
    currentGameId = null;
  }

  if (!gameId) return;

  currentGameId = gameId;
  currentSubscription = consumer.subscriptions.create(
    { channel: "GameChannel", game_id: gameId },
    {
      connected() {},
      disconnected() {},
      received(data) {
        if (data.type === "game_ended") {
          window.location.href = "/games";
          return;
        }

        playCardSound();

        if (data.canasta_completed) {
          showCardModal({
            title: `🃏 Canasta completed! (${data.canasta_rank})`,
            confetti: true
          });
          setTimeout(() => location.reload(), 1600);
        } else if (data.game_over) {
          showCardModal({
            title: `🏆 Team ${parseInt(data.winning_team, 10) + 1} wins the game!`,
            confetti: true
          });
          setTimeout(() => location.reload(), 1600);
        } else if (data.round_ended) {
          showCardModal({
            title: `Round over — new hands dealt!`,
            confetti: true
          });
          setTimeout(() => location.reload(), 1600);
        } else if (data.aces_played_by) {
          showCardModal({
            title: `🔥 ${data.aces_played_by} threw down Aces!`,
            subtitle: "Pile cleared",
            cards: data.aces_played_cards || [],
            confetti: true
          });
          setTimeout(() => location.reload(), 1600);
        } else if (data.finished_player_name) {
          showCardModal({
            title: `🎉 ${data.finished_player_name} is out!`,
            confetti: true
          });
          setTimeout(() => location.reload(), 1600);
        } else {
          location.reload();
        }
      }
    }
  );
});
