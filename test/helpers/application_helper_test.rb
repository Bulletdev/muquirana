require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "#title(page_title)" do
    title("Test Title")
    assert_equal "Test Title", content_for(:title)
  end

  test "#header_title(page_title)" do
    header_title("Test Header Title")
    assert_equal "Test Header Title", content_for(:header_title)
  end

  def setup
    @account1 = Account.new(currency: "USD", balance: 1)
    @account2 = Account.new(currency: "USD", balance: 2)
    @account3 = Account.new(currency: "EUR", balance: -7)
  end

  # Locale explicito: o helper formata via Money, que depende de I18n.locale
  # para EUR (ver Money::Formatting#locale_options). O default do app e pt-BR,
  # onde o euro sai como €7,00 em vez de €7.00.
  test "#totals_by_currency(collection: collection, money_method: money_method)" do
    I18n.with_locale(:en) do
      assert_equal "$3.00", totals_by_currency(collection: [ @account1, @account2 ], money_method: :balance_money)
      assert_equal "$3.00 | -€7.00", totals_by_currency(collection: [ @account1, @account2, @account3 ], money_method: :balance_money)
      assert_equal "", totals_by_currency(collection: [], money_method: :balance_money)
      assert_equal "$0.00", totals_by_currency(collection: [ Account.new(currency: "USD", balance: 0) ], money_method: :balance_money)
      assert_equal "-$3.00 | €7.00", totals_by_currency(collection: [ @account1, @account2, @account3 ], money_method: :balance_money, negate: true)
    end
  end

  test "#totals_by_currency formats in pt-BR" do
    I18n.with_locale(:"pt-BR") do
      assert_equal "$3.00 | -€7,00", totals_by_currency(collection: [ @account1, @account2, @account3 ], money_method: :balance_money)
    end
  end
end
