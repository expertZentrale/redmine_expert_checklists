# Loads Redmine's own test helper - the tests require a Redmine environment
# (the Docker container or a Redmine checkout), they cannot run standalone.
require File.expand_path(File.dirname(__FILE__) + '/../../../test/test_helper')

# RedmineUP Checklists' table, for the import tests where that plugin is not
# installed (GitHub CI). Created here, outside any test transaction: DDL inside
# one would commit it on MariaDB and break the fixture rollback.
unless ActiveRecord::Base.connection.table_exists?('checklists')
  ActiveRecord::Base.connection.create_table :checklists do |t|
    t.boolean :is_done, :default => false
    t.string :subject, :limit => 512
    t.integer :position, :default => 1
    t.integer :issue_id, :null => false
    t.timestamps :null => true
    t.boolean :is_section, :default => false
  end
end

module ExpertChecklistsTestHelper
  # Project 1 (ecookbook) with the module on; role 1 (Manager, jsmith's role
  # there) may view, tick and edit.
  def enable_checklists(project = Project.find(1), role = Role.find(1))
    project.enable_module!(:expert_checklists)
    [:view_expert_checklists, :done_expert_checklists, :edit_expert_checklists].each do |permission|
      role.add_permission!(permission)
    end
    project
  end

  def with_checklist_settings(values)
    saved = Setting.plugin_redmine_expert_checklists
    Setting.plugin_redmine_expert_checklists = saved.merge(values.transform_keys(&:to_s))
    yield
  ensure
    Setting.plugin_redmine_expert_checklists = saved
  end

  def add_items(issue, *subjects)
    subjects.each_with_index.map do |subject, index|
      done = subject.start_with?('[x] ')
      section = subject.start_with?('-- ')
      ExpertChecklistItem.create!(:issue => issue, :subject => subject.sub(/\A(\[x\] |-- )/, ''),
                                  :is_done => done, :is_section => section, :position => index + 1)
    end
  end

  # The job of the bundled mails goes to the :test adapter, so tests decide
  # when it runs; the mail jobs core queues stay :inline (Redmine's test env).
  def use_test_job_adapter
    @expert_checklists_adapter = ExpertChecklistNotificationJob.queue_adapter
    ExpertChecklistNotificationJob.queue_adapter = :test
  end

  def restore_job_adapter
    ExpertChecklistNotificationJob.queue_adapter = @expert_checklists_adapter if @expert_checklists_adapter
  end

  def enqueued_checklist_jobs
    ExpertChecklistNotificationJob.queue_adapter.enqueued_jobs.select do |job|
      job[:job] == ExpertChecklistNotificationJob || job['job_class'] == 'ExpertChecklistNotificationJob'
    end
  end

  def checklist_details(journal)
    journal.details.select { |detail| detail.property == RedmineExpertChecklists::DETAIL_PROPERTY }
  end

  def insert_legacy_item(id, issue_id, subject, is_done = false, position = 1, is_section = false)
    connection = ActiveRecord::Base.connection
    connection.execute(
      "INSERT INTO checklists (id, issue_id, subject, is_done, position, is_section, created_at, updated_at) " \
      "VALUES (#{id.to_i}, #{issue_id.to_i}, #{connection.quote(subject)}, " \
      "#{is_done ? connection.quoted_true : connection.quoted_false}, #{position.to_i}, " \
      "#{is_section ? connection.quoted_true : connection.quoted_false}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
    )
  end
end
