require "test_helper"

class CreditCardBillingCycleTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:credit_card)
  end

  test "requires a credit card account" do
    cycle = CreditCardBillingCycle.new(
      account: accounts(:depository),
      closing_on: Date.new(2026, 2, 20),
      due_on: Date.new(2026, 3, 5)
    )

    assert_not cycle.valid?
    assert_includes cycle.errors[:account], "must be a credit card"
  end

  test "due date must be after the closing date" do
    cycle = @account.credit_card_billing_cycles.build(
      closing_on: Date.new(2026, 2, 20),
      due_on: Date.new(2026, 2, 10)
    )

    assert_not cycle.valid?
  end

  test "allows only one override per closing month" do
    @account.credit_card_billing_cycles.create!(closing_on: Date.new(2026, 2, 20), due_on: Date.new(2026, 3, 5))

    dup = @account.credit_card_billing_cycles.build(closing_on: Date.new(2026, 2, 25), due_on: Date.new(2026, 3, 8))

    assert_not dup.valid?
    assert_includes dup.errors[:closing_on], "already has an override for that month"
  end
end
