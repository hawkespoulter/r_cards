class GamesController < ApplicationController
  def index
    @games = Game.all
  end

  def show
    @game = Game.find(params[:id])
  end

  def new
    @game = Game.new
  end

  def create
    @game = Game.new(game_params)
    @game.players << current_user.id
    if @game.save
      redirect_to @game
    else
      render :new
    end
  end

  def join
    @game = Game.find(params[:id])
    @game.players << current_user.id
    @game.save
    redirect_to @game
  end

  def edit
  end

  def update
  end

  def destroy
    @game = Game.find(params[:id])
    @game.destroy
    redirect_to games_path
  end

  private

  def game_params
    params.require(:game).permit(:name)
  end

end
