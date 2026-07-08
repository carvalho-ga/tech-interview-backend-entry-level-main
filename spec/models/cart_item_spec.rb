require 'rails_helper'

RSpec.describe CartItem, type: :model do
  context 'when validating quantity' do
    it 'is invalid with zero quantity' do
      cart_item = build(:cart_item, quantity: 0)
      expect(cart_item.valid?).to be_falsey
      expect(cart_item.errors[:quantity]).to be_present
    end

    it 'is invalid with negative quantity' do
      cart_item = build(:cart_item, quantity: -1)
      expect(cart_item.valid?).to be_falsey
    end

    it 'is valid with quantity greater than zero' do
      cart_item = build(:cart_item, quantity: 1)
      expect(cart_item.valid?).to be_truthy
    end
  end

  context 'when validating uniqueness' do
    it 'does not allow the same product twice in the same cart' do
      cart = create(:cart)
      product = create(:product)
      create(:cart_item, cart: cart, product: product)

      duplicate = build(:cart_item, cart: cart, product: product)
      expect(duplicate.valid?).to be_falsey
      expect(duplicate.errors[:product_id]).to include('already exists in this cart')
    end

    it 'allows the same product in different carts' do
      product = create(:product)
      create(:cart_item, cart: create(:cart), product: product)

      other_cart_item = build(:cart_item, cart: create(:cart), product: product)
      expect(other_cart_item.valid?).to be_truthy
    end
  end
end
