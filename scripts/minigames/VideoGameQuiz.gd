extends "res://scripts/minigames/BaseTextFieldQuiz.gd"

func _init():
	quiz_title = "Video Game Quiz"
	max_rounds = 7
	question_pool = [
		{"q": "Welches ist das meistverkaufte Videospiel aller Zeiten?", "a": "Minecraft"},
		{"q": "Wie heißt der Bruder von Mario?", "a": "Luigi"},
		{"q": "In welchem Spiel baut man mit Blöcken und flieht vor Creepern?", "a": "Minecraft"},
		{"q": "Wie heißt der Hauptcharakter in der Legend of Zelda Reihe?", "a": "Link"},
		{"q": "Von welcher Firma stammt die PlayStation?", "a": "Sony"},
		{"q": "Welches Pokémon ist das bekannteste und gelb?", "a": "Pikachu"},
		{"q": "In welchem Spiel springt man aus einem fliegenden Bus auf eine Insel?", "a": "Fortnite"},
		{"q": "Wie heißt der blaue Igel, der Ringe sammelt?", "a": "Sonic"},
		{"q": "Was ist das Hauptziel in Pac-Man?", "a": "Alle Punkte fressen und Geistern ausweichen"},
		{"q": "Welche Konsole führte Mii-Charaktere ein?", "a": "Nintendo Wii"},
		{"q": "In welchem Spiel fängt man Tiere in Bällen?", "a": "Pokémon"},
		{"q": "Wie heißt der Pilz, der Mario wachsen lässt?", "a": "Superpilz / Pilz"}
	]
