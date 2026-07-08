class AddCardBackToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :card_back, :string
  end
end
