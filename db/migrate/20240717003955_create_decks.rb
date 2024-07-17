class CreateDecks < ActiveRecord::Migration[7.1]
  def change
    create_table :decks do |t|
      t.references :game, foreign_key: true
      t.jsonb :cards, default: []
      
      t.timestamps
    end
  end
end
