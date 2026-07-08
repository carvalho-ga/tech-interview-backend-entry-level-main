Rails.application.routes.draw do
  resources :products

  get    '/cart',             to: 'carts#show'
  post   '/cart',             to: 'carts#create'
  post   '/cart/add_item',    to: 'carts#add_item'
  post   '/cart/add_items',   to: 'carts#add_item'
  delete '/cart/:product_id', to: 'carts#remove_item'

  get "up" => "rails/health#show", as: :rails_health_check

  root "rails/health#show"
end
