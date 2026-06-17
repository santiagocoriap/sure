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
end
