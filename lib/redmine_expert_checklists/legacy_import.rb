module RedmineExpertChecklists
  # Takes over what RedmineUP Checklists left in the database. Reads its tables
  # with plain SQL - the plugin itself may already be gone - and writes ours.
  # Every phase can run again: permissions and modules are only added, queries
  # only rewritten where they still name RedmineUP's columns and filters.
  #
  #   import = LegacyImport.new
  #   import.report                      # counts, nothing written
  #   import.run(%w(items permissions))  # report after writing
  #   LegacyImport.new(:projects => [project]).run(LegacyImport::PROJECT_PHASES)
  #
  # Which side holds an issue's current checklist: while RedmineUP is
  # installed, RedmineUP does in every project where our module is off, so the
  # items step copies those issues again, replacing what an earlier run copied.
  # In projects with our module on, and everywhere once RedmineUP is gone, ours
  # do: only issues without items of ours are imported.
  #
  # With :projects, items, saved queries and the module step only touch those
  # projects. That switches projects over one at a time while RedmineUP stays
  # installed, which needs its permissions in a project module of their own
  # (RedmineExpertChecklists.legacy_switchable?); the module step switches that
  # one off where it switches ours on. Steps that change what users see refuse
  # otherwise, unless forced: our module next to an active RedmineUP shows two
  # checklists on every issue, and saved queries converted while projects
  # still use RedmineUP find nothing there.
  class LegacyImport
    PHASES = %w(items permissions settings queries modules).freeze
    NEEDS_REDMINEUP_GONE = %w(queries modules).freeze
    # Switching single projects; permissions and settings are global steps.
    PROJECT_PHASES = %w(items queries modules).freeze
    BATCH = 500

    PERMISSIONS = {
      :view_checklists => :view_expert_checklists,
      :done_checklists => :done_expert_checklists,
      :edit_checklists => :edit_expert_checklists
    }.freeze
    COLUMNS = { :checklist_relations => :expert_checklist }.freeze
    FILTERS = { 'checklists_status' => 'expert_checklist_status',
                'checklists_item' => 'expert_checklist_item' }.freeze

    attr_reader :force, :projects

    def self.available?
      connection.table_exists?('checklists')
    end

    def self.connection
      ActiveRecord::Base.connection
    end

    # RedmineUP's items of one issue as unsaved items of ours, in its order;
    # what a copy of an issue still using RedmineUP starts with.
    def self.items_of(issue_id)
      section = connection.column_exists?(:checklists, :is_section) ? 'is_section' : connection.quoted_false
      rows = connection.select_rows(
        "SELECT subject, is_done, #{section}, position FROM checklists " \
        "WHERE issue_id = #{issue_id.to_i} ORDER BY position, id"
      )
      rows.reject { |subject, *| subject.to_s.strip.empty? }.map do |subject, is_done, is_section, position|
        ExpertChecklistItem.new(:subject => subject.to_s.strip[0, RedmineExpertChecklists::SUBJECT_MAX],
                                :is_done => is_done, :is_section => is_section, :position => position)
      end
    end

    # options: :force, :replace (see the rake task), :projects (Project
    # records or ids; limits items, queries and modules to them). :replace
    # deletes items of every project, so it is ignored with :projects.
    def initialize(options = {})
      @projects = Array(options[:projects]).compact.map { |project| project.is_a?(Project) ? project : Project.find(project) }
      @force = options[:force] ? true : false
      @replace = options[:replace] && @projects.empty? ? true : false
    end

    # Chosen projects with neither issue tracking nor our module: the module
    # step skips them, so their items and queries would change while
    # RedmineUP stays on. Switched ones may run again (RedmineUP's module off).
    def ineligible_projects
      projects.reject do |project|
        project.module_enabled?(:issue_tracking) || RedmineExpertChecklists.enabled?(project)
      end
    end

    def projects?
      projects.any?
    end

    def blocked?(phase)
      return false if force || !RedmineExpertChecklists.redmineup_present?

      case phase
      when 'modules'
        !RedmineExpertChecklists.legacy_switchable?
      when 'queries'
        !(RedmineExpertChecklists.legacy_switchable? && (projects? || projects_left.zero?))
      else
        false
      end
    end

    # Switching single projects needs RedmineUP switchable per project.
    def switch_blocked?
      blocked?('modules')
    end

    # What a run would do. Never writes.
    def report
      result = { 'redmineup_installed' => RedmineExpertChecklists.redmineup_present?,
                 'legacy_table' => self.class.available?,
                 'switchable' => RedmineExpertChecklists.legacy_switchable? }
      result.merge!(items_report) if result['legacy_table']
      result['roles'] = roles_to_update.size
      result['queries'] = queries_to_convert.size
      result['projects'] = projects_to_enable.size
      result['projects_switched'] = EnabledModule.where(:name => RedmineExpertChecklists::MODULE.to_s).count
      result['settings'] = mapped_settings
      result
    end

    # Projects that use issue tracking and do not have our module yet.
    def projects_left_ids
      projects_to_enable
    end

    def projects_left
      projects_left_ids.size
    end

    # Phases run in PHASES order whatever order they are given in: items must
    # be copied while RedmineUP still holds the issues, before modules.
    def run(phases)
      phases = PHASES & Array(phases).map(&:to_s)
      # Switching our module on without copying the items would hide them
      # (and RedmineUP's module goes off with it).
      phases = PHASES & (phases + ['items']) if phases.include?('modules') && !blocked?('modules')
      # Switching projects is all or nothing; a global run commits batch by batch.
      return run_phases(phases) unless projects?
      if ineligible_projects.any?
        raise ArgumentError, "Projects without issue tracking: #{ineligible_projects.map(&:identifier).join(', ')}"
      end

      ActiveRecord::Base.transaction { run_phases(phases) }
    end

    private

    def run_phases(phases)
      done = {}
      phases.each do |phase|
        done[phase] = blocked?(phase) ? 'blocked' : send("import_#{phase}")
      end
      stamp unless done.empty?
      done
    end

    def connection
      self.class.connection
    end

    def legacy_column?(name)
      connection.column_exists?(:checklists, name)
    end

    def project_ids
      projects.map(&:id)
    end

    # SQL condition on issues aliased i, limiting a run to its projects.
    def project_condition
      projects? ? " AND i.project_id IN (#{project_ids.join(',')})" : ''
    end

    # ---- items -----------------------------------------------------------

    def items_report
      orphans =
        if projects?
          0
        else
          connection.select_value(
            'SELECT COUNT(*) FROM checklists c LEFT JOIN issues i ON i.id = c.issue_id WHERE i.id IS NULL'
          ).to_i
        end
      existing = "FROM checklists c INNER JOIN issues i ON i.id = c.issue_id WHERE 1=1#{project_condition}"
      blank = connection.select_value(
        "SELECT COUNT(*) #{existing} AND (c.subject IS NULL OR TRIM(c.subject) = '')"
      ).to_i
      long = connection.select_value(
        "SELECT COUNT(*) #{existing} AND LENGTH(c.subject) > #{RedmineExpertChecklists::SUBJECT_MAX}"
      ).to_i
      issues = connection.select_value("SELECT COUNT(DISTINCT c.issue_id) #{existing}").to_i
      {
        'legacy_items' => connection.select_value("SELECT COUNT(*) #{existing}").to_i + orphans,
        'legacy_issues' => issues,
        'orphan_items' => orphans,
        'blank_items' => blank,
        'long_items' => long,
        'issues_to_import' => pending_issue_ids.size,
        'issues_to_clear' => emptied_issue_ids.size,
        'issues_already_imported' => issues - pending_issue_ids.size
      }
    end

    # Legacy issues that exist and whose checklist RedmineUP still holds (see
    # the class comment): while it is installed, those in projects without our
    # module; afterwards, those without items of ours.
    def pending_issue_ids
      @pending_issue_ids ||= begin
        condition =
          if RedmineExpertChecklists.redmineup_present?
            legacy_live_condition
          else
            "NOT EXISTS (SELECT 1 FROM #{ExpertChecklistItem.table_name} e WHERE e.issue_id = c.issue_id)"
          end
        connection.select_values(<<~SQL).map(&:to_i)
          SELECT DISTINCT c.issue_id FROM checklists c
          INNER JOIN issues i ON i.id = c.issue_id
          WHERE #{condition}#{project_condition}
          ORDER BY c.issue_id
        SQL
      end
    end

    # Issues RedmineUP still holds whose checklist was emptied there after an
    # earlier copy: the copy goes too.
    def emptied_issue_ids
      return [] unless RedmineExpertChecklists.redmineup_present?

      @emptied_issue_ids ||= connection.select_values(<<~SQL).map(&:to_i)
        SELECT DISTINCT e.issue_id FROM #{ExpertChecklistItem.table_name} e
        INNER JOIN issues i ON i.id = e.issue_id
        WHERE #{legacy_live_condition}#{project_condition}
          AND NOT EXISTS (SELECT 1 FROM checklists c WHERE c.issue_id = e.issue_id)
        ORDER BY e.issue_id
      SQL
    end

    # Issues aliased i in projects without our module.
    def legacy_live_condition
      "i.project_id NOT IN (SELECT em.project_id FROM #{EnabledModule.table_name} em " \
        "WHERE em.name = '#{RedmineExpertChecklists::MODULE}')"
    end

    def import_items
      return { 'imported' => 0 } unless self.class.available?

      replace_existing if @replace
      imported = 0
      renumbered = 0
      replaced = 0
      emptied_issue_ids.each_slice(BATCH) do |ids|
        replaced += ExpertChecklistItem.where(:issue_id => ids).delete_all
      end
      pending_issue_ids.each_slice(BATCH) do |ids|
        ExpertChecklistItem.transaction do
          # An earlier copy of an issue RedmineUP still holds is out of date.
          replaced += ExpertChecklistItem.where(:issue_id => ids).delete_all
          collisions = connection.select_values(<<~SQL).map(&:to_i)
            SELECT c.id FROM checklists c
            INNER JOIN #{ExpertChecklistItem.table_name} e ON e.id = c.id
            WHERE c.issue_id IN (#{ids.join(',')})
          SQL
          imported += insert_items(ids, collisions, true)
          unless collisions.empty?
            renumbered += insert_items(ids, collisions, false)
          end
        end
      end
      connection.reset_pk_sequence!(ExpertChecklistItem.table_name) if connection.respond_to?(:reset_pk_sequence!)
      @pending_issue_ids = @emptied_issue_ids = nil
      { 'imported' => imported + renumbered, 'new_ids' => renumbered, 'replaced' => replaced }
    end

    # keep_ids: insert every row whose id is free with that id (history JSON
    # and API clients refer to it); otherwise insert the colliding rows with new
    # ids. Collisions only happen where both plugins were used side by side.
    def insert_items(issue_ids, collisions, keep_ids)
      falsy = connection.quoted_false
      section = legacy_column?(:is_section) ? "COALESCE(c.is_section, #{falsy})" : falsy
      created = legacy_column?(:created_at) ? 'COALESCE(c.created_at, CURRENT_TIMESTAMP)' : 'CURRENT_TIMESTAMP'
      updated = legacy_column?(:updated_at) ? 'COALESCE(c.updated_at, c.created_at, CURRENT_TIMESTAMP)' : created
      id_filter =
        if collisions.empty?
          keep_ids ? '' : ' AND 1=0'
        else
          " AND c.id #{keep_ids ? 'NOT IN' : 'IN'} (#{collisions.join(',')})"
        end
      columns = 'issue_id, subject, is_done, is_section, position, created_at, updated_at'
      select = "c.issue_id, SUBSTR(TRIM(c.subject), 1, #{RedmineExpertChecklists::SUBJECT_MAX}), " \
               "COALESCE(c.is_done, #{falsy}), #{section}, COALESCE(c.position, 1), #{created}, #{updated}"
      if keep_ids
        columns = "id, #{columns}"
        select = "c.id, #{select}"
      end
      connection.exec_update(<<~SQL)
        INSERT INTO #{ExpertChecklistItem.table_name} (#{columns})
        SELECT #{select} FROM checklists c
        WHERE c.issue_id IN (#{issue_ids.join(',')})
          AND c.subject IS NOT NULL AND TRIM(c.subject) <> ''#{id_filter}
        ORDER BY c.issue_id, c.position, c.id
      SQL
    end

    # Re-import over a rehearsal: only while no project uses our module, so no
    # real data of ours can be lost.
    def replace_existing
      return if EnabledModule.where(:name => RedmineExpertChecklists::MODULE.to_s).exists?

      ExpertChecklistItem.delete_all
      @pending_issue_ids = @emptied_issue_ids = nil
    end

    # ---- permissions -----------------------------------------------------

    def roles_to_update
      Role.all.to_a.select do |role|
        PERMISSIONS.any? { |legacy, ours| role.permissions.include?(legacy) && !role.permissions.include?(ours) }
      end
    end

    def import_permissions
      roles = roles_to_update
      roles.each do |role|
        PERMISSIONS.each do |legacy, ours|
          role.add_permission!(ours) if role.permissions.include?(legacy) && !role.permissions.include?(ours)
        end
      end
      { 'roles' => roles.size }
    end

    # ---- settings --------------------------------------------------------

    def legacy_settings
      value = Setting.where(:name => 'plugin_redmine_checklists').pluck(:value).first
      return {} if value.blank?

      data = YAML.safe_load(value, :permitted_classes => permitted_yaml_classes, :aliases => true)
      data.is_a?(Hash) ? data.to_h.transform_keys(&:to_s) : {}
    rescue StandardError
      # A format we cannot read: fall back to the two flags by pattern.
      { 'issue_done_ratio' => (value.to_s =~ /issue_done_ratio['"]?:\s*['"]?(1|true)/ ? '1' : '0'),
        'block_issue_closing' => (value.to_s =~ /block_issue_closing['"]?:\s*['"]?(1|true)/ ? '1' : '0') }
    end

    def permitted_yaml_classes
      classes = [Symbol, ActiveSupport::HashWithIndifferentAccess]
      configured = Rails.configuration.active_record.yaml_column_permitted_classes rescue nil
      classes + Array(configured)
    end

    def mapped_settings
      legacy = legacy_settings
      events = Setting.notified_events
      notifications =
        if events.include?('issue_updated') then 'issue_updated'
        elsif events.include?('checklist_updated') then 'always'
        else 'never'
        end
      {
        'notifications' => notifications,
        'done_ratio_from_checklist' => LegacyDiff.truthy?(legacy['issue_done_ratio']) ? '1' : '0',
        'block_issue_closing' => LegacyDiff.truthy?(legacy['block_issue_closing']) ? '1' : '0'
      }
    end

    def import_settings
      mapped = mapped_settings
      Setting.plugin_redmine_expert_checklists = RedmineExpertChecklists.settings.to_h.merge(mapped)
      mapped
    end

    # ---- saved queries ---------------------------------------------------

    # With :projects, only queries of those projects; global ones follow once
    # every project has been switched.
    def queries_to_convert
      scope = projects? ? IssueQuery.where(:project_id => project_ids) : IssueQuery.all
      scope.to_a.select do |query|
        (query.column_names || []).any? { |name| COLUMNS.key?(name.to_sym) } ||
          (query.filters || {}).keys.any? { |field| FILTERS.key?(field.to_s) }
      end
    end

    def import_queries
      queries = queries_to_convert
      queries.each do |query|
        if query.column_names
          query.column_names = query.column_names.map { |name| COLUMNS[name.to_sym] || name }
        end
        query.filters = convert_filters(query.filters || {})
        query.save(:validate => false)
      end
      { 'queries' => queries.size }
    end

    # RedmineUP's "is not done/undone" matched issues having an item in the
    # other state, which is ours with the opposite value.
    def convert_filters(filters)
      filters.each_with_object({}) do |(field, filter), converted|
        name = FILTERS[field.to_s]
        if name.nil?
          converted[field] = filter
          next
        end
        filter = filter.to_h.transform_keys(&:to_sym)
        if name == 'expert_checklist_status' && filter[:operator].to_s == '!'
          filter = { :operator => '=', :values => Array(filter[:values]).map { |v| v.to_s == '1' ? '0' : '1' }.uniq }
        end
        converted[name] = filter
      end
    end

    # ---- modules ---------------------------------------------------------

    def projects_to_enable
      enabled = EnabledModule.where(:name => RedmineExpertChecklists::MODULE.to_s).select(:project_id)
      scope = EnabledModule.where(:name => 'issue_tracking').where.not(:project_id => enabled)
      scope = scope.where(:project_id => project_ids) if projects?
      scope.pluck(:project_id)
    end

    # RedmineUP's own module, when it has one; never issue_tracking.
    def legacy_module_name
      name = RedmineExpertChecklists.legacy_module
      name if RedmineExpertChecklists.legacy_switchable? && name.present?
    end

    # Ours on, RedmineUP's own module off: one checklist per issue. A global
    # run also changes the modules new projects start with.
    def import_modules
      ours = RedmineExpertChecklists::MODULE.to_s
      ids = projects_to_enable
      ids.each { |id| EnabledModule.create!(:project_id => id, :name => ours) }
      switched_off = 0
      if (legacy = legacy_module_name)
        # Ids first: MySQL cannot delete from a table it reads in a subquery.
        switched = EnabledModule.where(:name => ours).pluck(:project_id)
        switched &= project_ids if projects?
        switched_off = EnabledModule.where(:name => legacy, :project_id => switched).delete_all
      end
      update_default_modules(ours, legacy) unless projects?
      { 'projects' => ids.size, 'redmineup_off' => switched_off }
    end

    def update_default_modules(ours, legacy)
      defaults = Setting.default_projects_modules
      updated = defaults.dup
      updated += [ours] if updated.include?('issue_tracking') && !updated.include?(ours)
      updated -= [legacy] if legacy && updated.include?(ours)
      Setting.default_projects_modules = updated if updated != defaults
    end

    def stamp
      Setting.plugin_redmine_expert_checklists =
        RedmineExpertChecklists.settings.to_h.merge('legacy_import_done_at' => Time.now.strftime('%Y-%m-%d %H:%M'))
    end
  end
end
