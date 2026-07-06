class Player < ApplicationRecord
  belongs_to :user
  belongs_to :game

  before_create :initialize_hand
  before_create :assign_default_team

  private

  def initialize_hand
    self.hand ||= []
  end

  # Alternates by join order so teams start out even; the host can
  # rearrange them from the lobby before the game starts (see
  # GamesController#set_team).
  def assign_default_team
    self.team ||= game.players.count % 2
  end
end
