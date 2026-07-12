class StatsController < ApplicationController
  before_action :authenticate_user!

  # Sort keys a visitor can order the all-players table by — allowlisted
  # rather than passing params[:sort] straight into a DB column reference.
  SORTABLE_STATS = %w[
    games_played games_won rounds_played rounds_won total_points best_round_score
    canastas_made clean_canastas_made dirty_canastas_made red_threes_played
    piles_picked_up cards_drawn cards_discarded times_gone_out
  ].freeze

  def index
    @my_stats = current_user.canasta_stats

    sort = SORTABLE_STATS.include?(params[:sort]) ? params[:sort] : "games_won"
    @sort = sort
    @players = User.all.select { |u| u.canasta_stats.present? }
                   .sort_by { |u| -(u.canasta_stats[sort].to_i) }
  end
end
