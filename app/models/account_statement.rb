# frozen_string_literal: true

require "digest/sha2"
require "stringio"

# Documento financeiro (PDF) enviado pelo usuario para importacao via IA.
#
# Guarda o arquivo original (ActiveStorage) e o hash SHA-256 do conteudo. O hash
# serve para deduplicar: subir o mesmo PDF duas vezes reaproveita o statement
# existente em vez de criar outro e reprocessar (o que gastaria OpenAI de novo).
#
# Versao enxuta do AccountStatement do Sure - sem reconciliacao de saldo,
# matching automatico de conta nem deteccao de metadados. So o necessario para o
# fluxo US-12 (upload -> IA -> import_rows -> publish).
class AccountStatement < ApplicationRecord
  DuplicateUploadError = Class.new(StandardError) do
    attr_reader :statement

    def initialize(statement)
      @statement = statement
      super("Statement file has already been uploaded")
    end
  end

  InvalidUploadError = Class.new(StandardError)

  PreparedUpload = Data.define(:content, :filename, :content_type, :byte_size, :content_sha256)

  MAX_FILE_SIZE = 25.megabytes
  ALLOWED_CONTENT_TYPES = %w[application/pdf].freeze

  belongs_to :family
  belongs_to :account, optional: true

  has_many :pdf_imports, dependent: :restrict_with_error
  has_one_attached :original_file, dependent: :purge_later

  validates :filename, :content_type, presence: true
  validates :byte_size, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: MAX_FILE_SIZE }
  validates :content_type, inclusion: { in: ALLOWED_CONTENT_TYPES }
  validates :content_sha256,
            format: { with: /\A[0-9a-f]{64}\z/ },
            uniqueness: { scope: :family_id, message: :duplicate_statement_file },
            allow_nil: true

  scope :ordered, -> { order(created_at: :desc) }

  class << self
    def create_from_upload!(family:, file:, account: nil)
      create_from_prepared_upload!(family: family, account: account, prepared_upload: prepare_upload!(file))
    end

    def create_from_prepared_upload!(family:, prepared_upload:, account: nil)
      duplicate = duplicate_for(family, prepared_upload)
      raise DuplicateUploadError, duplicate if duplicate

      statement = family.account_statements.build(
        account: account,
        filename: prepared_upload.filename,
        content_type: prepared_upload.content_type,
        byte_size: prepared_upload.byte_size,
        content_sha256: prepared_upload.content_sha256
      )

      statement.original_file.attach(
        io: StringIO.new(prepared_upload.content),
        filename: prepared_upload.filename,
        content_type: prepared_upload.content_type
      )

      statement.save!
      statement
    rescue ActiveRecord::RecordNotUnique
      duplicate = duplicate_for(family, prepared_upload)
      raise DuplicateUploadError, duplicate if duplicate

      raise
    end

    def prepare_upload!(file)
      filename = file.original_filename.to_s
      content = file.read
      file.rewind if file.respond_to?(:rewind)

      byte_size = content.to_s.bytesize
      raise InvalidUploadError if byte_size.zero?
      raise InvalidUploadError if byte_size > MAX_FILE_SIZE
      raise InvalidUploadError unless valid_pdf_content?(content)

      PreparedUpload.new(
        content: content,
        filename: filename,
        content_type: "application/pdf",
        byte_size: byte_size,
        content_sha256: Digest::SHA256.hexdigest(content)
      )
    end

    def valid_pdf_content?(content)
      content.to_s.start_with?("%PDF-")
    end

    def duplicate_for(family, prepared_upload)
      return nil if prepared_upload.content_sha256.blank?

      family.account_statements.find_by(content_sha256: prepared_upload.content_sha256)
    end
  end

  def original_file_content
    original_file.download if original_file.attached?
  end
end
