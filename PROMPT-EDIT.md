Change this Shelf app. The rules in the original prompt still apply. They follow the code.

Change:
{{CHANGE}}

Current file:

```swift
{{SOURCE}}
```

Reply with the whole updated file in one ```swift block, starting with the same three comment lines: `// Name:`, `// Icon:` and `// Tint:`. Keep the `DB` keys the app already uses, so the data it has saved still loads.

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
