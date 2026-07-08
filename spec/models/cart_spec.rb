require 'rails_helper'

RSpec.describe Cart, type: :model do
  context 'when validating' do
    it 'validates numericality of total_price' do
      cart = described_class.new(total_price: -1)
      expect(cart.valid?).to be_falsey
      expect(cart.errors[:total_price]).to include("must be greater than or equal to 0")
    end
  end

  describe 'mark_as_abandoned' do
    let(:shopping_cart) { create(:shopping_cart) }

    it 'marks the shopping cart as abandoned if inactive for a certain time' do
      shopping_cart.update(last_interaction_at: 3.hours.ago)
      expect { shopping_cart.mark_as_abandoned }.to change { shopping_cart.abandoned? }.from(false).to(true)
    end
  end

  describe 'remove_if_abandoned' do
    let(:shopping_cart) { create(:shopping_cart, last_interaction_at: 7.days.ago) }

    it 'removes the shopping cart if abandoned for a certain time' do
      shopping_cart.mark_as_abandoned
      expect { shopping_cart.remove_if_abandoned }.to change { Cart.count }.by(-1)
    end

    it 'does not remove the cart if it is not abandoned' do
      shopping_cart

      expect { shopping_cart.remove_if_abandoned }.not_to change { Cart.count }
    end
  end

  describe 'recalculate_total' do
    let(:cart) { create(:cart) }
    let(:product) { create(:product, price: 10.0) }

    it 'sets total_price based on the sum of all items' do
      create(:cart_item, cart: cart, product: product, quantity: 3)
      cart.recalculate_total
      expect(cart.total_price.to_f).to eq(30.0)
    end

    it 'sets total_price to zero when cart has no items' do
      cart.recalculate_total
      expect(cart.total_price.to_f).to eq(0.0)
    end

    it 'updates last_interaction_at' do
      original_time = 1.hour.ago
      cart.update(last_interaction_at: original_time)
      cart.recalculate_total
      expect(cart.last_interaction_at).to be > original_time
    end
  end

  describe 'add_product' do
    let(:cart) { create(:cart) }
    let(:product) { create(:product, price: 10.0) }

    it 'creates a new cart item when the product is not yet in the cart' do
      expect { cart.add_product(product, 2) }.to change { cart.cart_items.count }.by(1)
      expect(cart.cart_items.find_by(product: product).quantity).to eq(2)
    end

    it 'increments the quantity when the product is already in the cart' do
      create(:cart_item, cart: cart, product: product, quantity: 1)
      cart.add_product(product, 2)
      expect(cart.cart_items.find_by(product: product).quantity).to eq(3)
    end

    it 'recalculates the total price' do
      cart.add_product(product, 2)
      expect(cart.total_price.to_f).to eq(20.0)
    end

    it 'returns false and does not change the cart when quantity is zero or negative' do
      expect { cart.add_product(product, 0) }.not_to change { cart.cart_items.count }
      expect(cart.add_product(product, -1)).to be false
    end
  end

  describe 'remove_product' do
    let(:cart) { create(:cart) }
    let(:product) { create(:product, price: 10.0) }

    it 'removes the item and recalculates the total' do
      create(:cart_item, cart: cart, product: product, quantity: 2)
      cart.recalculate_total

      expect(cart.remove_product(product.id)).to be true
      expect(cart.cart_items.count).to eq(0)
      expect(cart.total_price.to_f).to eq(0.0)
    end

    it 'returns false when the product is not in the cart' do
      expect(cart.remove_product(product.id)).to be false
    end
  end

  describe '.find_or_create_for_session' do
    it 'returns the cart matching the given cart_id' do
      cart = create(:cart)
      expect(Cart.find_or_create_for_session(cart_id: cart.id)).to eq(cart)
    end

    it 'falls back to the cart owning an existing cart item for the product' do
      cart = create(:cart)
      product = create(:product)
      create(:cart_item, cart: cart, product: product)

      expect(Cart.find_or_create_for_session(cart_id: nil, product_id: product.id)).to eq(cart)
    end

    it 'creates a new cart when nothing matches' do
      expect { Cart.find_or_create_for_session(cart_id: nil, product_id: nil) }.to change { Cart.count }.by(1)
    end
  end
end
