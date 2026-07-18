require "test_helper"

class Assistant::Function::CreateTagTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @fn = Assistant::Function::CreateTag.new(@user)
  end

  test "sem confirmacao devolve previa e nao grava" do
    result = nil
    assert_no_difference "Tag.count" do
      result = @fn.call("name" => "Mercado")
    end

    assert result[:requires_confirmation]
    assert_equal "create_tag", result[:action]
    assert_equal "Mercado", result[:preview][:name]
  end

  test "com confirmed=true cria a tag" do
    result = nil
    assert_difference "@user.family.tags.count", 1 do
      result = @fn.call("name" => "Mercado", "confirmed" => true)
    end

    assert result[:success]
    assert_equal "Mercado", result[:tag][:name]
    assert @user.family.tags.exists?(name: "Mercado")
  end

  test "nome vazio retorna erro sem gravar" do
    assert_no_difference "Tag.count" do
      result = @fn.call("name" => "  ", "confirmed" => true)
      assert_not result[:success]
      assert_equal "name_required", result[:error]
    end
  end

  test "nome duplicado retorna validation_failed" do
    existing = @user.family.tags.first
    assert_no_difference "Tag.count" do
      result = @fn.call("name" => existing.name, "confirmed" => true)
      assert_not result[:success]
      assert_equal "validation_failed", result[:error]
    end
  end
end
