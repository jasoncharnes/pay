require "test_helper"

class Pay::Paddle::Subscription::Test < ActiveSupport::TestCase
  setup do
    @billable = User.create!(email: "gob@bluth.com", processor: :paddle, processor_id: "17368056")
  end

  test "paddle cancel" do
    @billable.subscriptions.create!(
      processor: :paddle,
      processor_id: "3576212",
      name: "default",
      processor_plan: "some-plan",
      status: "active"
    )
    subscription = @billable.subscription
    next_payment_date = Time.zone.parse(subscription.processor_subscription.next_payment[:date])
    subscription.cancel
    assert_equal subscription.ends_at, next_payment_date
    assert_equal "canceled", subscription.status
  end

  test "paddle cancel_now!" do
    @billable.subscriptions.create!(
      processor: :paddle,
      processor_id: "3484448",
      name: "default",
      processor_plan: "some-plan",
      status: "active"
    )
    subscription = @billable.subscription
    subscription.cancel_now!
    assert subscription.ends_at <= Time.zone.now
    assert_equal "canceled", subscription.status
  end

  test "paddle processor subscription" do
    @billable.subscriptions.create!(
      processor: :paddle,
      processor_id: "3484448",
      name: "default",
      processor_plan: "some-plan",
      status: "active"
    )
    assert_equal @billable.subscription.processor_subscription.class, OpenStruct
    assert_equal "active", @billable.subscription.status
  end

  test "paddle pause" do
    @billable.subscriptions.create!(
      processor: :paddle,
      processor_id: "3576390",
      name: "default",
      processor_plan: "some-plan",
      status: "active"
    )
    subscription = @billable.subscription
    next_payment_date = Time.zone.parse(subscription.processor_subscription.next_payment[:date])
    subscription.pause
    assert subscription.paused?
    assert_equal next_payment_date, subscription.paddle_paused_from
  end

  test "paddle pause grace period" do
    @billable.subscriptions.create!(
      processor: :paddle,
      processor_id: "3576390",
      name: "default",
      processor_plan: "some-plan",
      status: "active",
      paddle_paused_from: Time.zone.now + 1.week
    )
    subscription = @billable.subscription
    assert subscription.paused?
    assert subscription.on_grace_period?
  end

  test "paddle paused subscription is not active" do
    @billable.subscriptions.create!(
      processor: :paddle,
      processor_id: "3576390",
      name: "default",
      processor_plan: "some-plan",
      status: "paused"
    )
    assert_not @billable.subscription.active?
  end

  test "paddle paused subscription is not canceled" do
    @billable.subscriptions.create!(
      processor: :paddle,
      processor_id: "3576390",
      name: "default",
      processor_plan: "some-plan",
      status: "paused"
    )
    assert_not @billable.subscription.canceled?
  end

  test "paddle resume on paused state" do
    travel_to(VCR.current_cassette.originally_recorded_at || Time.current) do
      @billable.subscriptions.create!(
        processor: :paddle,
        processor_id: "3576390",
        name: "default",
        processor_plan: "some-plan",
        status: "trialing",
        trial_ends_at: (Date.today + 3).to_datetime
      )
      subscription = @billable.subscription
      next_payment_date = Time.zone.parse(subscription.processor_subscription.next_payment[:date])

      subscription.pause
      assert_equal Time.zone.parse(subscription.paddle_paused_from), next_payment_date

      subscription.resume
      assert_nil subscription.paddle_paused_from
      assert_equal "active", subscription.status
    end
  end

  test "paddle can swap plans" do
    @billable.subscriptions.create!(
      processor: :paddle,
      processor_id: "3576390",
      name: "default",
      processor_plan: "594469",
      status: "active"
    )
    @billable.subscription.swap("594470")

    assert_equal 594470, @billable.subscription.processor_subscription.plan_id
    assert_equal "active", @billable.subscription.status
  end
end
