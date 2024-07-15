class RemovePlayersFromGames < ActiveRecord::Migration[7.1]
  def change
    remove_column :games, :players, :integer, array: true, default: []
  end
end
