require File.expand_path('../../test_helper', __FILE__)

class ExpertChecklistItemTest < ActiveSupport::TestCase
  include ExpertChecklistsTestHelper

  fixtures :projects, :users, :roles, :members, :member_roles, :issues, :issue_statuses,
           :trackers, :projects_trackers, :enumerations

  def setup
    @issue = Issue.find(1)
  end

  def test_requires_subject_and_issue
    item = ExpertChecklistItem.new
    assert_not item.valid?
    assert item.errors[:subject].any?
    assert item.errors[:issue].any?
  end

  def test_subject_is_limited_to_1000_characters
    item = ExpertChecklistItem.new(:issue => @issue, :subject => 'x' * 1001)
    assert_not item.valid?
    item.subject = 'x' * 1000
    assert item.valid?
  end

  def test_line_breaks_and_padding_are_removed
    item = ExpertChecklistItem.create!(:issue => @issue, :subject => "  first\r\nsecond  ")
    assert_equal 'first second', item.subject
  end

  def test_items_without_position_go_to_the_end
    add_items(@issue, 'a', 'b')
    item = ExpertChecklistItem.create!(:issue => @issue, :subject => 'c')
    assert_equal 3, item.position
    assert_equal %w(a b c), @issue.reload.expert_checklist_items.map(&:subject)
  end

  def test_given_position_is_kept
    item = ExpertChecklistItem.create!(:issue => @issue, :subject => 'first', :position => 7)
    assert_equal 7, item.position
  end

  def test_export_line
    done, open, section = add_items(@issue, '[x] done', 'open', '-- Section')
    assert_equal '[+] done', done.to_export_line
    assert_equal '[-] open', open.to_export_line
    assert_equal 'Section', section.to_export_line
  end

  def test_items_are_deleted_with_the_issue
    add_items(@issue, 'a', 'b')
    assert_difference 'ExpertChecklistItem.count', -2 do
      @issue.destroy
    end
  end

  def test_done_ratio_floors_to_tens_and_skips_sections
    items = add_items(@issue, '-- Section', '[x] a', '[x] b', 'c')
    assert_equal 60, RedmineExpertChecklists.done_ratio_for(items)
    assert_nil RedmineExpertChecklists.done_ratio_for(items.select(&:is_section?))
  end
end
