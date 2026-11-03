# POST /expert_checklists/notifications/flush (admin API key): queues every
# checklist mail that is due. Optional - the plugin sweeps overdue mails itself
# after every checklist change - but an external cron calling this makes sure
# a mail whose job died with a pod goes out even if nobody ticks afterwards.
class ExpertChecklistNotificationsController < ApplicationController
  accept_api_auth :flush
  before_action :require_admin

  def flush
    count = ExpertChecklistNotification.sweep!(500, 0.seconds)
    render :json => { :enqueued => count }
  end
end
