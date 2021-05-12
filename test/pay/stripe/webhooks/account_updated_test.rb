require "test_helper"

class Pay::Stripe::Webhooks::AccountUpdatedTest < ActiveSupport::TestCase
  setup do
    @event = OpenStruct.new
    @event.data = JSON.parse(File.read("test/support/fixtures/stripe/account_updated_event.json"), object_class: OpenStruct)
  end

  test "an account is authorized" do
    @account = Account.create! merchant_processor: :stripe, stripe_connect_account_id: @event.data.data.object.id

    Pay::Stripe::Webhooks::AccountUpdated.new.call(@event)

    assert @account.reload.onboarding_complete
  end
end
