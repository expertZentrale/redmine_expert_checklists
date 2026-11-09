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

# RedmineUP's template tables, same reason.
unless ActiveRecord::Base.connection.table_exists?('checklist_template_categories')
  ActiveRecord::Base.connection.create_table :checklist_template_categories do |t|
    t.string :name
    t.integer :position, :default => 1
  end
end
unless ActiveRecord::Base.connection.table_exists?('checklist_templates')
  ActiveRecord::Base.connection.create_table :checklist_templates do |t|
    t.string :name
    t.integer :project_id
    t.integer :category_id
    t.integer :user_id
    t.boolean :is_public
    t.text :template_items
    t.boolean :is_default, :default => false
    t.integer :tracker_id
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

  # Takes all three checklist permissions from the role; any one of them
  # shows the checklist.
  def revoke_checklists(role = Role.find(1))
    RedmineExpertChecklists::VIEW_PERMISSIONS.each { |permission| role.remove_permission!(permission) }
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

  def insert_legacy_template(id, project_id, name, items, options = {})
    connection = ActiveRecord::Base.connection
    bool = lambda { |value| value ? connection.quoted_true : connection.quoted_false }
    connection.execute(
      'INSERT INTO checklist_templates (id, project_id, name, template_items, category_id, user_id, is_public, ' \
      'is_default, tracker_id) ' \
      "VALUES (#{id.to_i}, #{project_id ? project_id.to_i : 'NULL'}, #{connection.quote(name)}, " \
      "#{connection.quote(items)}, #{options[:category_id] ? options[:category_id].to_i : 'NULL'}, " \
      "#{options.fetch(:user_id, 2).to_i}, #{bool.call(options.fetch(:is_public, true))}, " \
      "#{bool.call(options[:is_default])}, #{options[:tracker_id] ? options[:tracker_id].to_i : 'NULL'})"
    )
  end

  def add_template(attributes = {})
    ExpertChecklistTemplate.create!({ :project_id => 1, :name => 'Template', :items => "One\nTwo",
                                      :author_id => 2 }.merge(attributes))
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
