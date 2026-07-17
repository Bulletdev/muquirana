require "test_helper"

class TrendTest < ActiveSupport::TestCase
  test "handles money trend" do
    trend = Trend.new(current: Money.new(100), previous: Money.new(50))
    assert_equal "up", trend.direction
    assert_equal Money.new(50), trend.value
    assert_equal 100.0, trend.percent
  end

  test "up" do
    trend = Trend.new(current: 100, previous: 50)
    assert_equal "up", trend.direction
    assert_equal "var(--color-success)", trend.color
  end

  test "down" do
    trend = Trend.new(current: 50, previous: 100)
    assert_equal "down", trend.direction
    assert_equal "var(--color-destructive)", trend.color
  end

  test "flat" do
    trend1 = Trend.new(current: 100, previous: 100)
    trend2 = Trend.new(current: 100, previous: nil)
    assert_equal "flat", trend1.direction
    assert_equal "up", trend2.direction
    assert_equal "var(--color-gray)", trend1.color
  end

  test "infinitely up" do
    trend = Trend.new(current: 100, previous: 0)
    assert_equal "up", trend.direction
  end

  test "infinitely down" do
    trend = Trend.new(current: 0, previous: 100)
    assert_equal "down", trend.direction
  end

  # Base negativa: o patrimonio ficou menos negativo (-100 -> -50), ou seja,
  # melhorou. A direcao e "up" e o percentual precisa ser positivo. Antes do fix,
  # dividir pela base com sinal (-100) invertia o sinal e dava -50%, contradizendo
  # a seta pra cima.
  test "negative base keeps percent sign aligned with direction (improving)" do
    trend = Trend.new(current: -50, previous: -100)
    assert_equal "up", trend.direction
    assert_equal 50.0, trend.percent
    assert_equal "50.0%", trend.percent_formatted
  end

  # Base negativa piorando: -100 -> -150, direcao "down", percentual negativo.
  test "negative base keeps percent sign aligned with direction (worsening)" do
    trend = Trend.new(current: -150, previous: -100)
    assert_equal "down", trend.direction
    assert_equal(-50.0, trend.percent)
    assert_equal "-50.0%", trend.percent_formatted
  end

  # Base zero com atual positivo: +infinito e "＋∞".
  test "zero base with positive current is positive infinity" do
    trend = Trend.new(current: 100, previous: 0)
    assert_equal "up", trend.direction
    assert_equal Float::INFINITY, trend.percent
    assert_equal "＋∞", trend.percent_formatted
  end

  # Base zero com atual negativo: -infinito e "-∞" (nao "＋∞" como antes do fix).
  test "zero base with negative current is negative infinity" do
    trend = Trend.new(current: -100, previous: 0)
    assert_equal "down", trend.direction
    assert_equal(-Float::INFINITY, trend.percent)
    assert_equal "-∞", trend.percent_formatted
  end

  # Base e atual zero: 0%, sem infinito.
  test "zero base and zero current is zero percent" do
    trend = Trend.new(current: 0, previous: 0)
    assert_equal "flat", trend.direction
    assert_equal 0.0, trend.percent
  end
end
