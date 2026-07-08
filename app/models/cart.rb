class Cart < ApplicationRecord
  has_many :cart_items, dependent: :destroy
  has_many :products, through: :cart_items

  validates :total_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :active,          -> { where(abandoned: false) }
  scope :inactive_since,  ->(duration) { where('last_interaction_at <= :t OR (last_interaction_at IS NULL AND created_at <= :t)', t: duration.ago) }
  scope :abandoned_since, ->(duration) { where(abandoned: true).where('abandoned_at <= ?', duration.ago) }

  def mark_as_abandoned
    update!(abandoned: true, abandoned_at: Time.current)
  end

  def abandoned?
    abandoned
  end

  def remove_if_abandoned
    destroy if abandoned?
  end

  def recalculate_total
    total = cart_items.includes(:product).sum { |item| item.product.price * item.quantity }
    update!(total_price: total, last_interaction_at: Time.current)
  end
end
