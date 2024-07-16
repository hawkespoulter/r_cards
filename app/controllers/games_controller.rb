class GamesController < ApplicationController

  # Rest endpoints
  def index
    @games = Game.all
  end

  def show
    @game = Game.find(params[:id])
    @players = @game.players.where.not(user_id: current_user.id)
    @current_player = @game.players.where(user_id: current_user.id).first
    @game_started = @game.turn_order.present?
  end

  def new
    @game = Game.new
  end

  def create
    @game = Game.new(game_params)
    if @game.save
      @game.players.create(user: current_user)
      redirect_to @game
    else
      render :new
    end
  end

  def destroy
    @game = Game.find(params[:id])
    @game.destroy
    redirect_to games_path
  end

  # Game logic endpoints

  def join
    @game = Game.find(params[:id])
    
    if @game.players.where(user_id: current_user.id).exists?
      flash[:notice] = "You are already part of this game."
    else
      @player = @game.players.create(user: current_user)
      flash[:notice] = "You have joined the game successfully." if @player.persisted?
    end
  
    redirect_to @game
  end

  def start
    @game = Game.find(params[:id])
    @game.start_game
  end

  def take_turn
    @game = Game.find(params[:id])
    @game.take_turn

    redirect_to @game
  end

  private

  def game_params
    params.require(:game).permit(:name)
  end

end
