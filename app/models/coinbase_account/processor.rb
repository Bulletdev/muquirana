# Materializa/atualiza a Account do dominio para um CoinbaseAccount e -- coracao
# do escopo -- cria os Holdings de cada cripto em BRL (via HoldingsProcessor) e
# faz o saldo da conta refletir a soma desses holdings.
#
# Diferente do Binance/Mercado Bitcoin (que gravam so um saldo agregado), o
# Coinbase gera HOLDINGS por cripto (Holding + Security::Resolver, padrao
# CRYPTO:<codigo>). Como Crypto e conta de tipo :investment, o saldo = caixa +
# holdings; aqui caixa e 0 e o saldo total vem dos holdings.
#
# Cria a Account e o vinculo AccountProvider automaticamente (como o
# PlaidAccount::Processor faz), validando a fundacao generica ponta a ponta.
class CoinbaseAccount::Processor
  attr_reader :coinbase_account

  def initialize(coinbase_account)
    @coinbase_account = coinbase_account
  end

  def process
    CoinbaseAccount.transaction do
      account = coinbase_account.account || build_account

      # Persiste a conta antes dos holdings (holdings pertencem a account).
      account.assign_attributes(
        accountable: account.accountable || Crypto.new,
        cash_balance: 0,
        currency: family.currency
      )
      account.name = coinbase_account.name if account.name.blank?
      account.balance ||= 0
      account.save!

      # Fundacao generica: garante o join polimorfico
      AccountProvider.find_or_create_by!(
        account: account,
        provider_type: "CoinbaseAccount",
        provider_id: coinbase_account.id
      )

      # Cria/atualiza os Holdings (um por cripto) em BRL. Passamos a account
      # explicitamente: a associacao coinbase_account.account foi memoizada como
      # nil antes de criarmos o AccountProvider agora.
      CoinbaseAccount::HoldingsProcessor.new(coinbase_account, account: account).process

      # Saldo total = soma dos holdings de hoje (ja em BRL / moeda da familia)
      total = account.holdings
        .where(date: Date.current, currency: family.currency)
        .sum(:amount)

      account.update!(balance: total, cash_balance: 0)
      account.set_current_balance(total)

      account
    end
  end

  private
    def family
      coinbase_account.coinbase_item.family
    end

    def build_account
      family.accounts.build(
        name: coinbase_account.name,
        currency: family.currency,
        balance: 0,
        accountable: Crypto.new
      )
    end
end
