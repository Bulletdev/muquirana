require "test_helper"
require "ostruct"

class MoneyTest < ActiveSupport::TestCase
  test "can create with default currency" do
    value = Money.new(1000)
    assert_equal 1000, value.amount
  end

  test "can create with custom currency" do
    value1 = Money.new(1000, :EUR)
    value2 = Money.new(1000, :eur)
    value3 = Money.new(1000, "eur")
    value4 = Money.new(1000, "EUR")

    assert_equal value1.currency.iso_code, value2.currency.iso_code
    assert_equal value2.currency.iso_code, value3.currency.iso_code
    assert_equal value3.currency.iso_code, value4.currency.iso_code
  end

  test "equality tests amount and currency" do
    assert_equal Money.new(1000), Money.new(1000)
    assert_not_equal Money.new(1000), Money.new(1001)
    assert_not_equal Money.new(1000, :usd), Money.new(1000, :eur)
  end

  test "can compare with zero Numeric" do
    assert_equal Money.new(0), 0
    assert_raises(TypeError) { Money.new(1) == 1 }
  end

  test "can negate" do
    assert_equal (-Money.new(1000)), Money.new(-1000)
  end

  test "can use comparison operators" do
    assert_operator Money.new(1000), :>, Money.new(999)
    assert_operator Money.new(1000), :>=, Money.new(1000)
    assert_operator Money.new(1000), :<, Money.new(1001)
    assert_operator Money.new(1000), :<=, Money.new(1000)
  end

  test "can add and subtract" do
    assert_equal Money.new(1000) + Money.new(1000), Money.new(2000)
    assert_equal Money.new(1000) + 1000, Money.new(2000)
    assert_equal Money.new(1000) - Money.new(1000), Money.new(0)
    assert_equal Money.new(1000) - 1000, Money.new(0)
  end

  test "can multiply" do
    assert_equal Money.new(1000) * 2, Money.new(2000)
    assert_raises(TypeError) { Money.new(1000) * Money.new(2) }
  end

  test "can divide" do
    assert_equal Money.new(1000) / 2, Money.new(500)
    assert_equal Money.new(1000) / Money.new(500), 2
    assert_raise(TypeError) { 1000 / Money.new(2) }
  end

  test "operator order does not matter" do
    assert_equal Money.new(1000) + 1000, 1000 + Money.new(1000)
    assert_equal Money.new(1000) - 1000, 1000 - Money.new(1000)
    assert_equal Money.new(1000) * 2, 2 * Money.new(1000)
  end

  test "can get absolute value" do
    assert_equal Money.new(1000).abs, Money.new(1000)
    assert_equal Money.new(-1000).abs, Money.new(1000)
  end

  test "can test if zero" do
    assert Money.new(0).zero?
    assert_not Money.new(1000).zero?
  end

  test "can test if negative" do
    assert Money.new(-1000).negative?
    assert_not Money.new(1000).negative?
  end

  test "can test if positive" do
    assert Money.new(1000).positive?
    assert_not Money.new(-1000).positive?
  end

  # Money#format depende de I18n.locale (ver Money::Formatting#locale_options),
  # entao cada caso e explicito sobre o locale em vez de herdar o default do app.
  #
  # O caso original passava locale: :nl, que agora levanta I18n::InvalidLocale:
  # number_to_currency valida o locale contra available_locales, e o holandes
  # deixou de ser suportado. O branch [:"EUR", :nl] de locale_options ficou
  # inalcancavel, assim como [:"EUR", :pt] -- pt-BR nao e :pt.
  test "can format" do
    assert_equal "$1,000.90", Money.new(1000.899).to_s
  end

  # BRL e USD nao tem override em locale_options: usam os separadores da propria
  # moeda (config/currencies.yml) e por isso saem iguais em qualquer locale.
  test "formats currency by the currency's own separators" do
    [ :en, :"pt-BR" ].each do |locale|
      I18n.with_locale(locale) do
        assert_equal "R$1.000,12", Money.new(1000.12, :brl).to_s, "BRL em #{locale}"
        assert_equal "$1,000.12", Money.new(1000.12, :usd).to_s, "USD em #{locale}"
      end
    end
  end

  # EUR TEM override em locale_options, mas apenas para :en/:en_IE (estilo
  # americano) e :nl/:pt (estilo europeu). pt-BR nao esta na lista e cai no else,
  # usando os separadores do EUR -- que e o resultado correto: brasileiro escreve
  # euro com "." de milhar e "," de decimal, igual ao europeu.
  test "formats EUR according to locale" do
    assert_equal "€1,000.12", Money.new(1000.12, :eur).format(locale: :en)
    assert_equal "€1.000,12", Money.new(1000.12, :eur).format(locale: :"pt-BR")
  end

  test "converts currency when rate available" do
    ExchangeRate.expects(:find_or_fetch_rate).returns(OpenStruct.new(rate: 1.2))

    assert_equal Money.new(1000).exchange_to(:eur), Money.new(1000 * 1.2, :eur)
  end

  test "raises when no conversion rate available and no fallback rate provided" do
    ExchangeRate.expects(:find_or_fetch_rate).returns(nil)

    assert_raises Money::ConversionError do
      Money.new(1000).exchange_to(:jpy)
    end
  end

  test "converts currency with a fallback rate" do
    ExchangeRate.expects(:find_or_fetch_rate).returns(nil).twice

    assert_equal 0, Money.new(1000).exchange_to(:jpy, fallback_rate: 0)
    assert_equal Money.new(1000, :jpy), Money.new(1000, :usd).exchange_to(:jpy, fallback_rate: 1)
  end
end
