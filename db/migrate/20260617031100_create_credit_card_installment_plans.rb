class CreateCreditCardInstallmentPlans < ActiveRecord::Migration[7.2]
  def change
    create_table :credit_card_installment_plans, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.string :name, null: false
      t.decimal :total_amount, precision: 19, scale: 4, null: false
      t.string :currency, null: false
      t.integer :installments_count, null: false
      t.integer :paid_installments, null: false, default: 0
      t.date :first_payment_on, null: false
      t.string :status, null: false, default: "active"
      t.text :notes
      t.timestamps

      t.index [ :family_id, :account_id, :status ], name: "idx_on_family_id_account_id_status_b72a40c74d"
      t.index [ :account_id, :first_payment_on ], name: "idx_cc_installments_account_first_payment"
      t.check_constraint "total_amount >= 0", name: "chk_cc_installment_plans_total_amount"
      t.check_constraint "installments_count > 0", name: "chk_cc_installment_plans_installments_count"
      t.check_constraint "paid_installments >= 0 AND paid_installments <= installments_count", name: "chk_cc_installment_plans_paid_installments"
      t.check_constraint "status IN ('active', 'completed', 'cancelled')", name: "chk_cc_installment_plans_status"
    end
  end
end
