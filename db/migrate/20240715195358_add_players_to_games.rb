class AddPlayersToGames < ActiveRecord::Migration[7.1]
  def change
    add_column :games, :players, :integer, array: true, default: []
  end
end
