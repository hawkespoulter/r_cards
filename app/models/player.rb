class Player < ApplicationRecord
  belongs_to :user
  belongs_to :game

  before_create :initialize_hand

  private

  def initialize_hand
    self.hand ||= []
  end
end
