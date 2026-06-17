class RecurringTransactionsController < ApplicationController
  layout "settings"

  def index
    load_index_data
  end

  def update_settings
    Current.family.update!(recurring_settings_params)

    respond_to do |format|
      format.html do
        flash[:notice] = t("recurring_transactions.settings_updated")
        redirect_to recurring_transactions_path
      end
    end
  end

  def identify
    count = RecurringTransaction.identify_patterns_for!(Current.family)

    respond_to do |format|
      format.html do
        flash[:notice] = t("recurring_transactions.identified", count: count)
        redirect_to recurring_transactions_path
      end
    end
  end

  def create
    @recurring_transaction = Current.family.recurring_transactions.build(recurring_transaction_params)
    @recurring_transaction.manual = true
    @recurring_transaction.status = "active"
    @recurring_transaction.last_occurrence_date = Date.current
    @recurring_transaction.next_expected_date = RecurringTransaction.calculate_next_expected_date_from_today(
      @recurring_transaction.expected_day_of_month
    )
    @recurring_transaction.currency ||= @recurring_transaction.account&.currency || Current.family.currency
    @recurring_transaction.save!

    redirect_to recurring_transactions_path, notice: t("recurring_transactions.create.success")
  rescue ActiveRecord::RecordInvalid
    load_index_data
    flash.now[:alert] = @recurring_transaction.errors.full_messages.to_sentence
    render :index, status: :unprocessable_entity
  end

  def cleanup
    count = RecurringTransaction.cleanup_stale_for(Current.family)

    respond_to do |format|
      format.html do
        flash[:notice] = t("recurring_transactions.cleaned_up", count: count)
        redirect_to recurring_transactions_path
      end
    end
  end

  def toggle_status
    @recurring_transaction = Current.family.recurring_transactions.accessible_by(Current.user).find(params[:id])

    if @recurring_transaction.active?
      @recurring_transaction.mark_inactive!
      message = t("recurring_transactions.marked_inactive")
    else
      @recurring_transaction.mark_active!
      message = t("recurring_transactions.marked_active")
    end

    respond_to do |format|
      format.html do
        flash[:notice] = message
        redirect_to recurring_transactions_path
      end
    end
  end

  def destroy
    @recurring_transaction = Current.family.recurring_transactions.accessible_by(Current.user).find(params[:id])
    @recurring_transaction.destroy!

    flash[:notice] = t("recurring_transactions.deleted")
    redirect_to recurring_transactions_path
  end

  private

    def load_index_data
      @recurring_transactions = Current.family.recurring_transactions
                                      .accessible_by(Current.user)
                                      .includes(:merchant)
                                      .order(status: :asc, next_expected_date: :asc)
      @family = Current.family
      @accounts = Current.user.accessible_accounts.writable_by(Current.user).visible.alphabetically
    end

    def recurring_settings_params
      { recurring_transactions_disabled: params[:recurring_transactions_disabled] == "true" }
    end

    def recurring_transaction_params
      permitted = params.require(:recurring_transaction).permit(:name, :amount, :currency, :expected_day_of_month, :account_id)
      account = Current.user.accessible_accounts.writable_by(Current.user).find(permitted[:account_id])
      permitted[:account] = account
      permitted.except(:account_id)
    end
end
