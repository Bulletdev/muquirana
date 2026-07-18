# Materializa/atualiza a Account do dominio para um MercadoBitcoinAccount.
#
# DIFERENCA-CHAVE em relacao ao BinanceAccount::Processor: o Mercado Bitcoin e
# uma exchange brasileira e opera em BRL nativamente. O saldo importado JA esta
# em BRL, entao NAO ha conversao de moeda (sem ExchangeRate, sem stale) -- so
# atribuimos o valor direto. Isso simplifica o processor.
#
# Cria a Account e o vinculo AccountProvider automaticamente (como o
# PlaidAccount::Processor faz), validando a fundacao generica ponta a ponta.
class MercadoBitcoinAccount::Processor
  attr_reader :mercado_bitcoin_account

  def initialize(mercado_bitcoin_account)
    @mercado_bitcoin_account = mercado_bitcoin_account
  end

  def process
    MercadoBitcoinAccount.transaction do
      account = mercado_bitcoin_account.account || build_account

      balance = (mercado_bitcoin_account.current_balance || 0).to_d

      account.assign_attributes(
        accountable: account.accountable || Crypto.new,
        balance: balance,
        cash_balance: 0,
        currency: "BRL"
      )
      account.name = mercado_bitcoin_account.name if account.name.blank?
      account.save!

      # Fundacao generica: garante o join polimorfico
      AccountProvider.find_or_create_by!(
        account: account,
        provider_type: "MercadoBitcoinAccount",
        provider_id: mercado_bitcoin_account.id
      )

      account.set_current_balance(balance)

      account
    end
  end

  private
    def family
      mercado_bitcoin_account.mercado_bitcoin_item.family
    end

    def build_account
      family.accounts.build(
        name: mercado_bitcoin_account.name,
        currency: "BRL",
        accountable: Crypto.new
      )
    end
end
