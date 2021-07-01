class AddPayMerchantToAccounts < ActiveRecord::Migration[6.1]
  def up
    remove_column :accounts, :pay_data, :string
    add_column :accounts, :pay_data, Pay::Adapter.json_column_type
  end

  def down
    add_column :accounts, :pay_data, :string
    remove_column :accounts, :pay_data, Pay::Adapter.json_column_type
  end
end
