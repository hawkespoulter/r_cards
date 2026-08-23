// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import "channels"
import "click_cards"
import "canasta_cards"
import "lucky_seven_cards"

// click_cards.js / canasta_cards.js bind their interaction handlers on
// "turbo:load", which only fires on full Turbo Drive navigations. Turbo
// Stream renders (both the acting player's own action responses and other
// players' board syncs — see channels/game_channel.js) patch the DOM without
// firing that event, so without this hook those handlers would go stale
// after the very first stream-driven update. A single response can contain
// several <turbo-stream> elements (e.g. the board plus two nav regions) that
// all apply synchronously in one tick, so the redispatch is coalesced with a
// microtask to fire turbo:load exactly once per response instead of once per
// stream element.
let boardSyncPending = false;
document.addEventListener("turbo:before-stream-render", (event) => {
  const original = event.detail.render;
  event.detail.render = (streamElement) => {
    original(streamElement);
    if (!boardSyncPending) {
      boardSyncPending = true;
      queueMicrotask(() => {
        boardSyncPending = false;
        document.dispatchEvent(new Event("turbo:load"));
      });
    }
  };
});
