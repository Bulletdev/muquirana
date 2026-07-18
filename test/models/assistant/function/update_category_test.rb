require "test_helper"

class Assistant::Function::UpdateCategoryTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @category = categories(:income)
    @category.update!(color: "#e99537", lucide_icon: "circle-dollar-sign")
    @fn = Assistant::Function::UpdateCategory.new(@user)
  end

  test "id invalido retorna not_found" do
    result = @fn.call("id" => "nao-e-uuid", "name" => "X", "confirmed" => true)
    assert_not result[:success]
    assert_equal "not_found", result[:error]
  end

  test "categoria de outra familia retorna not_found (isolamento)" do
    outra = categories(:one) # familia empty
    result = @fn.call("id" => outra.id, "name" => "Hack", "confirmed" => true)
    assert_not result[:success]
    assert_equal "not_found", result[:error]
    assert_not_equal "Hack", outra.reload.name
  end

  test "sem alteracoes retorna no_changes" do
    result = @fn.call("id" => @category.id, "confirmed" => true)
    assert_not result[:success]
    assert_equal "no_changes", result[:error]
  end

  test "sem confirmacao devolve previa e nao altera" do
    result = @fn.call("id" => @category.id, "name" => "Receitas")

    assert result[:requires_confirmation]
    assert_equal "Receitas", result[:preview][:name]
    assert_equal "Income", @category.reload.name
  end

  test "com confirmed=true atualiza a categoria" do
    result = @fn.call("id" => @category.id, "name" => "Receitas", "color" => "#4da568", "confirmed" => true)

    assert result[:success]
    @category.reload
    assert_equal "Receitas", @category.name
    assert_equal "#4da568", @category.color
  end
end
