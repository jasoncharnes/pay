class RemoveNotNullConstraintOnProcessorIdInPaySubscriptions < ActiveRecord::Migration[6.1]
  def up
    change_column :pay_subscriptions, :processor_plan, :string, null: true
  end

  def down
    change_column :pay_subscriptions, :processor_plan, :string, null: false
  end
end
