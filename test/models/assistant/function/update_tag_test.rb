require "test_helper"

class Assistant::Function::UpdateTagTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @tag = tags(:one) # "Trips", dylan_family
    @fn = Assistant::Function::UpdateTag.new(@user)
  end

  test "tag inexistente retorna not_found" do
    result = @fn.call("name" => "Inexistente", "new_name" => "X", "confirmed" => true)
    assert_not result[:success]
    assert_equal "not_found", result[:error]
  end

  test "sem alteracoes retorna no_changes" do
    result = @fn.call("name" => @tag.name, "confirmed" => true)
    assert_not result[:success]
    assert_equal "no_changes", result[:error]
  end

  test "sem confirmacao devolve previa e nao altera" do
    result = @fn.call("name" => @tag.name, "new_name" => "Viagens")

    assert result[:requires_confirmation]
    assert_equal "Viagens", result[:preview][:name]
    assert_equal "Trips", @tag.reload.name
  end

  test "com confirmed=true atualiza a tag" do
    result = @fn.call("name" => @tag.name, "new_name" => "Viagens", "confirmed" => true)

    assert result[:success]
    assert_equal "Viagens", @tag.reload.name
  end
end
