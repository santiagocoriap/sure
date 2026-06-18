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

    assert_equal 1, dates.size
    assert (period_start..period_end).cover?(dates.first), "the payment date should fall inside the period"
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

  test "payment_on_for falls back to the plan anchor when the card has no due day" do
    plan = CreditCardInstallmentPlan.new(first_payment_on: Date.new(2026, 3, 9))
    assert_equal Date.new(2026, 3, 9), plan.payment_on_for(1)
    assert_equal Date.new(2026, 4, 9), plan.payment_on_for(2)
    assert_equal Date.new(2026, 5, 9), plan.payment_on_for(3)
  end

  test "payment_on_for uses the card's due date and per-month override for each installment" do
    account = accounts(:credit_card)
    account.credit_card.update!(closing_day: 27, due_day: 10)
    # July is overridden to be due the 13th; other months use the default due day (10th)
    account.credit_card_billing_cycles.create!(closing_on: Date.new(2026, 7, 2), due_on: Date.new(2026, 7, 13))

    plan = account.credit_card_installment_plans.create!(
      name: "TV", total_amount: 600, installments_count: 6, paid_installments: 0,
      first_payment_on: Date.new(2026, 7, 1), purchased_on: Date.new(2026, 6, 20)
    )
    plan = CreditCardInstallmentPlan.find(plan.id)

    assert_equal Date.new(2026, 7, 13), plan.payment_on_for(1), "July installment should use the override due date"
    assert_equal Date.new(2026, 8, 10), plan.payment_on_for(2), "August should use the default due day"
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

  test "marking paid with a payment account records a transfer from bank to card" do
    plan = credit_card_installment_plans(:iphone)
    plan.update!(installments_count: 3, paid_installments: 0, payment_account: accounts(:depository))

    assert_difference -> { Transfer.count }, 1 do
      plan.mark_next_installment_paid!
    end

    payment = plan.reload.charge_transactions.where(installment_number: nil).sole
    transfer = payment.transfer_as_inflow
    assert_not_nil transfer
    assert_equal accounts(:depository), transfer.outflow_transaction.entry.account
    assert_equal plan.account, transfer.inflow_transaction.entry.account
    assert_equal plan.monthly_amount, transfer.outflow_transaction.entry.amount
    assert_equal 1, plan.paid_installments
  end

  test "unmarking paid reverses the payment transfer" do
    plan = credit_card_installment_plans(:iphone)
    plan.update!(installments_count: 3, paid_installments: 0, payment_account: accounts(:depository))
    plan.mark_next_installment_paid!

    assert_difference -> { Transfer.count }, -1 do
      plan.unmark_last_installment_paid!
    end
    assert_equal 0, plan.reload.paid_installments
    assert_equal 0, plan.charge_transactions.where(installment_number: nil).count
  end

  test "marking paid without a payment account lowers the card debt one-sidedly" do
    plan = credit_card_installment_plans(:iphone)
    plan.update!(installments_count: 3, paid_installments: 0, payment_account: nil)

    assert_difference -> { plan.account.entries.count }, 1 do
      plan.mark_next_installment_paid!
    end
    payment = plan.reload.charge_transactions.where(installment_number: nil).sole
    assert_equal "cc_payment", payment.kind
    assert_equal(-plan.monthly_amount, payment.entry.amount)
  end

  test "pay_due_installments! pays everything due by the cutoff in one call" do
    plan = credit_card_installment_plans(:iphone)
    plan.update!(
      installments_count: 6,
      paid_installments: 0,
      total_amount: 1200,
      first_payment_on: 2.months.ago.to_date.beginning_of_month,
      payment_account: accounts(:depository)
    )
    plan.charge_transactions.each { |t| t.entry.destroy! }

    due = plan.installments_due_through
    assert_operator due, :>=, 1, "fixture should have at least one installment due"

    assert_difference -> { Transfer.count }, due do
      assert_equal due, plan.pay_due_installments!
    end

    assert_equal due, plan.reload.paid_installments
    assert_equal 0, plan.installments_due_through, "nothing should remain due after paying"
  end
end
