class CreateBugs < ActiveRecord::Migration[7.1]
  def change
    create_table :bugs do |t|
      t.text :description, null: false
      t.integer :status, default: 0, null: false

      t.timestamps
    end
  end
end
