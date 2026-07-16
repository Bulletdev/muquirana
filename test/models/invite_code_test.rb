require "test_helper"

class InviteCodeTest < ActiveSupport::TestCase
  test "codigo novo nasce para uma pessoa e sem uso" do
    code = InviteCode.create!

    assert_equal 1, code.max_uses
    assert_equal 0, code.uses_count
    assert code.available?
    assert_not code.exhausted?
    assert_not code.revoked?
  end

  test "generate! aceita o limite de usos" do
    token = InviteCode.generate!(max_uses: 5)

    assert_equal 5, InviteCode.find_by(token: token).max_uses
  end

  test "max_uses tem que ser positivo" do
    assert_not InviteCode.new(max_uses: 0).valid?
    assert_not InviteCode.new(max_uses: -3).valid?
  end

  # O ponto do multi-uso: o mesmo link serve varias pessoas.
  test "o link continua valendo enquanto houver vaga" do
    code = InviteCode.create!(max_uses: 3)

    assert code.mark_used!(users(:family_admin))
    assert_equal code, InviteCode.claimable(code.token), "ainda tem vaga: tem que valer"

    assert code.reload.mark_used!(users(:family_member))
    assert code.reload.available?
    assert_equal 2, code.uses_count
  end

  test "no limite, o link para de valer" do
    code = InviteCode.create!(max_uses: 1)
    code.mark_used!(users(:family_admin))

    assert code.reload.exhausted?
    assert_nil InviteCode.claimable(code.token)
    assert_not code.mark_used!(users(:family_member)), "nao pode furar o limite"
  end

  # O UPDATE carrega a condicao `uses_count < max_uses` justamente para isto:
  # se a checagem fosse em Ruby antes do save, os dois passariam.
  test "dois usos simultaneos na ultima vaga: so um passa" do
    code = InviteCode.create!(max_uses: 1)
    a = InviteCode.find(code.id)
    b = InviteCode.find(code.id)

    primeiro = a.mark_used!(users(:family_admin))
    segundo = b.mark_used!(users(:family_member))

    assert primeiro
    assert_not segundo, "a segunda gravacao tinha que falhar"
    assert_equal 1, code.reload.uses_count
  end

  test "revogar tira do ar sem apagar quem entrou" do
    code = InviteCode.create!(max_uses: 5)
    code.mark_used!(users(:family_admin))

    assert_no_difference "InviteCode.count" do
      code.revoke!
    end

    assert code.revoked?
    assert_not code.available?
    assert_nil InviteCode.claimable(code.token), "link revogado nao pode mais valer"
    assert_equal [ users(:family_admin) ], code.users.to_a, "o historico de quem entrou fica"
  end

  test "revogado nao aceita mais uso mesmo com vaga sobrando" do
    code = InviteCode.create!(max_uses: 5)
    code.revoke!

    assert_not code.reload.mark_used!(users(:family_admin))
    assert_equal 0, code.reload.uses_count
  end

  test "registra quem usou" do
    code = InviteCode.create!(max_uses: 2)
    code.mark_used!(users(:family_admin))
    code.reload.mark_used!(users(:family_member))

    assert_equal 2, code.reload.users.count
    assert_includes code.users, users(:family_admin)
    assert_equal code, users(:family_admin).reload.invite_code
  end

  test "claimable ignora maiuscula e codigo inexistente" do
    code = InviteCode.create!

    assert_equal code, InviteCode.claimable(code.token.upcase)
    assert_nil InviteCode.claimable("naoexiste")
    assert_nil InviteCode.claimable(nil)
  end
end
