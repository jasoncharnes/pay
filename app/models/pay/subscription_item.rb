class Pay::SubscriptionItem < ApplicationRecord
  self.table_name = "pay_subscription_items"

  belongs_to :subscription, class_name: "Pay::Subscription", foreign_key: :pay_subscription_id

  validates :processor_id, presence: true
  validates :processor_price, presence: true
  validates :quantity, numericality: {
    only_integer: true,
    greater_than_or_equal_to: 1
  }
end
