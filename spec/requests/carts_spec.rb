require 'rails_helper'

RSpec.describe "/carts", type: :request do
  describe "POST /add_items" do
    let(:cart) { Cart.create }
    let(:product) { Product.create(name: "Test Product", price: 10.0) }
    let!(:cart_item) { CartItem.create(cart: cart, product: product, quantity: 1) }

    context 'when the product already is in the cart' do
      subject do
        post '/cart/add_items', params: { product_id: product.id, quantity: 1 }, as: :json
        post '/cart/add_items', params: { product_id: product.id, quantity: 1 }, as: :json
      end

      it 'updates the quantity of the existing item in the cart' do
        expect { subject }.to change { cart_item.reload.quantity }.by(2)
      end
    end
  end

  describe "POST /cart" do
    let!(:product) { create(:product, name: 'Notebook', price: 3500.00) }

    context 'when cart does not exist in session' do
      it 'creates a new cart and returns it with the product' do
        post '/cart', params: { product_id: product.id, quantity: 2 }, as: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['id']).to be_present
        expect(json['products'].length).to eq(1)
        expect(json['products'].first['name']).to eq('Notebook')
        expect(json['products'].first['quantity']).to eq(2)
        expect(json['total_price']).to eq(7000.00)
      end
    end

    context 'when the same product is added twice' do
      it 'increments the quantity instead of creating a duplicate' do
        post '/cart', params: { product_id: product.id, quantity: 1 }, as: :json
        post '/cart', params: { product_id: product.id, quantity: 1 }, as: :json

        json = JSON.parse(response.body)
        expect(json['products'].length).to eq(1)
        expect(json['products'].first['quantity']).to eq(2)
      end
    end

    context 'when product does not exist' do
      it 'returns 404 not found' do
        post '/cart', params: { product_id: 99999, quantity: 1 }, as: :json
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when quantity is zero' do
      it 'returns 422 unprocessable entity' do
        post '/cart', params: { product_id: product.id, quantity: 0 }, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'when quantity is negative' do
      it 'returns 422 unprocessable entity' do
        post '/cart', params: { product_id: product.id, quantity: -5 }, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET /cart" do
    context 'when cart exists in session' do
      it 'returns the cart with its products' do
        product = create(:product, name: 'Mouse', price: 9.99)
        post '/cart', params: { product_id: product.id, quantity: 1 }, as: :json

        get '/cart'

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['id']).to be_present
        expect(json['products']).to be_an(Array)
        expect(json['products'].first['name']).to eq('Mouse')
      end
    end

    context 'when no cart in session' do
      it 'returns an empty response without persisting a cart' do
        get '/cart'

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['products']).to eq([])
      end
    end
  end

  describe "POST /cart/add_item" do
    let!(:product) { create(:product, price: 7.00) }

    it 'adds a product and returns updated cart' do
      post '/cart/add_item', params: { product_id: product.id, quantity: 2 }, as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['products'].first['quantity']).to eq(2)
      expect(json['total_price']).to eq(14.00)
    end

    it 'increments the quantity when the product is already in the cart' do
      post '/cart/add_item', params: { product_id: product.id, quantity: 1 }, as: :json
      post '/cart/add_item', params: { product_id: product.id, quantity: 2 }, as: :json

      json = JSON.parse(response.body)
      expect(json['products'].length).to eq(1)
      expect(json['products'].first['quantity']).to eq(3)
      expect(json['total_price']).to eq(21.00)
    end

    it 'supports multiple different products in the same cart' do
      other_product = create(:product, price: 5.00)

      post '/cart/add_item', params: { product_id: product.id, quantity: 1 }, as: :json
      post '/cart/add_item', params: { product_id: other_product.id, quantity: 1 }, as: :json

      json = JSON.parse(response.body)
      expect(json['products'].length).to eq(2)
      expect(json['total_price']).to eq(12.00)
    end

    context 'when quantity is zero' do
      it 'returns 422 unprocessable entity' do
        post '/cart/add_item', params: { product_id: product.id, quantity: 0 }, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'when quantity is negative' do
      it 'returns 422 unprocessable entity' do
        post '/cart/add_item', params: { product_id: product.id, quantity: -3 }, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'when product does not exist' do
      it 'returns 404 not found' do
        post '/cart/add_item', params: { product_id: 99999, quantity: 1 }, as: :json
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "DELETE /cart/:product_id" do
    let!(:product) { create(:product, price: 10.00) }

    context 'when product exists in cart' do
      it 'removes the product and returns updated cart' do
        post '/cart', params: { product_id: product.id, quantity: 1 }, as: :json
        delete "/cart/#{product.id}"

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['products']).to eq([])
        expect(json['total_price']).to eq(0)
      end
    end

    context 'when product is not in cart' do
      it 'returns 422 with an error message' do
        other_product = create(:product)
        post '/cart', params: { product_id: product.id, quantity: 1 }, as: :json
        delete "/cart/#{other_product.id}"

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('Product not found in cart')
      end
    end
  end
end
