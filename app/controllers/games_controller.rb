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
    @canasta        = @game.canasta if @game.canasta?

    if @game_started
      @current_turn_name = @game.players.find(@game.current_turn).user.name
    end
    @is_host = @game.players.order(:created_at).first&.user_id == current_user.id
  end

  def new
    @game = Game.new(pass_locks_out: true, leader_can_continue: true)
  end

  def create
    @game = Game.new(game_params)
    if @game.save
      @game.players.create(user: current_user)
      ActionCable.server.broadcast "lobby", { message: "update" }
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
    ActionCable.server.broadcast "lobby", { message: "update" }
    redirect_to games_path
  end

  def leave
    @game = Game.find(params[:id])
    @game.players.find_by(user_id: current_user.id)&.destroy
    ActionCable.server.broadcast "lobby", { message: "update" }
    ActionCable.server.broadcast "game_#{@game.id}", { message: "update" }
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

    cards = begin
      params[:cards].present? ? JSON.parse(params[:cards]) : []
    rescue JSON::ParserError
      []
    end
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

    if Player.where(user_id: current_user.id).exists?
      return redirect_to games_path, alert: "You're already in a game — leave it before joining another."
    end

    @game.players.create(user: current_user)
    ActionCable.server.broadcast "lobby", { message: "update" }
    ActionCable.server.broadcast "game_#{@game.id}", { message: "update" }
    redirect_to @game
  end

  def start
    @game = Game.find(params[:id])
    is_host = @game.players.order(:created_at).first&.user_id == current_user.id
    return redirect_to @game, alert: "Only the host can start the game." unless is_host
    return redirect_to @game if @game.turn_order.present?

    if @game.canasta? && @game.players.count != 4
      return redirect_to @game, alert: "Canasta needs exactly 4 players to start."
    end

    @game.start_game
    ActionCable.server.broadcast "game_#{@game.id}", { message: 'Game started!' }
    ActionCable.server.broadcast "lobby", { message: "update" }
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

    cards = begin
      params[:cards].present? ? JSON.parse(params[:cards]) : []
    rescue JSON::ParserError
      []
    end
    result = @scum.play_cards(@current_player, cards)

    if result[:error]
      redirect_to @game, alert: result[:error]
    else
      ActionCable.server.broadcast "game_#{@game.id}", {
        message:              'update',
        finished_player_name: result[:finished_player_name],
        aces_played_by:       result[:aces_played_by],
        aces_played_cards:    result[:aces_played_cards]
      }
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

  def draw
    @game           = Game.find(params[:id])
    @canasta        = @game.canasta
    @current_player = @game.players.find_by(user_id: current_user.id)

    result = @canasta.draw(@current_player)
    if result[:error]
      redirect_to @game, alert: result[:error]
    else
      ActionCable.server.broadcast "game_#{@game.id}", { message: 'update' }
      redirect_to @game
    end
  end

  def play_red_three
    @game           = Game.find(params[:id])
    @canasta        = @game.canasta
    @current_player = @game.players.find_by(user_id: current_user.id)

    result = @canasta.play_red_three(@current_player, params[:card])

    if result[:error]
      redirect_to @game, alert: result[:error]
    else
      ActionCable.server.broadcast "game_#{@game.id}", { message: 'update' }
      redirect_to @game
    end
  end

  def draw_red_three_replacement
    @game           = Game.find(params[:id])
    @canasta        = @game.canasta
    @current_player = @game.players.find_by(user_id: current_user.id)

    result = @canasta.draw_red_three_replacement(@current_player)

    if result[:error]
      redirect_to @game, alert: result[:error]
    else
      ActionCable.server.broadcast "game_#{@game.id}", { message: 'update' }
      redirect_to @game
    end
  end

  def pickup_discard
    @game           = Game.find(params[:id])
    @canasta        = @game.canasta
    @current_player = @game.players.find_by(user_id: current_user.id)

    result = @canasta.pickup_discard(@current_player)

    if result[:error]
      redirect_to @game, alert: result[:error]
    else
      ActionCable.server.broadcast "game_#{@game.id}", {
        message: 'update', canasta_completed: result[:canasta_completed], canasta_rank: result[:canasta_rank],
        canasta_seq: result[:canasta_seq],
        pickup_cards: result[:pickup_cards], pickup_seq: result[:pickup_seq],
        acting_player_id: @current_player.id, acting_player_name: @current_player.user.name
      }
      redirect_to @game
    end
  end

  def meld
    @game           = Game.find(params[:id])
    @canasta        = @game.canasta
    @current_player = @game.players.find_by(user_id: current_user.id)

    cards = begin
      params[:cards].present? ? JSON.parse(params[:cards]) : []
    rescue JSON::ParserError
      []
    end
    target_rank = params[:target_rank].presence
    result = @canasta.meld(@current_player, cards, target_rank: target_rank)

    if result[:error]
      redirect_to @game, alert: result[:error]
    else
      ActionCable.server.broadcast "game_#{@game.id}", {
        message: 'update', canasta_completed: result[:canasta_completed], canasta_rank: result[:canasta_rank],
        canasta_seq: result[:canasta_seq], acting_player_id: @current_player.id
      }
      redirect_to @game
    end
  end

  def undo_meld
    @game           = Game.find(params[:id])
    @canasta        = @game.canasta
    @current_player = @game.players.find_by(user_id: current_user.id)

    result = @canasta.undo_meld(@current_player)

    if result[:error]
      redirect_to @game, alert: result[:error]
    else
      ActionCable.server.broadcast "game_#{@game.id}", { message: 'update' }
      redirect_to @game
    end
  end

  def discard
    @game           = Game.find(params[:id])
    @canasta        = @game.canasta
    @current_player = @game.players.find_by(user_id: current_user.id)

    result = @canasta.discard(@current_player, params[:card])

    if result[:error]
      redirect_to @game, alert: result[:error]
    else
      # Going out ends the round and puts up the score-summary screen for
      # everyone; the "round over" / "game over" celebration toasts fire
      # later, from advance_round, once the host actually dismisses it.
      ActionCable.server.broadcast "game_#{@game.id}", { message: 'update', round_ended: result[:round_ended] }
      redirect_to @game
    end
  end

  def advance_round
    @game    = Game.find(params[:id])
    @canasta = @game.canasta
    is_host = @game.players.order(:created_at).first&.user_id == current_user.id
    return redirect_to @game, alert: "Only the host can continue to the next round." unless is_host

    result = @canasta.advance_round

    if result[:error]
      redirect_to @game, alert: result[:error]
    else
      ActionCable.server.broadcast "game_#{@game.id}", {
        message: 'update',
        next_round: result[:next_round],
        game_over: result[:game_over],
        winning_team: result[:game_over] && @canasta.winning_team
      }
      redirect_to @game
    end
  end

  private

  def game_params
    params.require(:game).permit(:game_type, :pass_locks_out, :florida_rules)
  end

  def settings_params
    { pass_locks_out: params[:pass_locks_out], leader_can_continue: params[:leader_can_continue],
      florida_rules: params[:florida_rules], card_back: params[:card_back] }
  end
end
