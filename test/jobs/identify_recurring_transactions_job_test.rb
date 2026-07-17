require "test_helper"

class IdentifyRecurringTransactionsJobTest < ActiveJob::TestCase
  setup do
    @family = families(:dylan_family)
  end

  test "schedule_for enqueues a debounced job for the family" do
    assert_enqueued_with(job: IdentifyRecurringTransactionsJob) do
      IdentifyRecurringTransactionsJob.schedule_for(@family)
    end
  end

  test "identify_patterns_for schedules the job" do
    assert_enqueued_jobs 1, only: IdentifyRecurringTransactionsJob do
      RecurringTransaction.identify_patterns_for(@family)
    end
  end
end
