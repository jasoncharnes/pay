module Pay
  module Stripe
    module Webhooks
      class PaymentIntentSucceeded
        def call(event)
          object = event.data.object
          object.charges.data.each do |charge|
            pay_charge = Pay::Stripe::Charge.sync(charge.id, object: charge)
            notify_user(pay_charge.owner, pay_charge) if pay_charge
          end
        end

        def notify_user(billable, charge)
          if Pay.send_emails && charge.respond_to?(:receipt)
            Pay::UserMailer.with(billable: billable, charge: charge).receipt.deliver_later
          end
        end
      end
    end
  end
end
