import consumer from "channels/consumer"
import { playKnock, playCardSound } from "sound_effects"

let currentSubscription = null;
let currentGameId = null;

function showFinishToast(name) {
  const toast = document.createElement("div");
  toast.className = "finish-toast";
  toast.textContent = `🎉 ${name} is out!`;
  document.body.appendChild(toast);
  requestAnimationFrame(() => toast.classList.add("show"));
}

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

        if (data.finished_player_name) {
          showFinishToast(data.finished_player_name);
          setTimeout(() => location.reload(), 1400);
        } else {
          location.reload();
        }
      }
    }
  );
});
