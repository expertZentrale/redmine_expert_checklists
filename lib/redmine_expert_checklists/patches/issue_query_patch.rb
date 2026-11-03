module RedmineExpertChecklists
  module Patches
    # Issue list integration: the "Checklist" column (HTML, CSV, PDF) and two
    # filters - by done state and by item text.
    #
    # UnboundMethod capture, because redmine_agile, redmine_contacts_helpdesk
    # and redmine_expert_agile wrap available_columns, issues and
    # initialize_available_filters too (some with alias_method). ExpertAgileQuery
    # inherits from IssueQuery, so expert agile boards get the column as well.
    module IssueQueryPatch
      COLUMN = :expert_checklist
      STATUS_FILTER = 'expert_checklist_status'.freeze
      ITEM_FILTER = 'expert_checklist_item'.freeze

      def self.offered?(project, user = User.current)
        if project
          RedmineExpertChecklists.enabled?(project) && user.allowed_to?(:view_expert_checklists, project)
        else
          user.allowed_to?(:view_expert_checklists, nil, :global => true)
        end
      end

      def self.apply!(base = IssueQuery)
        return if base.instance_variable_get(:@expert_checklists_query_patched)

        base.include(SqlMethods)

        original_columns = base.instance_method(:available_columns)
        base.send(:define_method, :available_columns) do
          columns = original_columns.bind(self).call
          if columns.none? { |column| column.name == COLUMN } &&
             RedmineExpertChecklists::Patches::IssueQueryPatch.offered?(project)
            columns << QueryColumn.new(COLUMN, :caption => :label_expert_checklist,
                                               :sortable => false, :groupable => false)
          end
          columns
        end

        original_filters = base.instance_method(:initialize_available_filters)
        visibility = base.private_method_defined?(:initialize_available_filters) ? :private : :public
        base.send(:define_method, :initialize_available_filters) do
          original_filters.bind(self).call
          next unless RedmineExpertChecklists::Patches::IssueQueryPatch.offered?(project)

          add_available_filter(STATUS_FILTER,
                               :type => :list_optional, :name => l(:field_expert_checklist_status),
                               :values => lambda {
                                 [[l(:label_expert_checklist_status_open), '0'],
                                  [l(:label_expert_checklist_status_done), '1']]
                               })
          add_available_filter(ITEM_FILTER, :type => :string, :name => l(:field_expert_checklist_item))
        end
        base.send(visibility, :initialize_available_filters)

        # One query per page for the column instead of one per row.
        original_issues = base.instance_method(:issues)
        base.send(:define_method, :issues) do |*args|
          rows = original_issues.bind(self).call(*args)
          RedmineExpertChecklists::Patches::IssueQueryPatch.preload(rows) if has_column?(COLUMN)
          rows
        end

        base.instance_variable_set(:@expert_checklists_query_patched, true)
      end

      def self.preload(issues)
        ids = issues.map(&:id)
        return if ids.empty?

        by_issue = ExpertChecklistItem.where(:issue_id => ids).order(:issue_id, :position, :id).group_by(&:issue_id)
        issues.each { |issue| issue.expert_checklist_preloaded = by_issue[issue.id] || [] }
      end

      # Dispatched by Query#statement for a saved filter even when the filter is
      # not offered to the current user; the permission condition keeps the
      # results inside what the user may see.
      module SqlMethods
        def sql_for_expert_checklist_status_field(_field, operator, value)
          base = expert_checklist_subquery("eci.is_section = #{expert_checklist_false}")
          sql =
            case operator
            when '*' then "EXISTS (#{base})"
            when '!*' then "NOT EXISTS (#{base})"
            else
              states = Array(value).map { |v| v.to_s == '1' }.uniq
              return(operator == '!' ? '1=1' : '1=0') if states.empty?

              condition = states.map { |done| "eci.is_done = #{done ? expert_checklist_true : expert_checklist_false}" }
              "#{'NOT ' if operator == '!'}EXISTS (#{base} AND (#{condition.join(' OR ')}))"
            end
          expert_checklist_visible(sql)
        end

        def sql_for_expert_checklist_item_field(field, operator, value)
          base = expert_checklist_subquery
          sql =
            case operator
            when '*' then "EXISTS (#{base})"
            when '!*' then "NOT EXISTS (#{base})"
            when '!', '!~'
              positive = operator == '!' ? '=' : '~'
              "NOT EXISTS (#{base} AND #{sql_for_field(field, positive, value, 'eci', 'subject')})"
            else
              "EXISTS (#{base} AND #{sql_for_field(field, operator, value, 'eci', 'subject')})"
            end
          expert_checklist_visible(sql)
        end

        private

        def expert_checklist_subquery(condition = nil)
          sql = "SELECT 1 FROM #{ExpertChecklistItem.table_name} eci WHERE eci.issue_id = #{Issue.table_name}.id"
          condition ? "#{sql} AND #{condition}" : sql
        end

        def expert_checklist_visible(sql)
          "(#{Project.allowed_to_condition(User.current, :view_expert_checklists)} AND #{sql})"
        end

        def expert_checklist_true
          ExpertChecklistItem.connection.quoted_true
        end

        def expert_checklist_false
          ExpertChecklistItem.connection.quoted_false
        end
      end
    end
  end
end
