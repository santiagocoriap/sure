class CreditCard < ApplicationRecord
  include Accountable

  DEFAULT_SUBTYPE = "credit_card"

  SUBTYPES = {
    "credit_card" => { short: "Credit Card", long: "Credit Card" }
  }.freeze

  class << self
    def color
      "#F13636"
    end

    def icon
      "credit-card"
    end

    def classification
      "liability"
    end
  end

  def available_credit_money
    available_credit ? Money.new(available_credit, account.currency) : nil
  end

  def minimum_payment_money
    minimum_payment ? Money.new(minimum_payment, account.currency) : nil
  end

  def annual_fee_money
    annual_fee ? Money.new(annual_fee, account.currency) : nil
  end

  def credit_limit_money
    credit_limit ? Money.new(credit_limit, account.currency) : nil
  end

  def available_credit_amount
    return available_credit if available_credit.present?
    return nil if credit_limit.blank? || account.blank?

    [ credit_limit - account.balance, 0 ].max
  end

  def utilization_percent
    limit = credit_limit.presence || (available_credit.present? && account.present? ? account.balance + available_credit : nil)
    return nil if limit.blank? || limit <= 0 || account.blank?

    ((account.balance / limit) * 100).clamp(0, 100)
  end

  def payment_due_on_for(period)
    cycle_date_for(due_day, period)
  end

  def closing_on_for(period)
    cycle_date_for(closing_day, period)
  end

  # First installment payment date for a purchase made on `purchase_date`.
  # Posts the day before the due date, in the cycle AFTER the statement the
  # purchase closes in. Falls back to the first of next month when the card
  # has no cycle days configured.
  def installment_first_payment_on(purchase_date)
    return purchase_date.next_month.beginning_of_month if closing_day.blank? || due_day.blank?

    next_close = next_day_occurrence(closing_day, on_or_after: purchase_date)
    due_date   = day_in_month(due_day, next_close.next_month)
    due_date - 1
  end

  private
    def next_day_occurrence(day, on_or_after:)
      candidate = day_in_month(day, on_or_after)
      candidate >= on_or_after ? candidate : day_in_month(day, on_or_after.next_month)
    end

    def day_in_month(day, ref_date)
      Date.new(ref_date.year, ref_date.month, [ day, ref_date.end_of_month.day ].min)
    end

    def cycle_date_for(day, period)
      return nil if day.blank?

      period_start = period.respond_to?(:start_date) ? period.start_date : period.first
      period_end = period.respond_to?(:end_date) ? period.end_date : period.last
      date = Date.new(period_start.year, period_start.month, [ day, period_start.end_of_month.day ].min)
      date = date.next_month if date < period_start
      return nil if date > period_end

      date
    end
end
