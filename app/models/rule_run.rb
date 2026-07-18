class RuleRun < ApplicationRecord
  belongs_to :rule

  validates :execution_type, inclusion: { in: %w[manual scheduled] }
  validates :status, inclusion: { in: %w[pending success failed] }
  validates :executed_at, presence: true
  validates :transactions_queued, numericality: { greater_than_or_equal_to: 0 }
  validates :transactions_processed, numericality: { greater_than_or_equal_to: 0 }
  validates :transactions_modified, numericality: { greater_than_or_equal_to: 0 }
  validates :pending_jobs_count, numericality: { greater_than_or_equal_to: 0 }

  scope :recent, -> { order(executed_at: :desc) }
  scope :for_rule, ->(rule) { where(rule: rule) }
  scope :successful, -> { where(status: "success") }
  scope :failed, -> { where(status: "failed") }
  scope :pending, -> { where(status: "pending") }

  def pending?
    status == "pending"
  end

  def success?
    status == "success"
  end

  def failed?
    status == "failed"
  end

  def transactions_blocked
    [ transactions_processed - transactions_modified, 0 ].max
  end

  # Thread-safe helper to record the completion of an async job tied to this run
  # (e.g. AI enrichment batches). Marks the run as successful once every pending
  # job reports back.
  def complete_job!(modified_count: 0)
    with_lock do
      increment!(:transactions_modified, modified_count)
      decrement!(:pending_jobs_count)

      update!(status: "success") if pending_jobs_count <= 0
    end
  end
end
