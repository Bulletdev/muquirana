require "test_helper"

class ChatErrorMessageTest < ActiveSupport::TestCase
  setup { @chat = chats(:one) }

  # O motivo do erro so aparecia sob AI_DEBUG_MODE, desligado em producao: o
  # usuario via "nao foi possivel gerar a resposta" e mais nada, sem saber se
  # era chave, cota, modelo ou rede.
  test "extrai a mensagem do erro salvo" do
    @chat.add_error(Provider::Openai::Error.new("You exceeded your current quota (insufficient_quota)"))

    assert_equal "You exceeded your current quota (insufficient_quota)", @chat.reload.error_message
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

    assert_equal "Rate limit reached", @chat.error_message
  end
end
