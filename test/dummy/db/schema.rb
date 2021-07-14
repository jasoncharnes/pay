# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2021_07_14_175351) do

  create_table "accounts", force: :cascade do |t|
    t.string "email"
    t.string "merchant_processor"
    if t.respond_to? :jsonb
      t.jsonb "pay_data"
    else
      t.json "pay_data"
    end
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "pay_charges", force: :cascade do |t|
    t.string "owner_type"
    t.integer "owner_id"
    t.string "processor", null: false
    t.string "processor_id", null: false
    t.integer "amount", null: false
    t.integer "amount_refunded"
    t.string "card_type"
    t.string "card_last4"
    t.string "card_exp_month"
    t.string "card_exp_year"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.text "data"
    t.string "currency"
    t.integer "application_fee_amount"
    t.integer "pay_subscription_id"
    t.index ["processor", "processor_id"], name: "index_pay_charges_on_processor_and_processor_id", unique: true
  end

  create_table "pay_subscriptions", force: :cascade do |t|
    t.string "owner_type"
    t.integer "owner_id"
    t.string "name", null: false
    t.string "processor", null: false
    t.string "processor_id", null: false
    t.string "processor_plan", null: false
    t.integer "quantity", default: 1, null: false
    t.datetime "trial_ends_at"
    t.datetime "ends_at"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string "status"
    t.text "data"
    t.decimal "application_fee_percent", precision: 8, scale: 2
    t.index ["processor", "processor_id"], name: "index_pay_subscriptions_on_processor_and_processor_id", unique: true
  end

  create_table "teams", force: :cascade do |t|
    t.string "email"
    t.string "name"
    t.string "owner_type"
    t.integer "owner_id"
    t.string "processor"
    t.string "processor_id"
    t.datetime "trial_ends_at"
    t.string "card_type"
    t.string "card_last4"
    t.string "card_exp_month"
    t.string "card_exp_year"
    t.text "extra_billing_info"
    t.json "pay_data"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["owner_type", "owner_id"], name: "index_teams_on_owner_type_and_owner_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email"
    t.string "first_name"
    t.string "last_name"
    t.string "processor"
    t.string "processor_id"
    t.datetime "trial_ends_at"
    t.string "card_type"
    t.string "card_last4"
    t.string "card_exp_month"
    t.string "card_exp_year"
    t.text "extra_billing_info"
    t.json "pay_data"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

end
