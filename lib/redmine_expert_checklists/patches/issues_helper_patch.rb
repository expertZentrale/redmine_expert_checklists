module RedmineExpertChecklists
  module Patches
    # Renders checklist history entries (ours, and RedmineUP's legacy ones once
    # that plugin is gone or switched off in the issue's project) as one line
    # per changed item. Every place core lists
    # journal details goes through details_to_strings: the history tab, both
    # notification mail formats, the PDF export and the journals Atom feed.
    #
    # UnboundMethod capture rather than prepend: RedmineUP Checklists wraps
    # details_to_strings with alias_method. Its plugin directory sorts before
    # ours, so we wrap its wrapper and hand it everything that is not ours.
    module IssuesHelperPatch
      def self.apply!(base = IssuesHelper)
        return if base.instance_variable_get(:@expert_checklists_patched)

        original = base.instance_method(:details_to_strings)
        base.send(:define_method, :details_to_strings) do |details, no_html = false, options = {}|
          issue = RedmineExpertChecklists::DetailRenderer.issue_for(details, @issue)
          ours, rest = details.partition { |detail| RedmineExpertChecklists::DetailRenderer.handles?(detail, issue) }
          strings = original.bind(self).call(rest, no_html, options)
          ours.each { |detail| strings.concat(RedmineExpertChecklists::DetailRenderer.strings(detail, no_html)) }
          strings
        end

        base.instance_variable_set(:@expert_checklists_patched, true)
      end
    end
  end
end
