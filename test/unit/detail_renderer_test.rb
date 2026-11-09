require File.expand_path('../../test_helper', __FILE__)

class DetailRendererTest < ActiveSupport::TestCase
  include ExpertChecklistsTestHelper

  fixtures :projects, :users, :issues, :issue_statuses, :trackers, :projects_trackers, :enumerations,
           :enabled_modules

  def setup
    User.current = nil
    ::I18n.locale = :en
  end

  def snap(subject, done = false, section = false)
    RedmineExpertChecklists.snapshot(subject, done, section).to_json
  end

  def detail(old_value, value, property = RedmineExpertChecklists::DETAIL_PROPERTY, prop_key = '1')
    JournalDetail.new(:property => property, :prop_key => prop_key, :old_value => old_value, :value => value)
  end

  def render(detail, no_html = true)
    RedmineExpertChecklists::DetailRenderer.strings(detail, no_html)
  end

  def test_added_deleted_done_reopened
    assert_equal ['Checklist item Buy milk added'], render(detail(nil, snap('Buy milk')))
    assert_equal ['Checklist section Shopping added'], render(detail(nil, snap('Shopping', false, true)))
    assert_equal ['Checklist item Buy milk deleted'], render(detail(snap('Buy milk'), nil))
    assert_equal ['Checklist item Buy milk done'], render(detail(snap('Buy milk'), snap('Buy milk', true)))
    assert_equal ['Checklist item Buy milk reopened'], render(detail(snap('Buy milk', true), snap('Buy milk')))
  end

  def test_rename_and_tick_in_one_detail_gives_two_lines
    lines = render(detail(snap('Buy mlk'), snap('Buy milk', true)))
    assert_equal ['Checklist item changed from Buy mlk to Buy milk', 'Checklist item Buy milk done'], lines
  end

  def test_html_escapes_subjects
    line = render(detail(nil, snap('<b>x</b>')), false).first
    assert line.html_safe?
    assert_include '<strong>Checklist</strong>', line
    assert_include '<i>&lt;b&gt;x&lt;/b&gt;</i>', line
  end

  def test_legacy_redmineup_snapshots_are_diffed_by_id
    RedmineExpertChecklists.stubs(:redmineup_present?).returns(false)
    old = [{ 'id' => 1, 'subject' => 'a', 'is_done' => false, 'position' => 1 },
           { 'checklist' => { 'id' => 2, 'subject' => 'b', 'is_done' => false } }].to_json
    new = [{ 'id' => 1, 'subject' => 'a', 'is_done' => true, 'position' => 1 },
           { 'id' => 3, 'subject' => 'c', 'is_done' => false, 'is_section' => true }].to_json
    legacy = detail(old, new, 'attr', 'checklist')
    assert RedmineExpertChecklists::DetailRenderer.handles?(legacy)
    assert_equal ['Checklist item a done', 'Checklist item b deleted', 'Checklist section c added'], render(legacy)
  end

  def test_legacy_reorder_only
    RedmineExpertChecklists.stubs(:redmineup_present?).returns(false)
    old = [{ 'id' => 1, 'subject' => 'a', 'position' => 1 }, { 'id' => 2, 'subject' => 'b', 'position' => 2 }]
    legacy = detail(old.to_json, old.reverse.to_json, 'attr', 'checklist')
    assert_equal ['Checklist reordered'], render(legacy)
  end

  def test_legacy_rows_without_ids_are_matched_by_subject
    RedmineExpertChecklists.stubs(:redmineup_present?).returns(false)
    old = [{ 'subject' => 'a', 'is_done' => false }, { 'subject' => 'b', 'is_done' => false }].to_json
    new = [{ 'subject' => 'a', 'is_done' => true }, { 'subject' => 'c', 'is_done' => false }].to_json
    assert_equal ['Checklist item a done', 'Checklist item b deleted', 'Checklist item c added'],
                 render(detail(old, new, 'attr', 'checklist'))
  end

  def test_legacy_text_format_falls_back_to_changed_from
    RedmineExpertChecklists.stubs(:redmineup_present?).returns(false)
    legacy = detail('[ ] a', '[x] a', 'attr', 'checklist')
    assert_equal ['Checklist changed from [ ] a to [x] a'], render(legacy)
  end

  def test_legacy_details_are_left_to_redmineup_while_it_is_installed
    RedmineExpertChecklists.stubs(:redmineup_present?).returns(true)
    assert_not RedmineExpertChecklists::DetailRenderer.handles?(detail('[]', '[]', 'attr', 'checklist'))
  end

  def test_details_to_strings_renders_ours_and_passes_the_rest_to_core
    view = ActionView::Base.respond_to?(:empty) ? ActionView::Base.empty : ActionView::Base.new
    view.extend(IssuesHelper)
    # RedmineUP's wrapper (dev image) reads @issue like the history view sets it.
    view.instance_variable_set(:@issue, Issue.find(1))
    details = [detail(nil, snap('Buy milk')),
               JournalDetail.new(:property => 'attr', :prop_key => 'done_ratio', :old_value => '0', :value => '50')]
    strings = view.details_to_strings(details, true)
    assert_include 'Checklist item Buy milk added', strings
    assert strings.any? { |s| s.include?('% Done') }
  end

  def test_legacy_details_are_ours_where_the_project_has_switched
    RedmineExpertChecklists.stubs(:redmineup_present?).returns(true)
    legacy = detail('[]', '[]', 'attr', 'checklist')
    assert_not RedmineExpertChecklists::DetailRenderer.handles?(legacy, Issue.find(1))
    Project.find(1).enable_module!(:expert_checklists)
    assert RedmineExpertChecklists::DetailRenderer.handles?(legacy, Issue.find(1))
  end

  def test_details_to_strings_renders_legacy_details_of_a_switched_project
    RedmineExpertChecklists.stubs(:redmineup_present?).returns(true)
    Project.find(1).enable_module!(:expert_checklists)
    view = ActionView::Base.respond_to?(:empty) ? ActionView::Base.empty : ActionView::Base.new
    view.extend(IssuesHelper)
    view.instance_variable_set(:@issue, Issue.find(1))
    old = [{ 'id' => 1, 'subject' => 'a', 'is_done' => false }].to_json
    new = [{ 'id' => 1, 'subject' => 'a', 'is_done' => true }].to_json
    assert_equal ['Checklist item a done'], view.details_to_strings([detail(old, new, 'attr', 'checklist')], true)
  end
end
