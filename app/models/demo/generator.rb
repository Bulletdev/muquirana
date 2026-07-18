class Demo::Generator
  # @param seed [Integer, String, nil] Seed value used to initialise the internal PRNG. If nil, the ENV variable DEMO_DATA_SEED will
  #   be honoured and default to a random seed when not present.
  #
  # Initialising an explicit PRNG gives us repeatable demo datasets while still
  #   allowing truly random data when the caller does not care about
  #   determinism.  The global `Kernel.rand` and helpers like `Array#sample`
  #   will also be seeded so that *all* random behaviour inside this object -
  #   including library helpers that rely on Ruby's global RNG - follow the
  #   same deterministic sequence.
  def initialize(seed: ENV.fetch("DEMO_DATA_SEED", nil))
    # Convert the seed to an Integer if one was provided, otherwise fall back
    # to a random, but memoised, seed so the generator instance can report it
    # back to callers when needed (e.g. for debugging a specific run).
    @seed = seed.present? ? seed.to_i : Random.new_seed

    # Internal PRNG instance - use this instead of the global RNG wherever we
    # explicitly call `rand` inside the class.  We override `rand` below so
    # existing method bodies automatically delegate here without requiring
    # widespread refactors.
    @rng = Random.new(@seed)

    # Also seed Ruby's global RNG so helpers that rely on it (e.g.
    # Array#sample, Kernel.rand in invoked libraries, etc.) remain
    # deterministic for the lifetime of this generator instance.
    srand(@seed)
  end

  # Expose the seed so callers can reproduce a run if necessary.
  attr_reader :seed

  # Generate empty family - no financial data
  def generate_empty_data!(skip_clear: false)
    with_timing(__method__) do
      unless skip_clear
        puts "Clearing existing data..."
        clear_all_data!
      end

      puts "Creating empty family..."
      create_family_and_users!(demo_family_name, "user@muquirana.local", onboarded: true, subscribed: true)

      puts "Empty demo data loaded successfully!"
    end
  end

  # Generate new user family - no financial data, needs onboarding
  def generate_new_user_data!(skip_clear: false)
    with_timing(__method__) do
      unless skip_clear
        puts "Clearing existing data..."
        clear_all_data!
      end

      puts "Creating new user family..."
      create_family_and_users!(demo_family_name, "user@muquirana.local", onboarded: false, subscribed: false)

      puts "New user demo data loaded successfully!"
    end
  end

  # Generate comprehensive realistic demo data with multi-currency
  def generate_default_data!(skip_clear: false, email: "user@muquirana.local")
    if skip_clear
      puts "⏭ Skipping data clearing (appending new family)..."
    else
      puts "Clearing existing data..."
      clear_all_data!
    end

    with_timing(__method__, max_seconds: 1000) do
      puts "Creating demo family..."
      family = create_family_and_users!(demo_family_name, email, onboarded: true, subscribed: true)

      puts "Creating realistic financial data..."
      create_realistic_categories!(family)
      create_realistic_accounts!(family)
      create_realistic_transactions!(family)
      # Auto-fill current-month budget based on recent spending averages
      generate_budget_auto_fill!(family)

      puts "Realistic demo data loaded successfully!"
    end
  end

  private

    # Simple timing helper. Pass a descriptive label and a block; the runtime
    # will be printed automatically when the block completes.
    # If max_seconds is provided, raise RuntimeError when the block exceeds that
    # duration.  Useful to keep CI/dev machines honest about demo-data perf.
    def with_timing(label, max_seconds: nil)
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = yield
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      puts "⏱ #{label} completed in #{duration.round(2)}s"

      if max_seconds && duration > max_seconds
        raise "Demo::Generator ##{label} exceeded #{max_seconds}s (#{duration.round(2)}s)"
      end

      result
    end

    # Override Kernel#rand so *all* `rand` calls inside this instance (including
    # those already present in the file) are routed through the seeded PRNG.
    def rand(*args)
      @rng.rand(*args)
    end



    def clear_all_data!
      family_count = Family.count
      if family_count > 50
        raise "Too much data to clear efficiently (#{family_count} families). Run 'rails db:reset' instead."
      end
      Demo::DataCleaner.new.destroy_everything!
    end

    # Nome da familia da demo. Env-configuravel; default pt-BR apresentavel.
    def demo_family_name
      ENV["DEMO_FAMILY_NAME"].presence || "Família Souza"
    end

    def create_family_and_users!(family_name, email, onboarded:, subscribed:)
      # Sem argumentos de locale/moeda: a familia herda os defaults da tabela
      # (BRL, pt-BR, %d/%m/%Y, BR, America/Sao_Paulo), definidos na migration
      # SetBrazilianDefaults. Antes estavam fixos em USD/en/US/America/New_York,
      # o que faria o seed produzir uma familia americana mesmo com os defaults
      # brasileiros -- e o app abriria em dolar na primeira execucao.
      family = Family.create!(name: family_name)

      family.start_subscription!("sub_demo_123") if subscribed

      # Nomes configuraveis por env. O default e apresentavel em pt-BR (a demo
      # publica nao pode dizer "Demo (admin) Muquirana" numa gravacao); e o
      # DEMO_ADMIN_NAME permite personalizar sem editar a UI a cada reset --
      # util para gravar um video com um nome proprio.
      admin_name = ENV["DEMO_ADMIN_NAME"].presence || "Ana Souza"
      admin_first, admin_last = admin_name.split(" ", 2)

      # Admin user
      family.users.create!(
        email: email,
        first_name: admin_first,
        last_name: admin_last.presence || "",
        role: "admin",
        password: "password",
        onboarded_at: onboarded ? Time.current : nil
      )

      # Member user
      family.users.create!(
        email: "partner_#{email}",
        first_name: "Bruno",
        last_name: admin_last.presence || "Souza",
        role: "member",
        password: "password",
        onboarded_at: onboarded ? Time.current : nil
      )

      family
    end

    def create_realistic_categories!(family)
      # Income categories (3 total)
      @salary_cat = family.categories.create!(name: "Salário", color: "#10b981", classification: "income")
      @freelance_cat = family.categories.create!(name: "Freelance", color: "#059669", classification: "income")
      @investment_income_cat = family.categories.create!(name: "Rendimentos", color: "#047857", classification: "income")

      # Expense categories with subcategories (12 total)
      @housing_cat = family.categories.create!(name: "Moradia", color: "#dc2626", classification: "expense")
      @rent_cat = family.categories.create!(name: "Aluguel/Financiamento", parent: @housing_cat, color: "#b91c1c", classification: "expense")
      @utilities_cat = family.categories.create!(name: "Contas de casa", parent: @housing_cat, color: "#991b1b", classification: "expense")

      @food_cat = family.categories.create!(name: "Alimentação", color: "#ea580c", classification: "expense")
      @groceries_cat = family.categories.create!(name: "Mercado", parent: @food_cat, color: "#c2410c", classification: "expense")
      @restaurants_cat = family.categories.create!(name: "Restaurantes", parent: @food_cat, color: "#9a3412", classification: "expense")
      @coffee_cat = family.categories.create!(name: "Café e delivery", parent: @food_cat, color: "#7c2d12", classification: "expense")

      @transportation_cat = family.categories.create!(name: "Transporte", color: "#2563eb", classification: "expense")
      @gas_cat = family.categories.create!(name: "Combustível", parent: @transportation_cat, color: "#1d4ed8", classification: "expense")
      @car_payment_cat = family.categories.create!(name: "Prestação do carro", parent: @transportation_cat, color: "#1e40af", classification: "expense")

      @entertainment_cat = family.categories.create!(name: "Lazer", color: "#7c3aed", classification: "expense")
      @healthcare_cat = family.categories.create!(name: "Saúde", color: "#db2777", classification: "expense")
      @shopping_cat = family.categories.create!(name: "Compras", color: "#059669", classification: "expense")
      @travel_cat = family.categories.create!(name: "Viagem", color: "#0891b2", classification: "expense")
      @personal_care_cat = family.categories.create!(name: "Cuidados pessoais", color: "#be185d", classification: "expense")

      # Additional high-level expense categories to reach 13 top-level items
      @insurance_cat = family.categories.create!(name: "Seguros", color: "#6366f1", classification: "expense")
      @misc_cat      = family.categories.create!(name: "Diversos", color: "#6b7280", classification: "expense")

      # Interest expense bucket
      @interest_cat = family.categories.create!(name: "Juros de empréstimo", color: "#475569", classification: "expense")
    end

    def create_realistic_accounts!(family)
      # Contas correntes (moeda da familia)
      @chase_checking = family.accounts.create!(accountable: Depository.new, name: "Nubank Conta", balance: 0, currency: "BRL")
      @ally_checking = family.accounts.create!(accountable: Depository.new, name: "Inter Conta Corrente", balance: 0, currency: "BRL")

      # Poupanca (moeda da familia)
      @marcus_savings = family.accounts.create!(accountable: Depository.new, name: "Poupança Caixa", balance: 0, currency: "BRL")

      # Conta em moeda estrangeira (EUR) - vitrine de multi-moeda
      @eu_checking = family.accounts.create!(accountable: Depository.new, name: "Conta em Euro (Wise)", balance: 0, currency: "EUR")

      # Cartoes de credito (moeda da familia)
      @amex_gold = family.accounts.create!(accountable: CreditCard.new, name: "Cartão Nubank", balance: 0, currency: "BRL")
      @chase_sapphire = family.accounts.create!(accountable: CreditCard.new, name: "Cartão Itaú", balance: 0, currency: "BRL")

      # Contas de investimento (moeda da familia + GBP no exterior)
      @vanguard_401k     = family.accounts.create!(accountable: Investment.new, name: "Previdência PGBL", balance: 0, currency: "BRL")
      @schwab_brokerage  = family.accounts.create!(accountable: Investment.new, name: "Corretora XP", balance: 0, currency: "BRL")
      @fidelity_roth_ira = family.accounts.create!(accountable: Investment.new, name: "Previdência VGBL", balance: 0, currency: "BRL")
      @hsa_investment    = family.accounts.create!(accountable: Investment.new, name: "Fundo de Reserva", balance: 0, currency: "BRL")
      @uk_isa           = family.accounts.create!(accountable: Investment.new, name: "Conta no Exterior", balance: 0, currency: "GBP")

      # Imoveis (moeda da familia)
      @home = family.accounts.create!(accountable: Property.new, name: "Casa própria", balance: 0, currency: "BRL")

      # Veiculos (moeda da familia)
      @honda_accord = family.accounts.create!(accountable: Vehicle.new, name: "Honda Civic 2019", balance: 0, currency: "BRL")
      @tesla_model3 = family.accounts.create!(accountable: Vehicle.new, name: "Toyota Corolla 2022", balance: 0, currency: "BRL")

      # Cripto (moeda da familia)
      @coinbase_usdc = family.accounts.create!(accountable: Crypto.new, name: "Binance USDC", balance: 0, currency: "BRL")

      # Emprestimos / passivos (moeda da familia)
      @mortgage      = family.accounts.create!(accountable: Loan.new, name: "Financiamento do imóvel", balance: 0, currency: "BRL")
      @car_loan      = family.accounts.create!(accountable: Loan.new, name: "Financiamento do carro", balance: 0, currency: "BRL")
      @student_loan  = family.accounts.create!(accountable: Loan.new, name: "FIES", balance: 0, currency: "BRL")

      @personal_loc  = family.accounts.create!(accountable: OtherLiability.new, name: "Cheque especial", balance: 0, currency: "BRL")

      # Outro ativo (moeda da familia)
      @jewelry = family.accounts.create!(accountable: OtherAsset.new, name: "Coleção de joias", balance: 0, currency: "BRL")
    end

    def create_realistic_transactions!(family)
      load_securities!

      puts "   Generating salary history (12 years)..."
      generate_salary_history!

      puts "   Generating housing transactions..."
      generate_housing_transactions!

      puts "   Generating food & dining transactions..."
      generate_food_transactions!

      puts "   Generating transportation transactions..."
      generate_transportation_transactions!

      puts "   Generating entertainment transactions..."
      generate_entertainment_transactions!

      puts "   Generating shopping transactions..."
      generate_shopping_transactions!

      puts "   Generating healthcare transactions..."
      generate_healthcare_transactions!

      puts "   Generating travel transactions..."
      generate_travel_transactions!

      puts "   Generating personal care transactions..."
      generate_personal_care_transactions!

      puts "   Generating investment transactions..."
      generate_investment_transactions!

      puts "   Generating major purchases..."
      generate_major_purchases!

      puts "   Generating transfers and payments..."
      generate_transfers_and_payments!

      puts "   Generating loan payments..."
      generate_loan_payments!

      puts "   Generating regular expense baseline..."
      generate_regular_expenses!

      puts "    Generating legacy historical data..."
      generate_legacy_transactions!

      puts "   Generating crypto & misc asset transactions..."
      generate_crypto_and_misc_assets!

      puts "   Reconciling balances to target snapshot..."
      reconcile_balances!(family)

      puts "   Generated approximately #{Entry.joins(:account).where(accounts: { family_id: family.id }).count} transactions"

      puts "Final sync to calculate adjusted balances..."
      sync_family_accounts!(family)
    end

    # Auto-fill current-month budget based on recent spending averages
    def generate_budget_auto_fill!(family)
      current_month   = Date.current.beginning_of_month
      analysis_start  = (current_month - 3.months).beginning_of_month
      analysis_period = analysis_start..(current_month - 1.day)

      # Fetch expense transactions in the analysis period
      txns = Entry.joins("INNER JOIN transactions ON transactions.id = entries.entryable_id")
                  .joins("INNER JOIN categories ON categories.id = transactions.category_id")
                  .where(entries: { entryable_type: "Transaction", date: analysis_period })
                  .where(categories: { classification: "expense" })

      spend_per_cat = txns.group("categories.id").sum("entries.amount")

      budget = family.budgets.where(start_date: current_month).first_or_initialize
      budget.update!(
        end_date: current_month.end_of_month,
        currency: family.currency,
        budgeted_spending: spend_per_cat.values.sum / 3.0, # placeholder, refine below
        expected_income: 0 # Could compute similarly if desired
      )

      spend_per_cat.each do |cat_id, total|
        avg = total / 3.0
        rounded = ((avg / 25.0).round) * 25
        category = Category.find(cat_id)
        budget.budget_categories.find_or_create_by!(category: category) do |bc|
          bc.budgeted_spending = rounded
          bc.currency = family.currency
        end
      end

      # O orcamento de uma categoria-pai e o envelope do grupo: a linha do pai
      # compara o gasto acumulado (proprio + subcategorias) contra o proprio
      # budgeted_spending. Como acima cada categoria foi orcada so pelo gasto
      # DIRETO dela, o pai ficaria menor que a soma das subs e apareceria com um
      # estouro fantasma. Entao embutimos os orcamentos das subs no envelope do
      # pai (mesmo invariante que a UI real garante via max_allocation).
      budget_categories = budget.budget_categories.includes(:category).to_a
      budget_categories.reject { |bc| bc.category.parent_id.present? }.each do |parent_bc|
        children_budget = budget_categories
          .select { |bc| bc.category.parent_id == parent_bc.category_id }
          .sum { |bc| bc.budgeted_spending || 0 }
        next if children_budget.zero?

        parent_bc.update!(budgeted_spending: (parent_bc.budgeted_spending || 0) + children_budget)
      end

      # Total orcado do mes = soma dos envelopes de topo (allocated_spending); as
      # subcategorias ja estao contidas nos pais, nao entram de novo.
      budget.update!(
        budgeted_spending: budget_categories.reject(&:subcategory?).sum { |bc| bc.budgeted_spending || 0 }
      )
    end

    # Helper method to get weighted random date (favoring recent years)
    def weighted_random_date
      # Focus on last 3 years for transaction generation
      rand(3.years.ago.to_date..Date.current)
    end

    # Helper method to get random accounts for transactions
    def random_checking_account
      [ @chase_checking, @ally_checking ].sample
    end

    # ---------------------------------------------------------------------------
    # Payroll system - 156 deterministic deposits (bi-weekly, six years)
    # ---------------------------------------------------------------------------
    def generate_salary_history!
      deposit_amount = 8_500  # Increased from 4,200 to ~$200k annually
      total_deposits = 78     # Reduced from 156 (only 3 years instead of 6)

      # Find first Friday ≥ 3.years.ago so the cadence remains bi-weekly.
      first_date = 3.years.ago.to_date
      first_date += 1 until first_date.friday?

      total_deposits.times do |i|
        date = first_date + (14 * i)
        break if date > Date.current # safety

        amount = -jitter(deposit_amount, 0.02).round # negative inflow per conventions
        create_transaction!(@chase_checking, amount, "Folha de pagamento", @salary_cat, date)

        # 10 % automated savings transfer to Marcus Savings same day
        savings_amount = (-amount * 0.10).round
        create_transfer!(@chase_checking, @marcus_savings, savings_amount, "Reserva automática (10% do salário)", date)
      end

      # Add freelance income to help balance expenses
      15.times do
        date = weighted_random_date
        amount = -rand(1500..4000)  # Negative for income
        create_transaction!(@chase_checking, amount, "Projeto freelance", @freelance_cat, date)
      end

      # Add quarterly investment dividends
      (3.years.ago.to_date..Date.current).each do |date|
        next unless date.day == 15 && [ 3, 6, 9, 12 ].include?(date.month) # Quarterly
        dividend_amount = -rand(800..1500)  # Negative for income
        create_transaction!(@chase_checking, dividend_amount, "Dividendos", @investment_income_cat, date)
      end

      # Add more regular freelance income to maintain positive checking balance
      40.times do  # Increased from 15
        date = weighted_random_date
        amount = -rand(800..2500)  # More frequent, smaller freelance income
        create_transaction!(@chase_checking, amount, "Pagamento freelance", @freelance_cat, date)
      end

      # Add side income streams
      25.times do
        date = weighted_random_date
        amount = -rand(200..800)
        income_types = [ "Gorjetas", "Venda de itens", "Reembolso", "Cashback", "Resgate de vale-presente" ]
        create_transaction!(@chase_checking, amount, income_types.sample, @freelance_cat, date)
      end
    end

    def generate_housing_transactions!
      start_date = 3.years.ago.to_date  # Reduced from 12 years
      base_rent = 2500 # Higher starting amount for higher income family

      # Monthly rent/mortgage payments
      (start_date..Date.current).each do |date|
        next unless date.day == 1 # First of month

        # Mortgage payment from checking account (positive expense)
        create_transaction!(@chase_checking, 2800, "Parcela do financiamento", @rent_cat, date)
        # Principal payment reduces mortgage debt (negative transaction)
        principal_payment = 800 # ~R$800 vai para o principal
        create_transaction!(@mortgage, -principal_payment, "Amortização", nil, date, kind: "funds_movement")
      end

      # Monthly utilities (reduced frequency)
      utilities = [
        { name: "Enel (luz)", range: 150..300 },
        { name: "Vivo Internet", range: 85..105 },
        { name: "Sabesp (água)", range: 60..90 },
        { name: "Comgás (gás)", range: 80..220 }
      ]

      utilities.each do |utility|
        (start_date..Date.current).each do |date|
          next unless date.day.between?(5, 15) && rand < 0.9 # Monthly with higher frequency
          amount = rand(utility[:range])
          create_transaction!(@chase_checking, amount, utility[:name], @utilities_cat, date)
        end
      end
    end

    def generate_food_transactions!
      # Weekly groceries (increased volume but kept amounts reasonable)
      120.times do  # Increased from 60
        date = weighted_random_date
        amount = rand(60..180) # Reduced max from 220
        stores = [ "Pão de Açúcar", "Carrefour", "Extra", "Assaí", "Hortifruti" ]
        create_transaction!(@chase_checking, amount, "#{stores.sample}", @groceries_cat, date)
      end

      # Restaurant dining (increased volume)
      100.times do  # Increased from 50
        date = weighted_random_date
        amount = rand(25..65) # Reduced max from 80
        restaurants = [ "Pizzaria do Bairro", "Temakeria", "Cantina Italiana", "Restaurante Mexicano", "Taverna Grega" ]
        create_transaction!(@chase_checking, amount, restaurants.sample, @restaurants_cat, date)
      end

      # Coffee & takeout (increased volume)
      80.times do  # Increased from 40
        date = weighted_random_date
        amount = rand(8..20) # Reduced from 10-25
        places = [ "Cafeteria", "Starbucks", "Padaria da Esquina", "Lanchonete" ]
        create_transaction!(@chase_checking, amount, places.sample, @coffee_cat, date)
      end
    end

    def generate_transportation_transactions!
      # Gas stations (checking account only)
      60.times do
        date = weighted_random_date
        amount = rand(35..75)
        stations = [ "Shell", "Ipiranga", "Petrobras", "Ale", "Shell", "BR" ]
        create_transaction!(@chase_checking, amount, "Posto #{stations.sample}", @gas_cat, date)
      end

      # Car payment (monthly for 6 years)
      car_payment_start = 6.years.ago.to_date
      car_payment_end = 1.year.ago.to_date

      (car_payment_start..car_payment_end).each do |date|
        next unless date.day == 15 # 15th of month
        create_transaction!(@chase_checking, 385, "Parcela do carro", @car_payment_cat, date)
      end
    end

    def generate_entertainment_transactions!
      # Monthly subscriptions (increased timeframe)
      subscriptions = [
        { name: "Netflix", amount: 15 },
        { name: "Spotify", amount: 12 },
        { name: "Disney+", amount: 8 },
        { name: "Max", amount: 16 },
        { name: "Amazon Prime", amount: 14 }
      ]

      subscriptions.each do |sub|
        (3.years.ago.to_date..Date.current).each do |date| # Reduced from 12 years
          next unless date.day == rand(1..28) && rand < 0.9 # Higher frequency for active subscriptions
          create_transaction!(@chase_checking, sub[:amount], sub[:name], @entertainment_cat, date)
        end
      end

      # Random entertainment (increased volume)
      60.times do  # Increased from 25
        date = weighted_random_date
        amount = rand(15..60) # Reduced from 20-80
        activities = [ "Cinema", "Jogo de futebol", "Museu", "Show de comédia", "Boliche", "Minigolfe", "Fliperama" ]
        create_transaction!(@chase_checking, amount, activities.sample, @entertainment_cat, date)
      end
    end

    def generate_shopping_transactions!
      # Online shopping (increased volume)
      80.times do  # Increased from 40
        date = weighted_random_date
        amount = rand(30..90) # Reduced max from 120
        stores = [ "Magazine Luiza", "Carrefour", "Atacadão" ]
        create_transaction!(@chase_checking, amount, "Compra em #{stores.sample}", @shopping_cat, date)
      end

      # In-store shopping (increased volume)
      60.times do  # Increased from 25
        date = weighted_random_date
        amount = rand(35..80) # Reduced max from 100
        stores = [ "Americanas", "Decathlon", "Livraria Cultura", "Loja de games" ]
        create_transaction!(@chase_checking, amount, stores.sample, @shopping_cat, date)
      end
    end

    def generate_healthcare_transactions!
      # Doctor visits (increased volume)
      45.times do  # Increased from 25
        date = weighted_random_date
        amount = rand(150..350) # Reduced from 180-450
        providers = [ "Dr. Silva", "Dra. Souza", "Dr. Oliveira", "Consulta com especialista", "Pronto atendimento" ]
        create_transaction!(@chase_checking, amount, providers.sample, @healthcare_cat, date)
      end

      # Pharmacy (increased volume)
      80.times do  # Increased from 40
        date = weighted_random_date
        amount = rand(12..65) # Reduced from 15-85
        pharmacies = [ "Drogasil", "Droga Raia", "Pacheco", "Farmácia do bairro" ]
        create_transaction!(@chase_checking, amount, pharmacies.sample, @healthcare_cat, date)
      end
    end

    def generate_travel_transactions!
      # Major vacations (reduced count - premium travel handled in credit card cycles)
      8.times do
        date = weighted_random_date

        # Smaller local trips from checking
        hotel_amount = rand(200..500)
        hotels = [ "Hotel", "B&B", "Resort" ]
        if rand < 0.3 && date > 3.years.ago.to_date # Some EUR transactions
          create_transaction!(@eu_checking, hotel_amount, hotels.sample, @travel_cat, date)
        else
          create_transaction!(@chase_checking, hotel_amount, hotels.sample, @travel_cat, date)
        end

        # Domestic flights (smaller amounts)
        flight_amount = rand(200..400)
        create_transaction!(@chase_checking, flight_amount, "Voo doméstico", @travel_cat, date + rand(1..5).days)

        # Local activities
        activity_amount = rand(50..150)
        activities = [ "Passeio guiado", "Ingresso de museu", "Passaporte de atividades" ]
        create_transaction!(@chase_checking, activity_amount, activities.sample, @travel_cat, date + rand(1..7).days)
      end
    end

    def generate_personal_care_transactions!
      # Gym membership
      (12.years.ago.to_date..Date.current).each do |date|
        next unless date.day == 1 && rand < 0.8 # Monthly
        create_transaction!(@chase_checking, 45, "Academia", @personal_care_cat, date)
      end

      # Beauty/grooming (checking account only)
      40.times do
        date = weighted_random_date
        amount = rand(25..80)
        services = [ "Salão de beleza", "Barbearia", "Manicure" ]
        create_transaction!(@chase_checking, amount, services.sample, @personal_care_cat, date)
      end
    end

    def generate_investment_transactions!
      security = Security.first || Security.create!(ticker: "VTI", name: "ETF Ibovespa (BOVA11)", country_code: "US")

      generate_401k_trades!(security)
      generate_brokerage_trades!(security)
      generate_roth_trades!(security)
      generate_uk_isa_trades!(security)
    end

    # ---------------------------------------------------- 401k (180 trades) --
    def generate_401k_trades!(security)
      payroll_dates = collect_payroll_dates.first(90) # 90 paydays ⇒ 180 trades

      payroll_dates.each do |date|
        # Employee contribution $1 200
        create_trade_for(@vanguard_401k, security, 1_200, date, "401k Employee")

        # Employer match $300
        create_trade_for(@vanguard_401k, security, 300, date, "401k Employer Match")
      end
    end

    # -------------------------------------------- Brokerage (144 trades) -----
    def generate_brokerage_trades!(security)
      date_cursor = 36.months.ago.beginning_of_month
      while date_cursor <= Date.current
        4.times do |i|
          trade_date = date_cursor + i * 7.days # roughly spread within month
          create_trade_for(@schwab_brokerage, security, rand(400..1_000), trade_date, "Compra na corretora")
        end
        date_cursor = date_cursor.next_month.beginning_of_month
      end
    end

    # ----------------------------------------------- Roth IRA (108 trades) ---
    def generate_roth_trades!(security)
      date_cursor = 36.months.ago.beginning_of_month
      while date_cursor <= Date.current
        # Split $500 monthly across 3 staggered trades
        3.times do |i|
          trade_date = date_cursor + i * 10.days
          create_trade_for(@fidelity_roth_ira, security, (500 / 3.0), trade_date, "Aporte em previdência")
        end
        date_cursor = date_cursor.next_month.beginning_of_month
      end
    end

    # ------------------------------------------------- UK ISA (108 trades) ----
    def generate_uk_isa_trades!(security)
      date_cursor = 36.months.ago.beginning_of_month
      while date_cursor <= Date.current
        3.times do |i|
          trade_date = date_cursor + i * 10.days
          create_trade_for(@uk_isa, security, (400 / 3.0), trade_date, "Aporte no exterior", price_range: 60..150)
        end
        date_cursor = date_cursor.next_month.beginning_of_month
      end
    end

    # --------------------------- Helpers for investment trade generation -----
    def collect_payroll_dates
      dates = []
      d = 36.months.ago.to_date
      d += 1 until d.friday?
      while d <= Date.current
        dates << d if d.cweek.even?
        d += 14 # next bi-weekly
      end
      dates
    end

    def create_trade_for(account, security, investment_amount, date, memo, price_range: 80..200)
      price = rand(price_range)
      qty   = (investment_amount.to_f / price).round(2)
      create_investment_transaction!(account, security, qty, price, date, memo)
    end

    def generate_major_purchases!
      # Home purchase (5 years ago) - only record the down payment, not full value
      # Property value will be set by valuation in reconcile_balances!
      home_date = 5.years.ago.to_date
      create_transaction!(@chase_checking, 70_000, "Entrada do imóvel", @housing_cat, home_date)
      create_transaction!(@mortgage, 320_000, "Saldo do financiamento", nil, home_date, kind: "funds_movement") # divida inicial do financiamento

      # Initial account funding (realistic amounts)
      # Saldos iniciais: estabelecem o ponto de partida das contas, nao sao
      # receita. Marcados funds_movement para nao virar "salario" no fluxo.
      create_transaction!(@chase_checking, -5_000, "Saldo inicial", nil, 12.years.ago.to_date, kind: "funds_movement")
      create_transaction!(@ally_checking, -2_000, "Saldo inicial", nil, 12.years.ago.to_date, kind: "funds_movement")
      create_transaction!(@marcus_savings, -10_000, "Saldo inicial", nil, 12.years.ago.to_date, kind: "funds_movement")
      create_transaction!(@eu_checking, -5_000, "Abertura de conta em euro", nil, 4.years.ago.to_date, kind: "funds_movement")

      # Car purchases (realistic amounts)
      create_transaction!(@chase_checking, 3_000, "Entrada do carro", @transportation_cat, 6.years.ago.to_date)
      create_transaction!(@chase_checking, 2_500, "Entrada do segundo carro", @transportation_cat, 8.years.ago.to_date)

      # Major but realistic expenses
      create_transaction!(@chase_checking, 8_000, "Reforma da cozinha", @utilities_cat, 2.years.ago.to_date)
      create_transaction!(@chase_checking, 5_000, "Reforma do banheiro", @utilities_cat, 1.year.ago.to_date)
      create_transaction!(@chase_checking, 12_000, "Troca do telhado", @utilities_cat, 3.years.ago.to_date)
      create_transaction!(@chase_checking, 8_000, "Emergência familiar", @healthcare_cat, 4.years.ago.to_date)
      create_transaction!(@chase_checking, 15_000, "Despesas do casamento", @entertainment_cat, 9.years.ago.to_date)
    end

    def generate_transfers_and_payments!
      generate_credit_card_cycles!

      generate_monthly_ally_transfers!
      generate_quarterly_fx_transfers!
      generate_additional_savings_transfers!
    end

    # Additional savings transfers to improve income/expense balance
    def generate_additional_savings_transfers!
      # Monthly extra savings transfers
      (3.years.ago.to_date..Date.current).each do |date|
        next unless date.day == 15 && rand < 0.7 # Semi-monthly savings
        amount = rand(500..1500)
        create_transfer!(@chase_checking, @marcus_savings, amount, "Transferência para poupança", date)
      end

      # Quarterly HSA contributions
      (3.years.ago.to_date..Date.current).each do |date|
        next unless date.day == 1 && [ 1, 4, 7, 10 ].include?(date.month) # Quarterly
        amount = rand(1000..2000)
        create_transfer!(@chase_checking, @hsa_investment, amount, "Aporte no fundo de reserva", date)
      end

      # Occasional windfalls (tax refunds, bonuses, etc.)
      8.times do
        date = weighted_random_date
        amount = rand(2000..8000)
        create_transaction!(@chase_checking, -amount, "Restituição do IR", @salary_cat, date)
      end

      # CRITICAL: Regular transfers FROM savings TO checking to maintain positive balance
      # This is realistic - people move money from savings to checking regularly
      (3.years.ago.to_date..Date.current).each do |date|
        next unless date.day == rand(20..28) && rand < 0.8 # Monthly transfers from savings
        amount = rand(2000..5000)
        create_transfer!(@marcus_savings, @chase_checking, amount, "Resgate da poupança", date)
      end

      # Weekly smaller transfers from savings for cash flow
      (3.years.ago.to_date..Date.current).each do |date|
        next unless date.wday == 1 && rand < 0.4 # Some Mondays
        amount = rand(500..1200)
        create_transfer!(@marcus_savings, @chase_checking, amount, "Movimentação semanal", date)
      end
    end

    # $300 from Chase Checking to Ally Checking on the first business day of each
    # month for the past 36 months.
    def generate_monthly_ally_transfers!
      date_cursor = 36.months.ago.beginning_of_month
      while date_cursor <= Date.current
        transfer_date = first_business_day(date_cursor)
        create_transfer!(@chase_checking, @ally_checking, 300, "Transferência mensal", transfer_date)
        date_cursor = date_cursor.next_month.beginning_of_month
      end
    end

    # Quarterly $2 000 FX transfer from Chase Checking to EUR account
    def generate_quarterly_fx_transfers!
      date_cursor = 36.months.ago.beginning_of_quarter
      while date_cursor <= Date.current
        transfer_date = date_cursor + 2.days # arbitrary within quarter start
        create_transfer!(@chase_checking, @eu_checking, 2_000, "Transferência em moeda", transfer_date)
        date_cursor = date_cursor.next_quarter.beginning_of_quarter
      end
    end

    # Returns the first weekday (Mon-Fri) of the month containing +date+.
    def first_business_day(date)
      d = date.beginning_of_month
      d += 1.day while d.saturday? || d.sunday?
      d
    end

    def generate_credit_card_cycles!
      # REDUCED: 30-45 charges per month across both cards for 36 months (≈1,400 total)
      # This is still significant but more realistic than 80-120/month
      # Pay 90-95 % of new balance 5 days post-cycle; final balances should
      # be ~$2 500 (Amex) and ~$4 200 (Sapphire).

      start_date = 36.months.ago.beginning_of_month
      end_date   = Date.current.end_of_month

      amex_balance      = 0
      sapphire_balance  = 0

      charges_this_run  = 0
      payments_this_run = 0

      date_cursor = start_date
      while date_cursor <= end_date
        # --- Charge generation (REDUCED FOR BALANCE) -------------------------
        month_charge_target = rand(30..45)  # Reduced from 80-120 to 30-45
        # Split roughly evenly but add a little variance.
        amex_count     = (month_charge_target * rand(0.45..0.55)).to_i
        sapphire_count = month_charge_target - amex_count

        amex_total     = generate_credit_card_charges(@amex_gold,     date_cursor, amex_count)
        sapphire_total = generate_credit_card_charges(@chase_sapphire, date_cursor, sapphire_count)

        amex_balance     += amex_total
        sapphire_balance += sapphire_total

        charges_this_run += (amex_count + sapphire_count)

        # --- Monthly payments (5 days after month end) ------------------------
        payment_date = (date_cursor.end_of_month + 5.days)

        if amex_total.positive?
          amex_payment = (amex_total * rand(0.90..0.95)).round
          create_transfer!(@chase_checking, @amex_gold, amex_payment, "Pagamento Cartão Nubank", payment_date)
          amex_balance -= amex_payment
          payments_this_run += 1
        end

        if sapphire_total.positive?
          sapphire_payment = (sapphire_total * rand(0.90..0.95)).round
          create_transfer!(@chase_checking, @chase_sapphire, sapphire_payment, "Pagamento Cartão Itaú", payment_date)
          sapphire_balance -= sapphire_payment
          payments_this_run += 1
        end

        date_cursor = date_cursor.next_month.beginning_of_month
      end

      # -----------------------------------------------------------------------
      # Re-balance to hit target ending balances (tolerance ±$250)
      # -----------------------------------------------------------------------
      target_amex     = 2_500
      target_sapphire = 4_200

      diff_amex     = amex_balance - target_amex
      diff_sapphire = sapphire_balance - target_sapphire

      if diff_amex.abs > 250
        adjust_payment = diff_amex.positive? ? diff_amex : 0
        create_transfer!(@chase_checking, @amex_gold, adjust_payment, "Ajuste Cartão Nubank", Date.current)
        amex_balance -= adjust_payment
      end

      if diff_sapphire.abs > 250
        adjust_payment = diff_sapphire.positive? ? diff_sapphire : 0
        create_transfer!(@chase_checking, @chase_sapphire, adjust_payment, "Ajuste Cartão Itaú", Date.current)
        sapphire_balance -= adjust_payment
      end

      puts "   Charges generated: #{charges_this_run} | Payments: #{payments_this_run}"
      puts "   Final Amex balance: ~$#{amex_balance} | target ~$#{target_amex}"
      puts "   Final Sapphire balance: ~$#{sapphire_balance} | target ~$#{target_sapphire}"
    end

    # Generate exactly +count+ charges on +account+ within the month of +base_date+.
    # Returns total charge amount.
    def generate_credit_card_charges(account, base_date, count)
      total = 0

      count.times do
        charge_date = base_date + rand(0..27).days

        amount = rand(15..80) # Reduced from 25..150 due to higher frequency
        # bias amounts to achieve reasonable monthly totals
        amount = jitter(amount, 0.15).round

        merchant = if account == @amex_gold
          pick([ "Pão de Açúcar", "Starbucks", "iFood", "Netflix", "Bistrô do Bairro", "Airbnb" ])
        else
          pick([ "LATAM", "Rede de Hotéis", "Decolar", "Apple", "Fast Shop", "Amazon" ])
        end

        create_transaction!(account, amount, merchant, random_expense_category, charge_date)
        total += amount
      end

      total
    end

    def random_expense_category
      [ @food_cat, @entertainment_cat, @shopping_cat, @travel_cat, @transportation_cat ].sample
    end

    def create_transaction!(account, amount, name, category, date, kind: "standard")
      # For credit cards (liabilities), positive amounts = charges (increase debt)
      # For checking accounts (assets), positive amounts = expenses (decrease balance)
      # The amount is already signed correctly by the caller
      #
      # kind: use "funds_movement" para ajustes que nao sao fluxo de caixa
      # (ex.: reducao de principal de financiamento) -- assim saem do Sankey.
      account.entries.create!(
        entryable: Transaction.new(category: category, kind: kind),
        amount: amount,
        name: name,
        currency: account.currency,
        date: date
      )
    end

    def create_investment_transaction!(account, security, qty, price, date, name)
      account.entries.create!(
        entryable: Trade.new(security: security, qty: qty, price: price, currency: account.currency),
        amount: -(qty * price),
        name: name,
        currency: account.currency,
        date: date
      )
    end

    def create_transfer!(from_account, to_account, amount, name, date)
      outflow = from_account.entries.create!(
        entryable: Transaction.new,
        amount: amount,
        name: name,
        currency: from_account.currency,
        date: date
      )
      inflow = to_account.entries.create!(
        entryable: Transaction.new,
        amount: -amount,
        name: name,
        currency: to_account.currency,
        date: date
      )
      Transfer.create!(inflow_transaction: inflow.entryable, outflow_transaction: outflow.entryable)

      # Espelha o casamento real (Family::AutoTransferMatchable): uma
      # transferencia so sai do fluxo de caixa quando AS DUAS pontas tem o
      # `kind` marcado. Sem isto, cada perna vira receita/despesa "Sem
      # categoria" e infla o Sankey com dinheiro que so andou entre contas.
      inflow.entryable.update!(kind: "funds_movement")
      outflow.entryable.update!(kind: Transfer.kind_for_account(from_account))
    end

    def load_securities!
      return if Security.exists?

      Security.create!([
        { ticker: "VTI", name: "ETF Ibovespa (BOVA11)", country_code: "US" },
        { ticker: "VXUS", name: "ETF S&P 500 (IVVB11)", country_code: "US" },
        { ticker: "BND", name: "ETF Renda Fixa (IMAB11)", country_code: "US" }
      ])
    end

    def sync_family_accounts!(family)
      family.accounts.each do |account|
        sync = Sync.create!(syncable: account)
        sync.perform
      end
    end

    # ---------------------------------------------------------------------------
    #                         Deterministic helper methods
    # ---------------------------------------------------------------------------

    # Deterministically walk through the elements of +array+, returning the next
    # element each time it is called with the *same* array instance.
    #
    # Example:
    #   colours = %w[red green blue]
    #   4.times.map { pick(colours) } #=> ["red", "green", "blue", "red"]
    def pick(array)
      @pick_indices ||= Hash.new(0)
      idx = @pick_indices[array.object_id]
      @pick_indices[array.object_id] += 1
      array[idx % array.length]
    end

    # Adds a small random variation (±pct, default 3%) to +num+.  Useful for
    # making otherwise deterministic amounts look more natural while retaining
    # overall reproducibility via the seeded RNG.
    def jitter(num, pct = 0.03)
      variation = num * pct * (rand * 2 - 1) # rand(-pct..pct)
      (num + variation).round(2)
    end

    # ---------------------------------------------------------------------------
    # Loan payments (Task 8)
    # ---------------------------------------------------------------------------
    def generate_loan_payments!
      date_cursor = 36.months.ago.beginning_of_month
      while date_cursor <= Date.current
        payment_date = first_business_day(date_cursor)

        # Mortgage
        make_loan_payment!(
          principal_account: @mortgage,
          principal_amount: 600,
          interest_amount: 1_100,
          interest_category: @housing_cat,
          date: payment_date,
          memo: "Parcela do financiamento"
        )

        # Student loan
        make_loan_payment!(
          principal_account: @student_loan,
          principal_amount: 350,
          interest_amount: 100,
          interest_category: @interest_cat,
          date: payment_date,
          memo: "Parcela do FIES"
        )

        # Car loan - assume 300 principal / 130 interest
        make_loan_payment!(
          principal_account: @car_loan,
          principal_amount: 300,
          interest_amount: 130,
          interest_category: @transportation_cat,
          date: payment_date,
          memo: "Parcela do carro"
        )

        date_cursor = date_cursor.next_month.beginning_of_month
      end
    end

    def make_loan_payment!(principal_account:, principal_amount:, interest_amount:, interest_category:, date:, memo:)
      # Principal portion - transfer from checking to loan account
      create_transfer!(@chase_checking, principal_account, principal_amount, memo, date)

      # Interest portion - expense from checking
      create_transaction!(@chase_checking, interest_amount, "Juros #{memo}", interest_category, date)
    end

    # Generate additional baseline expenses to reach 8k-12k transaction target
    def generate_regular_expenses!
      expense_generators = [
        ->(date) { create_transaction!(@chase_checking, jitter(rand(150..220), 0.05).round, pick([ "Enel (luz)", "Cemig", "Copel" ]), @utilities_cat, date) },
        ->(date) { create_transaction!(@chase_checking, jitter(rand(10..20), 0.1).round, pick([ "Spotify", "Netflix", "Globoplay", "Apple One" ]), @entertainment_cat, date) },
        ->(date) { create_transaction!(@chase_checking, jitter(rand(45..90), 0.1).round, pick([ "Pão de Açúcar", "Carrefour", "Extra" ]), @groceries_cat, date) },
        ->(date) { create_transaction!(@chase_checking, jitter(rand(25..50), 0.1).round, pick([ "Posto Shell", "Posto BR", "Ipiranga" ]), @gas_cat, date) },
        ->(date) { create_transaction!(@chase_checking, jitter(rand(15..40), 0.1).round, pick([ "Streaming de filme", "Compra de livro", "Jogo mobile" ]), @entertainment_cat, date) }
      ]

      desired = 600  # Increased from 300 to help reach 8k
      current = Entry.joins(:account).where(accounts: { id: [ @chase_checking.id ] }, entryable_type: "Transaction").count
      to_create = [ desired - current, 0 ].max

      to_create.times do
        date = weighted_random_date
        expense_generators.sample.call(date)
      end

      # Add high-volume, low-impact transactions to reach 8k minimum
      generate_micro_transactions!
    end

    # Generate many small transactions to reach volume target
    def generate_micro_transactions!
      # ATM withdrawals and fees (reduced)
      120.times do  # Reduced from 200
        date = weighted_random_date
        amount = rand(20..60)
        create_transaction!(@chase_checking, amount, "Saque no caixa eletrônico", @misc_cat, date)
        # Small ATM fee
        create_transaction!(@chase_checking, rand(2..4), "Tarifa de saque", @misc_cat, date)
      end

      # Small convenience store purchases (reduced)
      200.times do  # Reduced from 300
        date = weighted_random_date
        amount = rand(3..15)
        stores = [ "7-Eleven", "Wawa", "Circle K", "Quick Stop", "Mercadinho" ]
        create_transaction!(@chase_checking, amount, stores.sample, @shopping_cat, date)
      end

      # Small digital purchases (reduced)
      120.times do  # Reduced from 200
        date = weighted_random_date
        amount = rand(1..10)
        items = [ "Loja de apps", "Google Play", "iTunes", "Steam", "Livro Kindle" ]
        create_transaction!(@chase_checking, amount, items.sample, @entertainment_cat, date)
      end

      # Parking meters and tolls (reduced)
      100.times do  # Reduced from 150
        date = weighted_random_date
        amount = rand(2..8)
        create_transaction!(@chase_checking, amount, pick([ "Zona Azul", "Pedágio", "Estacionamento" ]), @transportation_cat, date)
      end

      # Small cash transactions (reduced)
      150.times do  # Reduced from 250
        date = weighted_random_date
        amount = rand(5..25)
        vendors = [ "Lanchonete", "Feira livre", "Camelô", "Gorjeta", "Doação" ]
        create_transaction!(@chase_checking, amount, vendors.sample, @misc_cat, date)
      end

      # Vending machine purchases (reduced)
      60.times do  # Reduced from 100
        date = weighted_random_date
        amount = rand(1..5)
        create_transaction!(@chase_checking, amount, "Máquina de snacks", @shopping_cat, date)
      end

      # Public transportation (reduced)
      120.times do  # Reduced from 180
        date = weighted_random_date
        amount = rand(2..8)
        transit = [ "Bilhete de transporte", "Passagem de ônibus", "Bilhete do metrô", "Uber/99" ]
        create_transaction!(@chase_checking, amount, transit.sample, @transportation_cat, date)
      end

      # Additional small transactions to ensure we reach 8k minimum (reduced)
      400.times do  # Reduced from 600
        date = weighted_random_date
        amount = rand(1..12)
        merchants = [
          "Banca de jornal", "Carrinho de café", "Gorjeta", "Caixa de doações", "Lavanderia",
          "Lava-rápido", "Aluguel de filme", "Orelhão", "Cabine de fotos", "Fliperama",
          "Correios", "Jornal", "Bilhete de loteria", "Máquina de chiclete", "Sorveteria"
        ]
        create_transaction!(@chase_checking, amount, merchants.sample, @misc_cat, date)
      end

      # Extra small transactions to ensure 8k+ volume
      500.times do
        date = weighted_random_date
        amount = rand(1..8)
        tiny_merchants = [
          "Máquina de doces", "Máquina de adesivos", "Balança de rua", "Doação",
          "Gorjeta a artista de rua", "Dízimo", "Barraca de limonada", "Biscoito beneficente",
          "Rifa", "Bazar de doces", "Gorjeta do lava-rápido", "Artista de rua"
        ]
        create_transaction!(@chase_checking, amount, tiny_merchants.sample, @misc_cat, date)
      end
    end

    # ---------------------------------------------------------------------------
    # Legacy historical transactions (Task 11)
    # ---------------------------------------------------------------------------
    def generate_legacy_transactions!
      # Small recent legacy transactions (3-6 years ago)
      count = rand(40..60)  # Increased from 20-30
      count.times do
        years_ago = rand(3..6)
        date = years_ago.years.ago.to_date - rand(0..364).days

        base_amount = rand(12..45)  # Reduced from 15-60
        discount    = (1 - 0.02 * [ years_ago - 3, 0 ].max)
        amount      = (base_amount * discount).round

        account = [ @chase_checking, @ally_checking ].sample
        category = pick([ @groceries_cat, @utilities_cat, @gas_cat, @restaurants_cat, @shopping_cat ])

        merchant = case category
        when @groceries_cat then pick(%w[Carrefour Assaí Extra])
        when @utilities_cat then pick([ "Enel", "Sabesp", "Comgás" ])
        when @gas_cat then pick([ "Shell", "Ipiranga", "Petrobras" ])
        when @restaurants_cat then pick([ "Lanchonete", "Hamburgueria", "Pizzaria" ])
        else pick([ "Loja de conveniência", "Loja de departamento", "Outlet" ])
        end

        create_transaction!(account, amount, merchant, category, date)
      end

      # Very old transactions (7-15 years ago) - just scattered outliers
      count = rand(25..40)  # Increased from 15-25
      count.times do
        years_ago = rand(7..15)
        date = years_ago.years.ago.to_date - rand(0..364).days

        base_amount = rand(8..30)  # Reduced from 10-40
        discount    = (1 - 0.03 * [ years_ago - 7, 0 ].max)  # More discount for very old
        amount      = (base_amount * discount).round.clamp(5, 25)  # Reduced max from 35

        account = @chase_checking  # Just use main checking for simplicity
        category = pick([ @groceries_cat, @gas_cat, @restaurants_cat ])

        merchant = case category
        when @groceries_cat then pick(%w[Carrefour Assaí])
        when @gas_cat then pick(%w[Shell Ipiranga])
        else pick([ "Lanchonete antiga", "Restaurante do bairro" ])
        end

        create_transaction!(account, amount, "#{merchant} (#{years_ago}y ago)", category, date)
      end

      # Additional small transactions to reach 8k minimum if needed
      additional_needed = [ 400, 0 ].max  # Increased from 200
      additional_needed.times do
        years_ago = rand(4..12)
        date = years_ago.years.ago.to_date - rand(0..364).days
        amount = rand(6..20)  # Reduced from 8-25

        account = [ @chase_checking, @ally_checking ].sample
        category = pick([ @groceries_cat, @gas_cat, @utilities_cat ])

        merchant = "#{pick(%w[Loja Posto Luz])}"
        create_transaction!(account, amount, merchant, category, date)
      end
    end

    # ---------------------------------------------------------------------------
    # Crypto & misc assets (Task 12)
    # ---------------------------------------------------------------------------
    def generate_crypto_and_misc_assets!
      # Aporte unico em cripto ha 18 meses -- estabelece a posicao, nao e receita
      deposit_date = 18.months.ago.to_date
      create_transaction!(@coinbase_usdc, -3_500, "Aporte inicial em cripto", nil, deposit_date, kind: "funds_movement")
    end

    # ---------------------------------------------------------------------------
    # Balance Reconciliation (Task 14)
    # ---------------------------------------------------------------------------
    def reconcile_balances!(family)
      # Use valuations only for property/vehicle accounts that should have specific values
      # All other accounts should reach target balances through natural transaction flow

      # Property valuations (these accounts are valued, not transaction-driven)
      @home.entries.create!(
        entryable: Valuation.new(kind: "current_anchor"),
        amount: 350_000,
        name: Valuation.build_current_anchor_name(@home.accountable_type),
        currency: "BRL",
        date: Date.current
      )

      # Vehicle valuations (these depreciate over time)
      @honda_accord.entries.create!(
        entryable: Valuation.new(kind: "current_anchor"),
        amount: 18_000,
        name: Valuation.build_current_anchor_name(@honda_accord.accountable_type),
        currency: "BRL",
        date: Date.current
      )

      @tesla_model3.entries.create!(
        entryable: Valuation.new(kind: "current_anchor"),
        amount: 4_500,
        name: Valuation.build_current_anchor_name(@tesla_model3.accountable_type),
        currency: "BRL",
        date: Date.current
      )

      @jewelry.entries.create!(
        entryable: Valuation.new(kind: "reconciliation"),
        amount: 2000,
        name: Valuation.build_reconciliation_name(@jewelry.accountable_type),
        currency: "BRL",
        date: 90.days.ago.to_date
      )

      @personal_loc.entries.create!(
        entryable: Valuation.new(kind: "reconciliation"),
        amount: 800,
        name: Valuation.build_reconciliation_name(@personal_loc.accountable_type),
        currency: "BRL",
        date: 120.days.ago.to_date
      )

      puts "   Set property and vehicle valuations"
    end
end
