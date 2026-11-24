Fix this Shelf app before it's installed. Shelf runs SwiftUI source on the phone with an interpreter called Kiln, so the whole app is one Swift file. What Kiln runs is listed after the code.

{{REQUEST}}

{{CURRENT}}

Reply with the whole fixed file in one ```swift block, starting with the same three comment lines: `// Name:`, `// Icon:` and `// Tint:`.

<!-- if install -->
## Installing

If you can run shell commands, install the fixed app yourself. Save the file as `App.swift`, then run:

```sh
curl -sS -X PUT {{ORIGIN}}/api/apps/{{SLUG}} \
  -H "Authorization: Bearer {{KEY}}" \
  -H "Content-Type: text/x-swift" \
  --data-binary @App.swift
```

- `201`: installed. Tell the user it's on their phone.
- `409`: the slug is taken. Pick another, in lowercase with hyphens, and run it again.
- `422` or `413`: the response says what's wrong. Fix it and run it again. A failed attempt doesn't use up the key.
- `401`: the key is used or has expired. Stop, and reply with the code instead.

The key installs one new app. It can't change existing apps, and it expires at {{EXPIRES}}. Never print the key back, or store it anywhere else.

If you can't run commands, reply with the code as described above.

<!-- end -->
{{RULES}}
