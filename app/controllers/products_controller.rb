class ProductsController < ApplicationController
  before_action :set_product, only: %i[ show update destroy ]

  DEFAULT_PER_PAGE = 25
  MAX_PER_PAGE = 100

  # GET /products
  def index
    page = [params[:page].to_i, 1].max
    per_page = params[:per_page].to_i
    per_page = DEFAULT_PER_PAGE if per_page <= 0
    per_page = MAX_PER_PAGE if per_page > MAX_PER_PAGE

    @products = Product.order(:id).limit(per_page).offset((page - 1) * per_page)

    render json: @products
  end

  # GET /products/1
  def show
    render json: @product
  end

  # POST /products
  def create
    @product = Product.new(product_params)

    if @product.save
      render json: @product, status: :created, location: @product
    else
      render json: @product.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /products/1
  def update
    if @product.update(product_params)
      render json: @product
    else
      render json: @product.errors, status: :unprocessable_entity
    end
  end

  # DELETE /products/1
  def destroy
    @product.destroy!
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_product
      @product = Product.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def product_params
      params.require(:product).permit(:name, :price)
    end
end
