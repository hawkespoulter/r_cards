class GamesController < ApplicationController

  def index
    @games = Game.all
  end

  def show
    @game = Game.find(params[:id])
    load_game_view_state
    respond_to do |format|
      format.html
      format.turbo_stream
    end
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
      respond_with_game_error(result[:error])
    else
      ActionCable.server.broadcast "game_#{@game.id}", { message: 'update' }
      respond_with_game_update
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
      respond_with_game_error(result[:error])
    else
      ActionCable.server.broadcast "game_#{@game.id}", { message: 'update' }
      respond_with_game_update
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
    respond_with_game_update
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
    respond_with_game_update
  end

  def set_team
    @game = Game.find(params[:id])
    is_host = @game.players.order(:created_at).first&.user_id == current_user.id
    return redirect_to @game, alert: "Only the host can assign teams." unless is_host
    return redirect_to @game if @game.turn_order.present?

    team = params[:team].to_i
    return redirect_to @game, alert: "Invalid team" unless [0, 1].include?(team)

    player = @game.players.find(params[:player_id])
    player.update!(team: team)
    ActionCable.server.broadcast "game_#{@game.id}", { message: "update" }
    respond_with_game_update
  end

  def take_turn
    @game = Game.find(params[:id])
    @game.take_turn
    ActionCable.server.broadcast "game_#{@game.id}", { message: 'Next turn!' }
    respond_with_game_update
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
      respond_with_game_error(result[:error])
    else
      ActionCable.server.broadcast "game_#{@game.id}", {
        message:              'update',
        finished_player_name: result[:finished_player_name],
        aces_played_by:       result[:aces_played_by],
        aces_played_cards:    result[:aces_played_cards]
      }
      respond_with_game_update
    end
  end

  def update_settings
    @game = Game.find(params[:id])
    @game.update!(settings_params)
    ActionCable.server.broadcast "game_#{@game.id}", { message: 'settings_updated' }
    respond_with_game_update
  end

  def pass
    @game           = Game.find(params[:id])
    @scum           = @game.scum
    @current_player = @game.players.find_by(user_id: current_user.id)

    result = @scum.pass_turn(@current_player)

    if result[:error]
      respond_with_game_error(result[:error])
    else
      ActionCable.server.broadcast "game_#{@game.id}", { message: 'update' }
      respond_with_game_update
    end
  end

  def draw
    @game           = Game.find(params[:id])
    @canasta        = @game.canasta
    @current_player = @game.players.find_by(user_id: current_user.id)

    result = @canasta.draw(@current_player)
    if result[:error]
      respond_with_game_error(result[:error])
    else
      # A draw can now end the round itself (stalemate: both piles ran dry),
      # same as discard going out — broadcast round_ended so everyone else's
      # board reveals the summary screen too.
      ActionCable.server.broadcast "game_#{@game.id}", { message: 'update', round_ended: result[:round_ended] }
      respond_with_game_update
    end
  end

  def play_red_three
    @game           = Game.find(params[:id])
    @canasta        = @game.canasta
    @current_player = @game.players.find_by(user_id: current_user.id)

    cards = begin
      params[:cards].present? ? JSON.parse(params[:cards]) : Array(params[:card])
    rescue JSON::ParserError
      Array(params[:card])
    end
    result = @canasta.play_red_three(@current_player, cards)

    if result[:error]
      respond_with_game_error(result[:error])
    else
      ActionCable.server.broadcast "game_#{@game.id}", { message: 'update' }
      respond_with_game_update
    end
  end

  def draw_red_three_replacement
    @game           = Game.find(params[:id])
    @canasta        = @game.canasta
    @current_player = @game.players.find_by(user_id: current_user.id)

    result = @canasta.draw_red_three_replacement(@current_player)

    if result[:error]
      respond_with_game_error(result[:error])
    else
      # Same stalemate possibility as #draw — broadcast round_ended so
      # everyone else's board reveals the summary screen too.
      ActionCable.server.broadcast "game_#{@game.id}", { message: 'update', round_ended: result[:round_ended] }
      respond_with_game_update
    end
  end

  def pickup_discard
    @game           = Game.find(params[:id])
    @canasta        = @game.canasta
    @current_player = @game.players.find_by(user_id: current_user.id)

    result = @canasta.pickup_discard(@current_player)

    if result[:error]
      respond_with_game_error(result[:error])
    else
      ActionCable.server.broadcast "game_#{@game.id}", {
        message: 'update', canasta_completed: result[:canasta_completed], canasta_rank: result[:canasta_rank],
        canasta_seq: result[:canasta_seq],
        pickup_cards: result[:pickup_cards], pickup_seq: result[:pickup_seq],
        acting_player_id: @current_player.id, acting_player_name: @current_player.user.name
      }
      respond_with_game_update
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
      respond_with_game_error(result[:error])
    else
      ActionCable.server.broadcast "game_#{@game.id}", {
        message: 'update', canasta_completed: result[:canasta_completed], canasta_rank: result[:canasta_rank],
        canasta_seq: result[:canasta_seq], canasta_cards: result[:canasta_cards], acting_player_id: @current_player.id
      }
      respond_with_game_update
    end
  end

  def undo_meld
    @game           = Game.find(params[:id])
    @canasta        = @game.canasta
    @current_player = @game.players.find_by(user_id: current_user.id)

    result = @canasta.undo_meld(@current_player)

    if result[:error]
      respond_with_game_error(result[:error])
    else
      ActionCable.server.broadcast "game_#{@game.id}", { message: 'update' }
      respond_with_game_update
    end
  end

  def discard
    @game           = Game.find(params[:id])
    @canasta        = @game.canasta
    @current_player = @game.players.find_by(user_id: current_user.id)

    result = @canasta.discard(@current_player, params[:card])

    if result[:error]
      respond_with_game_error(result[:error])
    else
      # Going out ends the round and puts up the score-summary screen for
      # everyone; the "round over" / "game over" celebration toasts fire
      # later, from advance_round, once the host actually dismisses it.
      ActionCable.server.broadcast "game_#{@game.id}", { message: 'update', round_ended: result[:round_ended] }
      respond_with_game_update
    end
  end

  def advance_round
    @game    = Game.find(params[:id])
    @canasta = @game.canasta
    is_host = @game.players.order(:created_at).first&.user_id == current_user.id
    return redirect_to @game, alert: "Only the host can continue to the next round." unless is_host

    result = @canasta.advance_round

    if result[:error]
      respond_with_game_error(result[:error])
    else
      ActionCable.server.broadcast "game_#{@game.id}", {
        message: 'update',
        next_round: result[:next_round],
        game_over: result[:game_over],
        winning_team: result[:game_over] && @canasta.winning_team
      }
      respond_with_game_update
    end
  end

  private

  # Populates everything `show.html.erb`/`show.turbo_stream.erb` need to
  # render the current player's view of @game. Assumes @game is already set.
  def load_game_view_state
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

  # Success response for any action that changes game state: Turbo Stream
  # clients (i.e. the acting player's own form submission) get an in-place
  # re-render of the board via show.turbo_stream.erb; anything else falls
  # back to the classic redirect.
  def respond_with_game_update
    load_game_view_state
    respond_to do |format|
      format.turbo_stream { render "games/show" }
      format.html { redirect_to @game }
    end
  end

  # Error response mirroring respond_with_game_update — Turbo Stream clients
  # get the error popup patched in without a navigation; others fall back to
  # the classic flash-based redirect.
  def respond_with_game_error(message)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "flash-error-container", partial: "layouts/flash_error", locals: { alert: message }
        )
      end
      format.html { redirect_to @game, alert: message }
    end
  end

  def game_params
    params.require(:game).permit(:game_type, :pass_locks_out, :florida_rules)
  end

  def settings_params
    { pass_locks_out: params[:pass_locks_out], leader_can_continue: params[:leader_can_continue],
      florida_rules: params[:florida_rules], card_back: params[:card_back],
      team1_name: params[:team1_name], team2_name: params[:team2_name] }.compact
  end
end
