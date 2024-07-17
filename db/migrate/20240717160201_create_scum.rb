class CreateScum < ActiveRecord::Migration[7.1]
  def change
    create_table :scums do |t|
      t.references :game, foreign_key: true
      t.jsonb :state, default: {}

      t.timestamps
    end
  end
end
