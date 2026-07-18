require "test_helper"

# Cobertura leve das tools de leitura ampliada da US-06. As tools de escrita tem
# testes dedicados; aqui garantimos apenas que as de leitura respondem amarradas
# a Current.family e no formato esperado.
class Assistant::Function::ReadToolsTest < ActiveSupport::TestCase
  setup { @user = users(:family_admin) }

  test "get_categories retorna categorias da familia com name_with_parent" do
    result = Assistant::Function::GetCategories.new(@user).call

    assert_equal @user.family.categories.count, result[:total]
    names = result[:categories].map { |c| c[:name_with_parent] }
    assert_includes names, "Food & Drink > Restaurants"
  end

  test "get_tags retorna tags da familia" do
    result = Assistant::Function::GetTags.new(@user).call

    assert_equal @user.family.tags.count, result[:total]
    assert_includes result[:tags].map { |t| t[:name] }, "Trips"
  end

  test "get_holdings retorna apenas posicoes de contas Investment/Crypto" do
    result = Assistant::Function::GetHoldings.new(@user).call("page" => 1)

    assert result.key?(:holdings)
    assert result.key?(:total_value)
    assert_equal 1, result[:page]
  end

  test "get_budget retorna o mes atual" do
    result = Assistant::Function::GetBudget.new(@user).call({})

    assert_equal @user.family.currency, result[:currency]
    assert result[:months].any? { |m| m[:is_current] }
  end

  test "get_budget rejeita mes em formato invalido" do
    assert_raises(Assistant::Error) do
      Assistant::Function::GetBudget.new(@user).call("month" => "2026/07")
    end
  end
end
