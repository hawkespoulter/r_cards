import consumer from "channels/consumer"

let currentSubscription = null;
let currentGameId = null;

document.addEventListener("turbo:load", function () {
  const container = document.querySelector("[data-game-id]");
  const gameId    = container?.dataset.gameId;

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
        } else {
          location.reload();
        }
      }
    }
  );
});
