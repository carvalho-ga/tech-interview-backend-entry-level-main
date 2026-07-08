FactoryBot.define do
  factory :cart, aliases: [:shopping_cart] do
    total_price { 0 }
    abandoned { false }
    last_interaction_at { Time.current }
    abandoned_at { nil }
  end
end
