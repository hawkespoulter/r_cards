class CreateLuckySevens < ActiveRecord::Migration[7.1]
  def change
    create_table :lucky_sevens do |t|
      t.bigint :game_id
      t.jsonb :game_state, default: {}
      t.timestamps
    end
    add_index :lucky_sevens, :game_id
    add_foreign_key :lucky_sevens, :games
  end
end
