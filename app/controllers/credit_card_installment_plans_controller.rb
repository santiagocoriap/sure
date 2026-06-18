class CreditCardInstallmentPlansController < ApplicationController
  before_action :set_account, only: %i[create pay_due]
  before_action :set_plan, only: %i[update destroy post_next unpost_last]

  def create
    @plan = @account.credit_card_installment_plans.build(plan_params)
    @plan.family = Current.family
    @plan.currency = @account.currency

    ActiveRecord::Base.transaction do
      @plan.save!
      # Track the purchase in the activity feed as one charge per remaining
      # monthly installment (spread across months so budgets stay accurate).
      @plan.post_remaining_installments!
    end

    redirect_to account_path(@account, tab: "installments"), notice: t("credit_card_installment_plans.create.success")
  rescue ActiveRecord::RecordInvalid
    redirect_to account_path(@account, tab: "installments"), alert: @plan.errors.full_messages.to_sentence
  end

  def update
    @plan.update!(plan_params)
    @plan.mark_completed_if_paid!

    redirect_to account_path(@plan.account, tab: "installments"), notice: t("credit_card_installment_plans.update.success")
  rescue ActiveRecord::RecordInvalid
    redirect_to account_path(@plan.account, tab: "installments"), alert: @plan.errors.full_messages.to_sentence
  end

  def post_next
    @plan.mark_next_installment_paid!
    redirect_to account_path(@plan.account, tab: "installments"), notice: t("credit_card_installment_plans.post_next.success")
  end

  def unpost_last
    @plan.unmark_last_installment_paid!
    redirect_to account_path(@plan.account, tab: "installments"), notice: t("credit_card_installment_plans.unpost_last.success")
  end

  def destroy
    account = @plan.account
    @plan.destroy!

    redirect_to account_path(account, tab: "installments"), notice: t("credit_card_installment_plans.destroy.success")
  end

  # Pays every installment due this month across all of the card's active plans.
  def pay_due
    paid = @account.credit_card_installment_plans.active.sum { |plan| plan.pay_due_installments! }

    redirect_to account_path(@account, tab: "installments"), notice: t("credit_card_installment_plans.pay_due.success", count: paid)
  end

  private
    def set_account
      @account = Current.user.accessible_accounts.writable_by(Current.user).find(params.require(:credit_card_installment_plan).permit(:account_id)[:account_id])
      raise ActiveRecord::RecordNotFound unless @account.credit_card?
    end

    def set_plan
      @plan = Current.family.credit_card_installment_plans
        .joins(:account)
        .merge(Account.writable_by(Current.user))
        .find(params[:id])
    end

    def plan_params
      params.require(:credit_card_installment_plan).permit(
        :account_id,
        :name,
        :total_amount,
        :installments_count,
        :paid_installments,
        :first_payment_on,
        :purchased_on,
        :category_id,
        :payment_account_id,
        :status,
        :notes
      )
    end
end
