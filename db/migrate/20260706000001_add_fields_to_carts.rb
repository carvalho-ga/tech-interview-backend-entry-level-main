class AddFieldsToCarts < ActiveRecord::Migration[7.1]
  def change
    add_column :carts, :abandoned, :boolean, default: false, null: false
    add_column :carts, :last_interaction_at, :datetime
    change_column_default :carts, :total_price, 0
  end
end
