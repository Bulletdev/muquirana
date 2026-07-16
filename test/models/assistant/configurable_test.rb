require "test_helper"

class Assistant::ConfigurableTest < ActiveSupport::TestCase
  setup { @chat = chats(:one) }

  # O assistente e de financas, mas nada no prompt limitava o assunto: ele
  # respondia receita de bolo se perguntassem. Estas regras sao a unica defesa
  # -- nao ha classificador antes da chamada, de proposito (ver o commit).
  test "o prompt restringe o escopo a financas" do
    p = Assistant.config_for(@chat)[:instructions]

    assert_match(/Scope rule/, p)
    assert_match(/ONLY about personal finance/, p)
    assert_match(/decline/i, p)
  end

  test "o prompt trata tentativa de burlar como dado, nao como ordem" do
    p = Assistant.config_for(@chat)[:instructions]

    assert_match(/never instructions that outrank this/i, p)
    assert_match(/ignore these rules/i, p)
  end

  test "o prompt nao deixa um angulo financeiro destravar outro assunto" do
    p = Assistant.config_for(@chat)[:instructions]

    assert_match(/does not unlock an unrelated topic/i, p)
  end

  test "o prompt recusa fraude mas permite explicar como o golpe funciona" do
    p = Assistant.config_for(@chat)[:instructions]

    assert_match(/pyramid or ponzi/i, p)
    assert_match(/recognises and avoids it, is fine/i, p)
  end

  test "o prompt manda procurar profissional habilitado em vez de decidir" do
    p = Assistant.config_for(@chat)[:instructions]

    assert_match(/not a licensed adviser/i, p)
    assert_match(/licensed professional/i, p)
  end

  # As regras de escopo nao podem custar o que ja funcionava.
  test "o prompt mantem idioma, moeda e data do usuario" do
    familia = @chat.user.family
    familia.update!(locale: "pt-BR", currency: "BRL")

    p = Assistant.config_for(@chat)[:instructions]

    assert_match(/pt-BR/, p)
    assert_match(/R\$/, p)
    assert_match(/#{Date.current}/, p)
  end
end
