require "test_helper"

class CreditCardBillingCyclesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    @account = accounts(:credit_card)
  end

  test "creates a billing cycle override" do
    assert_difference "CreditCardBillingCycle.count", 1 do
      post credit_card_billing_cycles_path, params: {
        credit_card_billing_cycle: {
          account_id: @account.id,
          closing_on: Date.new(2026, 2, 20),
          due_on: Date.new(2026, 3, 5)
        }
      }
    end

    assert_redirected_to account_path(@account, tab: "installments")
  end

  test "destroys a billing cycle override" do
    cycle = @account.credit_card_billing_cycles.create!(closing_on: Date.new(2026, 2, 20), due_on: Date.new(2026, 3, 5))

    assert_difference "CreditCardBillingCycle.count", -1 do
      delete credit_card_billing_cycle_path(cycle)
    end

    assert_redirected_to account_path(@account, tab: "installments")
  end
end
