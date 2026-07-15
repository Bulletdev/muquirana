require "test_helper"

class Valuation::NameTest < ActiveSupport::TestCase
  # Afirma pela CHAVE, nao pelo texto.
  #
  # O que este objeto faz e mapear (tipo de lancamento, tipo de conta) -> nome.
  # Fixar "Original purchase price" no assert testava, de quebra, o idioma da
  # app: com default_locale = pt-BR os 21 testes quebraram sem que o mapeamento
  # tivesse mudado. A chave testa o mapeamento; a traducao e verificada pelo
  # i18n-tasks e pela paridade dos locales.
  # Opening anchor tests
  test "generates opening anchor name for Property" do
    name = Valuation::Name.new("opening_anchor", "Property")
    assert_equal I18n.t("valuations.names.opening_anchor.asset"), name.to_s
  end

  test "generates opening anchor name for Loan" do
    name = Valuation::Name.new("opening_anchor", "Loan")
    assert_equal I18n.t("valuations.names.opening_anchor.loan"), name.to_s
  end

  test "generates opening anchor name for Investment" do
    name = Valuation::Name.new("opening_anchor", "Investment")
    assert_equal I18n.t("valuations.names.opening_anchor.account_value"), name.to_s
  end

  test "generates opening anchor name for Vehicle" do
    name = Valuation::Name.new("opening_anchor", "Vehicle")
    assert_equal I18n.t("valuations.names.opening_anchor.asset"), name.to_s
  end

  test "generates opening anchor name for Crypto" do
    name = Valuation::Name.new("opening_anchor", "Crypto")
    assert_equal I18n.t("valuations.names.opening_anchor.account_value"), name.to_s
  end

  test "generates opening anchor name for OtherAsset" do
    name = Valuation::Name.new("opening_anchor", "OtherAsset")
    assert_equal I18n.t("valuations.names.opening_anchor.account_value"), name.to_s
  end

  test "generates opening anchor name for other account types" do
    name = Valuation::Name.new("opening_anchor", "Depository")
    assert_equal I18n.t("valuations.names.opening_anchor.default"), name.to_s
  end

  # Current anchor tests
  test "generates current anchor name for Property" do
    name = Valuation::Name.new("current_anchor", "Property")
    assert_equal I18n.t("valuations.names.current_anchor.asset"), name.to_s
  end

  test "generates current anchor name for Loan" do
    name = Valuation::Name.new("current_anchor", "Loan")
    assert_equal I18n.t("valuations.names.current_anchor.loan"), name.to_s
  end

  test "generates current anchor name for Investment" do
    name = Valuation::Name.new("current_anchor", "Investment")
    assert_equal I18n.t("valuations.names.current_anchor.account_value"), name.to_s
  end

  test "generates current anchor name for Vehicle" do
    name = Valuation::Name.new("current_anchor", "Vehicle")
    assert_equal I18n.t("valuations.names.current_anchor.asset"), name.to_s
  end

  test "generates current anchor name for Crypto" do
    name = Valuation::Name.new("current_anchor", "Crypto")
    assert_equal I18n.t("valuations.names.current_anchor.account_value"), name.to_s
  end

  test "generates current anchor name for OtherAsset" do
    name = Valuation::Name.new("current_anchor", "OtherAsset")
    assert_equal I18n.t("valuations.names.current_anchor.account_value"), name.to_s
  end

  test "generates current anchor name for other account types" do
    name = Valuation::Name.new("current_anchor", "Depository")
    assert_equal I18n.t("valuations.names.current_anchor.default"), name.to_s
  end

  # Reconciliation tests
  test "generates recon name for Property" do
    name = Valuation::Name.new("reconciliation", "Property")
    assert_equal I18n.t("valuations.names.recon.value"), name.to_s
  end

  test "generates recon name for Investment" do
    name = Valuation::Name.new("reconciliation", "Investment")
    assert_equal I18n.t("valuations.names.recon.value"), name.to_s
  end

  test "generates recon name for Vehicle" do
    name = Valuation::Name.new("reconciliation", "Vehicle")
    assert_equal I18n.t("valuations.names.recon.value"), name.to_s
  end

  test "generates recon name for Crypto" do
    name = Valuation::Name.new("reconciliation", "Crypto")
    assert_equal I18n.t("valuations.names.recon.value"), name.to_s
  end

  test "generates recon name for OtherAsset" do
    name = Valuation::Name.new("reconciliation", "OtherAsset")
    assert_equal I18n.t("valuations.names.recon.value"), name.to_s
  end

  test "generates recon name for Loan" do
    name = Valuation::Name.new("reconciliation", "Loan")
    assert_equal I18n.t("valuations.names.recon.loan"), name.to_s
  end

  test "generates recon name for other account types" do
    name = Valuation::Name.new("reconciliation", "Depository")
    assert_equal I18n.t("valuations.names.recon.default"), name.to_s
  end
end
