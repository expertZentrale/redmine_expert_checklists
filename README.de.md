> [English version](README.md) · 🇩🇪 Deutsche Version

# Redmine expert Checklisten

Checklisten an Redmine-Tickets: Punkte direkt auf der Ticketseite abhaken, die Liste im
Ticketformular bearbeiten und jede Änderung im Ticketverlauf wiederfinden. Schnelle Häkchen einer
Person werden zu **einem Verlaufseintrag und einer Mail** gebündelt, die im Hintergrund verschickt
wird. Ein Klick antwortet sofort, statt auf eine Mail je Beobachter zu warten. Dazu gibt es eine
REST-API, eine Spalte mit Filtern in der Ticketliste und eine Übernahme aus RedmineUP Checklists,
bei der dessen Verlauf lesbar bleibt.
Läuft mit **Redmine 5.1, 6.0, 6.1 und 7.0**.

## Was es kann

- **Ticketseite.** Ein Checklisten-Block unter der Beschreibung, mit Abschnitten, Fortschritt
  (`3/5`) und „Erledigte ausblenden“. Ein Häkchen wird sofort gespeichert; das Bearbeitungsformular
  auf derselben Seite zieht mit. Wer es danach speichert, macht das Häkchen weder rückgängig noch
  bekommt er die Meldung, jemand anderes habe das Ticket geändert.
- **Ticketformular.** Punkte beim Bearbeiten hinzufügen, umbenennen, abhaken, löschen und
  umsortieren: Enter fügt den nächsten Punkt hinzu, Ziehen am Griff oder Alt+Pfeil hoch/runter
  verschiebt ihn, mehrere eingefügte Zeilen werden zu je einem Punkt (`-- ` beginnt einen
  Abschnitt, `[x] ` markiert einen Punkt als erledigt). Beim Kopieren eines Tickets wird die
  Checkliste mitkopiert, ebenso beim Massenkopieren, beim Kopieren eines Projekts und bei kopierten
  Unteraufgaben.
- **Verlauf.** Eine Zeile je geändertem Punkt („Checkliste: Punkt *Milch kaufen* erledigt“).
  Reines Umsortieren schreibt keinen Verlauf.
- **Mails.** Siehe [Verlauf und Mails](#verlauf-und-mails).
- **% erledigt aus der Checkliste** (optional): der Anteil abgehakter Punkte, auf Zehner abgerundet.
- **Schließen sperren** (optional): Ein Ticket mit offenen Punkten kann nicht auf einen
  geschlossenen Status gesetzt werden.
- **Ticketliste.** Eine Spalte „Checkliste“ (auch im CSV- und PDF-Export, als Zeilen
  `[+] erledigt` / `[-] offen`) und zwei Filter: nach Zustand der Punkte (hat offene / erledigte
  Punkte, hat überhaupt eine Checkliste) und nach Text eines Punkts.
- **REST-API.** Siehe [REST-API](#rest-api).
- **Übernahme aus RedmineUP Checklists.** Siehe [Umstieg von RedmineUP Checklists](#umstieg-von-redmineup-checklists).

Die Texte der Punkte sind reiner Text; Ticketverweise wie `#123` werden zu Links.

## Verlauf und Mails

Ein Häkchen auf der Ticketseite (und jede Änderung über die REST-API) steht sofort im Ticketverlauf,
die Mail wartet aber. Weitere Häkchen derselben Person innerhalb von **60 Sekunden** landen im selben
Verlaufseintrag, und die Mail geht raus, sobald 60 Sekunden lang niemand mehr abgehakt hat. Wer
einen Punkt abhakt und das Häkchen gleich wieder entfernt, hinterlässt weder Verlaufseintrag noch
Mail. Ein Bündel schließt spätestens nach zehn Minuten, und sobald jemand anderes etwas am Ticket
schreibt.

Die Mail ist Redmines eigene Benachrichtigung „Ticket aktualisiert“. Empfänger,
Benachrichtigungseinstellungen und private Notizen funktionieren also wie bei jeder anderen
Änderung. Wer keine der Checklisten-Berechtigungen hat, bekommt keine Mail zu
Checklisten-Änderungen und sieht sie auch nicht im Verlauf. Ändert die Checkliste % erledigt, ist
das ein normales Ticketfeld und erscheint wie jede andere Änderung.

Checklisten-Änderungen, die **mit dem Ticketformular** gespeichert werden, gehören zu dieser
Bearbeitung: Sie stehen in deren Verlaufseintrag und deren Mail, sofort.

Die ausstehenden Mails liegen in einer Tabelle, nicht nur im Speicher. Startet Redmine innerhalb
der Minute neu, verschickt die nächste Checklisten-Änderung irgendwo im System, was liegen geblieben
ist. Wer davon unabhängig sein will, lässt einen externen Job
`POST /expert_checklists/notifications/flush.json` mit dem API-Schlüssel eines Administrators
aufrufen. Scheitert die Übergabe einer Mail an Redmine (Datenbank oder Job-Warteschlange nicht
erreichbar), wird sie mit wachsenden Abständen bis zu einem Tag lang erneut versucht und danach mit
einem Fehler im Log verworfen.

Einstellung *Mails bei Checklisten-Änderungen*:

| Wert | Bedeutung |
|---|---|
| Wie bei Ticket-Änderungen (Standard) | Verschickt, wenn Redmine Ticket-Änderungen verschickt (*Administration » Konfiguration » E-Mail-Benachrichtigungen*, „Ticket aktualisiert“) |
| Immer | Verschickt, auch wenn Redmine Ticket-Änderungen nicht verschickt |
| Nie | Keine Mails für Checklisten-Änderungen; Formular-Änderungen mit anderen Änderungen werden weiter verschickt |

## Berechtigungen

Alles hängt am Projektmodul **expert Checklisten**. Solange es in einem Projekt aus ist, zeigt das
Plugin dort nichts und lehnt seine API ab.

| Berechtigung | Erlaubt |
|---|---|
| Checklisten ansehen | Checkliste, ihren Verlauf, Listenspalte und Filter sehen; die API lesen |
| Checklistenpunkte abhaken | Alles, was „Checklisten ansehen“ erlaubt, dazu Punkte auf der Ticketseite abhaken und das Häkchen entfernen |
| Checklisten bearbeiten | Alles oben, dazu Punkte im Ticketformular und über die API hinzufügen, umbenennen, umsortieren und löschen |

## Ticketliste

Die Spalte ist weder sortier- noch gruppierbar. Filter:

| Filter | Operatoren |
|---|---|
| Checklistenpunkte | *ist* offen / erledigt (hat mindestens einen solchen Punkt), *ist nicht*, *irgendein* (hat eine Checkliste), *keiner* |
| Text eines Checklistenpunkts | Redmines Textoperatoren (enthält, beginnt mit, ist, ...); „enthält nicht“ trifft auch Tickets ohne Checkliste |

Abschnitte zählen weder für den Fortschritt noch für den Zustandsfilter.

## REST-API

| Anfrage | Pfad |
|---|---|
| Punkte eines Tickets auflisten | `GET /issues/:issue_id/expert_checklist_items.json` |
| Punkt hinzufügen | `POST /issues/:issue_id/expert_checklist_items.json` |
| Punkt anzeigen / ändern / löschen | `GET` / `PUT` / `DELETE /expert_checklist_items/:id.json` |
| Abhaken / Häkchen entfernen | `PUT /expert_checklist_items/:id/done.json` mit `is_done=1` / `0` |

Wurzelschlüssel `checklist`, Felder `id`, `issue_id`, `subject`, `is_done`, `position`,
`is_section`, `created_at`, `updated_at` (XML geht auch):

```bash
curl -X POST -H "X-Redmine-API-Key: $KEY" -H 'Content-Type: application/json' \
     -d '{"checklist": {"subject": "Teile bestellen"}}' \
     https://redmine.example/issues/42/expert_checklist_items.json
```

Die Ticket-API nimmt die ganze Liste als `issue[expert_checklist_items_attributes]` an (ein Array
aus `{id, subject, is_done, is_section, _destroy}`; die Positionen folgen der Reihenfolge).

**Für RedmineUP Checklists geschriebene Programme laufen weiter:** Sobald RedmineUP Checklists
entfernt ist, beantwortet das Plugin auch dessen Pfade (`/issues/:id/checklists`, `/checklists/:id`)
mit denselben Wurzelschlüsseln und Feldern und nimmt `issue[checklists_attributes]` an.

## Umstieg von RedmineUP Checklists

Beide Plugins können nebeneinander installiert sein. Unseres bleibt unsichtbar, bis sein
Projektmodul eingeschaltet ist; der Umstieg lässt sich also vorbereiten und proben. Die Projekte
wechseln alle auf einmal (unten) oder [einzeln](#projektweise).

1. Dieses Plugin neben RedmineUP Checklists installieren und die Migrationen laufen lassen.
2. *Administration » expert Checklisten » Übernahme öffnen*. Die Seite zeigt, was sie gefunden hat
   (Punkte, Tickets, Rollen, gespeicherte Abfragen, Projekte), ohne etwas zu schreiben. Checklisten,
   Berechtigungen und Einstellungen lassen sich hier schon zum Ausprobieren übernehmen.
3. Datenbank sichern, dann `plugins/redmine_checklists` entfernen und neu starten. **Nicht**
   `rake redmine:plugins:migrate NAME=redmine_checklists VERSION=0` ausführen: Das löscht die
   Tabellen von RedmineUP und damit die Daten, die übernommen werden sollen.
4. Die Übernahme mit allen Schritten ausführen. Jeder Schritt kann noch einmal laufen.

| Schritt | Was er tut |
|---|---|
| Checklisten | Kopiert die Punkte **mit denselben IDs**. Solange RedmineUP installiert ist, wird jedes Ticket eines Projekts ohne unser Modul neu kopiert und eine frühere Kopie ersetzt; ist die RedmineUP-Checkliste inzwischen leer, verschwindet auch die Kopie (dort ist RedmineUP noch in Gebrauch); sonst nur Tickets ohne Checkliste von uns. Punkte gelöschter Tickets und leere Punkte werden übersprungen; Texte werden auf 1000 Zeichen gekürzt. |
| Berechtigungen | Jede Rolle, die RedmineUP-Checklisten ansehen, abhaken oder bearbeiten darf, bekommt die passende Berechtigung. |
| Einstellungen | % erledigt und die Sperre beim Schließen übernehmen die Werte von RedmineUP; die Mail-Einstellung richtet sich nach dessen Benachrichtigungsereignis „Checkliste aktualisiert“. |
| Gespeicherte Abfragen | Die Checklisten-Spalte und -Filter von RedmineUP in gespeicherten Ticket-Abfragen werden durch unsere ersetzt. Abfragen mit dem alten Filter würden ohne RedmineUP fehlschlagen. |
| Projektmodul | Schaltet *expert Checklisten* in jedem Projekt mit Ticket-Tracking ein, und für neue Projekte. Hat RedmineUP ein eigenes Projektmodul (siehe unten), geht das dort aus. |

Die Verlaufseinträge von RedmineUP werden weiter als lesbare Zeilen angezeigt („Checkliste: Punkt
*X* erledigt“). Für große Installationen läuft dieselbe Übernahme als Rake-Task:

```bash
bundle exec rake redmine_expert_checklists:legacy_import DRY_RUN=1 RAILS_ENV=production
bundle exec rake redmine_expert_checklists:legacy_import RAILS_ENV=production
```

### Projektweise

Um einzelne Projekte umzustellen, während RedmineUP für die übrigen installiert bleibt, muss sich
RedmineUP pro Projekt abschalten lassen. Von Haus aus geht das nicht: Seine Berechtigungen gehören
zum Modul *Ticket-Tracking*. Einmal vorbereiten:

1. In `plugins/redmine_checklists/init.rb` die Berechtigungen in ein eigenes Modul legen:
   `map.project_module :checklists do |map|` statt `:issue_tracking`.
2. Dieses Modul in jedem Projekt mit Ticket-Tracking einschalten, und für neue Projekte
   (*Administration » Konfiguration » Projekte*), damit sich für niemanden etwas ändert.
3. Einiges macht RedmineUP ohne Berechtigungsprüfung: die Sperre beim Schließen, % erledigt nach
   dem Bearbeiten, das Mitkopieren der Punkte und seine Spalte in der Ticketliste. Diese Stellen
   ebenfalls mit `project.module_enabled?(:checklists)` absichern (`need_to_block_issue_closing?`,
   `controller_issues_edit_after_save`, `after_create_from_copy`, `checklist_relations`); sonst
   wirken seine eingefrorenen Punkte in umgestellten Projekten weiter.

Die Übernahmeseite zeigt dann *Projektweise umstellen*:

1. Zuerst *Berechtigungen* und *Einstellungen* übernehmen; sie gelten für alle Projekte.
2. Projekte wählen und umstellen. Für jedes Projekt werden in einer Transaktion die Checklisten
   seiner Tickets neu kopiert, die gespeicherten Abfragen des Projekts umgestellt, *expert
   Checklisten* ein- und das Modul von RedmineUP ausgeschaltet. Als Rake-Task:
   `rake redmine_expert_checklists:legacy_import PROJECTS=eins,zwei RAILS_ENV=production`.
3. Sind alle Projekte umgestellt, die übrigen gespeicherten Abfragen (die ohne Projekt) umstellen
   und RedmineUP entfernen; die Übernahme muss danach nicht noch einmal laufen.

Solange beide in Gebrauch sind:

- Die Verlaufseinträge von RedmineUP erscheinen auch in umgestellten Projekten.
- Wird ein Ticket aus einem Projekt, das noch RedmineUP nutzt, in ein umgestelltes kopiert, kommen
  die Punkte von RedmineUP mit. Umgekehrt kopiert RedmineUP seine Punkte im Stand der Umstellung.
- Die Filter von RedmineUP in der Ticketliste durchsuchen weiter alle seine Punkte, auch die
  eingefrorenen umgestellter Projekte. Seine REST-Pfade lehnen Tickets umgestellter Projekte ab;
  dort `/issues/:id/expert_checklist_items` verwenden.
- Ein Projekt zurückstellen: Modul von RedmineUP ein-, unseres ausschalten. RedmineUP zeigt seine
  Punkte im Stand der Umstellung; eine spätere Umstellung kopiert sie neu.

Unterschiede zu RedmineUP Checklists:

- Der Editor im Ticketformular braucht *Checklisten bearbeiten*; mit *Checklistenpunkte abhaken*
  allein hakt man nur auf der Ticketseite ab.
- Die Sperre beim Schließen gilt nur für den Wechsel auf einen geschlossenen Status; Notizen an
  einem bereits geschlossenen Ticket gehen weiter.
- Vorlagen und das Checklisten-Benutzerfeld gehören noch nicht zu dieser Version. Ihre Daten
  bleiben in den Tabellen von RedmineUP, bis eine spätere Version sie übernimmt.
- RedmineUP-Agile-Boards zeigen auf den Karten keine Checklisten mehr; Boards von
  redmine_expert_agile können die Spalte „Checkliste“ anzeigen.

## Sprachen

Die Oberfläche gibt es auf Englisch, Deutsch, Spanisch, Französisch, Italienisch und Portugiesisch
(`en`, `de`, `es`, `fr`, `it`, `pt`, `pt-BR`). Redmine zeigt jedem Benutzer die Sprache aus seinem
Konto oder die Standardsprache unter *Administration » Konfiguration » Anzeige*; für jede andere
Sprache fällt es auf Englisch zurück. Diese Dokumentation gibt es auf Englisch und Deutsch.

Korrekturen von Muttersprachlern sind als Pull Request auf `config/locales/<sprache>.yml`
willkommen. `test/unit/locale_files_test.rb` prüft, dass jede Sprache jeden Schlüssel aus `en.yml`
hat, in derselben Reihenfolge und mit denselben `%{…}`-Platzhaltern.

## Installation

```bash
cd /pfad/zu/redmine/plugins
git clone https://github.com/expertZentrale/redmine_expert_checklists.git
cd ..
bundle exec rake redmine:plugins:migrate NAME=redmine_expert_checklists RAILS_ENV=production
# Redmine neu starten
```

Danach das Modul **expert Checklisten** in den Projekten einschalten, die es nutzen sollen (oder
die Übernahme nutzen, die das erledigt), und den Rollen die Berechtigungen geben.

## Tests

```bash
bundle exec rake redmine:plugins:test NAME=redmine_expert_checklists RAILS_ENV=test
```

Die CI führt sie gegen Redmine 5.1, 6.0, 6.1 und 7.0 auf MariaDB aus, gegen 5.1 und 7.0 zusätzlich
auf MySQL und PostgreSQL, und startet die offiziellen Redmine-Docker-Images mit eingebundenem Plugin.

## Lizenz

GNU General Public License v2 oder später, siehe [LICENSE](LICENSE).
