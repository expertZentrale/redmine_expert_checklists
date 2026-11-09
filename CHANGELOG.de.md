# Changelog – redmine_expert_checklists

> [English version](CHANGELOG.md) · 🇩🇪 Deutsche Version
>
> Maßgeblich ist die englische Fassung — daraus werden die Release-Notes erzeugt.

## [Unreleased]

### Hinzugefügt

- **Projektweise umstellen.** Die Übernahmeseite und der Rake-Task (`PROJECTS=`) stellen gewählte
  Projekte von RedmineUP Checklists um, während es für die übrigen installiert bleibt: Ihre
  Checklisten werden neu kopiert, ihre gespeicherten Abfragen umgestellt, unser Modul ein- und das
  von RedmineUP ausgeschaltet - in einer Transaktion. Dafür müssen die Berechtigungen von RedmineUP
  in einem eigenen Projektmodul liegen; die README nennt die nötigen Änderungen an RedmineUP.
- Die Verlaufseinträge von RedmineUP erscheinen auch in umgestellten Projekten, und eine Kopie aus
  einem Projekt, das noch RedmineUP nutzt, übernimmt dessen Punkte.

### Geändert

- **Der Schritt Checklisten kopiert neu, was RedmineUP noch führt.** Solange RedmineUP installiert
  ist, werden Tickets von Projekten ohne unser Modul erneut kopiert und eine frühere Kopie ersetzt,
  statt nach der ersten Kopie übersprungen zu werden. Ist es entfernt, werden Tickets mit einer
  Checkliste von uns weiter übersprungen.
- Der Schritt Projektmodul schaltet auch das eigene Modul von RedmineUP aus, wo es eines hat. Neben
  einem installierten RedmineUP ist er auf der Übernahmeseite nicht mehr vorausgewählt.

- **Die Tests laufen auch auf MySQL und PostgreSQL.** Die CI führt die Suite für jede unterstützte
  Redmine-Version auf MariaDB aus und für die älteste und die neueste (5.1 und 7.0) zusätzlich auf
  MySQL 8.4 und PostgreSQL 17.

## [0.1.0] - 2026-11-03

### Hinzugefügt

- Checklisten an Tickets: Punkte und Abschnitte, ein Block auf der Ticketseite mit Fortschritt und
  „Erledigte ausblenden“, Abhaken ohne Neuladen der Seite.
- Editor im Ticketformular: hinzufügen, umbenennen, abhaken, löschen, per Ziehen oder Alt+Pfeil
  umsortieren, mehrere eingefügte Zeilen als mehrere Punkte (`-- ` Abschnitt, `[x] ` erledigt).
  Zeilen überschreiben nur, was der Benutzer geändert hat; ein Häkchen, das jemand anderes gesetzt
  hat, während das Formular offen war, übersteht das Speichern.
- Verlauf: ein Eintragsdetail je geändertem Punkt, als eigene Zeile im Verlauf, in
  Benachrichtigungen, im PDF-Export und im Journal-Feed. Für Benutzer ohne Leserecht ausgeblendet.
- Gebündelte Mails: Häkchen und REST-Änderungen derselben Person innerhalb von 60 Sekunden teilen
  sich einen Verlaufseintrag und eine Benachrichtigung, die im Hintergrund rausgeht, sobald die
  Person aufhört (höchstens zehn Minuten je Bündel). Ausstehende Mails werden gespeichert, ein
  Aufräumer verschickt, was ein Neustart liegen gelassen hat, und
  `POST /expert_checklists/notifications/flush.json` (Admin-API-Schlüssel) verschickt alles
  Fällige. Einstellung: wie bei Ticket-Änderungen / immer / nie.
- Optional: % erledigt aus dem Anteil abgehakter Punkte; Sperre für den Wechsel auf einen
  geschlossenen Status, solange Punkte offen sind.
- Beim Kopieren eines Tickets (Formular, Massenkopie, Projektkopie, Unteraufgaben) wird die
  Checkliste mitkopiert.
- Ticketliste: Spalte „Checkliste“ (HTML, CSV, PDF) und Filter nach Zustand und Text der Punkte.
- REST-API unter `/issues/:id/expert_checklist_items` und `/expert_checklist_items/:id` (JSON und
  XML, Feldnamen wie RedmineUP), `issue[expert_checklist_items_attributes]` in der Ticket-API.
  Sobald RedmineUP Checklists entfernt ist, antworten auch dessen Pfade und
  `issue[checklists_attributes]`.
- Übernahme aus RedmineUP Checklists (Admin-Seite und Rake-Task, vorher Probelauf): Punkte mit ihren
  IDs, Berechtigungen, Einstellungen, gespeicherte Abfragen, Projektmodul. Die Verlaufseinträge von
  RedmineUP bleiben lesbar.
- Projektmodul „expert Checklisten“ mit den Berechtigungen ansehen, abhaken und bearbeiten.
- Oberfläche auf Englisch, Deutsch, Spanisch, Französisch, Italienisch und Portugiesisch
  (Portugal, Brasilien).
