module Pay
  module Stripe
    class Charge
      attr_reader :pay_charge

      delegate :processor_id, :owner, :stripe_account, to: :pay_charge

      def self.sync(charge_id, object: nil)
        object ||= ::Stripe::Charge.retrieve(id: charge_id)
        owner = Pay.find_billable(processor: :stripe, processor_id: object.customer)
        return unless owner

        attrs = {
          amount: object.amount,
          amount_refunded: object.amount_refunded,
          application_fee_amount: object.application_fee_amount,
          card_exp_month: object.payment_method_details.card.exp_month,
          card_exp_year: object.payment_method_details.card.exp_year,
          card_last4: object.payment_method_details.card.last4,
          card_type: object.payment_method_details.card.brand,
          created_at: Time.at(object.created),
          currency: object.currency,
          stripe_account: owner.stripe_account
        }

        # Associate charge with subscription if we can
        if object.invoice
          invoice = (object.invoice.is_a?(::Stripe::Invoice) ? object.invoice : ::Stripe::Invoice.retrieve(object.invoice))
          attrs[:subscription] = Pay::Subscription.find_by(processor: :stripe, processor_id: invoice.subscription)
        end

        # Update or create the charge
        processor_details = {processor: :stripe, processor_id: object.id}
        if (pay_charge = owner.charges.find_by(processor_details))
          pay_charge.with_lock do
            pay_charge.update(attrs)
          end
        else
          owner.charges.create(attrs.merge(processor_details))
        end
      end

      def initialize(pay_charge)
        @pay_charge = pay_charge
      end

      def charge
        ::Stripe::Charge.retrieve({id: processor_id, expand: ["customer", "invoice.subscription"]}, stripe_options)
      rescue ::Stripe::StripeError => e
        raise Pay::Stripe::Error, e
      end

      # https://stripe.com/docs/api/refunds/create
      #
      # refund!
      # refund!(5_00)
      # refund!(5_00, refund_application_fee: true)
      def refund!(amount_to_refund, **options)
        ::Stripe::Refund.create(options.merge(charge: processor_id, amount: amount_to_refund), stripe_options)
        pay_charge.update(amount_refunded: amount_to_refund)
      rescue ::Stripe::StripeError => e
        raise Pay::Stripe::Error, e
      end

      private

      # Options for Stripe requests
      def stripe_options
        {stripe_account: stripe_account}.compact
      end
    end
  end
end
