class RenameStateToGameStateInScums < ActiveRecord::Migration[7.1]
  def change
    rename_column :scums, :state, :game_state
  end
end
