class RemoveHandFromPlayers < ActiveRecord::Migration[7.1]
  def change
    remove_column :players, :hand, :string
  end
end
