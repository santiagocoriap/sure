class CreditCardBillingCyclesController < ApplicationController
  before_action :set_account, only: :create
  before_action :set_cycle, only: :destroy

  def create
    @cycle = @account.credit_card_billing_cycles.build(cycle_params)
    @cycle.save!

    redirect_to account_path(@account, tab: "installments"), notice: t("credit_card_billing_cycles.create.success")
  rescue ActiveRecord::RecordInvalid
    redirect_to account_path(@account, tab: "installments"), alert: @cycle.errors.full_messages.to_sentence
  end

  def destroy
    account = @cycle.account
    @cycle.destroy!

    redirect_to account_path(account, tab: "installments"), notice: t("credit_card_billing_cycles.destroy.success")
  end

  private
    def set_account
      @account = Current.user.accessible_accounts
        .writable_by(Current.user)
        .find(params.require(:credit_card_billing_cycle).permit(:account_id)[:account_id])
      raise ActiveRecord::RecordNotFound unless @account.credit_card?
    end

    def set_cycle
      accessible = Current.user.accessible_accounts.writable_by(Current.user)
      @cycle = CreditCardBillingCycle.where(account: accessible).find(params[:id])
    end

    def cycle_params
      params.require(:credit_card_billing_cycle).permit(:account_id, :closing_on, :due_on)
    end
end
