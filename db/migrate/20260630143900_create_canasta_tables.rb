class CreateCanastaTables < ActiveRecord::Migration[7.1]
  def change
    add_column :players, :team, :integer

    create_table :canastas do |t|
      t.bigint :game_id
      t.jsonb :game_state, default: {}
      t.timestamps
    end
    add_index :canastas, :game_id
    add_foreign_key :canastas, :games
  end
end
