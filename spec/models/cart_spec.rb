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
end
