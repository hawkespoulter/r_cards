class AddIsTurnToPlayers < ActiveRecord::Migration[7.1]
  def change
    add_column :players, :is_turn, :boolean
  end
end
