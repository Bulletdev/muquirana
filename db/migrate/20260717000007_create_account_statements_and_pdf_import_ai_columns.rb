class CreateAccountStatementsAndPdfImportAiColumns < ActiveRecord::Migration[7.2]
  def change
    # Documento (PDF) enviado pelo usuario para extracao via IA. Guarda o hash
    # do conteudo para deduplicar o mesmo arquivo e evitar reprocessar (gastar
    # OpenAI) duas vezes.
    create_table :account_statements, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.references :account, null: true, foreign_key: true, type: :uuid
      t.string :filename, null: false
      t.string :content_type, null: false
      t.bigint :byte_size, null: false
      t.string :content_sha256
      t.timestamps
    end

    add_index :account_statements, [ :family_id, :content_sha256 ], unique: true, name: "index_account_statements_on_family_and_sha"

    # Colunas de IA da importacao por PDF (caminho OpenAI).
    add_column :imports, :ai_summary, :text
    add_column :imports, :document_type, :string
    add_column :imports, :extracted_data, :jsonb, default: {}, null: false
    add_reference :imports, :account_statement, null: true, foreign_key: true, type: :uuid
  end
end
