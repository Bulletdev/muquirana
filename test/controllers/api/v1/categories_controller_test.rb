# frozen_string_literal: true

require "test_helper"

class Api::V1::CategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin) # dylan_family user
    @other_family_user = users(:family_member)
    @other_family_user.update!(family: families(:empty))

    @oauth_app = Doorkeeper::Application.create!(
      name: "Test API App",
      redirect_uri: "https://example.com/callback",
      scopes: "read read_write"
    )
  end

  test "should require authentication" do
    get "/api/v1/categories"
    assert_response :unauthorized

    response_body = JSON.parse(response.body)
    assert_equal "unauthorized", response_body["error"]
  end

  test "should return user's family categories with pagination" do
    get "/api/v1/categories", headers: auth_headers(@user)

    assert_response :success
    response_body = JSON.parse(response.body)

    assert response_body["categories"].is_a?(Array)
    assert response_body.key?("pagination")
    %w[page per_page total_count total_pages].each do |key|
      assert response_body["pagination"].key?(key), "Pagination should have #{key}"
    end

    family_category_names = @user.family.categories.pluck(:name)
    response_body["categories"].each do |category|
      assert_includes family_category_names, category["name"]
    end

    assert_equal @user.family.categories.count, response_body["pagination"]["total_count"]
  end

  test "should not return other family's categories" do
    get "/api/v1/categories", headers: auth_headers(@other_family_user)

    assert_response :success
    response_body = JSON.parse(response.body)

    names = response_body["categories"].map { |c| c["name"] }
    assert_includes names, categories(:one).name
    assert_not_includes names, categories(:food_and_drink).name
  end

  test "should return proper category data structure" do
    get "/api/v1/categories", headers: auth_headers(@user)

    assert_response :success
    response_body = JSON.parse(response.body)

    category = response_body["categories"].first
    %w[id name color icon classification parent_id].each do |field|
      assert category.key?(field), "Category should have #{field} field"
    end

    assert category["id"].is_a?(String), "ID should be string (UUID)"
    assert %w[income expense].include?(category["classification"])

    subcategory = response_body["categories"].find { |c| c["name"] == categories(:subcategory).name }
    assert_equal categories(:food_and_drink).id, subcategory["parent_id"]
  end

  test "should sort categories alphabetically" do
    get "/api/v1/categories", headers: auth_headers(@user)

    assert_response :success
    names = JSON.parse(response.body)["categories"].map { |c| c["name"] }
    assert_equal names.sort, names
  end

  test "should filter by classification" do
    categories(:income).update!(classification: "income")

    get "/api/v1/categories", params: { classification: "income" }, headers: auth_headers(@user)

    assert_response :success
    response_body = JSON.parse(response.body)

    assert_equal [ "income" ], response_body["categories"].map { |c| c["classification"] }.uniq
    assert_equal @user.family.categories.incomes.count, response_body["pagination"]["total_count"]
  end

  test "should ignore an invalid classification filter" do
    get "/api/v1/categories", params: { classification: "bogus" }, headers: auth_headers(@user)

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal @user.family.categories.count, response_body["pagination"]["total_count"]
  end

  test "should handle pagination parameters" do
    get "/api/v1/categories", params: { page: 1, per_page: 2 }, headers: auth_headers(@user)

    assert_response :success
    response_body = JSON.parse(response.body)

    assert response_body["categories"].length <= 2
    assert_equal 1, response_body["pagination"]["page"]
    assert_equal 2, response_body["pagination"]["per_page"]
  end

  test "should authenticate with an API key and expose rate limit headers" do
    @user.api_keys.active.destroy_all
    api_key = ApiKey.create!(
      user: @user,
      name: "Mobile client",
      source: "mobile",
      scopes: [ "read" ],
      display_key: "muq_test_categories_#{SecureRandom.hex(4)}"
    )
    Redis.new.del("api_rate_limit:#{api_key.id}")

    get "/api/v1/categories", headers: { "X-Api-Key" => api_key.plain_key }

    assert_response :success
    assert_equal @user.family.categories.count, JSON.parse(response.body)["pagination"]["total_count"]
    assert response.headers["X-RateLimit-Limit"].present?
    assert response.headers["X-RateLimit-Remaining"].present?
  end

  private

    def auth_headers(user)
      access_token = Doorkeeper::AccessToken.create!(
        application: @oauth_app,
        resource_owner_id: user.id,
        scopes: "read"
      )

      { "Authorization" => "Bearer #{access_token.token}" }
    end
end
