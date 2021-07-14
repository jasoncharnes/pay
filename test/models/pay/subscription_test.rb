require "test_helper"

class Pay::Subscription::Test < ActiveSupport::TestCase
  setup do
    @owner = User.create email: "bill@microsoft.com", card_token: "pm_card_visa", processor: :stripe
    @subscription = Pay.subscription_model.new processor: "stripe", status: "active"
  end

  test "validates subscription uniqueness by processor and processor ID" do
    subscription1 = create_subscription(name: "default", processor_id: 1)
    assert_raises ActiveRecord::RecordInvalid do
      subscription1 = create_subscription(name: "default", processor_id: 1)
    end
  end

  test "belongs to a polymorphic owner" do
    @subscription.owner = @owner
    assert_equal User, @subscription.owner.class
    @subscription.owner = Team.new
    assert_equal Team, @subscription.owner.class
  end

  test "braintree?" do
    assert @subscription.respond_to?(:braintree?)
  end

  test "stripe?" do
    assert @subscription.respond_to?(:stripe?)
  end

  test "paddle?" do
    assert @subscription.respond_to?(:paddle?)
  end

  test "braintree scope" do
    assert Pay.subscription_model.braintree.is_a?(ActiveRecord::Relation)
  end

  test "stripe scope" do
    assert Pay.subscription_model.stripe.is_a?(ActiveRecord::Relation)
  end

  test "paddle scope" do
    assert Pay.subscription_model.paddle.is_a?(ActiveRecord::Relation)
  end

  test ".for_name(name) scope" do
    subscription1 = create_subscription(name: "default")
    subscription2 = create_subscription(name: "superior")

    subscriptions = Pay.subscription_model.for_name("default")
    assert_includes subscriptions, subscription1
    refute_includes subscriptions, subscription2
  end

  test "on trial scope" do
    subscription1 = create_subscription(trial_ends_at: 7.days.from_now)
    subscription2 = create_subscription(trial_ends_at: nil)
    subscription3 = create_subscription(trial_ends_at: 7.days.ago)

    subscriptions = Pay.subscription_model.on_trial

    assert_includes subscriptions, subscription1
    refute_includes subscriptions, subscription2
    refute_includes subscriptions, subscription3
  end

  test "cancelled scope" do
    subscription1 = create_subscription(ends_at: 7.days.ago)
    subscription2 = create_subscription(ends_at: 7.days.from_now)
    subscription3 = create_subscription(ends_at: nil)

    subscriptions = Pay.subscription_model.cancelled

    assert_includes subscriptions, subscription1
    assert_includes subscriptions, subscription2
    refute_includes subscriptions, subscription3
  end

  test "on grace period scope" do
    subscription1 = create_subscription(ends_at: 7.days.from_now)
    subscription2 = create_subscription(ends_at: nil)
    subscription3 = create_subscription(ends_at: 7.days.ago)

    subscriptions = Pay.subscription_model.on_grace_period

    assert_includes subscriptions, subscription1
    refute_includes subscriptions, subscription2
    refute_includes subscriptions, subscription3
  end

  test "active scope" do
    subscription1 = create_subscription
    subscription2 = create_subscription(trial_ends_at: 7.days.from_now)
    subscription3 = create_subscription(ends_at: 7.days.from_now)
    subscription4 = create_subscription(ends_at: 7.days.ago)
    subscription5 = create_subscription(ends_at: 8.days.ago, trial_ends_at: 7.days.ago)

    subscriptions = Pay.subscription_model.active

    assert_includes subscriptions, subscription1
    assert_includes subscriptions, subscription2
    assert_includes subscriptions, subscription3
    refute_includes subscriptions, subscription4
    refute_includes subscriptions, subscription5
  end

  test "active trial" do
    @subscription.trial_ends_at = 5.minutes.from_now
    assert @subscription.on_trial?
  end

  test "inactive trial" do
    @subscription.trial_ends_at = 5.minutes.ago
    refute @subscription.on_trial?
  end

  test "no trial" do
    @subscription.trial_ends_at = nil
    refute @subscription.on_trial?
  end

  test "cancelled" do
    @subscription.ends_at = 1.week.ago
    assert @subscription.cancelled?
  end

  test "not cancelled" do
    @subscription.ends_at = nil
    refute @subscription.cancelled?
  end

  test "on grace period" do
    @subscription.ends_at = 5.minutes.from_now
    assert @subscription.on_grace_period?
  end

  test "off grace period" do
    @subscription.ends_at = 5.minutes.ago
    refute @subscription.on_grace_period?
  end

  test "no grace period" do
    @subscription.ends_at = nil
    refute @subscription.on_grace_period?
  end

  test "active" do
    @subscription.ends_at = nil
    @subscription.trial_ends_at = nil
    assert @subscription.active?
  end

  test "inactive" do
    @subscription.ends_at = 5.minutes.ago
    @subscription.trial_ends_at = nil
    refute @subscription.active?
  end

  test "cancel" do
    travel_to_cassette do
      subscription = @owner.subscribe
      refute subscription.ends_at?
      subscription.cancel
      assert subscription.ends_at?
      assert subscription.processor_subscription.cancel_at_period_end
    end
  end

  test "cancel trialing" do
    travel_to_cassette do
      subscription = @owner.subscribe(trial_period_days: 14)
      refute subscription.ends_at?
      subscription.cancel
      assert_equal subscription.ends_at.to_date, 14.days.from_now.to_date
      assert subscription.processor_subscription.cancel_at_period_end
    end
  end

  test "cancel_now!" do
    travel_to_cassette do
      subscription = @owner.subscribe
      refute subscription.ends_at?
      subscription.cancel_now!
      assert subscription.ends_at <= Time.current
    end
  end

  test "resume on grace period" do
    travel_to_cassette do
      subscription = @owner.subscribe
      subscription.cancel
      subscription.resume
      refute subscription.ends_at?
      refute subscription.processor_subscription.cancel_at_period_end
    end
  end

  test "resume off grace period" do
    travel_to_cassette do
      subscription = @owner.subscribe
      subscription.cancel_now!
      assert_raises StandardError do
        subscription.resume
      end
    end
  end

  test "processor subscription" do
    @subscription.payment_processor.stubs(:subscription).returns(:result)
    assert_equal :result, @subscription.processor_subscription
  end

  test "can swap plans" do
    travel_to_cassette do
      subscription = @owner.subscribe
      subscription.swap("small-annual")
      assert_equal "small-annual", subscription.processor_subscription.plan.id
    end
  end

  test "statuses affect active state" do
    %w[trialing active].each do |state|
      @subscription.status = state
      assert @subscription.active?
    end

    %w[incomplete incomplete_expired past_due canceled unpaid paused].each do |state|
      @subscription.status = state
      assert_not @subscription.active?
    end
  end

  test "correctly handles v1 subscriptions without statuses" do
    # Subscriptions in Pay v1.x didn't have a status column, so we've set all their statuses to active
    # We just want to make sure those old, ended subscriptions are still correct
    assert_not Pay::Subscription.new(processor: :stripe, status: :active, ends_at: 1.day.ago).active?
    assert Pay::Subscription.new(processor: :stripe, status: :active, ends_at: 1.day.ago).canceled?
  end

  private

  def create_subscription(options = {})
    defaults = {
      name: "default",
      owner: @owner,
      processor: "stripe",
      processor_id: rand(1..999_999_999),
      processor_plan: "default",
      quantity: "1",
      status: "active"
    }

    Pay.subscription_model.create! defaults.merge(options)
  end
end
