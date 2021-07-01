module Pay
  module Stripe
    class Subscription
      attr_reader :pay_subscription

      delegate :active?,
        :canceled?,
        :ends_at,
        :name,
        :on_trial?,
        :owner,
        :processor_id,
        :processor_plan,
        :processor_subscription,
        :prorate,
        :prorate?,
        :quantity,
        :quantity?,
        :stripe_account,
        :trial_ends_at,
        to: :pay_subscription

      def self.sync(subscription_id, object: nil, name: Pay.default_product_name)
        # Skip loading the latest subscription details from the API if we already have it
        object ||= ::Stripe::Subscription.retrieve(id: subscription_id, expand: ["pending_setup_intent", "latest_invoice.payment_intent"])

        owner = Pay.find_billable(processor: :stripe, processor_id: object.customer)
        return unless owner

        attributes = {
          application_fee_percent: object.application_fee_percent,
          processor_plan: object.plan&.id,
          quantity: object.quantity,
          name: name,
          status: object.status,
          stripe_account: owner.stripe_account,
          trial_ends_at: (object.trial_end ? Time.at(object.trial_end) : nil)
        }

        # Subscriptions cancelling in the future
        attributes[:ends_at] = Time.at(object.current_period_end) if object.cancel_at_period_end

        # Fully cancelled subscription
        attributes[:ends_at] = Time.at(object.ended_at) if object.ended_at

        # Update or create the subscription
        pay_subscription = owner.subscriptions.find_or_initialize_by(processor: :stripe, processor_id: object.id)

        pay_subscription.update(attributes)

        # Sync new items_data with existing subscription_item records
        # (subscription record must exist)
        if pay_subscription.persisted?
          si_attributes = sync_subscription_items_attributes(pay_subscription, object.items.data)
          pay_subscription.update(
            subscription_items_attributes: si_attributes
          )
        end

        pay_subscription
      end

      def self.sync_subscription_items_attributes(subscription, items_data)
        return subscription_items_attributes(items_data) if subscription.subscription_items.empty?

        # Destroy all existing subscription items
        items_to_destroy = subscription.subscription_items.map do |subscription_item|
          {id: subscription_item.id, _destroy: true}
        end

        # Rebuild subscription item records based on new items data
        subscription_items_attributes(items_data) + items_to_destroy
      end

      def self.subscription_items_attributes(items_data)
        items_data.map do |subscription_item|
          {
            processor_id: subscription_item.id,
            processor_price: subscription_item.price.id,
            quantity: subscription_item.quantity
          }
        end
      end

      def initialize(pay_subscription)
        @pay_subscription = pay_subscription
      end

      def subscription(**options)
        ::Stripe::Subscription.retrieve(options.merge(id: processor_id))
      end

      def cancel
        stripe_sub = ::Stripe::Subscription.update(processor_id, {cancel_at_period_end: true}, {stripe_account: stripe_account})
        pay_subscription.update(ends_at: (on_trial? ? trial_ends_at : Time.at(stripe_sub.current_period_end)))
      rescue ::Stripe::StripeError => e
        raise Pay::Stripe::Error, e
      end

      def cancel_now!
        ::Stripe::Subscription.delete(processor_id, {stripe_account: stripe_account})
        pay_subscription.update(ends_at: Time.current, status: :canceled)
      rescue ::Stripe::StripeError => e
        raise Pay::Stripe::Error, e
      end

      def change_quantity(quantity)
        ::Stripe::Subscription.update(
          processor_id,
          {quantity: quantity},
          {stripe_account: stripe_account}
        )
      rescue ::Stripe::StripeError => e
        raise Pay::Stripe::Error, e
      end

      def on_grace_period?
        canceled? && Time.zone.now < ends_at
      end

      def paused?
        false
      end

      def pause
        raise NotImplementedError, "Stripe does not support pausing subscriptions"
      end

      def resume
        unless on_grace_period?
          raise StandardError, "You can only resume subscriptions within their grace period."
        end

        ::Stripe::Subscription.update(
          processor_id,
          {
            plan: processor_plan,
            trial_end: (on_trial? ? trial_ends_at.to_i : "now"),
            cancel_at_period_end: false
          },
          {stripe_account: stripe_account}
        )
      rescue ::Stripe::StripeError => e
        raise Pay::Stripe::Error, e
      end

      def swap(plan)
        ::Stripe::Subscription.update(
          processor_id,
          {
            cancel_at_period_end: false,
            plan: plan,
            proration_behavior: (prorate ? "create_prorations" : "none"),
            trial_end: (on_trial? ? trial_ends_at.to_i : "now"),
            quantity: quantity
          },
          {stripe_account: stripe_account}
        )
      rescue ::Stripe::StripeError => e
        raise Pay::Stripe::Error, e
      end
    end
  end
end
