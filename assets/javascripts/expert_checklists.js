/*
 * redmine_expert_checklists - issue page ticking and the issue form editor.
 *
 * No inline script: labels come from a JSON island (script.ec-config), URLs from
 * data attributes. Events are delegated from document, so markup replaced by
 * Redmine's issue form refresh (replaceIssueFormWith) keeps working; only the
 * drag-and-drop binding is per element and re-attached after every ajax call.
 */
(function () {
  'use strict';

  var $ = window.jQuery;
  if (!$) { return; }

  var STORAGE_KEY = 'expert_checklists_hide_done';
  var queues = {};

  function config() {
    var el = document.querySelector('script.ec-config');
    if (!el) { return { labels: {} }; }
    try { return JSON.parse(el.textContent); } catch (e) { return { labels: {} }; }
  }

  function label(key) {
    return config().labels[key] || key;
  }

  function csrfToken() {
    var meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? meta.getAttribute('content') : '';
  }

  function storage(key, value) {
    try {
      if (arguments.length > 1) { window.localStorage.setItem(key, value); return value; }
      return window.localStorage.getItem(key);
    } catch (e) {
      return null;
    }
  }

  /* ---------- Issue page: ticking ---------- */

  function updateProgress($list) {
    var $items = $list.find('li.ec-item');
    var done = $items.filter('.ec-done').length;
    var $progress = $list.find('.ec-progress');
    $progress.attr('data-done', done).attr('data-total', $items.length);
    $progress.text(done + '/' + $items.length);
    // A section is complete when every item up to the next section is done.
    $list.find('li.ec-section').each(function () {
      var $rows = $(this).nextUntil('li.ec-section', 'li.ec-item');
      $(this).toggleClass('ec-section-done', $rows.length > 0 && $rows.not('.ec-done').length === 0);
    });
  }

  // Keeps the edit form (on the same page) in step with a tick, so saving the
  // form afterwards neither reverts the tick nor fails as stale.
  function syncForm(data) {
    if (data.lock_version !== undefined) { $('#issue_lock_version').val(data.lock_version); }
    if (data.done_ratio !== undefined && data.done_ratio !== null) {
      $('#issue_done_ratio').val(String(data.done_ratio));
      if (data.done_ratio_html) { $('.issue .attributes .progress .value').html(data.done_ratio_html); }
    }
    var $row = $('[data-ec-editor] [data-ec-row][data-ec-id="' + data.id + '"]');
    if ($row.length) {
      $row.find('input.ec-edit-check').prop('checked', !!data.is_done);
      $row.find('input[data-ec-field="is_done_was"]').val(data.is_done ? '1' : '0');
    }
  }

  function tick($check) {
    var $item = $check.closest('li.ec-item');
    var $list = $check.closest('[data-ec-list]');
    var key = $list.attr('data-issue-id') || 'list';
    var isDone = $check.prop('checked');

    // Optimistic: the box and progress change at once, a failure rolls back.
    $item.toggleClass('ec-done', isDone);
    updateProgress($list);
    applyHideDone($list);

    // Ticks of one list go out one after another, in click order.
    var previous = queues[key] || $.Deferred().resolve().promise();
    queues[key] = previous.then(function () {
      return $.ajax({
        url: $check.attr('data-url'),
        type: 'PUT',
        dataType: 'json',
        headers: { 'X-CSRF-Token': csrfToken(), 'Accept': 'application/json' },
        data: { is_done: isDone ? '1' : '0' }
      }).done(function (data) {
        syncForm(data);
      }).fail(function () {
        $check.prop('checked', !isDone);
        $item.toggleClass('ec-done', !isDone);
        updateProgress($list);
        $list.find('.ec-progress').text(label('saveFailed'));
      }).then(null, function () { return $.Deferred().resolve().promise(); });
    });
  }

  function applyHideDone($list) {
    var hide = storage(STORAGE_KEY) === '1';
    var $button = $list.find('.ec-toggle-done');
    var doneCount = $list.find('li.ec-item.ec-done').length;
    $button.prop('hidden', doneCount === 0 && !hide);
    $button.attr('aria-pressed', hide ? 'true' : 'false');
    $button.text(hide ? label('showDone') : label('hideDone'));
    $list.toggleClass('ec-hide-done', hide);
  }

  $(document).on('change', '[data-ec-list] input.ec-check', function () {
    tick($(this));
  });

  $(document).on('click', '[data-ec-list] .ec-toggle-done', function (event) {
    event.preventDefault();
    var hide = storage(STORAGE_KEY) !== '1';
    storage(STORAGE_KEY, hide ? '1' : '0');
    applyHideDone($(this).closest('[data-ec-list]'));
  });

  /* ---------- Issue form: the editor ---------- */

  // Rows are submitted in display order; the server takes positions from it.
  function renumber($editor) {
    $editor.find('ul.ec-edit-items > li[data-ec-row]').each(function (index) {
      $(this).find('[name^="issue[expert_checklist_items_attributes]"]').each(function () {
        this.name = this.name.replace(/\[expert_checklist_items_attributes\]\[[^\]]*\]/,
          '[expert_checklist_items_attributes][' + index + ']');
      });
    });
  }

  function announce($editor, text) {
    $editor.find('.ec-live').text(text);
  }

  function newRow($editor, section) {
    var template = $editor.find(section ? 'template.ec-section-template' : 'template.ec-row-template')[0];
    var html = template.innerHTML.replace(/__INDEX__/g, String(Date.now()));
    return $($.parseHTML($.trim(html)));
  }

  function addRow($editor, $after, section, subject) {
    var $row = newRow($editor, section);
    if (subject) { $row.find('input.ec-subject-input').val(subject); }
    if ($after && $after.length) {
      $row.insertAfter($after);
    } else {
      $editor.find('ul.ec-edit-items').append($row);
    }
    renumber($editor);
    return $row;
  }

  function removeRow($row) {
    var $editor = $row.closest('[data-ec-editor]');
    var $prev = visibleRows($editor).eq(visibleRows($editor).index($row) - 1);
    if ($row.find('input[data-ec-field="id"]').length) {
      // Persisted: keep the row, flag it, hide it.
      $row.find('input[data-ec-field="_destroy"]').val('1');
      $row.addClass('ec-removed').prop('hidden', true);
    } else {
      $row.remove();
    }
    renumber($editor);
    return $prev;
  }

  function visibleRows($editor) {
    return $editor.find('ul.ec-edit-items > li[data-ec-row]').not('.ec-removed');
  }

  function move($row, direction) {
    var $editor = $row.closest('[data-ec-editor]');
    var $rows = visibleRows($editor);
    var index = $rows.index($row);
    var $target = $rows.eq(index + direction);
    if (index + direction < 0 || !$target.length) { return; }
    if (direction < 0) { $row.insertBefore($target); } else { $row.insertAfter($target); }
    renumber($editor);
    $row.find('input.ec-subject-input').trigger('focus');
    announce($editor, label('moved').replace('%{position}', String(visibleRows($editor).index($row) + 1)));
  }

  // One line per item; "-- " starts a section, "[x] " a done item, list bullets
  // and "[ ] " are dropped. Duplicates of existing rows are skipped.
  function parseLines(text) {
    return text.split(/\r?\n/).map(function (line) {
      var item = { subject: $.trim(line), section: false, done: false };
      if (/^--\s*/.test(item.subject)) {
        item.section = true;
        item.subject = $.trim(item.subject.replace(/^--\s*/, ''));
      }
      if (/^\[[xX]\]\s*/.test(item.subject)) { item.done = true; }
      item.subject = $.trim(item.subject.replace(/^(?:[-*•]\s+|\[[ xX]?\]\s*)/, ''));
      return item;
    }).filter(function (item) { return item.subject.length > 0; });
  }

  function existingSubjects($editor) {
    var seen = {};
    visibleRows($editor).find('input.ec-subject-input').each(function () {
      seen[$.trim(this.value).toLowerCase()] = true;
    });
    return seen;
  }

  function initEditor(editor) {
    var $editor = $(editor);
    if ($editor.attr('data-ec-ready')) { return; }
    $editor.attr('data-ec-ready', '1');
    renumber($editor);
    if ($.fn.sortable) {
      $editor.find('ul.ec-edit-items').sortable({
        handle: '.ec-handle',
        axis: 'y',
        items: '> li[data-ec-row]',
        update: function () { renumber($editor); }
      });
    }
  }

  function initAll() {
    $('[data-ec-editor]').each(function () { initEditor(this); });
    // Template categories on the settings page: core's drag-and-drop reordering.
    if ($.fn.positionedItems) {
      $('table.ec-template-categories tbody').not('.ui-sortable').positionedItems();
    }
    $('[data-ec-list]').each(function () {
      updateProgress($(this));
      applyHideDone($(this));
    });
  }

  $(document).on('click', '[data-ec-editor] .ec-add-item, [data-ec-editor] .ec-add-section', function () {
    var $editor = $(this).closest('[data-ec-editor]');
    var $row = addRow($editor, null, $(this).hasClass('ec-add-section'));
    $row.find('input.ec-subject-input').trigger('focus');
  });

  $(document).on('click', '[data-ec-editor] .ec-remove', function () {
    var $prev = removeRow($(this).closest('li[data-ec-row]'));
    if ($prev && $prev.length) { $prev.find('input.ec-subject-input').trigger('focus'); }
  });

  $(document).on('click', '[data-ec-editor] .ec-move-up', function () {
    move($(this).closest('li[data-ec-row]'), -1);
  });

  $(document).on('click', '[data-ec-editor] .ec-move-down', function () {
    move($(this).closest('li[data-ec-row]'), 1);
  });

  $(document).on('keydown', '[data-ec-editor] input.ec-subject-input', function (event) {
    var $row = $(this).closest('li[data-ec-row]');
    var $editor = $row.closest('[data-ec-editor]');
    if (event.key === 'Enter') {
      // Enter adds the next item instead of submitting the issue form.
      event.preventDefault();
      addRow($editor, $row, false).find('input.ec-subject-input').trigger('focus');
    } else if (event.key === 'Backspace' && this.value === '' && !$row.find('input[data-ec-field="id"]').length) {
      event.preventDefault();
      var $prev = removeRow($row);
      if ($prev && $prev.length) { $prev.find('input.ec-subject-input').trigger('focus'); }
    } else if (event.altKey && (event.key === 'ArrowUp' || event.key === 'ArrowDown')) {
      event.preventDefault();
      move($row, event.key === 'ArrowUp' ? -1 : 1);
    }
  });

  $(document).on('paste', '[data-ec-editor] input.ec-subject-input', function (event) {
    var clipboard = (event.originalEvent || event).clipboardData;
    var text = clipboard ? clipboard.getData('text/plain') : '';
    if (!/[\r\n]/.test(text)) { return; }
    event.preventDefault();
    var $row = $(this).closest('li[data-ec-row]');
    var $editor = $row.closest('[data-ec-editor]');
    var seen = existingSubjects($editor);
    var $after = $row;
    var input = this;
    parseLines(text).forEach(function (item) {
      var key = item.subject.toLowerCase();
      if (seen[key]) { return; }
      seen[key] = true;
      if (input && input.value === '' && !item.section) {
        input.value = item.subject;
        $(input).closest('li[data-ec-row]').find('input.ec-edit-check').prop('checked', item.done);
        input = null;
        return;
      }
      $after = addRow($editor, $after, item.section, item.subject);
      $after.find('input.ec-edit-check').prop('checked', item.done);
    });
  });

  // "Add from template": appends the template's items that are not in the list
  // yet (same text), like a paste of its lines. Rows come from script.ec-templates.
  $(document).on('change', '[data-ec-editor] select.ec-template', function () {
    var $editor = $(this).closest('[data-ec-editor]');
    var id = this.value;
    this.value = '';
    if (!id) { return; }
    var templates;
    try { templates = JSON.parse($editor.find('script.ec-templates').text()); } catch (e) { return; }
    var seen = existingSubjects($editor);
    var $after = visibleRows($editor).last();
    var added = 0;
    (templates[id] || []).forEach(function (row) {
      var key = $.trim(row.subject).toLowerCase();
      if (!key || seen[key]) { return; }
      seen[key] = true;
      $after = addRow($editor, $after, !!row.is_section, row.subject);
      $after.find('input.ec-edit-check').prop('checked', !!row.is_done);
      added += 1;
    });
    announce($editor, label('templateAdded').replace('%{count}', String(added)));
  });

  $(document).on('submit', 'form', function () {
    $(this).find('[data-ec-editor]').each(function () { renumber($(this)); });
  });

  $(initAll);
  $(document).ajaxComplete(initAll);
})();
