require "test_helper"

class RecurringTransactionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @account = accounts(:depository)
  end

  test "creates a manual recurring payment" do
    assert_difference "RecurringTransaction.count", 1 do
      post recurring_transactions_path, params: {
        recurring_transaction: {
          account_id: @account.id,
          name: "Gym",
          amount: 45,
          currency: "USD",
          expected_day_of_month: 12
        }
      }
    end

    recurring = RecurringTransaction.order(:created_at).last
    assert recurring.manual?
    assert_equal @account, recurring.account
    assert_equal "Gym", recurring.name
    assert_equal 45, recurring.amount
    assert_equal 12, recurring.expected_day_of_month
    assert_redirected_to recurring_transactions_path
  end
end
