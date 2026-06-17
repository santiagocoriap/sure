require "test_helper"

class CreditCardInstallmentPlansControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @account = accounts(:credit_card)
  end

  test "creates an installment plan" do
    assert_difference "CreditCardInstallmentPlan.count", 1 do
      post credit_card_installment_plans_path, params: {
        credit_card_installment_plan: {
          account_id: @account.id,
          name: "Notebook",
          total_amount: 1800,
          installments_count: 18,
          paid_installments: 0,
          first_payment_on: Date.current
        }
      }
    end

    plan = CreditCardInstallmentPlan.order(:created_at).last
    assert_equal @account, plan.account
    assert_equal @account.family, plan.family
    assert_equal "USD", plan.currency
    assert_redirected_to account_path(@account, tab: "installments")
  end

  test "updates paid installments" do
    plan = credit_card_installment_plans(:iphone)

    patch credit_card_installment_plan_path(plan), params: {
      credit_card_installment_plan: { paid_installments: 4 }
    }

    assert_equal 4, plan.reload.paid_installments
    assert_redirected_to account_path(@account, tab: "installments")
  end

  test "post_next posts the next installment as an activity entry" do
    plan = credit_card_installment_plans(:iphone)
    plan.update!(installments_count: 3, paid_installments: 0, first_payment_on: Date.current >> 6)
    plan.installment_transactions.each { |t| t.entry.destroy! }

    assert_difference "plan.account.entries.count", 1 do
      post post_next_credit_card_installment_plan_path(plan)
    end
    assert_redirected_to account_path(plan.account, tab: "installments")
    assert_equal 1, plan.reload.paid_installments
  end

  test "unpost_last removes the most recent installment entry" do
    plan = credit_card_installment_plans(:iphone)
    plan.update!(installments_count: 3, paid_installments: 0, first_payment_on: Date.current >> 6)
    plan.installment_transactions.each { |t| t.entry.destroy! }
    plan.post_next_installment!

    assert_difference "plan.account.entries.count", -1 do
      delete unpost_last_credit_card_installment_plan_path(plan)
    end
  end

  test "installments tab renders with the schedule and override controls" do
    get account_path(@account, tab: "installments")
    assert_response :success
  end
end
