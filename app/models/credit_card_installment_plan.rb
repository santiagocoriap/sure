class CreditCardInstallmentPlan < ApplicationRecord
  include Monetizable

  belongs_to :family
  belongs_to :account
  # Bank/asset account that installment payments are drawn from (optional).
  belongs_to :payment_account, class_name: "Account", optional: true

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
  before_destroy :destroy_linked_transactions

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

  # The due date for installment `sequence`. Uses the card's actual due date for
  # that installment's month — a per-month billing-cycle override when one exists,
  # otherwise the card's default due day — so every plan lines up with the card's
  # real due dates. Falls back to the plan's own anchor when the card has no due
  # day configured.
  def payment_on_for(sequence)
    nominal_due = (first_payment_on + 1) >> (sequence - 1)
    account&.credit_card&.due_on_in_month(nominal_due) || (nominal_due - 1)
  end

  # Posts one credit card charge per still-unpaid installment — each for the
  # monthly amount, dated on its scheduled payment date — so the spend is spread
  # across months (correct for budgeting) and shows in the activity feed. Already
  # paid installments are skipped; idempotent via the unique (plan, number) index.
  def post_remaining_installments!
    posted = posted_installment_numbers
    ((paid_installments + 1)..installments_count).each do |sequence|
      next if posted.include?(sequence)

      create_installment_entry!(sequence, payment_on_for(sequence))
    end
  end

  # Marks the next installment paid: records the payment (a transfer from the
  # chosen bank account to the card, so net worth stays correct) and advances the
  # paid counter.
  def mark_next_installment_paid!
    return if paid_installments >= installments_count

    ActiveRecord::Base.transaction do
      create_installment_payment!
      update!(paid_installments: paid_installments + 1)
      mark_completed_if_paid!
    end
  end

  # Number of still-unpaid installments whose scheduled date has arrived by
  # `through` (defaults to the end of the current month).
  def installments_due_through(through = Date.current.end_of_month)
    return 0 unless active?

    ((paid_installments + 1)..installments_count).count { |sequence| payment_on_for(sequence) <= through }
  end

  def amount_due_through(through = Date.current.end_of_month)
    installments_due_through(through) * monthly_amount
  end

  # Pays every installment due by `through` in one go (the usual "pay the card"
  # action), recording a payment for each. Returns how many were paid.
  def pay_due_installments!(through: Date.current.end_of_month)
    count = installments_due_through(through)
    count.times { mark_next_installment_paid! }
    count
  end

  # Reverses the most recent installment payment and steps the counter back.
  def unmark_last_installment_paid!
    return if paid_installments <= 0

    ActiveRecord::Base.transaction do
      remove_payment!(installment_payments.order(:created_at).last)
      was_completed = completed?
      update!(paid_installments: paid_installments - 1)
      update!(status: "active") if was_completed
    end
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

    # Linked transactions split into the monthly purchase charges (which carry an
    # installment_number) and the payments toward them (which do not).
    def installment_charges
      charge_transactions.where.not(installment_number: nil)
    end

    def installment_payments
      charge_transactions.where(installment_number: nil)
    end

    # Records one installment payment. With a payment account set this is a proper
    # transfer (bank balance down, card debt down — net-worth neutral); without
    # one it falls back to a one-sided cc_payment that just lowers the card debt.
    def create_installment_payment!
      return if monthly_amount <= 0

      if payment_account.present?
        transfer = Transfer::Creator.new(
          family: family,
          source_account_id: payment_account_id,
          destination_account_id: account_id,
          date: Date.current,
          amount: monthly_amount
        ).create
        # Tag the card side of the transfer so we can find/undo it later.
        transfer.inflow_transaction.update!(credit_card_installment_plan_id: id)
      else
        entry = account.entries.create!(
          name: "Payment - #{name}",
          date: Date.current,
          amount: -monthly_amount, # negative on a liability = debt decreases
          currency: currency,
          entryable: Transaction.new(kind: "cc_payment", credit_card_installment_plan_id: id)
        )
        entry.lock_saved_attributes!
        entry.mark_user_modified!
        entry.sync_account_later
      end
    end

    def remove_payment!(payment)
      return if payment.nil?

      transfer = payment.transfer_as_inflow
      if transfer
        bank_entry = transfer.outflow_transaction.entry
        card_entry = transfer.inflow_transaction.entry
        transfer.destroy!
        bank_entry.destroy!
        card_entry.destroy!
      else
        payment.entry.destroy!
      end
    end

    def posted_installment_numbers
      Transaction.where(credit_card_installment_plan_id: id).where.not(installment_number: nil).pluck(:installment_number)
    end

    def create_installment_entry!(sequence, date)
      entry = account.entries.create!(
        name: "#{name} (#{sequence}/#{installments_count})",
        date: date,
        amount: monthly_amount, # positive = outflow on a liability (Sure convention)
        currency: currency,
        entryable: Transaction.new(
          category_id: category_id,
          credit_card_installment_plan_id: id,
          installment_number: sequence
        )
      )
      entry.lock_saved_attributes!
      entry.mark_user_modified!
      entry.sync_account_later
      entry
    end

    def destroy_linked_transactions
      installment_payments.to_a.each { |payment| remove_payment!(payment) }
      Entry.where(
        entryable_type: "Transaction",
        entryable_id: installment_charges.select(:id)
      ).destroy_all
    end
end
