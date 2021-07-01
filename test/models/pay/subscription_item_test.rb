require "test_helper"

class Pay::SubscriptionItemTest < ActiveSupport::TestCase
  setup do
    @subscription_item = Pay::SubscriptionItem.new
  end

  test "belongs to a subscription" do
    @subscription = Pay.subscription_model.new processor: "stripe", status: "active"
    @subscription_item.subscription = @subscription

    assert_equal Pay::Subscription, @subscription_item.subscription.class
  end
end
