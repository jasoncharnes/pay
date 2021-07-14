module Pay
  class Subscription < Pay::ApplicationRecord
    self.table_name = Pay.subscription_table

    STATUSES = %w[incomplete incomplete_expired trialing active past_due canceled unpaid paused]

    # Only serialize for non-json columns
    serialize :data unless json_column?("data")

    # Associations
    belongs_to :owner, polymorphic: true
    has_many :charges, class_name: "Pay::Charge", foreign_key: :pay_subscription_id

    # Validations
    validates :name, presence: true
    validates :processor, presence: true
    validates :processor_id, presence: true, uniqueness: {scope: :processor, case_sensitive: false}
    validates :processor_plan, presence: true
    validates :quantity, presence: true
    validates :status, presence: true

    # Scopes
    scope :for_name, ->(name) { where(name: name) }
    scope :on_trial, -> { where.not(trial_ends_at: nil).where("#{table_name}.trial_ends_at > ?", Time.zone.now) }
    scope :cancelled, -> { where.not(ends_at: nil) }
    scope :on_grace_period, -> { cancelled.where("#{table_name}.ends_at > ?", Time.zone.now) }
    scope :active, -> { where(ends_at: nil).or(on_grace_period).or(on_trial) }
    scope :incomplete, -> { where(status: :incomplete) }
    scope :past_due, -> { where(status: :past_due) }

    # TODO: Include these with a module
    store_accessor :data, :paddle_update_url
    store_accessor :data, :paddle_cancel_url
    store_accessor :data, :paddle_paused_from
    store_accessor :data, :stripe_account

    attribute :prorate, :boolean, default: true

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
      "Pay::#{name.to_s.classify}::Subscription".constantize
    end

    delegate :on_grace_period?,
      :paused?,
      :pause,
      :cancel,
      :cancel_now!,
      to: :payment_processor

    def no_prorate
      self.prorate = false
    end

    def skip_trial
      self.trial_ends_at = nil
    end

    def on_trial?
      trial_ends_at? && Time.zone.now < trial_ends_at
    end

    def canceled?
      ends_at?
    end

    def cancelled?
      canceled?
    end

    def active?
      ["trialing", "active"].include?(status) && (ends_at.nil? || on_grace_period? || on_trial?)
    end

    def past_due?
      status == "past_due"
    end

    def incomplete?
      status == "incomplete"
    end

    def has_incomplete_payment?
      past_due? || incomplete?
    end

    def change_quantity(quantity)
      payment_processor.change_quantity(quantity)
      update(quantity: quantity)
    end

    def resume
      payment_processor.resume
      update(ends_at: nil, status: "active")
      self
    end

    def swap(plan)
      payment_processor.swap(plan)
      update(processor_plan: plan, ends_at: nil)
    end

    def swap_and_invoice(plan)
      swap(plan)
      owner.invoice!(subscription_id: processor_id)
    end

    def processor_subscription(**options)
      payment_processor.subscription(**options)
    end

    def latest_payment
      return unless stripe?
      processor_subscription(expand: ["latest_invoice.payment_intent"]).latest_invoice.payment_intent
    end
  end
end
