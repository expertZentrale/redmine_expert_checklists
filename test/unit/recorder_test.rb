require File.expand_path('../../test_helper', __FILE__)

# Direct changes (ticks, REST): history entries and the bundled, delayed mail.
class RecorderTest < ActiveSupport::TestCase
  include ExpertChecklistsTestHelper

  fixtures :projects, :users, :email_addresses, :user_preferences, :roles, :members, :member_roles,
           :issues, :issue_statuses, :trackers, :projects_trackers, :enumerations,
           :enabled_modules, :journals, :journal_details, :watchers

  def setup
    enable_checklists
    use_test_job_adapter
    @issue = Issue.find(1)
    @admin = User.find(1)
    @items = add_items(@issue, 'Buy milk', 'Bake bread')
    User.current = @admin
    ActionMailer::Base.deliveries.clear
  end

  def teardown
    restore_job_adapter
    User.current = nil
  end

  def tick(item, done = true, user = @admin)
    RedmineExpertChecklists::Recorder.call(@issue, user) { item.update!(:is_done => done) }
  end

  def recipients
    ActionMailer::Base.deliveries.flat_map { |mail| Array(mail.to) + Array(mail.cc) + Array(mail.bcc) }
  end

  def test_tick_writes_a_journal_and_no_mail_in_the_request
    journal = tick(@items[0])
    assert journal.persisted?
    assert_equal 1, checklist_details(journal).size
    assert_empty ActionMailer::Base.deliveries
    row = ExpertChecklistNotification.find_by(:journal_id => journal.id)
    assert_equal 1, row.revision
    assert_equal [[journal.id, 1]], enqueued_checklist_jobs.map { |job| job[:args] }.uniq
  end

  def test_ticks_within_the_window_merge_into_one_journal_and_one_mail
    first = tick(@items[0])
    travel 20.seconds do
      second = tick(@items[1])
      assert_equal first.id, second.id
      assert_equal 2, checklist_details(second.reload).size
      assert_equal 2, ExpertChecklistNotification.find_by(:journal_id => first.id).revision
    end

    travel 85.seconds do
      # The job for revision 1 finds nothing to send.
      assert_equal false, ExpertChecklistNotification.deliver(first.id, 1)
      assert_empty ActionMailer::Base.deliveries
      assert ExpertChecklistNotification.deliver(first.id, 2)
    end
    assert ActionMailer::Base.deliveries.any?
    body = ActionMailer::Base.deliveries.last.text_part.body.to_s
    assert_include 'Checklist item Buy milk done', body
    assert_include 'Checklist item Bake bread done', body
    assert_nil ExpertChecklistNotification.find_by(:journal_id => first.id)
  end

  def test_tick_and_untick_cancel_out
    journal = tick(@items[0])
    travel 5.seconds do
      assert_nil tick(@items[0], false)
    end
    assert_nil Journal.find_by(:id => journal.id)
    assert_nil ExpertChecklistNotification.find_by(:journal_id => journal.id)
  end

  def test_tick_after_the_window_starts_a_new_journal
    first = tick(@items[0])
    travel 61.seconds do
      assert_not_equal first.id, tick(@items[1]).id
    end
  end

  def test_another_user_starts_a_new_journal
    first = tick(@items[0])
    assert_not_equal first.id, tick(@items[1], true, User.find(2)).id
  end

  def test_a_comment_in_between_starts_a_new_journal
    first = tick(@items[0])
    @issue.reload.init_journal(User.find(2), 'A note')
    @issue.save!
    assert_not_equal first.id, tick(@items[1]).id
  end

  def test_the_bundle_stops_growing_after_ten_minutes
    items = add_items(@issue, *('a'..'m').to_a)
    base = Time.now.change(:usec => 0)
    first = travel_to(base) { tick(items[0]) }
    journals = (1..12).map { |step| travel_to(base + (step * 50).seconds) { tick(items[step]) } }
    assert_equal [first.id], journals[0..10].map(&:id).uniq
    assert_not_equal first.id, journals[11].id
  end

  def test_reorder_alone_writes_nothing
    assert_no_difference 'Journal.count' do
      assert_nil RedmineExpertChecklists::Recorder.call(@issue, @admin) { @items[0].update!(:position => 9) }
    end
  end

  def test_never_sends_no_mail
    journal = tick(@items[0])
    with_checklist_settings('notifications' => 'never') do
      travel 61.seconds do
        assert_equal false, ExpertChecklistNotification.deliver(journal.id, 1)
      end
    end
    assert_empty ActionMailer::Base.deliveries
  end

  def test_users_without_view_permission_get_no_mail
    journal = tick(@items[0])
    travel(61.seconds) { ExpertChecklistNotification.deliver(journal.id, 1) }
    assert_include 'jsmith@somenet.foo', recipients

    ActionMailer::Base.deliveries.clear
    Role.find(1).remove_permission!(:view_expert_checklists)
    journal = tick(@items[1])
    travel(61.seconds) { ExpertChecklistNotification.deliver(journal.id, 1) }
    assert_not_include 'jsmith@somenet.foo', recipients
  end

  def test_sweeper_requeues_overdue_rows
    journal = tick(@items[0])
    ExpertChecklistNotificationJob.queue_adapter.enqueued_jobs.clear
    travel 2.minutes do
      assert_equal 1, ExpertChecklistNotification.sweep!
    end
    assert_equal [[journal.id, 1]], enqueued_checklist_jobs.map { |job| job[:args] }
  end

  def test_inline_adapter_leaves_the_row_for_the_sweeper
    ExpertChecklistNotificationJob.queue_adapter = :inline
    journal = tick(@items[0])
    assert ExpertChecklistNotification.find_by(:journal_id => journal.id)
  end

  def test_done_ratio_follows_the_checklist
    with_settings(:issue_done_ratio => 'issue_field') do
      with_checklist_settings('done_ratio_from_checklist' => '1') do
        journal = tick(@items[0])
        assert_equal 50, @issue.reload.done_ratio
        ratio = journal.details.detect { |d| d.property == 'attr' && d.prop_key == 'done_ratio' }
        assert_equal '50', ratio.value
      end
    end
  end

  # Our own write leaves lock_version alone (other plugins' journal callbacks
  # may still save the issue; the tick response hands the page the new value).
  def test_tick_updates_updated_on
    travel 1.hour do
      tick(@items[0])
      assert_in_delta Time.now.to_i, @issue.reload.updated_on.to_i, 2
    end
  end
end
