module Pay
  class Charge < Pay::ApplicationRecord
    self.table_name = Pay.chargeable_table

    # Only serialize for non-json columns
    serialize :data unless json_column?("data")

    # Associations
    belongs_to :owner, polymorphic: true
    belongs_to :subscription, optional: true, class_name: "Pay::Subscription", foreign_key: :pay_subscription_id

    # Scopes
    scope :sorted, -> { order(created_at: :desc) }
    default_scope -> { sorted }

    # Validations
    validates :amount, presence: true
    validates :processor, presence: true
    validates :processor_id, presence: true, uniqueness: {scope: :processor, case_sensitive: false}
    validates :card_type, presence: true

    store_accessor :data, :paddle_receipt_url
    store_accessor :data, :stripe_account

    # Helpers for payment processors
    %w[braintree stripe paddle fake_processor].each do |processor_name|
      define_method "#{processor_name}?" do
        processor == processor_name
      end

      scope processor_name, -> { where(processor: processor_name) }
    end

    def payment_processor
      @payment_processor ||= payment_processor_for(processor).new(self)
    end

    def payment_processor_for(name)
      "Pay::#{name.to_s.classify}::Charge".constantize
    end

    def processor_charge
      payment_processor.charge
    end

    def refund!(refund_amount = nil)
      refund_amount ||= amount
      payment_processor.refund!(refund_amount)
    end

    def charged_to
      "#{card_type} (**** **** **** #{card_last4})"
    end

    def paypal?
      braintree? && card_type == "PayPal"
    end
  end
end
