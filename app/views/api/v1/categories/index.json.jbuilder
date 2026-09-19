# frozen_string_literal: true

json.categories @categories do |category|
  json.id category.id
  json.name category.name
  json.color category.color
  json.icon category.lucide_icon
  json.classification category.classification
  json.parent_id category.parent_id
end

json.pagination do
  json.page @pagy.page
  json.per_page @per_page
  json.total_count @pagy.count
  json.total_pages @pagy.pages
end
