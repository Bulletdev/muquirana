require "test_helper"

class Assistant::Function::CreateCategoryTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @fn = Assistant::Function::CreateCategory.new(@user)
  end

  test "sem confirmacao devolve previa e nao grava" do
    result = nil
    assert_no_difference "Category.count" do
      result = @fn.call("name" => "Assinaturas")
    end

    assert result[:requires_confirmation]
    assert_equal "create_category", result[:action]
    assert_equal "Assinaturas", result[:preview][:name]
  end

  test "com confirmed=true cria a categoria com icone e cor padrao" do
    result = nil
    assert_difference "@user.family.categories.count", 1 do
      result = @fn.call("name" => "Assinaturas", "confirmed" => true)
    end

    assert result[:success]
    category = @user.family.categories.find(result[:category][:id])
    assert_equal "Assinaturas", category.name
    assert category.lucide_icon.present?
    assert category.color.present?
  end

  test "cria subcategoria herdando a cor do pai" do
    parent = categories(:food_and_drink)
    parent.update!(color: "#123456", lucide_icon: "utensils")

    result = @fn.call("name" => "Delivery", "parent_id" => parent.id, "confirmed" => true)

    assert result[:success]
    category = @user.family.categories.find(result[:category][:id])
    assert_equal parent.id, category.parent_id
    assert_equal "#123456", category.color
    assert_equal "Food & Drink > Delivery", result[:category][:name_with_parent]
  end

  test "parent_id invalido retorna parent_not_found" do
    assert_no_difference "Category.count" do
      result = @fn.call("name" => "X", "parent_id" => "nao-e-uuid", "confirmed" => true)
      assert_not result[:success]
      assert_equal "parent_not_found", result[:error]
    end
  end

  test "nome duplicado retorna validation_failed" do
    existing = @user.family.categories.first
    assert_no_difference "Category.count" do
      result = @fn.call("name" => existing.name, "confirmed" => true)
      assert_not result[:success]
      assert_equal "validation_failed", result[:error]
    end
  end
end
