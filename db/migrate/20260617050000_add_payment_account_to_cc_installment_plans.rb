class AddPaymentAccountToCcInstallmentPlans < ActiveRecord::Migration[7.2]
  def change
    add_reference :credit_card_installment_plans, :payment_account,
                  type: :uuid, null: true,
                  foreign_key: { to_table: :accounts, on_delete: :nullify }
  end
end
