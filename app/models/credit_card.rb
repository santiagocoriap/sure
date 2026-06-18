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
    override = billing_cycle_due_in(period)
    return override.due_on if override

    cycle_date_for(due_day, period)
  end

  def closing_on_for(period)
    override = billing_cycle_closing_in_period(period)
    return override.closing_on if override

    cycle_date_for(closing_day, period)
  end

  # The actual closing date for the month containing `date` (a per-month override
  # if one exists, otherwise the default closing day).
  def closing_on_in_month(date)
    cycle = billing_cycle_closing_in_month(date)
    return cycle.closing_on if cycle
    return nil if closing_day.blank?

    day_in_month(closing_day, date)
  end

  # The actual payment due date for the month containing `date`.
  def due_on_in_month(date)
    cycle = billing_cycle_due_in(date)
    return cycle.due_on if cycle
    return nil if due_day.blank?

    day_in_month(due_day, date)
  end

  # First installment payment date for a purchase made on `purchase_date`.
  # Posts the day before the due date, in the cycle AFTER the statement the
  # purchase closes in. Per-month billing-cycle overrides take precedence over
  # the default closing/due days. Falls back to the first of next month when the
  # card has no cycle days configured.
  def installment_first_payment_on(purchase_date)
    return purchase_date.next_month.beginning_of_month if closing_day.blank? || due_day.blank?

    month = purchase_date.beginning_of_month
    loop do
      cycle = billing_cycle_closing_in_month(month)
      close = cycle&.closing_on || day_in_month(closing_day, month)

      if close >= purchase_date
        due = cycle&.due_on || next_due_after(close)
        return due - 1
      end

      month = month.next_month
    end
  end

  private
    def billing_cycles
      @billing_cycles ||= (account&.credit_card_billing_cycles&.to_a || [])
    end

    def billing_cycle_closing_in_month(date)
      billing_cycles.find { |c| c.closing_on.beginning_of_month == date.beginning_of_month }
    end

    def billing_cycle_due_in(period)
      period_start = period.respond_to?(:start_date) ? period.start_date : (period.respond_to?(:first) ? period.first : period.beginning_of_month)
      period_end = period.respond_to?(:end_date) ? period.end_date : (period.respond_to?(:last) ? period.last : period.end_of_month)
      billing_cycles.find { |c| c.due_on >= period_start && c.due_on <= period_end }
    end

    def billing_cycle_closing_in_period(period)
      period_start = period.respond_to?(:start_date) ? period.start_date : period.first
      period_end = period.respond_to?(:end_date) ? period.end_date : period.last
      billing_cycles.find { |c| c.closing_on >= period_start && c.closing_on <= period_end }
    end

    # The first payment due date strictly after the given closing date. When the
    # due day falls later in the closing month (e.g. closes the 3rd, due the 13th)
    # the payment is due that same month; otherwise it rolls to the next month.
    def next_due_after(close)
      candidate = day_in_month(due_day, close)
      candidate = day_in_month(due_day, close.next_month) if candidate <= close
      candidate
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
