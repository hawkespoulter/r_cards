class AddSettingsToGames < ActiveRecord::Migration[7.1]
  def change
    add_column :games, :settings, :jsonb, default: {}
  end
end
