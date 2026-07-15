class SetBrazilianDefaults < ActiveRecord::Migration[7.2]
  # O locale nao e global: Localize#switch_locale (app/controllers/concerns/
  # localize.rb:11) resolve `Current.family.try(:locale) || I18n.default_locale`.
  # O default_locale do Rails so alcanca quem esta deslogado -- cada familia
  # carrega o proprio locale, moeda, formato de data e pais.
  #
  # Sem esta migration, uma familia nova nasceria em ingles e dolar mesmo com
  # config.i18n.default_locale = :"pt-BR".
  #
  # Apenas defaults de coluna mudam. Registros existentes ficam como estao:
  # trocar a moeda de uma familia com lancamentos nao converte valor nenhum --
  # os mesmos numeros passariam a ser exibidos como reais.
  #
  # Nao alterados de proposito:
  #   balances.currency e security_prices.currency (default "USD") -- sempre
  #     gravados com moeda explicita, vinda da conta ou do provider de cotacao.
  #   imports.number_format -- nao tem default; e obrigatorio e escolhido pelo
  #     usuario. O formato brasileiro ("1.234,56") ja esta em Import::NUMBER_FORMATS.

  def up
    change_column_default :families, :currency, from: "USD", to: "BRL"
    change_column_default :families, :locale, from: "en", to: "pt-BR"
    change_column_default :families, :date_format, from: "%m-%d-%Y", to: "%d/%m/%Y"
    change_column_default :families, :country, from: "US", to: "BR"
    change_column_default :families, :timezone, from: nil, to: "America/Sao_Paulo"

    # Formato de data pre-selecionado ao importar CSV. Extrato de banco
    # brasileiro traz DD/MM/YYYY; o default americano faria 03/07 ser lido como
    # 7 de marco.
    change_column_default :imports, :date_format, from: "%m/%d/%Y", to: "%d/%m/%Y"
  end

  def down
    change_column_default :families, :currency, from: "BRL", to: "USD"
    change_column_default :families, :locale, from: "pt-BR", to: "en"
    change_column_default :families, :date_format, from: "%d/%m/%Y", to: "%m-%d-%Y"
    change_column_default :families, :country, from: "BR", to: "US"
    change_column_default :families, :timezone, from: "America/Sao_Paulo", to: nil
    change_column_default :imports, :date_format, from: "%d/%m/%Y", to: "%m/%d/%Y"
  end
end
