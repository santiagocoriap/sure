require "test_helper"

class CreditCardTest < ActiveSupport::TestCase
  setup do
    @card = CreditCard.new(closing_day: 27, due_day: 10)
  end

  test "first payment is day before due in the cycle after the close (bought before close)" do
    assert_equal Date.new(2026, 3, 9), @card.installment_first_payment_on(Date.new(2026, 2, 26))
  end

  test "purchase after close rolls to the next statement cycle" do
    assert_equal Date.new(2026, 4, 9), @card.installment_first_payment_on(Date.new(2026, 2, 28))
  end

  test "purchase exactly on closing day still closes that cycle" do
    assert_equal Date.new(2026, 3, 9), @card.installment_first_payment_on(Date.new(2026, 2, 27))
  end

  test "falls back to first of next month when cycle days are missing" do
    card = CreditCard.new(closing_day: nil, due_day: nil)
    assert_equal Date.new(2026, 3, 1), card.installment_first_payment_on(Date.new(2026, 2, 28))
  end

  test "due date can fall in the same month as the close (closes the 3rd, due the 13th)" do
    card = CreditCard.new(closing_day: 3, due_day: 13)

    # Bought before the 3rd -> closes the 3rd, due the 13th same month -> first payment the 12th
    assert_equal Date.new(2026, 7, 12), card.installment_first_payment_on(Date.new(2026, 7, 1))

    # Bought after the 3rd -> rolls to next month: closes Aug 3, due Aug 13 -> first payment Aug 12
    assert_equal Date.new(2026, 8, 12), card.installment_first_payment_on(Date.new(2026, 7, 5))
  end

  test "a per-month billing cycle override drives the installment schedule for that cycle" do
    account = accounts(:credit_card)
    account.credit_card.update!(closing_day: 27, due_day: 10)
    # February closes early (the 20th) and is due Mar 5 this month only
    account.credit_card_billing_cycles.create!(closing_on: Date.new(2026, 2, 20), due_on: Date.new(2026, 3, 5))
    card = Account.find(account.id).credit_card

    # Bought before the overridden close -> first payment is the day before the overridden due date
    assert_equal Date.new(2026, 3, 4), card.installment_first_payment_on(Date.new(2026, 2, 18))

    # Bought after the overridden close -> rolls to the next (default) cycle: close Mar 27, due Apr 10
    assert_equal Date.new(2026, 4, 9), card.installment_first_payment_on(Date.new(2026, 2, 22))
  end
end
