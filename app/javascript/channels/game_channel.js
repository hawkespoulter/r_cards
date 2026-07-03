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
          const myPlayerId = document.querySelector("[data-game-id]")?.dataset.playerId;
          const isActingPlayer = myPlayerId != null && String(data.acting_player_id) === myPlayerId;

          if (!isActingPlayer) {
            // The acting player is about to be navigated to a fresh page by
            // their own meld POST's redirect — showing the modal here, on
            // the page they're already leaving, just gets it wiped out
            // early by that navigation. Their own canasta_cards.js check
            // (once the fresh page loads) shows it uninterrupted instead.
            const key = data.canasta_seq != null ? `r_cards_canasta_made_${gameId}_${data.canasta_seq}` : null;
            const alreadyShown = key && sessionStorage.getItem(key) === "1";
            if (!alreadyShown) {
              if (key) sessionStorage.setItem(key, "1");
              const rankCard = data.canasta_rank === "jo" ? "jo" : "h" + data.canasta_rank;
              showCardModal({
                title: "Canasta!",
                cards: [rankCard],
                confetti: true,
                confettiCard: rankCard
              });
              setTimeout(() => location.reload(), 1600);
            }
          }
        } else if (data.pickup_cards) {
          // Same acting-player exclusion as canasta_completed above — the
          // acting player already sees this via their own fresh page load
          // (canasta_cards.js's [data-last-pickup] check), which shares the
          // same sessionStorage key so neither path double-shows it.
          const myPlayerId = document.querySelector("[data-game-id]")?.dataset.playerId;
          const isActingPlayer = myPlayerId != null && String(data.acting_player_id) === myPlayerId;

          if (!isActingPlayer) {
            const key = data.pickup_seq != null ? `r_cards_canasta_pickup_${gameId}_${data.pickup_seq}` : null;
            const alreadyShown = key && sessionStorage.getItem(key) === "1";
            if (!alreadyShown) {
              if (key) sessionStorage.setItem(key, "1");
              showCardModal({
                title: `${data.acting_player_name} picked up the pile!`,
                cards: data.pickup_cards,
                duration: 3000
              });
              setTimeout(() => location.reload(), 3000);
            }
          }
        } else if (data.game_over) {
          showCardModal({
            title: `🏆 Team ${parseInt(data.winning_team, 10) + 1} wins the game!`,
            confetti: true
          });
          setTimeout(() => location.reload(), 1600);
        } else if (data.round_ended) {
          // Reveals the round-summary screen — actual scoring toast/reload
          // for starting the next round comes later, from `next_round`,
          // once the host reviews the summary and continues.
          location.reload();
        } else if (data.next_round) {
          showCardModal({
            title: `New round — hands dealt!`,
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
