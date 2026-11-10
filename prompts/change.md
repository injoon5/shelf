Change this Shelf app.

Change:
{{CHANGE}}

{{CURRENT}}

## Reply format

Reply with the whole updated file in one ```swift block. Start it with the same three comment lines: `// Name:`, `// Icon:` and `// Tint:`.

## Keep saved data loading

- Keep every `DB` and `@AppStorage` key the app already uses.
- Never rename or remove a field of a saved type. Add new fields only as optionals or with default values.
- If the saved shape really must change, read the old key, convert it, and save it under a new key. Leave the old key in place.

{{RULES}}

{{INSTALL}}
