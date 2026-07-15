require "test_helper"

class InviteCodesControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.config.app_mode.stubs(:self_hosted?).returns(true)
  end

  test "admin lista os codigos" do
    sign_in users(:family_admin)
    InviteCode.generate!

    get invite_codes_url

    assert_response :success
  end

  test "admin gera codigo" do
    sign_in users(:family_admin)

    assert_difference "InviteCode.count", 1 do
      post invite_codes_url
    end
  end

  # Revogar era a lacuna: um codigo gerado por engano, ou um link que foi para
  # o grupo errado, so saia do ar quando alguem o usasse.
  test "admin revoga codigo nao usado" do
    sign_in users(:family_admin)
    code = InviteCode.create!

    assert_difference "InviteCode.count", -1 do
      delete invite_code_url(code)
    end

    assert_nil InviteCode.claimable(code.token), "o link tem que parar de funcionar"
  end

  # Listar codigos e, na pratica, poder convidar: cada codigo vale por uma conta
  # nova no servidor de quem hospeda. Isso e do admin.
  test "membro comum nao lista os codigos" do
    membro = users(:family_member)
    refute membro.admin?
    sign_in membro
    InviteCode.generate!

    get invite_codes_url

    assert_response :not_found
  end

  test "membro comum nao gera codigo" do
    sign_in users(:family_member)

    assert_no_difference "InviteCode.count" do
      post invite_codes_url
    end
  end

  test "membro comum nao revoga codigo" do
    code = InviteCode.create!
    sign_in users(:family_member)

    assert_no_difference "InviteCode.count" do
      delete invite_code_url(code)
    end
  end
end
