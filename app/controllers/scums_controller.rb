class ScumsController < ApplicationController
  def create
    game = Game.create(name: "Scum")
    scum = Scum.create(game: game)
    deck = Deck.create(game: game)

    render json: { game: game, scum: scum, deck: deck }
  end

end