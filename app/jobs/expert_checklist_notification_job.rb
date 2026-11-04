# Sends the bundled notification of one checklist journal once its bundle
# window has passed. See ExpertChecklistNotification for the claim protocol.
class ExpertChecklistNotificationJob < ActiveJob::Base
  queue_as :default

  def perform(journal_id, revision)
    ExpertChecklistNotification.deliver(journal_id, revision)
  end
end
