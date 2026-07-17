require "test_helper"

class Insight::BodyWriterTest < ActiveSupport::TestCase
  setup do
    @family = families(:empty)
    @family.update!(currency: "BRL")
    # Ninguem na familia deu opt-in em IA -- garante o caminho de template sem
    # tocar a rede.
    @family.users.update_all(ai_enabled: false)

    @generated = Insight::Generator::GeneratedInsight.new(
      insight_type: "idle_cash",
      priority: "low",
      title: "Dinheiro parado em Poupanca",
      template_key: "idle_cash",
      facts: { account: "Poupanca", balance: "R$ 30.000,00", idle_days: 60 },
      metadata: {},
      currency: "BRL",
      period_start: nil,
      period_end: nil,
      dedup_key: "idle_cash:abc:2026-06"
    )
  end

  test "falls back to the i18n template when nobody in the family has AI enabled" do
    # A familia vazia nao tem usuario com IA habilitada, entao nenhum provider e
    # consultado e nenhuma chamada de rede acontece.
    assert_not @family.users.any?(&:ai_enabled?)

    body = Insight::BodyWriter.new(@family).write(@generated)

    expected = I18n.t(
      "insights.templates.idle_cash",
      account: "Poupanca", balance: "R$ 30.000,00", idle_days: 60
    )
    assert_equal expected, body
    assert_includes body, "Poupanca"
    assert_includes body, "R$ 30.000,00"
  end

  test "uses the localized template body per the current locale" do
    writer = Insight::BodyWriter.new(@family)

    pt_body = I18n.with_locale(:"pt-BR") { writer.write(@generated) }
    en_body = I18n.with_locale(:en) { writer.write(@generated) }

    assert_includes pt_body, "sem nenhuma movimentação"
    assert_includes en_body, "with no activity"
    assert_not_equal pt_body, en_body
  end

  test "falls back to the template when the LLM call raises" do
    writer = Insight::BodyWriter.new(@family)

    failing_provider = mock("llm_provider")
    failing_provider.stubs(:chat_response).raises(StandardError.new("boom"))
    writer.stubs(:provider).returns(failing_provider)

    body = writer.write(@generated)

    expected = I18n.t(
      "insights.templates.idle_cash",
      account: "Poupanca", balance: "R$ 30.000,00", idle_days: 60
    )
    assert_equal expected, body
  end
end
