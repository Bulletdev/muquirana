class TransactionAttachmentsController < ApplicationController
  before_action :set_transaction
  before_action :set_attachment, only: %i[show destroy]
  before_action :require_owner!, only: %i[create destroy]

  def show
    disposition = params[:disposition] == "attachment" ? "attachment" : "inline"
    redirect_to rails_blob_url(@attachment, disposition: disposition)
  end

  def create
    attachments = attachment_params

    if attachments.blank?
      respond_to do |format|
        format.html { redirect_back_or_to transaction_path(@transaction), alert: t("transaction_attachments.no_files_selected") }
        format.turbo_stream { flash.now[:alert] = t("transaction_attachments.no_files_selected") }
      end
      return
    end

    @transaction.with_lock do
      current_count = @transaction.attachments.count
      new_count = attachments.is_a?(Array) ? attachments.length : 1

      if current_count + new_count > Transaction::MAX_ATTACHMENTS_PER_TRANSACTION
        respond_to do |format|
          format.html { redirect_back_or_to transaction_path(@transaction), alert: t("transaction_attachments.cannot_exceed", count: Transaction::MAX_ATTACHMENTS_PER_TRANSACTION) }
          format.turbo_stream { flash.now[:alert] = t("transaction_attachments.cannot_exceed", count: Transaction::MAX_ATTACHMENTS_PER_TRANSACTION) }
        end
        return
      end

      existing_ids = @transaction.attachments.pluck(:id)
      attachment_proxy = @transaction.attachments.attach(attachments)

      if @transaction.valid?
        message = new_count == 1 ? t("transaction_attachments.uploaded_one") : t("transaction_attachments.uploaded_many", count: new_count)
        respond_to do |format|
          format.html { redirect_back_or_to transaction_path(@transaction), notice: message }
          format.turbo_stream { flash.now[:notice] = message }
        end
      else
        # Purge blobs that were just attached but failed validation
        newly_added = Array(attachment_proxy).reject { |a| existing_ids.include?(a.id) }
        newly_added.each(&:purge)
        error_messages = @transaction.errors.full_messages_for(:attachments).join(", ")
        respond_to do |format|
          format.html { redirect_back_or_to transaction_path(@transaction), alert: t("transaction_attachments.failed_upload", error: error_messages) }
          format.turbo_stream { flash.now[:alert] = t("transaction_attachments.failed_upload", error: error_messages) }
        end
      end
    end
  rescue => e
    logger.error "#{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
    respond_to do |format|
      format.html { redirect_back_or_to transaction_path(@transaction), alert: t("transaction_attachments.upload_failed") }
      format.turbo_stream { flash.now[:alert] = t("transaction_attachments.upload_failed") }
    end
  end

  def destroy
    @attachment.purge
    message = t("transaction_attachments.attachment_deleted")
    respond_to do |format|
      format.html { redirect_back_or_to transaction_path(@transaction), notice: message }
      format.turbo_stream { flash.now[:notice] = message }
    end
  rescue => e
    logger.error "#{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
    respond_to do |format|
      format.html { redirect_back_or_to transaction_path(@transaction), alert: t("transaction_attachments.delete_failed") }
      format.turbo_stream { flash.now[:alert] = t("transaction_attachments.delete_failed") }
    end
  end

  private
    def set_transaction
      @transaction = Current.family.transactions.find(params[:transaction_id])
    end

    def set_attachment
      @attachment = @transaction.attachments.find(params[:id])
    end

    # Single family: only the family owner (admin) may manage attachments.
    def require_owner!
      return if Current.user.admin?

      respond_to do |format|
        format.html { redirect_back_or_to transaction_path(@transaction), alert: t("transaction_attachments.not_authorized") }
        format.turbo_stream do
          flash.now[:alert] = t("transaction_attachments.not_authorized")
          render turbo_stream: flash_notification_stream_items
        end
      end
    end

    def attachment_params
      if params.has_key?(:attachments)
        Array(params.fetch(:attachments, [])).reject(&:blank?).map do |param|
          param.respond_to?(:permit) ? param.permit(:file, :filename, :content_type, :description, :metadata) : param
        end
      elsif params.has_key?(:attachment)
        param = params[:attachment]
        return nil if param.blank?
        param.respond_to?(:permit) ? param.permit(:file, :filename, :content_type, :description, :metadata) : param
      end
    end
end
