class RemoveNotNullConstraintOnQuantityInPaySubscriptions < ActiveRecord::Migration[6.1]
  def up
    change_column :pay_subscriptions, :quantity, :integer, default: 1, null: true
  end

  def down
    change_column :pay_subscriptions, :quantity, :integer, default: 1, null: false
  end
end
