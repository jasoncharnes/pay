# frozen_string_literal: true

class AddPayBillableTo<%= table_name.camelize %> < ActiveRecord::Migration<%= migration_version %>
  def change
    change_table :<%= table_name %>, bulk: true do |t|
      t.string :processor
      t.string :processor_id
      t.public_send(Pay::Adapter.json_column_type, :pay_data)
      t.datetime :trial_ends_at
      t.string :card_type
      t.string :card_last4
      t.string :card_exp_month
      t.string :card_exp_year
      t.text :extra_billing_info
    end
  end
end
