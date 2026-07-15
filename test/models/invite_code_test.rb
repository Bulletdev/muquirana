require "test_helper"

class InviteCodeTest < ActiveSupport::TestCase
  test "novo codigo nasce sem uso" do
    code = InviteCode.create!

    assert_not code.used?
    assert_nil code.used_by
    assert_includes InviteCode.unused, code
  end

  test "claimable acha codigo nao usado e ignora maiuscula" do
    code = InviteCode.create!

    assert_equal code, InviteCode.claimable(code.token.upcase)
  end

  test "claimable nao acha codigo ja usado" do
    code = InviteCode.create!
    code.mark_used!(users(:family_admin))

    assert_nil InviteCode.claimable(code.token), "codigo usado nao pode ser reutilizado"
  end

  test "mark_used registra quem usou e quando" do
    code = InviteCode.create!
    user = users(:family_admin)

    assert code.mark_used!(user)

    code.reload
    assert code.used?
    assert_equal user, code.used_by
    assert_not_nil code.used_at
  end

  # O registro nao pode sumir: era isso que deixava o admin sem informacao
  # nenhuma sobre quem entrou na instancia dele.
  test "usar o codigo nao apaga o registro" do
    code = InviteCode.create!

    assert_no_difference "InviteCode.count" do
      code.mark_used!(users(:family_admin))
    end
  end

  test "mark_used e uma vez so, mesmo chamado em corrida" do
    code = InviteCode.create!
    primeiro = users(:family_admin)
    segundo = users(:family_member)

    assert code.mark_used!(primeiro)
    assert_not code.mark_used!(segundo), "o segundo uso tem que falhar"

    assert_equal primeiro, code.reload.used_by
  end
end
