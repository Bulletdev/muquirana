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

    assert_equal 1, InviteCode.recent_first.first.max_uses, "sem escolher, o link e para uma pessoa"
  end

  test "admin escolhe para quantas pessoas o link vale" do
    sign_in users(:family_admin)

    post invite_codes_url, params: { max_uses: 5 }

    assert_equal 5, InviteCode.recent_first.first.max_uses
  end

  # max_uses vem de um <select>, ou seja, input do usuario: pode chegar
  # qualquer coisa por fora do formulario.
  test "max_uses invalido cai no minimo em vez de explodir" do
    sign_in users(:family_admin)

    [ "abc", "-5", "0", "", nil ].each do |lixo|
      post invite_codes_url, params: { max_uses: lixo }

      assert_equal 1, InviteCode.recent_first.first.max_uses, "max_uses=#{lixo.inspect} devia virar 1"
    end
  end

  # Um link para 100 mil pessoas nao e convite, e cadastro aberto -- e para
  # isso ja existe o botao de desligar a exigencia de convite.
  test "max_uses tem teto" do
    sign_in users(:family_admin)

    post invite_codes_url, params: { max_uses: 999_999 }

    assert_equal InviteCodesController::MAX_USES_LIMIT, InviteCode.recent_first.first.max_uses
  end

  # Revogar era a lacuna: um codigo gerado por engano, ou um link que foi para
  # o grupo errado, so saia do ar quando alguem o usasse.
  # Revogar NAO destroi: cada conta aponta para o convite de onde veio, e
  # apagar a linha apagaria justamente o registro de quem entrou.
  test "admin revoga o link sem apagar o historico" do
    sign_in users(:family_admin)
    code = InviteCode.create!(max_uses: 5)
    code.mark_used!(users(:family_member))

    assert_no_difference "InviteCode.count" do
      delete invite_code_url(code)
    end

    assert code.reload.revoked?
    assert_nil InviteCode.claimable(code.token), "o link tem que parar de funcionar"
    assert_equal [ users(:family_member) ], code.users.to_a, "quem entrou continua registrado"
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

    delete invite_code_url(code)

    assert_not code.reload.revoked?
  end
end
