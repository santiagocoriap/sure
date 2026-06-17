class AddCycleFieldsToCreditCards < ActiveRecord::Migration[7.2]
  def change
    add_column :credit_cards, :credit_limit, :decimal, precision: 19, scale: 4
    add_column :credit_cards, :closing_day, :integer
    add_column :credit_cards, :due_day, :integer

    add_check_constraint :credit_cards, "closing_day IS NULL OR (closing_day >= 1 AND closing_day <= 31)", name: "chk_credit_cards_closing_day"
    add_check_constraint :credit_cards, "due_day IS NULL OR (due_day >= 1 AND due_day <= 31)", name: "chk_credit_cards_due_day"
    add_check_constraint :credit_cards, "credit_limit IS NULL OR credit_limit >= 0", name: "chk_credit_cards_credit_limit"
  end
end
