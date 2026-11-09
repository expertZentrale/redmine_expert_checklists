require File.expand_path('../../test_helper', __FILE__)

class ExpertChecklistTemplateTest < ActiveSupport::TestCase
  include ExpertChecklistsTestHelper

  fixtures :projects, :users, :roles, :members, :member_roles, :issues, :issue_statuses,
           :trackers, :projects_trackers, :enumerations, :enabled_modules

  def setup
    @project = enable_checklists
    @bug = Tracker.find(1)
    @feature = Tracker.find(2)
  end

  def default_for(tracker, user = User.find(2))
    ExpertChecklistTemplate.default_for(@project, tracker, user)
  end

  def test_parse_reads_the_paste_format
    rows = ExpertChecklistTemplate.parse("-- Prep\r\n[x] Buy milk\n- Bake\n\n[ ] Eat\n--Done")
    assert_equal [['Prep', false, true], ['Buy milk', true, false], ['Bake', false, false],
                  ['Eat', false, false], ['Done', false, true]],
                 rows.map { |row| [row['subject'], row['is_done'], row['is_section']] }
  end

  def test_items_are_normalized_and_required
    template = ExpertChecklistTemplate.new(:name => 'T', :items => "a\r\nb\r\n")
    assert template.valid?
    assert_equal "a\nb", template.items
    template.items = "\n  \n"
    assert_not template.valid?
    assert template.errors[:items].any?
  end

  def test_default_precedence
    global_all = add_template(:project_id => nil, :is_default => true, :name => 'global all')
    global_bug = add_template(:project_id => nil, :is_default => true, :tracker_id => 1, :name => 'global bug')
    assert_equal global_bug, default_for(@bug)
    assert_equal global_all, default_for(@feature)

    project_all = add_template(:is_default => true, :name => 'project all')
    assert_equal project_all, default_for(@bug)
    project_bug = add_template(:is_default => true, :tracker_id => 1, :name => 'project bug')
    assert_equal project_bug, default_for(@bug)
    assert_equal project_all, default_for(@feature)
  end

  def test_no_default_without_the_module_or_a_default_flag
    add_template(:name => 'not default')
    assert_nil default_for(@bug)
    add_template(:is_default => true)
    @project.disable_module!(:expert_checklists)
    assert_nil ExpertChecklistTemplate.default_for(@project.reload, @bug, User.find(2))
  end

  def test_private_templates_only_for_their_author
    template = add_template(:is_public => false, :is_default => true)
    assert_equal template, default_for(@bug, User.find(2))
    assert_nil default_for(@bug, User.find(3))
    assert_nil default_for(@bug, User.find(1))
  end

  def test_available_for_filters_project_and_tracker
    add_template(:project_id => 2, :name => 'other project')
    add_template(:tracker_id => 1, :name => 'bugs only')
    add_template(:name => 'all trackers')
    add_template(:project_id => nil, :name => 'global')
    names = ExpertChecklistTemplate.available_for(@project, @feature, User.find(2)).map(&:name)
    assert_equal ['all trackers', 'global'], names.sort
  end

  def test_editable_by
    Role.find(1).add_permission!(:manage_expert_checklist_templates)
    private_one = add_template(:author_id => 3, :is_public => false)
    assert_not private_one.editable_by?(User.find(2))
    assert private_one.editable_by?(User.find(1))
    public_one = add_template(:author_id => 3)
    assert public_one.editable_by?(User.find(2))
    assert_not public_one.editable_by?(User.find(3))
    global = add_template(:project_id => nil)
    assert global.editable_by?(User.find(1))
    assert_not global.editable_by?(User.find(2))
  end

  def test_matches_compares_subjects_and_sections
    template = add_template(:items => "-- S\na")
    assert template.matches?(template.build_items)
    ticked = template.build_items
    ticked.last.is_done = true
    assert template.matches?(ticked)
    renamed = template.build_items
    renamed.last.subject = 'b'
    assert_not template.matches?(renamed)
  end

  def test_default_is_applied_to_new_issues_but_not_to_copies
    add_template(:is_default => true, :items => "-- Check\nReproduce")
    issue = Issue.new(:project => @project, :tracker => @bug, :author => User.find(2), :subject => 'New')
    issue.expert_checklists_apply_default_template(User.find(2))
    assert_equal %w(Check Reproduce), issue.expert_checklist_items.map(&:subject)
    assert issue.expert_checklist_items.first.is_section?

    copy = Issue.new.copy_from(Issue.find(1))
    copy.expert_checklists_apply_default_template(User.find(2))
    assert_empty copy.expert_checklist_items.to_a
  end

  def test_deleting_a_category_keeps_its_templates
    category = ExpertChecklistTemplateCategory.create!(:name => 'C')
    template = add_template(:category_id => category.id)
    category.destroy
    assert_nil template.reload.category_id
  end
end
