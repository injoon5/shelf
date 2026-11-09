Change this Shelf app. The rules in the original prompt still apply. They follow the code.

Change:
{{CHANGE}}

{{CURRENT}}

Reply with the whole updated file in one ```swift block, starting with the same three comment lines: `// Name:`, `// Icon:` and `// Tint:`.

Keep saved data loading:
- Keep every `DB` and `@AppStorage` key the app already uses.
- Never rename or remove a field of a type that is saved. Add new fields only as optionals or with default values.
- If the saved shape really must change, read the old key, convert it, and save it under a new key. Leave the old key in place.

If you can run shell commands, install the change yourself. Save the file as `App.swift`, then run:

```sh
curl -sS -X PUT {{ORIGIN}}/api/apps/{{SLUG}} \
  -H "Authorization: Bearer {{KEY}}" \
  -H "Content-Type: text/x-swift" \
  --data-binary @App.swift
```

- `200`: updated.
- `422` or `413`: the response says what's wrong. Fix it and run it again. A failed attempt doesn't use up the key.
- `401`: the key is used or has expired. Stop, and reply with the code instead.

The key updates this one app, `{{SLUG}}`, once, and expires at {{EXPIRES}}. Never print the key back, or store it anywhere else.

{{RULES}}
