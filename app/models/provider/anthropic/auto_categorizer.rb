class Provider::Anthropic::AutoCategorizer
  # Modelo Claude atual e barato para classificacao em lote (nao-deprecado).
  MODEL = "claude-haiku-4-5".freeze

  TOOL_NAME = "report_categorizations".freeze

  # Uso (tokens) da ultima chamada, para o provider registrar o custo.
  attr_reader :usage

  def initialize(client, transactions: [], user_categories: [])
    @client = client
    @transactions = transactions
    @user_categories = user_categories
    @usage = nil
  end

  def auto_categorize
    response = client.messages.create(
      model: MODEL,
      max_tokens: max_tokens,
      system_: instructions,
      messages: [ { role: "user", content: user_message } ],
      tools: [ output_tool ],
      # Forca o modelo a responder via tool (JSON estruturado garantido).
      tool_choice: { type: "tool", name: TOOL_NAME, disable_parallel_tool_use: true }
    )

    @usage = usage_hash(response.usage)

    Rails.logger.info("Tokens used to auto-categorize transactions: #{@usage["total_tokens"]}")

    build_response(extract_categorizations(response))
  end

  private
    attr_reader :client, :transactions, :user_categories

    AutoCategorization = Provider::LlmConcept::AutoCategorization

    def max_tokens
      ENV.fetch("ANTHROPIC_MAX_TOKENS", 4096).to_i
    end

    def output_tool
      {
        name: TOOL_NAME,
        description: "Return the categorization decision for each input transaction.",
        input_schema: {
          type: "object",
          properties: {
            categorizations: {
              type: "array",
              description: "One categorization per input transaction.",
              items: {
                type: "object",
                properties: {
                  transaction_id: {
                    type: "string",
                    description: "The internal ID of the original transaction",
                    enum: transactions.map { |t| t[:id] }
                  },
                  category_name: {
                    type: [ "string", "null" ],
                    description: "Matched category name from the user's categories, or null when uncertain.",
                    # `null` precisa estar no enum: JSON Schema `enum` restringe os
                    # valores ao conjunto listado, entao sem ele o Claude nao
                    # conseguiria abster-se (categorizacao forcada e errada).
                    enum: user_categories.map { |c| c[:name] } + [ nil ]
                  }
                },
                required: [ "transaction_id", "category_name" ],
                additionalProperties: false
              }
            }
          },
          required: [ "categorizations" ],
          additionalProperties: false
        }
      }
    end

    def instructions
      <<~INSTRUCTIONS.strip_heredoc
        You are an assistant to a consumer personal finance app. You will be provided a list of the user's
        transactions and a list of the user's categories. Your job is to auto-categorize each transaction
        and return the result via the report_categorizations tool.

        Follow ALL the rules below:

        - Return one result per transaction, correlated by transaction_id
        - Use the most specific category possible (subcategory over parent category)
        - Any category may be used regardless of whether the transaction is income or expense
        - Return null for category_name when you are not 60%+ confident, or when the description is
          generic/ambiguous (e.g., "POS DEBIT", "ACH WITHDRAWAL", "CHECK #1234")
        - The `hint` field on a transaction (when present) comes from third-party aggregators and may
          or may not match the user's categories -- treat it as a weak signal
      INSTRUCTIONS
    end

    def user_message
      <<~MESSAGE.strip_heredoc
        Here are the user's available categories in JSON:

        ```json
        #{user_categories.to_json}
        ```

        Auto-categorize the following transactions:

        ```json
        #{transactions.to_json}
        ```
      MESSAGE
    end

    def extract_categorizations(response)
      tool_use = Array(response.content).find { |block| block_type(block) == :tool_use }
      raise Provider::Anthropic::Error, "Model did not invoke #{TOOL_NAME}" unless tool_use

      input = block_input(tool_use)
      input = JSON.parse(input) if input.is_a?(String)
      categorizations = input.is_a?(Hash) ? (input["categorizations"] || input[:categorizations]) : nil

      raise Provider::Anthropic::Error, "Tool call missing categorizations" unless categorizations.is_a?(Array)
      categorizations
    end

    def build_response(categorizations)
      categorizations.map do |c|
        category_name = c["category_name"] || c[:category_name]
        AutoCategorization.new(
          transaction_id: c["transaction_id"] || c[:transaction_id],
          category_name: normalize_category(category_name)
        )
      end
    end

    def normalize_category(value)
      return nil if value.nil?
      str = value.to_s.strip
      return nil if str.empty? || str.casecmp("null").zero?

      match = user_categories.find { |c| c[:name].to_s.casecmp(str).zero? }
      match ? match[:name] : str
    end

    def block_type(block)
      raw = block.respond_to?(:type) ? block.type : (block[:type] || block["type"])
      raw.to_s.to_sym
    end

    def block_input(block)
      block.respond_to?(:input) ? block.input : (block[:input] || block["input"])
    end

    def usage_hash(raw_usage)
      return {} unless raw_usage

      input = raw_usage.input_tokens.to_i
      output = raw_usage.output_tokens.to_i
      hash = {
        "input_tokens" => input,
        "output_tokens" => output,
        "total_tokens" => input + output
      }
      hash["cache_creation_input_tokens"] = raw_usage.cache_creation_input_tokens if raw_usage.respond_to?(:cache_creation_input_tokens) && raw_usage.cache_creation_input_tokens
      hash["cache_read_input_tokens"] = raw_usage.cache_read_input_tokens if raw_usage.respond_to?(:cache_read_input_tokens) && raw_usage.cache_read_input_tokens
      hash
    end
end
