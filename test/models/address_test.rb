require "test_helper"

class AddressTest < ActiveSupport::TestCase
  # O valor testado aqui E o formato de um locale (address.format), entao cada
  # teste fixa explicitamente o locale cuja convencao esta verificando.
  test "can print a formatted address" do
    address = Address.new(
      line1: "123 Main St",
      locality: "San Francisco",
      region: "CA",
      country: "US",
      postal_code: "94101"
    )

    I18n.with_locale(:en) do
      assert_equal "123 Main St, San Francisco, CA 94101 US", address.to_s
    end
  end

  test "can print a formatted address in pt-BR" do
    address = Address.new(
      line1: "Rua das Flores 100",
      locality: "Campinas",
      region: "SP",
      country: "BR",
      postal_code: "13010001" # coluna e integer, entao nada de mascara/zero a esquerda
    )

    # Convencao brasileira: cidade - estado, depois o CEP
    I18n.with_locale(:"pt-BR") do
      assert_equal "Rua das Flores 100, Campinas - SP, 13010001 BR", address.to_s
    end
  end

  test "can print a formatted address with line2" do
    address = Address.new(
      line1: "123 Main St",
      line2: "Apt 1",
      locality: "San Francisco",
      region: "CA",
      country: "US",
      postal_code: "94101"
    )

    I18n.with_locale(:en) do
      assert_equal "123 Main St Apt 1, San Francisco, CA 94101 US", address.to_s
    end
  end

  test "can print empty when address is empty" do
    address = Address.new(
      line1: nil,
      line2: nil,
      locality: nil,
      region: nil,
      country: nil,
      postal_code: nil
    )

    I18n.with_locale(:en) do
      assert_equal "", address.to_s
    end
  end

  test "can strip extras commas and spaces" do
    address = Address.new(
      line1: "123 Main St ,",
      locality: " San Francisco, ",
    )

    I18n.with_locale(:en) do
      assert_equal "123 Main St, San Francisco", address.to_s
    end
  end
end
