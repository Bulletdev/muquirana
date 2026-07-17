module Provider::LlmConcept
  extend ActiveSupport::Concern

  AutoCategorization = Data.define(:transaction_id, :category_name)

  def auto_categorize(transactions)
    raise NotImplementedError, "Subclasses must implement #auto_categorize"
  end

  AutoDetectedMerchant = Data.define(:transaction_id, :business_name, :business_url)

  def auto_detect_merchants(transactions)
    raise NotImplementedError, "Subclasses must implement #auto_detect_merchants"
  end

  ChatMessage = Data.define(:id, :output_text)
  # usage carrega os tokens consumidos quando o chunk e do tipo "response"
  # (evento response.completed); nos demais chunks fica nil.
  ChatStreamChunk = Data.define(:type, :data, :usage)
  ChatResponse = Data.define(:id, :model, :messages, :function_requests)
  ChatFunctionRequest = Data.define(:id, :call_id, :function_name, :function_args)

  def chat_response(prompt, model:, instructions: nil, functions: [], function_results: [], streamer: nil, previous_response_id: nil, family: nil)
    raise NotImplementedError, "Subclasses must implement #chat_response"
  end

  # Resultado da classificacao de um documento PDF (importacao por IA).
  PdfProcessingResult = Data.define(:summary, :document_type, :extracted_data)

  # Se o provider sabe ler PDFs. Por padrao nao - override no provider que
  # implementa (ex.: Provider::Openai).
  def supports_pdf_processing?
    false
  end

  def process_pdf(pdf_content:, family: nil)
    raise NotImplementedError, "Subclasses must implement #process_pdf"
  end

  def extract_bank_statement(pdf_content:, family: nil)
    raise NotImplementedError, "Subclasses must implement #extract_bank_statement"
  end
end
