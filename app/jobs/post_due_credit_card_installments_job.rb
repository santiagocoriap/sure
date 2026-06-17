class PostDueCreditCardInstallmentsJob < ApplicationJob
  queue_as :scheduled

  def perform(through: Date.current)
    CreditCardInstallmentPlan.active.find_each do |plan|
      plan.post_due_installments!(through: through)
    end
  end
end
