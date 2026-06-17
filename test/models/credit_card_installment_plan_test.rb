require "test_helper"

class CreditCardInstallmentPlanTest < ActiveSupport::TestCase
  setup do
    @plan = credit_card_installment_plans(:iphone)
  end

  test "calculates monthly and remaining amounts" do
    assert_equal 100, @plan.monthly_amount
    assert_equal 900, @plan.remaining_amount
    assert_equal 9, @plan.remaining_installments
    assert_equal 25, @plan.progress_percent
  end

  test "returns payment dates inside a period" do
    period_start = Date.current.beginning_of_month
    period_end = Date.current.end_of_month

    dates = @plan.payment_dates_between(period_start, period_end)

    assert_equal [ period_start ], dates
  end

  test "payment_dates_between aligns with payment_on_for (day before due, not raw first_payment_on)" do
    plan = CreditCardInstallmentPlan.new(
      first_payment_on: Date.new(2026, 1, 9),
      installments_count: 3,
      paid_installments: 0,
      status: "active"
    )

    dates = plan.payment_dates_between(Date.new(2026, 1, 1), Date.new(2026, 12, 31))

    assert_equal [ plan.payment_on_for(1), plan.payment_on_for(2), plan.payment_on_for(3) ], dates
    assert_equal [ Date.new(2026, 1, 9), Date.new(2026, 2, 9), Date.new(2026, 3, 9) ], dates
  end

  test "requires a credit card account" do
    plan = CreditCardInstallmentPlan.new(
      account: accounts(:depository),
      name: "Laptop",
      total_amount: 1000,
      installments_count: 10,
      paid_installments: 0,
      first_payment_on: Date.current
    )

    assert_not plan.valid?
    assert_includes plan.errors[:account], "must be a credit card"
  end

  test "payment_on_for advances one month per installment, day before due" do
    plan = CreditCardInstallmentPlan.new(first_payment_on: Date.new(2026, 3, 9))
    assert_equal Date.new(2026, 3, 9), plan.payment_on_for(1)
    assert_equal Date.new(2026, 4, 9), plan.payment_on_for(2)
    assert_equal Date.new(2026, 5, 9), plan.payment_on_for(3)
  end

  test "post_due_installments! posts only installments due on or before the cutoff and is idempotent" do
    plan = credit_card_installment_plans(:iphone)
    plan.update!(installments_count: 3, paid_installments: 0, first_payment_on: Date.new(2026, 1, 9))
    plan.installment_transactions.each { |t| t.entry.destroy! }

    cutoff = Date.new(2026, 2, 28)
    assert_difference "plan.account.entries.count", 2 do
      plan.post_due_installments!(through: cutoff)
    end
    assert_no_difference "plan.account.entries.count" do
      plan.post_due_installments!(through: cutoff)
    end

    numbers = plan.reload.installment_transactions.pluck(:installment_number).sort
    assert_equal [ 1, 2 ], numbers
    assert_equal 2, plan.paid_installments

    entry = plan.installment_transactions.order(:installment_number).first.entry
    assert_equal plan.monthly_amount, entry.amount
    assert_equal "#{plan.name} (1/3)", entry.name
    assert_equal Date.new(2026, 1, 9), entry.date
  end

  test "post_next_installment! posts the next installment dated today" do
    plan = credit_card_installment_plans(:iphone)
    plan.update!(installments_count: 3, paid_installments: 0, first_payment_on: Date.current >> 6)
    plan.installment_transactions.each { |t| t.entry.destroy! }

    assert_difference "plan.account.entries.count", 1 do
      plan.post_next_installment!
    end
    entry = plan.reload.installment_transactions.sole.entry
    assert_equal 1, entry.entryable.installment_number
    assert_equal Date.current, entry.date
    assert_equal 1, plan.paid_installments
  end

  test "unpost_last_installment! removes the most recent posted installment" do
    plan = credit_card_installment_plans(:iphone)
    plan.update!(installments_count: 3, paid_installments: 0, first_payment_on: Date.current >> 6)
    plan.installment_transactions.each { |t| t.entry.destroy! }
    plan.post_next_installment!
    plan.post_next_installment!

    assert_difference "plan.account.entries.count", -1 do
      plan.unpost_last_installment!
    end
    assert_equal 1, plan.reload.paid_installments
  end
end
