require "test_helper"

class ChatErrorMessageTest < ActiveSupport::TestCase
  setup { @chat = chats(:one) }

  # Erros conhecidos do provedor de IA viram uma frase limpa em pt-BR com o que
  # fazer. O texto cru (ingles, com URL e codigo) so no modo debug. Ver
  # Chat#friendly_ai_error. O esperado sai do proprio I18n.t para o teste nao
  # quebrar quando a copy for reescrita.
  test "cota esgotada vira mensagem amigavel" do
    @chat.add_error(Provider::Openai::Error.new("You exceeded your current quota (insufficient_quota)"))

    assert_equal I18n.t("chats.error.reasons.quota"), @chat.reload.error_message
  end

  # Quando o corpo da resposta veio junto, casa pelo CODIGO (mais confiavel que
  # o texto da mensagem do Faraday).
  test "casa o erro pelo codigo no corpo da resposta" do
    @chat.add_error(Provider::Openai::Error.new(
      "the server responded with status 401",
      details: { "error" => { "code" => "invalid_api_key" } }
    ))

    assert_equal I18n.t("chats.error.reasons.invalid_key"), @chat.reload.error_message
  end

  # Erro sem sinal conhecido cai na mensagem crua: melhor mostrar algo do que
  # nada.
  test "erro desconhecido cai na mensagem crua" do
    @chat.add_error(Provider::Openai::Error.new("algo bem estranho aconteceu"))

    assert_equal "algo bem estranho aconteceu", @chat.reload.error_message
  end

  test "sem erro, nao ha mensagem" do
    @chat.clear_error

    assert_nil @chat.error_message
  end

  # A tela do chat nao pode cair porque o erro foi gravado num formato
  # inesperado: perde-se o motivo, nao a pagina.
  test "erro em formato desconhecido nao derruba a tela" do
    @chat.update_column(:error, "isto nao e json")

    assert_nothing_raised { assert_nil @chat.error_message }
  end

  test "erro gravado como hash tambem funciona" do
    @chat.update_column(:error, { "message" => "Rate limit reached" })

    assert_equal I18n.t("chats.error.reasons.rate_limit"), @chat.error_message
  end
end
