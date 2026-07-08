require 'rails_helper'

RSpec.describe MarkCartAsAbandonedJob, type: :job do
  describe '#perform' do
    context 'marking carts as abandoned' do
      it 'marks carts inactive for more than 3 hours as abandoned' do
        cart = create(:cart, last_interaction_at: 4.hours.ago)

        described_class.new.perform

        expect(cart.reload.abandoned?).to be true
        expect(cart.reload.abandoned_at).to be_present
      end

      it 'marks carts with nil last_interaction_at as abandoned when created over 3 hours ago' do
        cart = create(:cart, last_interaction_at: nil, created_at: 4.hours.ago)

        described_class.new.perform

        expect(cart.reload.abandoned?).to be true
      end

      it 'does not mark recently active carts as abandoned' do
        cart = create(:cart, last_interaction_at: 1.hour.ago)

        described_class.new.perform

        expect(cart.reload.abandoned?).to be false
      end
    end

    context 'removing abandoned carts' do
      it 'removes carts with abandoned_at older than 7 days' do
        create(:cart, abandoned: true, abandoned_at: 8.days.ago)

        expect { described_class.new.perform }.to change { Cart.count }.by(-1)
      end

      it 'does not remove carts abandoned recently' do
        create(:cart, abandoned: true, abandoned_at: 1.day.ago)

        expect { described_class.new.perform }.not_to change { Cart.count }
      end

      it 'removes the cart items along with the cart, via cascade delete' do
        cart = create(:cart, abandoned: true, abandoned_at: 8.days.ago)
        create(:cart_item, cart: cart)

        expect { described_class.new.perform }.to change { CartItem.count }.by(-1)
      end
    end
  end
end
