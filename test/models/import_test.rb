require "test_helper"

# US-15: Deteccao de charset no import CSV.
#
# Extratos de banco BR costumam ser exportados em Latin-1 (ISO-8859-1). Sem
# transcodificacao, os acentos quebram no parse ("Ã§" no lugar de "ç"). O
# callback ensure_utf8_encoding detecta o encoding (rchardet) e converte para
# UTF-8 antes do CSV.parse.
class ImportTest < ActiveSupport::TestCase
  setup do
    @import = imports(:transaction)
  end

  test "transcodes a Latin-1 (ISO-8859-1) file to UTF-8 preserving accents" do
    # binread devolve os bytes crus (ASCII-8BIT), como num upload real
    latin1 = file_fixture("imports/transactions_latin1.csv").binread
    refute latin1.dup.force_encoding("UTF-8").valid_encoding?,
      "fixture deveria ter bytes invalidos em UTF-8 (i.e. estar em Latin-1)"

    @import.update!(raw_file_str: latin1)

    stored = @import.reload.raw_file_str
    assert_equal Encoding::UTF_8, stored.encoding
    assert stored.valid_encoding?, "raw_file_str deveria ser UTF-8 valido"
    assert_includes stored, "Padaria Pão de Açúcar"
    assert_includes stored, "Alimentação"
    assert_includes stored, "Farmácia São João"
    assert_includes stored, "Saúde"
    assert_includes stored, "Salário"
  end

  test "parses accented columns correctly after Latin-1 import" do
    latin1 = file_fixture("imports/transactions_latin1.csv").binread
    @import.update!(raw_file_str: latin1)

    rows = @import.reload.send(:parsed_csv)
    assert_equal "Padaria Pão de Açúcar", rows[0]["name"]
    assert_equal "Alimentação", rows[0]["category"]
    assert_equal "Saúde", rows[1]["category"]
  end

  test "leaves a valid UTF-8 file untouched" do
    utf8 = file_fixture("imports/transactions_utf8.csv").read
    assert_equal Encoding::UTF_8, utf8.encoding
    assert utf8.valid_encoding?

    @import.update!(raw_file_str: utf8)

    stored = @import.reload.raw_file_str
    assert_equal Encoding::UTF_8, stored.encoding
    assert stored.valid_encoding?
    assert_includes stored, "Padaria Pão de Açúcar"
    assert_includes stored, "Alimentação"
    # Conteudo identico ao original (nenhuma substituicao de bytes)
    assert_equal utf8, stored
  end

  test "handles nil and empty raw_file_str without error" do
    assert_nothing_raised do
      @import.update!(raw_file_str: nil)
      @import.update!(raw_file_str: "")
    end
  end
end
