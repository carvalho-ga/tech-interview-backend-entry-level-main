class Cart < ApplicationRecord
  class InvalidQuantityError < StandardError; end
  class ProductNotInCartError < StandardError; end

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

  def self.find_or_create_for_session(cart_id: nil, product_id: nil)
    if cart_id.present?
      cart = find_by(id: cart_id)
      return cart if cart
    end

    if product_id.present?
      existing_item = CartItem.find_by(product_id: product_id)
      return existing_item.cart if existing_item
    end

    create!(total_price: 0)
  end

  def self.valid_quantity?(quantity)
    quantity.to_i.positive?
  end

  def add_product(product, quantity)
    quantity = quantity.to_i
    return false unless quantity.positive?

    with_lock do
      cart_item = cart_items.find_by(product: product)

      if cart_item
        cart_item.increment!(:quantity, quantity)
      else
        cart_items.create!(product: product, quantity: quantity)
      end

      recalculate_total
    end

    true
  end

  def remove_product(product_id)
    removed = false

    with_lock do
      cart_item = cart_items.find_by(product_id: product_id)

      if cart_item
        cart_item.destroy
        recalculate_total
        removed = true
      end
    end

    removed
  end

  def recalculate_total
    total = cart_items.includes(:product).sum { |item| item.product.price * item.quantity }
    update!(total_price: total, last_interaction_at: Time.current)
  end
end
