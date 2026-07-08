class CartsController < ApplicationController
  before_action :set_cart, only: [:add_item, :remove_item]

  def show
    cart = Cart.find_by(id: session[:cart_id])
    render json: cart ? cart_response(cart) : { id: nil, products: [], total_price: 0 }
  end

  def create
    product = find_product(params[:product_id])
    return unless product

    quantity = params[:quantity].to_i
    return render_invalid_quantity if quantity <= 0

    cart = find_or_create_cart(product_id: product.id)
    cart.add_product(product, quantity)

    render json: cart_response(cart), status: :ok
  end

  def add_item
    product = find_product(params[:product_id])
    return unless product

    quantity = params[:quantity].to_i
    return render_invalid_quantity if quantity <= 0

    @cart.add_product(product, quantity)

    render json: cart_response(@cart), status: :ok
  end

  def remove_item
    unless @cart.remove_product(params[:product_id])
      return render json: { error: 'Product not found in cart' }, status: :unprocessable_entity
    end

    render json: cart_response(@cart), status: :ok
  end

  private

  def set_cart
    @cart = find_or_create_cart(product_id: params[:product_id])
  end

  def find_or_create_cart(product_id: nil)
    if session[:cart_id].present?
      cart = Cart.find_by(id: session[:cart_id])
      return cart if cart.present?
    end

    if product_id.present?
      existing_item = CartItem.find_by(product_id: product_id)
      if existing_item
        session[:cart_id] = existing_item.cart_id
        return existing_item.cart
      end
    end

    cart = Cart.create!(total_price: 0)
    session[:cart_id] = cart.id
    cart
  end

  def find_product(product_id)
    product = Product.find_by(id: product_id)
    render json: { error: 'Product not found' }, status: :not_found if product.nil?
    product
  end

  def render_invalid_quantity
    render json: { error: 'Quantity must be greater than zero' }, status: :unprocessable_entity
  end

  def cart_response(cart)
    {
      id: cart.id,
      products: cart.cart_items.includes(:product).map { |item|
        {
          id: item.product.id,
          name: item.product.name,
          quantity: item.quantity,
          unit_price: item.product.price.to_f,
          total_price: (item.product.price * item.quantity).round(2).to_f
        }
      },
      total_price: (cart.total_price || 0).to_f
    }
  end
end
