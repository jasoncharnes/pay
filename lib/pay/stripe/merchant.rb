module Pay
  module Stripe
    class Merchant
      attr_reader :merchant

      delegate :stripe_connect_account_id,
        to: :merchant

      def initialize(merchant)
        @merchant = merchant
      end

      def create_account(**options)
        defaults = {
          type: "express",
          capabilities: {
            card_payments: {requested: true},
            transfers: {requested: true}
          }
        }

        stripe_account = ::Stripe::Account.create(defaults.merge(options))
        merchant.update(stripe_connect_account_id: stripe_account.id)
        stripe_account
      rescue ::Stripe::StripeError => e
        raise Pay::Stripe::Error, e
      end

      def account
        ::Stripe::Account.retrieve(stripe_connect_account_id)
      rescue ::Stripe::StripeError => e
        raise Pay::Stripe::Error, e
      end

      def account_link(refresh_url:, return_url:, type: "account_onboarding", **options)
        ::Stripe::AccountLink.create({
          account: stripe_connect_account_id,
          refresh_url: refresh_url,
          return_url: return_url,
          type: type
        })
      rescue ::Stripe::StripeError => e
        raise Pay::Stripe::Error, e
      end

      # A single-use login link for Express accounts to access their Stripe dashboard
      def login_link(**options)
        ::Stripe::Account.create_login_link(stripe_connect_account_id)
      rescue ::Stripe::StripeError => e
        raise Pay::Stripe::Error, e
      end

      # Transfer money from the platform to this connected account
      # https://stripe.com/docs/connect/charges-transfers#transfer-availability
      def transfer(amount:, currency: "usd", **options)
        ::Stripe::Transfer.create({
          amount: amount,
          currency: currency,
          destination: stripe_connect_account_id,
        }.merge(options))
      rescue ::Stripe::StripeError => e
        raise Pay::Stripe::Error, e
      end
    end
  end
end
