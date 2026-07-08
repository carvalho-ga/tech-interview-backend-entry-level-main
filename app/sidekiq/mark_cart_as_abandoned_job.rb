class MarkCartAsAbandonedJob
  include Sidekiq::Job

  def perform
    mark_inactive_carts_as_abandoned
    remove_long_abandoned_carts
  end

  private

  def mark_inactive_carts_as_abandoned
    Cart.active.inactive_since(3.hours).find_each(&:mark_as_abandoned)
  end

  def remove_long_abandoned_carts
    Cart.abandoned_since(7.days).find_each(&:destroy)
  end
end
