class AddTurnOrderToGames < ActiveRecord::Migration[7.1]
  def change
    add_column :games, :turn_order, :integer, array: true, default: []
  end
end
