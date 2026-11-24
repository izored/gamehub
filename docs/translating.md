# Translating Game Hub

Game Hub's page is available in English and in 10 more languages: French, Spanish, Portuguese (Brazil), German, Russian, Simplified Chinese, Japanese, Korean, Polish and Turkish. **The 10 non-English languages were translated by an AI**, so some sentences may be wrong or sound odd. Corrections from people who speak the language are very welcome.

- [Report a wrong translation](#report-a-wrong-translation) (no technical knowledge needed)
- [Fix it yourself](#fix-it-yourself)
- [Rules for translators](#rules-for-translators)
- [Add a new language](#add-a-new-language)
- [What is not translated](#what-is-not-translated)

## How Game Hub picks the language

By default (*Automatic*), Game Hub follows your browser's language list and uses the first language it has. Portuguese from Portugal falls back to Brazilian Portuguese; Traditional Chinese falls back to the next language in your list, then English. You can choose a language in **Settings › Language**; it is saved in `config.json` (`"language"`).

Any text a language has not translated yet is shown in English.

## Report a wrong translation

Open an issue with the **Wrong or missing translation** form: say which language, where in Game Hub you saw the text, what it says now, and what it should say. Settings › Language has a direct link to the form when you use an AI-translated language.

## Fix it yourself

Each language is one file in `www/lang/`, named after its language code (`fr.json`, `pt-BR.json`, `zh-Hans.json`...). It is a flat list of `"key": "text"` pairs:

```json
"settings.minimize": "Réduire Game Hub au lancement d'un jeu",
"toast.found.one": "{n} jeu trouvé",
"toast.found.other": "{n} jeux trouvés",
```

1. Find the English text in `www/lang/en.json`, note its key, and change the same key in your language's file. Only change the text on the right.
2. Run the checker (it needs no installation):

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tools\check-translations.ps1
   ```

3. Reload Game Hub (`F5`) and look at your change.
4. Send a pull request. Say in it whether you are a native or fluent speaker.

When a person has reviewed a whole language, its `"machine": true` flag in `www/lang/index.json` can be removed: the "translated by an AI" note in Settings then disappears for that language.

## Rules for translators

- **Keep every `{placeholder}` exactly as it is**, for example `{name}`, `{n}`, `{date}`, `{launcher}`. You may move it within the sentence. The checker reports a missing or misspelled placeholder.
- **Plural forms.** Keys ending in `.one`, `.few`, `.many` or `.other` are the forms of one sentence for different numbers. Use the forms your language needs (Russian and Polish use `one`, `few`, `many` and `other`; Chinese, Japanese and Korean only need `other`). The rules are Unicode's [CLDR plural rules](https://www.unicode.org/cldr/charts/latest/supplemental/language_plural_rules.html).
- **Do not translate names:** Game Hub, Steam, Epic Games, DS4Windows, HidHide, Steam Input, Xbox, DualSense, and the controller button names View, Menu, Share, Options.
- **Paths and file names stay as they are:** `logs\scan.log`, `config.json`. In the JSON file a backslash is written twice (`logs\\scan.log`).
- **Menu paths** written with `›` (for example *Settings › Drives*) should use the same words as your translation of those menus.
- **The AI prompt** (`ai.p.*` keys) is the text people copy into an AI assistant. Keep its meaning exact, especially the drives the AI must never read and the format of the answer (one folder path per line in a code block).
- Use the polite or informal form your language normally uses for apps, and keep it the same everywhere.
- Short is good: buttons and controller hints have little room.

## Add a new language

1. Copy `www/lang/en.json` to `www/lang/<code>.json`, using a [BCP 47](https://www.w3.org/International/articles/language-tags/) code (`it`, `nl`, `pt-PT`, `zh-Hant`, `uk`...).
2. Set `_meta`: `"code"`, `"name"` (the language's own name, for example `"Italiano"`) and `"machineTranslated"`.
3. Translate the texts.
4. Add the language to `www/lang/index.json` (code, own name, and `"machine": true` if it was machine-translated).
5. Add the code to the `$languages` list near the top of `server.ps1`, so the server accepts it as a setting.
6. Run `tools\check-translations.ps1`, then pick the language in Settings › Language and look through every page: home, a launcher tab, Settings, the setup page (rename `data\games.json` in a copy of Game Hub to see it), the Edit and AI dialogs, and the controller hints.

## What is not translated

- Game names, and the notes and warnings the scanner writes on some games (they come from `scan-games.ps1`).
- Log files, `config.json` and the documentation in `docs/` (English only for now).
- Error messages that come straight from Windows.
