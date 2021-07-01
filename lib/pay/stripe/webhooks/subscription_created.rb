module Pay
  module Stripe
    module Webhooks
      class SubscriptionCreated
        def call(event)
          object = event.data.object
          Pay::Stripe::Subscription.sync(object.id, object: object)
        end
      end
    end
  end
end
