class GamesController < ApplicationController
  def index
    @games = Game.all
  end

  def show
  end

  def new
    @game = Game.new
  end

  def create
    @game = Game.new(game_params)
    if @game.save
      ActionCable.server.broadcast('game_channel', @game)
      redirect_to games_path, notice: 'Game was successfully created.'
    else
      render :new
    end
  end

  def edit
  end

  def update
  end

  def destroy
  end

  private

  def game_params
    params.require(:game).permit(:name)
  end

end
