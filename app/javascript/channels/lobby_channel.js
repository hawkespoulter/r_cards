import consumer from "channels/consumer"

let lobbySubscription = null;

document.addEventListener("turbo:load", function () {
  const isLobby = document.querySelector("[data-lobby]");

  if (!isLobby) {
    if (lobbySubscription) {
      lobbySubscription.unsubscribe();
      lobbySubscription = null;
    }
    return;
  }

  if (lobbySubscription) return;

  lobbySubscription = consumer.subscriptions.create("LobbyChannel", {
    connected() {},
    disconnected() {},
    received(_data) { location.reload(); }
  });
});
