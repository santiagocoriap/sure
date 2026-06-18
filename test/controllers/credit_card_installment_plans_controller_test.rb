require "test_helper"

class CreditCardInstallmentPlansControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @account = accounts(:credit_card)
  end

  test "creates an installment plan and posts the remaining installments as monthly charges" do
    # 1800 / 18 = 100 monthly; 6 already paid -> 12 remaining charges of 100
    assert_difference "CreditCardInstallmentPlan.count", 1 do
      assert_difference "@account.entries.count", 12 do
        post credit_card_installment_plans_path, params: {
          credit_card_installment_plan: {
            account_id: @account.id,
            name: "Notebook",
            total_amount: 1800,
            installments_count: 18,
            paid_installments: 6,
            first_payment_on: 6.months.ago.to_date
          }
        }
      end
    end

    plan = CreditCardInstallmentPlan.order(:created_at).last
    assert_equal @account, plan.account
    assert_equal @account.family, plan.family
    assert_equal "USD", plan.currency
    assert_equal (7..18).to_a, plan.charge_transactions.map(&:installment_number).sort
    assert plan.charge_transactions.all? { |t| t.entry.amount == 100 }
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

  test "post_next marks the next installment paid" do
    plan = credit_card_installment_plans(:iphone)
    plan.update!(installments_count: 3, paid_installments: 1)

    post post_next_credit_card_installment_plan_path(plan)

    assert_equal 2, plan.reload.paid_installments
    assert_redirected_to account_path(plan.account, tab: "installments")
  end

  test "unpost_last unmarks the last paid installment" do
    plan = credit_card_installment_plans(:iphone)
    plan.update!(installments_count: 3, paid_installments: 2)

    delete unpost_last_credit_card_installment_plan_path(plan)

    assert_equal 1, plan.reload.paid_installments
    assert_redirected_to account_path(plan.account, tab: "installments")
  end

  test "installments tab renders with the schedule and override controls" do
    get account_path(@account, tab: "installments")
    assert_response :success
  end
end
