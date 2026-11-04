module RedmineExpertChecklists
  module Patches
    # Draws the "Checklist" list cell as a compact list with done items struck
    # through. CSV and PDF do not come here; they print ListValue#to_s.
    #
    # UnboundMethod capture: RedmineUP Checklists and redmine_contacts wrap
    # column_value with alias_method.
    module QueriesHelperPatch
      def self.apply!(base = QueriesHelper)
        return if base.instance_variable_get(:@expert_checklists_patched)

        original = base.instance_method(:column_value)
        base.send(:define_method, :column_value) do |column, item, value|
          if column.name == RedmineExpertChecklists::Patches::IssueQueryPatch::COLUMN &&
             value.is_a?(RedmineExpertChecklists::ListValue)
            RedmineExpertChecklists::Patches::QueriesHelperPatch.list_html(self, value)
          else
            original.bind(self).call(column, item, value)
          end
        end

        base.instance_variable_set(:@expert_checklists_patched, true)
      end

      def self.list_html(view, value)
        view.content_tag(:ul, :class => 'ec-col') do
          view.safe_join(value.items.map do |item|
            css = item.is_section? ? 'ec-section' : (item.is_done? ? 'ec-done' : 'ec-open')
            text = item.is_section? ? item.subject : "#{item.is_done? ? "☑" : "☐"} #{item.subject}"
            view.content_tag(:li, text, :class => css)
          end)
        end
      end
    end
  end
end
