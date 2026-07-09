import consumer from "channels/consumer"
import { playKnock, playCardSound } from "sound_effects"
import { showCardModal } from "card_modal"

let currentSubscription = null;
let currentGameId = null;

// Patches the board in place instead of a full page reload — fetches this
// player's own personalized turbo_stream render (hand/team perspective is
// computed server-side from their session, same as a full reload would,
// just without the navigation) and lets Turbo apply it.
function syncBoard(gameId) {
  fetch(`/games/${gameId}`, { headers: { Accept: "text/vnd.turbo-stream.html" } })
    .then((r) => r.text())
    .then((html) => Turbo.renderStreamMessage(html));
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

        // "silent" broadcasts are administrative, not gameplay — joining,
        // starting the game, moving someone between teams, renaming teams —
        // none of those are a card being played, so they shouldn't play the
        // card sound the way an actual turn action does.
        if (!data.silent) playCardSound();

        if (data.canasta_completed) {
          const myPlayerId = document.querySelector("[data-game-id]")?.dataset.playerId;
          const isActingPlayer = myPlayerId != null && String(data.acting_player_id) === myPlayerId;

          if (!isActingPlayer) {
            // The acting player's own turbo_stream response already synced
            // their board and shows this via canasta_cards.js's own
            // [data-last-canasta] check, keyed off the same sessionStorage
            // key — so this branch only needs to cover everyone else.
            const key = data.canasta_seq != null ? `r_cards_canasta_made_${gameId}_${data.canasta_seq}` : null;
            const alreadyShown = key && sessionStorage.getItem(key) === "1";
            if (!alreadyShown) {
              if (key) sessionStorage.setItem(key, "1");
              const rankCard = data.canasta_rank === "jo" ? "jo" : "h" + data.canasta_rank;
              const canastaCards = data.canasta_cards && data.canasta_cards.length ? data.canasta_cards : [rankCard];
              showCardModal({
                title: "Canasta!",
                cards: canastaCards,
                confetti: true,
                confettiCard: rankCard,
                duration: 2800,
                autoDismiss: true
              });
            }
          }
          syncBoard(gameId);
        } else if (data.pickup_cards) {
          // Same acting-player exclusion as canasta_completed above — the
          // acting player already sees this via their own synced board
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
                duration: 3000,
                autoDismiss: true
              });
            }
          }
          syncBoard(gameId);
        } else if (data.game_over) {
          showCardModal({
            title: `🏆 Team ${parseInt(data.winning_team, 10) + 1} wins the game!`,
            confetti: true
          });
          syncBoard(gameId);
        } else if (data.round_ended) {
          // Reveals the round-summary screen — actual scoring toast/sync
          // for starting the next round comes later, from `next_round`,
          // once the host reviews the summary and continues.
          syncBoard(gameId);
        } else if (data.next_round) {
          showCardModal({
            title: `New round — hands dealt!`,
            confetti: true
          });
          syncBoard(gameId);
        } else if (data.aces_played_by) {
          showCardModal({
            title: `🔥 ${data.aces_played_by} threw down Aces!`,
            subtitle: "Pile cleared",
            cards: data.aces_played_cards || [],
            confetti: true
          });
          syncBoard(gameId);
        } else if (data.finished_player_name) {
          showCardModal({
            title: `🎉 ${data.finished_player_name} is out!`,
            confetti: true
          });
          syncBoard(gameId);
        } else {
          syncBoard(gameId);
        }
      }
    }
  );
});
