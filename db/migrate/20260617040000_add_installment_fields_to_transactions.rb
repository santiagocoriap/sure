class AddInstallmentFieldsToTransactions < ActiveRecord::Migration[7.2]
  def change
    add_column :transactions, :installment_number, :integer
    add_reference :transactions, :credit_card_installment_plan,
                  type: :uuid,
                  null: true,
                  foreign_key: { to_table: :credit_card_installment_plans, on_delete: :nullify }

    add_index :transactions,
              [ :credit_card_installment_plan_id, :installment_number ],
              unique: true,
              name: "idx_unique_installment_per_plan",
              where: "credit_card_installment_plan_id IS NOT NULL"
  end
end
