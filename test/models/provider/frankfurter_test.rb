require "test_helper"

class Provider::FrankfurterTest < ActiveSupport::TestCase
  setup do
    @provider = Provider::Frankfurter.new
  end

  test "busca cotacao unica" do
    VCR.use_cassette("frankfurter/exchange_rate") do
      response = @provider.fetch_exchange_rate(from: "USD", to: "BRL", date: Date.parse("2024-01-15"))

      assert response.success?
      rate = response.data
      assert_equal "USD", rate.from
      assert_equal "BRL", rate.to
      assert rate.date.is_a?(Date)
      assert rate.rate.positive?
    end
  end

  test "busca o historico como intervalo" do
    VCR.use_cassette("frankfurter/exchange_rates") do
      response = @provider.fetch_exchange_rates(
        from: "EUR", to: "BRL",
        start_date: Date.parse("2024-01-01"), end_date: Date.parse("2024-01-31")
      )

      assert response.success?
      rates = response.data

      # O endpoint de range da v2 preenche fim de semana e feriado do lado do
      # servidor (carrega a ultima cotacao), entao vem uma cotacao por dia
      # CORRIDO -- 31 em janeiro -- em ordem e todas EUR->BRL.
      assert_equal 31, rates.count
      assert_equal rates, rates.sort_by(&:date)
      assert_equal Date.parse("2024-01-01"), rates.first.date
      assert_equal Date.parse("2024-01-31"), rates.last.date
      assert rates.all? { |r| r.from == "EUR" && r.to == "BRL" }
    end
  end

  # Mesma moeda nao chama a API (cotacao e 1 por definicao). Sem cassette de
  # proposito: se isto tocasse a rede, seria bug.
  test "mesma moeda vale 1 sem tocar a rede" do
    response = @provider.fetch_exchange_rate(from: "BRL", to: "BRL", date: Date.current)

    assert response.success?
    assert_equal 1.0, response.data.rate
  end

  test "mesma moeda no intervalo vale 1 em cada dia" do
    response = @provider.fetch_exchange_rates(
      from: "BRL", to: "BRL",
      start_date: Date.parse("2024-01-01"), end_date: Date.parse("2024-01-05")
    )

    assert response.success?
    assert_equal 5, response.data.count
    assert response.data.all? { |r| r.rate == 1.0 }
  end

  # from/to vao no PATH da URL. Sanitizar impede que lixo vire parte da rota.
  test "sanitiza o codigo de moeda" do
    assert_equal "USD", @provider.send(:sanitize_currency, "usd")
    assert_equal "BRL", @provider.send(:sanitize_currency, "b/r?l")
    assert_equal "USD", @provider.send(:sanitize_currency, "USD ")
  end

  # O provider e sempre disponivel (sem chave) e vem antes do Synth morto.
  test "o registry prefere o Frankfurter para cambio" do
    registry = Provider::Registry.for_concept(:exchange_rates)

    assert_instance_of Provider::Frankfurter, registry.get_provider(:frankfurter)
    assert_instance_of Provider::Frankfurter, ExchangeRate.send(:provider)
  end
end
