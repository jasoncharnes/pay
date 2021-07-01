class CreatePaySubscriptionItems < ActiveRecord::Migration[6.1]
  def change
    create_table :pay_subscription_items do |t|
      t.references :pay_subscription
      t.string :processor_id, null: false
      t.string :processor_price, null: false
      t.integer :quantity, default: 1, null: false
      t.timestamps
    end
  end
end
