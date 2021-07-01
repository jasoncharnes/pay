module Pay
  module Stripe
    module Webhooks
      class ChargeRefunded
        def call(event)
          object = event.data.object
          pay_charge = Pay::Stripe::Charge.sync(object.id, object: object)
          notify_user(pay_charge.owner, pay_charge) if pay_charge
        end

        def notify_user(billable, charge)
          if Pay.send_emails
            Pay::UserMailer.with(billable: billable, charge: charge).refund.deliver_later
          end
        end
      end
    end
  end
end
