class ChangeNameToEnumInGames < ActiveRecord::Migration[7.1]
  def change
    add_column :games, :game_type, :integer, default: 0
    remove_column :games, :name, :string
  end
end
