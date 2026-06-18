class CreateCreditCardBillingCycles < ActiveRecord::Migration[7.2]
  def change
    create_table :credit_card_billing_cycles, id: :uuid do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.date :closing_on, null: false
      t.date :due_on, null: false
      t.timestamps

      t.index [ :account_id, :closing_on ], unique: true, name: "idx_unique_cc_billing_cycle_close"
    end
  end
end
