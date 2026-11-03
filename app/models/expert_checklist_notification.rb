# A checklist journal whose notification mail has not gone out yet.
#
# RedmineExpertChecklists::Recorder creates the row with the journal (core's own
# mail is switched off for it) and bumps revision/due_at whenever the same user
# changes the checklist again within the bundle window. The job enqueued for a
# revision claims the row by deleting it; a job for an older revision deletes
# nothing and stops. Row locks make the claim and a concurrent merge exclusive
# across pods: either the merge wins (the old job stops, a new one is queued)
# or the claim wins (the merge finds no row and starts a new journal).
class ExpertChecklistNotification < (defined?(ApplicationRecord) ? ApplicationRecord : ActiveRecord::Base)
  SWEEP_CACHE_KEY = 'redmine_expert_checklists:notification_sweep'.freeze
  # A due row is only re-enqueued once its own job had this long to run.
  SWEEP_GRACE = 30.seconds
  SWEEP_BATCH = 50

  # Sends the mail for one revision. Returns true when a mail was handed to
  # core (deliver_issue_edit queues one per recipient).
  def self.deliver(journal_id, revision)
    claimed = where(:journal_id => journal_id, :revision => revision).
                where('due_at <= ?', Time.now + 1.second).delete_all
    return false unless claimed == 1

    journal = Journal.find_by(:id => journal_id)
    return false unless journal && journal.journalized
    return false unless RedmineExpertChecklists.notify_enabled?

    # Core picks the recipients (assignee, author, watchers, mentions; private
    # notes and notification preferences respected) and drops everybody for
    # whom journal.visible_details is empty - JournalPatch hides checklist
    # details from users without the view permission.
    Mailer.deliver_issue_edit(journal)
    true
  end

  def self.enqueue(journal_id, revision, due_at = nil)
    job = ExpertChecklistNotificationJob
    job = job.set(:wait_until => due_at) if due_at && due_at > Time.now
    job.perform_later(journal_id, revision)
    true
  rescue NotImplementedError, StandardError => e
    # The :inline adapter (tests, some setups) cannot schedule; the sweeper
    # picks the row up once it is due.
    Rails.logger.info("redmine_expert_checklists: notification for journal #{journal_id} left to the sweeper (#{e.class})")
    false
  end

  # Re-enqueues overdue rows whose job was lost (pod restart). Called after
  # every checklist write; runs at most once a minute across all pods (Redis
  # SET NX in production). Never raises.
  def self.sweep_if_due
    return unless Rails.cache.write(SWEEP_CACHE_KEY, true, :expires_in => 1.minute, :unless_exist => true)

    sweep!
  rescue StandardError => e
    Rails.logger.warn("redmine_expert_checklists: notification sweep skipped (#{e.class}: #{e.message})")
    nil
  end

  # grace: how long past due_at a row must be before it counts as lost.
  def self.sweep!(limit = SWEEP_BATCH, grace = SWEEP_GRACE)
    rows = where('due_at < ?', Time.now - grace).order(:due_at).limit(limit).pluck(:journal_id, :revision)
    rows.each { |journal_id, revision| enqueue(journal_id, revision) }
    rows.size
  end
end
