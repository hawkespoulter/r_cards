class AddCanastaStatsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :canasta_stats, :jsonb, default: {}, null: false
  end
end
