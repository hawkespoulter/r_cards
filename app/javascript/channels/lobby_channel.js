import consumer from "channels/consumer"

let lobbySubscription = null;
let isNavigatingAway   = false;

// A broadcast can arrive while this tab's own join/leave/delete request is
// still in flight — don't let it reload over (and cancel) our own pending
// navigation to wherever that request is taking us.
window.addEventListener("beforeunload", function () {
  isNavigatingAway = true;
});

document.addEventListener("turbo:load", function () {
  isNavigatingAway = false;

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
    received(_data) {
      if (isNavigatingAway) return;
      location.reload();
    }
  });
});
