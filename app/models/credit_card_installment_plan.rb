class CreditCardInstallmentPlan < ApplicationRecord
  include Monetizable

  belongs_to :family
  belongs_to :account

  has_many :charge_transactions,
           class_name: "Transaction",
           foreign_key: :credit_card_installment_plan_id,
           inverse_of: :credit_card_installment_plan

  monetize :total_amount

  enum :status, { active: "active", completed: "completed", cancelled: "cancelled" }

  validates :name, :currency, :first_payment_on, :purchased_on, :status, presence: true
  validates :total_amount, numericality: { greater_than_or_equal_to: 0 }
  validates :installments_count, numericality: { only_integer: true, greater_than: 0 }
  validates :paid_installments, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :account_is_credit_card
  validate :paid_installments_not_greater_than_total
  validate :account_belongs_to_family

  scope :ordered, -> { order(status: :asc, first_payment_on: :asc, created_at: :desc) }

  before_validation :assign_family_and_currency
  before_destroy :destroy_installment_entries

  def monthly_amount
    return 0.to_d if installments_count.to_i.zero?

    total_amount / installments_count
  end

  def monthly_amount_money
    Money.new(monthly_amount, currency)
  end

  def paid_amount
    monthly_amount * paid_installments
  end

  def remaining_amount
    [ total_amount - paid_amount, 0 ].max
  end

  def remaining_installments
    [ installments_count - paid_installments, 0 ].max
  end

  def progress_percent
    return 0 if installments_count.zero?

    ((paid_installments.to_f / installments_count) * 100).round
  end

  def payment_dates_between(start_date, end_date)
    return [] unless active?

    (paid_installments...installments_count).filter_map do |index|
      date = payment_on_for(index + 1)
      date if date >= start_date && date <= end_date
    end
  end

  def payment_due_in_period?(period)
    payment_dates_between(period.start_date, period.end_date).any?
  end

  def mark_completed_if_paid!
    update!(status: "completed") if remaining_installments.zero? && active?
  end

  def payment_on_for(sequence)
    first_due = first_payment_on + 1
    (first_due >> (sequence - 1)) - 1
  end

  # Posts the outstanding (still-unpaid) balance of this plan as a single credit
  # card charge linked to the plan, so the purchase shows in the activity feed and
  # the card's debt reflects what is actually still owed. For a brand-new purchase
  # nothing is paid yet, so this is the full amount; for a partly-paid purchase it
  # is total minus what has already been paid. Returns nil when nothing is owed.
  def post_outstanding_charge!(date:, name:, category_id: nil)
    return if remaining_amount <= 0

    entry = account.entries.create!(
      name: name,
      date: date,
      amount: remaining_amount, # positive = outflow on a liability (Sure convention)
      currency: currency,
      entryable: Transaction.new(
        category_id: category_id,
        credit_card_installment_plan_id: id
      )
    )
    entry.lock_saved_attributes!
    entry.mark_user_modified!
    entry.sync_account_later
    entry
  end

  # Manual payoff tracking: bump the count of installments the user has paid.
  def mark_next_installment_paid!
    return if paid_installments >= installments_count

    update!(paid_installments: paid_installments + 1)
    mark_completed_if_paid!
  end

  def unmark_last_installment_paid!
    return if paid_installments <= 0

    was_completed = completed?
    update!(paid_installments: paid_installments - 1)
    update!(status: "active") if was_completed
  end

  private
    def assign_family_and_currency
      self.family ||= account&.family
      self.currency ||= account&.currency
      self.purchased_on ||= first_payment_on
    end

    def account_is_credit_card
      return if account&.credit_card?

      errors.add(:account, "must be a credit card")
    end

    def paid_installments_not_greater_than_total
      return if paid_installments.blank? || installments_count.blank?
      return if paid_installments <= installments_count

      errors.add(:paid_installments, "cannot be greater than installments count")
    end

    def account_belongs_to_family
      return if account.blank? || family.blank? || account.family_id == family_id

      errors.add(:account, "must belong to the same family")
    end

    def destroy_installment_entries
      Entry.where(
        entryable_type: "Transaction",
        entryable_id: charge_transactions.select(:id)
      ).destroy_all
    end
end
