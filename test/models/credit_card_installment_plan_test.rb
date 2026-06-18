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

  test "post_remaining_installments! posts one monthly charge per unpaid installment, on schedule" do
    # iphone fixture: 1200 total, 12 installments, 3 paid -> 9 remaining of 100 each
    plan = credit_card_installment_plans(:iphone)
    plan.charge_transactions.each { |t| t.entry.destroy! }

    assert_difference "plan.account.entries.count", 9 do
      plan.post_remaining_installments!
    end
    # Idempotent: a second call posts nothing new
    assert_no_difference "plan.account.entries.count" do
      plan.post_remaining_installments!
    end

    txns = plan.reload.charge_transactions.includes(:entry).sort_by(&:installment_number)
    assert_equal (4..12).to_a, txns.map(&:installment_number)
    assert txns.all? { |t| t.entry.amount == plan.monthly_amount }
    assert_equal plan.payment_on_for(4), txns.first.entry.date
    assert_equal plan.payment_on_for(12), txns.last.entry.date
  end

  test "post_remaining_installments! posts nothing when the plan is fully paid" do
    plan = credit_card_installment_plans(:iphone)
    plan.update!(installments_count: 3, paid_installments: 3, status: "completed")
    plan.charge_transactions.each { |t| t.entry.destroy! }

    assert_no_difference "plan.account.entries.count" do
      plan.post_remaining_installments!
    end
  end

  test "mark_next_installment_paid! bumps the counter and caps at the total" do
    plan = credit_card_installment_plans(:iphone)
    plan.update!(installments_count: 3, paid_installments: 2)

    plan.mark_next_installment_paid!
    assert_equal 3, plan.reload.paid_installments
    assert plan.completed?

    plan.mark_next_installment_paid! # already at max — no-op
    assert_equal 3, plan.reload.paid_installments
  end

  test "unmark_last_installment_paid! decrements and reactivates a completed plan" do
    plan = credit_card_installment_plans(:iphone)
    plan.update!(installments_count: 3, paid_installments: 3, status: "completed")

    plan.unmark_last_installment_paid!
    assert_equal 2, plan.reload.paid_installments
    assert plan.active?
  end
end
