# Arcaders – System-Prompts & Richtlinien für Entwicklungs-Agenten

Diese Datei dient als **verbindliche Projektanweisung** für alle KI-Agenten und Threads, die an der Godot 4.x Party-Minispielsammlung **Arcaders** arbeiten.

---

## 1. Kernphilosophie & Architektur

- **Game Engine**: Godot 4.x (GDScript & Scene Tree `.tscn`).
- **Architektur**: Zentrales Hauptspielbrett (`MainBoard.tscn`), Minispiel-Szenen (`res://scenes/minigames/`) und Web-Controller für Smartphones (`controller-web/` via WebSockets über `NetworkManager.gd`).
- **Audiomanagement**: `AudioManager.gd` steuert Musik und SFX zentral. Minispiele dürfen keine hardcodierten Musik-Streams unkontrolliert abspielen.
- **Konsistenz vor Neu-Erfindung**: Jedes neue Feature und jedes Minispiel muss sich nahtlos anfühlen, als stamme es aus einem einzigen Guss.

---

## 2. UI-Komponenten: Zuerst prüfen, dann nachfragen!

Bevor **irgendein neues UI-Element** erstellt oder geskriptet wird:
1. **Immer zuerst prüfen**, welche Komponenten und Ressourcen im Projekt bereits existieren.
2. Vorhandene Shared-Komponenten MÜSSEN wiederverwendet werden:
   - `GameButton.tscn` (`res://scenes/ui/GameButton.tscn` | UID: `uid://cax2j4f2e2n4c`) – Für alle Hauptaktionen ("SPIEL STARTEN", "WEITER", etc. im markanten Orange).
   - `SecondaryButton.tscn` (`res://scenes/ui/SecondaryButton.tscn` | UID: `uid://b2x7m8p9q4k1s`) – Für alle Sekundäraktionen ("ABBRECHEN", "SCHLIESSEN", "SPIELSTAND LADEN", "ÜBERSPRINGEN", "AUFGEBEN", "ZURÜCKSETZEN", etc. im stilvollen Schieferblau-Design mit Gold-Hover).
   - `DangerButton` Theme-Variation – Für alle Straf-/Aufgabe-Aktionen ("Aufgeben (-1 Punkt)", "Runde abbrechen" im dunklen Karminrot-Slate mit leuchtendem Rubin-Hover).
   - `SuccessButton` Theme-Variation – Für Bestätigungs-/Erfolgs-Aktionen ("Geschafft! (+1 Punkt)" im Smaragdgrün-Look).
   - `PixelBackButton.tscn` (`res://scenes/ui/PixelBackButton.tscn`) – Zentraler pixelartiger Zurück-Button für alle Bildschirme.
   - `QuizParticipantCard.tscn` (`res://scenes/minigames/QuizParticipantCard.tscn` | UID: `uid://d3j5a8q2qar7b`) – Jeder Spieler/jedes Team erhält bei quiz-/rundenbasierten Minispielen eine solche Karte mit animiertem Charakter-Sprite, Teamrahmen und Status!
   - `panel_side_style.tres` (`res://resources/panel_side_style.tres` | UID: `uid://c6f2y8p1n5m4a`) – Verbindlicher Standard für alle In-Game Extra-Info Panels, Side-Panels, Challenge-Boxen und Status-Dashboards (Fire Emblem Standard: 3px Gold-Rahmen, dunkles Glas, 10px Radius).
   - `panel_modal_style.tres` (`res://resources/panel_modal_style.tres` | UID: `uid://d1x8j2n7p9k3q`) – Verbindlicher Standard für alle Vollbild-Modale, Siegerehrungen und Pause-/Einstellungs-Dialoge (4px Gold-Rahmen, 12px Radius, 24px Schatten auf abgedunkeltem Backdrop).
   - `global_button_theme.tres` (`res://resources/global_button_theme.tres` | UID: `uid://dd6a17ffebae1`) – Das Standard-Theme für Typografie und Steuerelemente.
   - `supermario_tileset.tres` (`res://resources/supermario_tileset.tres` | UID: `uid://c5xk8j2p1n1q4`) & `BackgroundTileMap.gd` – Für den retro-animierten Kacheldekorhintergrund der Menüs.
3. **Vermeidung von UI-Wildwuchs**:
   - Keine unterschiedlichen, ad-hoc erstellten Box-Designs oder zufällige bunte Rahmen.
   - Verschachtelte Elemente innerhalb eines Side-Panels tragen KEINE zusätzlichen dicken Rahmen, sondern werden durch dezent abgedunkelte Flächen (`Color(0.04, 0.05, 0.08, 0.5)`) oder `HSeparator` strukturiert.
4. **Wenn ein komplett neues UI-Element oder Layout-Muster benötigt wird**:
   - **ERST beim Nutzer nachfragen** und die Idee vorschlagen, anstatt eigenmächtig abweichende UI-Elemente zu bauen!

---

## 3. Typografie & Design-Konsistenz

- Alle Screens und Minispiele müssen dieselben Schriftarten und Schrifthierarchien aus `global_button_theme.tres` verwenden.
- **H1 (Überschriften)**: Schriftgröße `72` auf Erklärseiten, `46` bis `56` auf In-Game-Boards. Stets zentriert.
- **H3 (Untertitel & Fließtext)**: Zeilenabstand `line_spacing = 8`, gut lesbar, niemals überladen.
- **Buttons**: Einheitliche Mindesthöhen (z. B. `360 x 60 px` für Start-Buttons, `200-240 x 48 px` für In-Game-Aktionen).
- **Audio-Feedback**: Alle klickbaren Buttons müssen mit `_connect_buttons_sfx(self)` den einheitlichen Sound `button_press` abspielen.

---

## 4. Standardisierte Erklärseite (Intro-Screen) für JEDES Minispiel

Jedes Minispiel beginnt **ausnahmslos** mit einer Erklärseite, die dem Layout von **Ice Climbers** und **Bet Buddy Extreme** entspricht:

### Scene-Tree Struktur der Erklärseite:
```text
IntroContainer (CenterContainer, anchors preset 15, offset_top 80, offset_bottom -80)
 └── VBox (VBoxContainer, custom_minimum_size: Vector2(1040, 0), separation: 20)
      ├── Title (Label, theme_type_variation: "H1", font_size: 72, horizontal_alignment: 1)
      ├── ScrollArea (ScrollContainer, custom_minimum_size: Vector2(1040, 480), size_flags_horizontal: 4)
      │    └── InstructionContainer (MarginContainer, margin_left: 20, margin_top: 10, margin_right: 32, margin_bottom: 10)
      │         └── Instruction (Label, theme_type_variation: "H3", line_spacing: 8, autowrap_mode: 2, horizontal_alignment: 1)
      └── StartGameButton (Instance von res://scenes/ui/GameButton.tscn, custom_minimum_size: Vector2(360, 60), size_flags: 4)
PixelBackButton (Instance von res://scenes/ui/PixelBackButton.tscn, Position 14, 14, 64, 64)
```

### Schreibstil der Spielregeln:
- **Nummerierte, klare Abschnitte** (`1.`, `2.`, `3.`, `4.`, `5.`) mit prägnanter Überschrift und anschließendem kurzem Erklärtext.
- Wichtige Regeln (z. B. "Nicht im Team absprechen!", Timer, Punkte) werden explizit hervorgehoben.
- Punktesystem am Ende aufführen (z. B. *Geschafft: +1 Punkt | Zeit abgelaufen: -1 Punkt*).

---

## 5. Hintergrund-Progression (Erklärseite ➔ Spielstart)

- **Auf der Erklärseite**: Der retro TileMap-Hintergrund (`BackgroundTileMap`) ist aktiv.
- **Bei Klick auf "SPIEL STARTEN"**:
  1. `BackgroundTileMap.visible = false` (MUSS bei AUSNAHMSLOS JEDEM Minispiel ausgeblendet werden, damit animierte Kacheln nicht durchscheinen).
  2. Der spielspezifische Pixel-Art-Hintergrund (`gameplay_bg`, `TextureRect`) wird sichtbar geschaltet (`stretch_mode = STRETCH_KEEP_ASPECT_COVERED`, `texture_filter = TEXTURE_FILTER_NEAREST`).
  3. Eine universelle Kontrast-Tönung (`gameplay_dim`, `ColorRect`, z. B. `Color(0.04, 0.03, 0.02, 0.38 - 0.45)`) liegt darüber (`mouse_filter = Control.MOUSE_FILTER_IGNORE`), um Texte und HUD-Elemente vor hellen oder unruhigen Hintergrunddetails zu schützen.

---

## 6. Layout-Disziplin & Barrierefreiheit (Keine Überlappungen & Hoher Kontrast!)

- **Keine hardcodierten, überlappenden Positionen**: Nutze stets Godot-Container (`MarginContainer`, `VBoxContainer`, `HBoxContainer`, `GridContainer`, `CenterContainer`).
- **Elemente dürfen niemals übereinander stehen oder Text abschneiden**:
  - `autowrap_mode = TextServer.AUTOWRAP_WORD_SMART` bei dynamischen Texten.
  - `custom_minimum_size` bei Karten und Buttons festlegen.
- **Klick-Blockaden verhindern**: Reine Dekorations-Container, Sprite-Holder und Dim-Overlays MÜSSEN zwingend `mouse_filter = Control.MOUSE_FILTER_IGNORE` besitzen!
- **Universeller Textkontrast**:
  - Alle Labels besitzen über `MainTheme.tres` und `global_button_theme.tres` standardmäßig eine dunkle Outline (`font_outline_color = Color(0.04, 0.04, 0.06, 0.96)`, `outline_size = 6-14 px`).
  - In-Game Anzeigen, Dashboards, Fragen und HUDs werden zusätzlich in dunklen Panels (`panel_side_style.tres` mit `Color(0.08, 0.09, 0.14, 0.92)` und Gold-Rahmen) gebettet.
- **Farbcodierung + Text**: Teams haben Farben, aber jede Farbkodierung muss immer durch Text (Name des Spielers/Teams) ergänzt werden (Barrierefreiheit für Farbenfehlsichtigkeit).

---

## 7. In-Game Punkteanzeige & Teilnehmer-Karten (Videospielquiz-Standard)

- **Punkteanzeige oben zentriert**:
  - Nutze einen zentrierten `ScoreContainer` (`HBoxContainer`).
  - Jedes Team erhält einen Badge (`PanelContainer`):
    - Team-Farbrahmen (`border_width = 2`, `corner_radius = 8`)
    - Farbiger Indikatorpunkt (`14 x 14 px`)
    - Teamname in Teamfarbe
    - Vertikaler Trennstrich
    - Punktestand im Format `X / Y Pkt` (Weiß bei 0+, Rot bei Minuspunkten).
- **Jeder Spieler hat einen eigenen Kasten (`QuizParticipantCard`)**:
  - Bei Spielen mit Runden, Wetten oder Antworten erhält jeder Spieler eine `QuizParticipantCard`.
  - **Einheitliche Wortwahl & Visuelle Zustände (AUSNAHMSLOS IN JEDEM SPIEL)**:
    1. **Warten auf Eingabe (`State.WAITING`)**: Text: `"Tippt gerade..."` (grau `Color(0.6, 0.6, 0.6)`), Fill schwarz (`Color(0.1, 0.1, 0.1)`), Stroke in Teamfarbe (`border_width = 4`), kein Icon.
    2. **Eingesendet (`State.SUBMITTED`)**: Text: `"Eingereicht!"` (grün `Color(0.08, 0.55, 0.18)`), Fill weiß (`Color(1, 1, 1)`), Stroke in Teamfarbe (`border_width = 4`), Name dunkel ohne Outline, KEIN Haken-Icon!
    3. **Aufgedeckt (`State.REVEALED`)**: Text: Gegebene Antwort/Gebot (`raw_answer`, weiß mit dunkler Outline), Fill schwarz, Stroke in Teamfarbe.
    4. **Punkte vergeben / Gewonnen / Ausgewählt (`State.SELECTED`)**: Text: Antwort/Gebot (`raw_answer`, weiß mit dunkler Outline), Fill in Teamfarbe (`team_color`), Stroke in Teamfarbe (`team_color`), KEIN Drop-Shadow (`shadow_size = 0`).

---

## 8. Navigations- & Zurück-Button-Sicherheit

- `PixelBackButton.gd` besitzt `auto_return_to_main_board = true` und bricht die Runde eigenständig sauber ab.
- **Verbinde niemals `pixel_back_btn.pressed` mit einem zweiten Szenenwechsel**, wenn `auto_return_to_main_board` aktiv ist.
- Vor JEDEM `change_scene_to_file(...)` MUSS geprüft werden:
  ```gdscript
  var tree = get_tree()
  if tree:
      tree.change_scene_to_file("res://scenes/MainBoard.tscn")
  ```
- Beim Verlassen eines Minispiels über den Zurück-Button wird `NetworkManager.current_turn_number` um 1 reduziert, wenn das Spiel noch nicht gewertet wurde, damit keine Spielzüge verloren gehen.

---

## 9. Mobile Controller (`controller-web`)

- **Einfachheit & Fokus**: Nur Steuerelemente anzeigen, die aktuell gebraucht werden.
- **Keine verwirrenden Preset-Zahlen**: Direkte Eingabe mit Stepper (`-`, Zahlenfeld, `+`) genügt vollkommen.
- **Keine überflüssigen Timer auf dem Smartphone**: Wenn auf dem TV-Bildschirm ein Timer läuft, muss dieser nicht auf dem Handy dupliziert werden, um Verwirrung zu vermeiden.
- **Zustandswechsel**: Synchronisierung immer über `NetworkManager.broadcast({ "type": "state_change", "state": ... })` bzw. gezielte `send_to_player`-Aufrufe.

---

## 10. Pixel-Art Icons statt Unicode-Emojis (Verbindliche Icon-Richtlinie)

- **Absolutes Emoji-Verbot in der UI**: In Labels, Buttons, Texten, Beschriftungen und Dialogen dürfen **keine Unicode-Emojis** (wie ⭐, 🎲, ⏱, ✓, ❌, ⏸ etc.) verwendet werden! Unicode-Emojis stammen aus System-Fonts (Apple, Windows, Android), werden glatt/vektoriell gerendert und brechen den konsistenten Pixel-Art-Look.
- **Immer echte Pixel-Art Icons verwenden**:
  - Nutze die standardisierte `PixelIcon`-Komponente (`PixelIcon.gd` | `res://scenes/ui/PixelIcon.tscn`) oder Texturen aus `res://assets/ui/icons/pixel/` (wie `star.svg`, `dice.svg`, `hourglass.svg`, `check.svg`, `trophy.svg`, etc.).
  - Texturen und `TextureRect` müssen immer zwingend mit `texture_filter = TEXTURE_FILTER_NEAREST` gerendert werden, um pixelgenaue Schärfe zu garantieren.
  - Karten (`QuizParticipantCard`) stellen Status und Auszeichnungen über ihr integriertes `StatusIcon` dar, nicht über Emoji-Text im Label.

---

## 11. Checkliste vor dem Abschließen eines Tasks

1. Wurden bestehende Komponenten (`GameButton`, `SecondaryButton`, `QuizParticipantCard`) wiederverwendet?
2. Wurde der Ice-Climbers-Stil für die Erklärseite exakt eingehalten?
3. Läuft die Erklärseite mit `BackgroundTileMap` und schaltet bei Spielstart sauber auf das Spiel-Hintergrundbild um?
4. Sind alle Buttons mit SFX verknüpft und navigieren ohne `get_tree()`-Fehler zurück?
5. Wurde `MinigameResultHelper.award_points` vermieden und stattdessen `NetworkManager.minigame_winners[...]` befüllt?
6. Ist das Smartphone-Interface aufgeräumt und responsiv?
7. Wurden alle Unicode-Emojis vermieden und stattdessen standardisierte Pixel-Art-Icons (`assets/ui/icons/pixel/`) verwendet?
