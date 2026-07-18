require "test_helper"

class TransactionTest < ActiveSupport::TestCase
  setup do
    @transaction = entries(:transaction).transaction
  end

  test "accepts a supported image attachment" do
    @transaction.attachments.attach(
      io: file_fixture("profile_image.png").open,
      filename: "receipt.png",
      content_type: "image/png"
    )

    assert @transaction.valid?
  end

  test "rejects an unsupported content type" do
    @transaction.attachments.attach(
      io: StringIO.new("plain text"),
      filename: "notes.txt",
      content_type: "text/plain"
    )

    assert @transaction.invalid?
    assert @transaction.errors[:attachments].present?
  end

  test "rejects an attachment above the size limit" do
    @transaction.attachments.attach(
      io: StringIO.new("x"),
      filename: "big.png",
      content_type: "image/png"
    )
    @transaction.attachments.first.blob.update!(byte_size: Transaction::MAX_ATTACHMENT_SIZE + 1)

    assert @transaction.invalid?
    assert @transaction.errors[:attachments].present?
  end

  test "rejects more than the maximum number of attachments" do
    (Transaction::MAX_ATTACHMENTS_PER_TRANSACTION + 1).times do |i|
      @transaction.attachments.attach(
        io: StringIO.new("x"),
        filename: "file#{i}.png",
        content_type: "image/png"
      )
    end

    assert @transaction.invalid?
    assert @transaction.errors[:attachments].present?
  end
end
