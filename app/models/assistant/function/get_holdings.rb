class Assistant::Function::GetHoldings < Assistant::Function
  include Pagy::Backend

  SUPPORTED_ACCOUNT_TYPES = %w[Investment Crypto].freeze

  class << self
    def default_page_size
      50
    end

    def name
      "get_holdings"
    end

    def description
      <<~INSTRUCTIONS
        Use para consultar as posicoes de investimento (holdings) do usuario usando
        filtros opcionais.

        Esta funcao e otima para:
        - Encontrar posicoes ou ativos especificos
        - Ver a composicao e a alocacao da carteira
        - Ver o valor investido e o custo medio

        Observacao: esta funcao retorna apenas posicoes de contas do tipo Investment e Crypto.

        Sobre paginacao:

        Esta funcao pode ser paginada. Espere as seguintes propriedades na resposta:

        - `total_pages`: numero total de paginas de resultados
        - `page`: pagina atual
        - `page_size`: itens por pagina (sempre #{default_page_size})
        - `total_results`: total de resultados para os filtros informados
        - `total_value`: valor total de todas as posicoes para os filtros informados

        Exemplo simples (todas as posicoes atuais):

        ```
        get_holdings({
          page: 1
        })
        ```

        Exemplo com filtros:

        ```
        get_holdings({
          page: 1,
          accounts: ["Corretora"],
          securities: ["AAPL", "GOOGL"]
        })
        ```
      INSTRUCTIONS
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      required: [ "page" ],
      properties: {
        page: {
          type: "integer",
          description: "Numero da pagina"
        },
        accounts: {
          type: "array",
          description: "Filtra posicoes por nome da conta (apenas contas Investment e Crypto)",
          items: { enum: investment_account_names },
          minItems: 1,
          uniqueItems: true
        },
        securities: {
          type: "array",
          description: "Filtra posicoes pelo ticker do ativo",
          items: { enum: family_security_tickers },
          minItems: 1,
          uniqueItems: true
        }
      }
    )
  end

  def call(params = {})
    holdings_query = build_holdings_query(params)

    pagy, paginated_holdings = pagy(
      holdings_query.includes(:security, :account).order(amount: :desc),
      page: params["page"] || 1,
      limit: default_page_size
    )

    total_value = holdings_query.sum(:amount)

    normalized_holdings = paginated_holdings.map do |holding|
      avg_cost = holding.avg_cost
      {
        ticker: holding.ticker,
        name: holding.name,
        quantity: holding.qty.to_f,
        price: holding.price.to_f,
        currency: holding.currency,
        amount: holding.amount.to_f,
        formatted_amount: holding.amount_money.format,
        weight: holding.weight&.round(2),
        average_cost: avg_cost&.amount&.to_f,
        formatted_average_cost: avg_cost&.format,
        account: holding.account.name,
        date: holding.date
      }
    end

    {
      holdings: normalized_holdings,
      total_results: pagy.count,
      page: pagy.page,
      page_size: default_page_size,
      total_pages: pagy.pages,
      total_value: Money.new(total_value, family.currency).format
    }
  end

  private
    def default_page_size
      self.class.default_page_size
    end

    def build_holdings_query(params)
      accounts = investment_accounts

      if params["accounts"].present?
        accounts = accounts.where(name: params["accounts"])
      end

      holdings = Holding.where(account: accounts)
        .where(
          id: Holding.where(account: accounts)
            .select("DISTINCT ON (account_id, security_id) id")
            .where.not(qty: 0)
            .order(:account_id, :security_id, date: :desc)
        )

      if params["securities"].present?
        security_ids = Security.where(ticker: params["securities"]).pluck(:id)
        holdings = holdings.where(security_id: security_ids)
      end

      holdings
    end

    def investment_accounts
      family.accounts.visible.where(accountable_type: SUPPORTED_ACCOUNT_TYPES)
    end

    def investment_account_names
      @investment_account_names ||= investment_accounts.pluck(:name)
    end

    def family_security_tickers
      @family_security_tickers ||= Security
        .where(id: Holding.where(account_id: investment_accounts.select(:id)).select(:security_id))
        .distinct
        .pluck(:ticker)
    end
end
