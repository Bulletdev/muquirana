# Baixa o extrato Flex da IBKR, parseia com IbkrItem::ReportParser e materializa
# um IbkrAccount por conta do extrato (a Flex Query pode cobrir varias contas).
#
# Aqui so guardamos os dados crus (posicoes/trades/caixa) nos IbkrAccounts; a
# conversao multi-moeda -> BRL e a criacao de Holdings/Trades acontecem depois,
# no IbkrAccount::Processor.
class IbkrItem::Importer
  attr_reader :ibkr_item, :ibkr_provider

  def initialize(ibkr_item, ibkr_provider:)
    @ibkr_item = ibkr_item
    @ibkr_provider = ibkr_provider
  end

  def import
    raise Provider::IbkrFlex::ConfigurationError, "Credenciais da IBKR nao configuradas" unless ibkr_provider

    xml_body = ibkr_provider.download_statement
    parsed = IbkrItem::ReportParser.new(xml_body).parse

    accounts_imported = 0
    ibkr_item.transaction do
      ibkr_item.upsert_ibkr_snapshot!(parsed[:metadata].merge("imported_at" => Time.current.iso8601))

      parsed[:accounts].each do |account_data|
        next if account_data[:ibkr_account_id].blank?

        ibkr_account = ibkr_item.ibkr_accounts.find_or_initialize_by(ibkr_account_id: account_data[:ibkr_account_id])
        ibkr_account.upsert_from_ibkr_statement!(account_data)
        accounts_imported += 1
      end
    end

    { success: true, accounts_imported: accounts_imported }
  end
end
