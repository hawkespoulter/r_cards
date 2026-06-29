class LobbyChannel < ApplicationCable::Channel
  def subscribed
    stream_from "lobby"
  end
end
