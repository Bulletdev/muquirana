require "test_helper"

class TransactionAttachmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @transaction = entries(:transaction).transaction
  end

  def valid_upload
    file_fixture_upload("profile_image.png", "image/png")
  end

  test "family owner can attach a file" do
    sign_in users(:family_admin)

    assert_difference -> { @transaction.attachments.count }, 1 do
      post transaction_attachments_url(@transaction), params: { attachments: [ valid_upload ] }
    end

    assert_redirected_to transaction_path(@transaction)
  end

  test "non owner cannot attach a file" do
    sign_in users(:family_member)

    assert_no_difference -> { @transaction.attachments.count } do
      post transaction_attachments_url(@transaction), params: { attachments: [ valid_upload ] }
    end

    assert_redirected_to transaction_path(@transaction)
    assert flash[:alert].present?
  end

  test "rejects an unsupported file type and purges the blob" do
    sign_in users(:family_admin)

    assert_no_difference -> { @transaction.attachments.count } do
      post transaction_attachments_url(@transaction),
        params: { attachments: [ file_fixture_upload("imports/valid.csv", "text/csv") ] }
    end

    assert_redirected_to transaction_path(@transaction)
    assert flash[:alert].present?
  end

  test "cannot exceed the maximum number of attachments" do
    sign_in users(:family_admin)

    Transaction::MAX_ATTACHMENTS_PER_TRANSACTION.times do |i|
      @transaction.attachments.attach(
        io: StringIO.new("x"),
        filename: "existing#{i}.png",
        content_type: "image/png"
      )
    end

    assert_no_difference -> { @transaction.attachments.count } do
      post transaction_attachments_url(@transaction), params: { attachments: [ valid_upload ] }
    end

    assert_redirected_to transaction_path(@transaction)
    assert flash[:alert].present?
  end

  test "family owner can remove an attachment" do
    sign_in users(:family_admin)
    @transaction.attachments.attach(
      io: file_fixture("profile_image.png").open,
      filename: "receipt.png",
      content_type: "image/png"
    )
    attachment = @transaction.attachments.first

    assert_difference -> { @transaction.attachments.count }, -1 do
      delete transaction_attachment_url(@transaction, attachment)
    end

    assert_redirected_to transaction_path(@transaction)
  end

  test "non owner cannot remove an attachment" do
    @transaction.attachments.attach(
      io: file_fixture("profile_image.png").open,
      filename: "receipt.png",
      content_type: "image/png"
    )
    attachment = @transaction.attachments.first
    sign_in users(:family_member)

    assert_no_difference -> { @transaction.attachments.count } do
      delete transaction_attachment_url(@transaction, attachment)
    end

    assert flash[:alert].present?
  end

  test "show redirects to the blob" do
    sign_in users(:family_admin)
    @transaction.attachments.attach(
      io: file_fixture("profile_image.png").open,
      filename: "receipt.png",
      content_type: "image/png"
    )
    attachment = @transaction.attachments.first

    get transaction_attachment_url(@transaction, attachment)
    assert_response :redirect
  end
end
