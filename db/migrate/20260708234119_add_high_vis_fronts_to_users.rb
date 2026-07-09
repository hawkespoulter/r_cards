class AddHighVisFrontsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :high_vis_fronts, :boolean, default: false, null: false
  end
end
