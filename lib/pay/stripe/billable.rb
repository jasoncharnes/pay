module Pay
  module Stripe
    class Billable
      include Rails.application.routes.url_helpers

      attr_reader :billable

      delegate :processor_id,
        :processor_id?,
        :email,
        :customer_name,
        :card_token,
        to: :billable

      class << self
        def default_url_options
          Rails.application.config.action_mailer.default_url_options || {}
        end
      end

      def initialize(billable)
        @billable = billable
      end

      # Handles Billable#customer
      #
      # Returns Stripe::Customer
      def customer
        stripe_customer = if processor_id?
          ::Stripe::Customer.retrieve(processor_id)
        else
          sc = ::Stripe::Customer.create(email: email, name: customer_name)
          billable.update(processor: :stripe, processor_id: sc.id)
          sc
        end

        # Update the user's card on file if a token was passed in
        if card_token.present?
          payment_method = ::Stripe::PaymentMethod.attach(card_token, customer: stripe_customer.id)
          stripe_customer = ::Stripe::Customer.update(stripe_customer.id, invoice_settings: {default_payment_method: payment_method.id})
          update_card_on_file(payment_method.card)
        end

        stripe_customer
      rescue ::Stripe::StripeError => e
        raise Pay::Stripe::Error, e
      end

      # Handles Billable#charge
      #
      # Returns Pay::Charge
      def charge(amount, options = {})
        stripe_customer = customer
        idempotency_key = options.delete(:idempotency_key) || SecureRandom.uuid
        args = {
          amount: amount,
          confirm: true,
          confirmation_method: :automatic,
          currency: "usd",
          customer: stripe_customer.id,
          payment_method: stripe_customer.invoice_settings.default_payment_method
        }.merge(options)

        payment_intent = ::Stripe::PaymentIntent.create(args, {idempotency_key: idempotency_key})
        Pay::Payment.new(payment_intent).validate

        # Create a new charge object
        save_pay_charge(payment_intent.charges.first)
      rescue ::Stripe::StripeError => e
        raise Pay::Stripe::Error, e
      end

      # Handles Billable#subscribe
      #
      # Returns Pay::Subscription
      def subscribe(name: Pay.default_product_name, plan: Pay.default_plan_name, **options)
        quantity = options.delete(:quantity) || 1
        idempotency_key = options.delete(:idempotency_key) || SecureRandom.uuid
        opts = {
          expand: ["pending_setup_intent", "latest_invoice.payment_intent"],
          items: [plan: plan, quantity: quantity],
          off_session: true
        }.merge(options)

        # Inherit trial from plan unless trial override was specified
        opts[:trial_from_plan] = true unless opts[:trial_period_days]

        # Load the Stripe customer to verify it exists and update card if needed
        opts[:customer] = customer.id

        stripe_sub = ::Stripe::Subscription.create(opts, {idempotency_key: idempotency_key})
        existing_subscription = Pay.subscription_model.find_by(processor: :stripe, processor_id: stripe_sub.id)
        # if this subscription already exists, return it instead of creating it
        return existing_subscription unless existing_subscription.nil?

        subscription = billable.create_pay_subscription(stripe_sub, "stripe", name, plan, status: stripe_sub.status, quantity: quantity)

        # No trial, card requires SCA
        if subscription.incomplete?
          Pay::Payment.new(stripe_sub.latest_invoice.payment_intent).validate

        # Trial, card requires SCA
        elsif subscription.on_trial? && stripe_sub.pending_setup_intent
          Pay::Payment.new(stripe_sub.pending_setup_intent).validate
        end

        subscription
      rescue ::Stripe::StripeError => e
        raise Pay::Stripe::Error, e
      end

      # Handles Billable#update_card
      #
      # Returns true if successful
      def update_card(payment_method_id)
        stripe_customer = customer

        return true if payment_method_id == stripe_customer.invoice_settings.default_payment_method

        payment_method = ::Stripe::PaymentMethod.attach(payment_method_id, customer: stripe_customer.id)
        ::Stripe::Customer.update(stripe_customer.id, invoice_settings: {default_payment_method: payment_method.id})

        update_card_on_file(payment_method.card)
        true
      rescue ::Stripe::StripeError => e
        raise Pay::Stripe::Error, e
      end

      def update_email!
        ::Stripe::Customer.update(processor_id, {email: email, name: customer_name})
      end

      def processor_subscription(subscription_id, options = {})
        ::Stripe::Subscription.retrieve(options.merge(id: subscription_id))
      end

      def invoice!(options = {})
        return unless processor_id?
        ::Stripe::Invoice.create(options.merge(customer: processor_id)).pay
      end

      def upcoming_invoice
        ::Stripe::Invoice.upcoming(customer: processor_id)
      end

      # Used by webhooks when the customer or source changes
      def sync_card_from_stripe
        if (payment_method_id = customer.invoice_settings.default_payment_method)
          update_card_on_file ::Stripe::PaymentMethod.retrieve(payment_method_id).card
        else
          billable.update(card_type: nil, card_last4: nil)
        end
      end

      def create_setup_intent
        ::Stripe::SetupIntent.create(customer: processor_id, usage: :off_session)
      end

      def trial_end_date(stripe_sub)
        # Times in Stripe are returned in UTC
        stripe_sub.trial_end.present? ? Time.at(stripe_sub.trial_end) : nil
      end

      # Save the card to the database as the user's current card
      def update_card_on_file(card)
        billable.update!(
          card_type: card.brand.capitalize,
          card_last4: card.last4,
          card_exp_month: card.exp_month,
          card_exp_year: card.exp_year
        )

        billable.card_token = nil
      end

      def save_pay_charge(object)
        charge = billable.charges.find_or_initialize_by(processor: :stripe, processor_id: object.id)

        charge.update(
          amount: object.amount,
          card_last4: object.payment_method_details.card.last4,
          card_type: object.payment_method_details.card.brand,
          card_exp_month: object.payment_method_details.card.exp_month,
          card_exp_year: object.payment_method_details.card.exp_year,
          created_at: Time.zone.at(object.created)
        )

        charge
      end

      # https://stripe.com/docs/api/checkout/sessions/create
      #
      # checkout(mode: "payment")
      # checkout(mode: "setup")
      # checkout(mode: "subscription")
      #
      # checkout(line_items: "price_12345", quantity: 2)
      # checkout(line_items [{ price: "price_123" }, { price: "price_456" }])
      # checkout(line_items, "price_12345", allow_promotion_codes: true)
      #
      def checkout(**options)
        args = {
          customer: processor_id,
          payment_method_types: ["card"],
          mode: "payment",
          # These placeholder URLs will be replaced in a following step.
          success_url: options.delete(:success_url) || root_url,
          cancel_url: options.delete(:cancel_url) || root_url
        }

        # Line items are optional
        if (line_items = options.delete(:line_items))
          args[:line_items] = Array.wrap(line_items).map { |item|
            if item.is_a? Hash
              item
            else
              {price: item, quantity: options.fetch(:quantity, 1)}
            end
          }
        end

        ::Stripe::Checkout::Session.create(args.merge(options))
      end

      # https://stripe.com/docs/api/checkout/sessions/create
      #
      # checkout_charge(amount: 15_00, name: "T-shirt", quantity: 2)
      #
      def checkout_charge(amount:, name:, quantity: 1, **options)
        currency = options.delete(:currency) || "usd"
        checkout(
          line_items: {
            price_data: {
              currency: currency,
              product_data: {name: name},
              unit_amount: amount
            },
            quantity: quantity
          },
          **options
        )
      end

      def billing_portal(**options)
        args = {
          customer: processor_id,
          return_url: options.delete(:return_url) || root_url
        }
        ::Stripe::BillingPortal::Session.create(args.merge(options))
      end
    end
  end
end
