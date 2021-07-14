require "test_helper"

class Pay::Charge::Test < ActiveSupport::TestCase
  setup do
    @charge = Pay.charge_model.new
  end

  test "validates charge uniqueness by processor and processor ID" do
    user = User.create! email: "test@example.com", id: 1001
    Pay.charge_model.create!(owner: user, amount: 1, processor: "stripe", processor_id: "1", card_type: "VISA")
    assert_raises ActiveRecord::RecordInvalid do
      Pay.charge_model.create!(owner: user, amount: 1, processor: "stripe", processor_id: "1", card_type: "VISA")
    end
  end

  test "belongs to a polymorphic owner" do
    @charge.owner = User.new
    assert_equal User, @charge.owner.class
    @charge.owner = Team.new
    assert_equal Team, @charge.owner.class
  end

  test "#charged_to" do
    @charge.card_type = "VISA"
    @charge.card_last4 = 1234
    assert_equal "VISA (**** **** **** 1234)", @charge.charged_to
  end

  test "finds polymorphic charge" do
    user_chargeable = User.create! email: "test@example.com", id: 1001
    team_chargeable = Team.create! id: 1001, owner: user_chargeable

    charge = Pay.charge_model.create!(
      owner: team_chargeable, amount: 1, processor: "stripe", processor_id: "1", card_type: "VISA"
    )

    assert_equal [], user_chargeable.charges
    assert_equal [charge], team_chargeable.charges
  end

  test "stores data about the charge" do
    data = {"foo" => "bar"}
    @charge.update(data: data)
    assert_equal data, @charge.data
  end
end
