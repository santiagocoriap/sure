class AddPurchaseAndCategoryToCcInstallmentPlans < ActiveRecord::Migration[7.2]
  def up
    add_column :credit_card_installment_plans, :purchased_on, :date
    add_reference :credit_card_installment_plans, :category,
                  type: :uuid, null: true,
                  foreign_key: { to_table: :categories, on_delete: :nullify }

    execute <<~SQL
      UPDATE credit_card_installment_plans
      SET purchased_on = first_payment_on
      WHERE purchased_on IS NULL
    SQL

    change_column_null :credit_card_installment_plans, :purchased_on, false
  end

  def down
    remove_reference :credit_card_installment_plans, :category
    remove_column :credit_card_installment_plans, :purchased_on
  end
end
