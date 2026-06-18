class CreditCardBillingCycle < ApplicationRecord
  belongs_to :account

  validates :closing_on, :due_on, presence: true
  validate :account_is_credit_card
  validate :due_after_closing
  validate :one_override_per_closing_month

  scope :ordered, -> { order(closing_on: :desc) }

  # The override that governs the statement closing in the given month, if any.
  scope :closing_in_month, ->(date) {
    where(closing_on: date.beginning_of_month..date.end_of_month)
  }

  # The override whose payment is due in the given month, if any.
  scope :due_in_month, ->(date) {
    where(due_on: date.beginning_of_month..date.end_of_month)
  }

  private
    def account_is_credit_card
      return if account&.credit_card?

      errors.add(:account, "must be a credit card")
    end

    def due_after_closing
      return if closing_on.blank? || due_on.blank?
      return if due_on > closing_on

      errors.add(:due_on, "must be after the closing date")
    end

    def one_override_per_closing_month
      return if closing_on.blank? || account_id.blank?

      clashing = CreditCardBillingCycle
        .where(account_id: account_id)
        .closing_in_month(closing_on)
        .where.not(id: id)

      errors.add(:closing_on, "already has an override for that month") if clashing.exists?
    end
end
