class Game < ApplicationRecord
  # serialize :players, Array

  def player_names
    users = User.where(:id => players)
    users.pluck(:name)
  end
end
