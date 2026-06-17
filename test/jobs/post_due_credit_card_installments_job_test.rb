require "test_helper"

class PostDueCreditCardInstallmentsJobTest < ActiveJob::TestCase
  test "posts due installments for active plans only" do
    plan = credit_card_installment_plans(:iphone)
    plan.update!(installments_count: 3, paid_installments: 0, first_payment_on: 1.month.ago.to_date)
    plan.installment_transactions.each { |t| t.entry.destroy! }

    PostDueCreditCardInstallmentsJob.perform_now

    assert plan.reload.installment_transactions.count >= 1
  end

  test "skips cancelled plans" do
    plan = credit_card_installment_plans(:iphone)
    plan.update!(installments_count: 3, paid_installments: 0,
                 first_payment_on: 1.month.ago.to_date, status: "cancelled")
    plan.installment_transactions.each { |t| t.entry.destroy! }

    PostDueCreditCardInstallmentsJob.perform_now

    assert_equal 0, plan.reload.installment_transactions.count
  end
end
