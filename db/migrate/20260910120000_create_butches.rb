class CreateButches < ActiveRecord::Migration[7.1]
  def change
    create_table :butches do |t|
      t.bigint :game_id
      t.jsonb :game_state, default: {}
      t.timestamps
    end
    add_index :butches, :game_id
    add_foreign_key :butches, :games
  end
end
