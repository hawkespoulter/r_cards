import consumer from "channels/consumer"

consumer.subscriptions.create("GameChannel", {
  connected() {
    // Called when the subscription is ready for use on the server
  },

  disconnected() {
    // Called when the subscription has been terminated by the server
  },

  received(data) {
    document.getElementById('game-updates').innerHTML += `<p>${data.message}</p>`;
  }
});
