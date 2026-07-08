class AddIndexesAndCascadeDeleteToCarts < ActiveRecord::Migration[7.1]
  def change
    add_index :carts, [:abandoned, :last_interaction_at]
    add_index :carts, [:abandoned, :abandoned_at]

    remove_foreign_key :cart_items, :carts
    add_foreign_key :cart_items, :carts, on_delete: :cascade
  end
end
