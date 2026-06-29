class GamesController < ApplicationController

  def index
    @games = Game.all
  end

  def show
    @game           = Game.find(params[:id])
    @players        = @game.players.where.not(user_id: current_user.id)
    @current_player = @game.players.find_by(user_id: current_user.id)
    @game_started   = @game.turn_order.present?
    @scum           = @game.scum if @game.scum?

    if @game_started
      @current_turn_name = @game.players.find(@game.current_turn).user.name
    end
    @is_host = @game.players.order(:created_at).first&.user_id == current_user.id
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
    is_host = @game.players.order(:created_at).first&.user_id == current_user.id
    return redirect_to @game, alert: "Only the host can end the game." unless is_host

    ActionCable.server.broadcast "game_#{@game.id}", { type: "game_ended" }
    @game.destroy
    redirect_to games_path
  end

  def leave
    @game = Game.find(params[:id])
    @game.players.find_by(user_id: current_user.id)&.destroy
    redirect_to games_path
  end

  def start_round
    @game = Game.find(params[:id])
    @scum = @game.scum

    is_host = @game.players.order(:created_at).first&.user_id == current_user.id
    return redirect_to @game, alert: "Only the host can start a new round." unless is_host

    result = @scum.start_new_round
    if result[:error]
      redirect_to @game, alert: result[:error]
    else
      ActionCable.server.broadcast "game_#{@game.id}", { message: 'update' }
      redirect_to @game
    end
  end

  def give_cards
    @game           = Game.find(params[:id])
    @scum           = @game.scum
    @current_player = @game.players.find_by(user_id: current_user.id)

    cards = params[:cards].present? ? JSON.parse(params[:cards]) : []
    result = @scum.give_cards(@current_player, cards)

    if result[:error]
      redirect_to @game, alert: result[:error]
    else
      ActionCable.server.broadcast "game_#{@game.id}", { message: 'update' }
      redirect_to @game
    end
  end

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
    ActionCable.server.broadcast "game_#{@game.id}", { message: 'Game started!' }
    redirect_to @game
  end

  def take_turn
    @game = Game.find(params[:id])
    @game.take_turn
    ActionCable.server.broadcast "game_#{@game.id}", { message: 'Next turn!' }
    redirect_to @game
  end

  def play_cards
    @game           = Game.find(params[:id])
    @scum           = @game.scum
    @current_player = @game.players.find_by(user_id: current_user.id)

    cards = params[:cards].present? ? JSON.parse(params[:cards]) : []
    result = @scum.play_cards(@current_player, cards)

    if result[:error]
      redirect_to @game, alert: result[:error]
    else
      ActionCable.server.broadcast "game_#{@game.id}", { message: 'update' }
      redirect_to @game
    end
  end

  def update_settings
    @game = Game.find(params[:id])
    @game.update!(settings_params)
    ActionCable.server.broadcast "game_#{@game.id}", { message: 'settings_updated' }
    redirect_to @game
  end

  def pass
    @game           = Game.find(params[:id])
    @scum           = @game.scum
    @current_player = @game.players.find_by(user_id: current_user.id)

    result = @scum.pass_turn(@current_player)

    if result[:error]
      redirect_to @game, alert: result[:error]
    else
      ActionCable.server.broadcast "game_#{@game.id}", { message: 'update' }
      redirect_to @game
    end
  end

  private

  def game_params
    params.require(:game).permit(:game_type, :pass_locks_out)
  end

  def settings_params
    { pass_locks_out: params[:pass_locks_out], leader_can_continue: params[:leader_can_continue] }
  end
end
