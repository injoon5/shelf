## Installing

If you can run shell commands, install the change yourself. Save the file as `App.swift`, then run:

```sh
curl -sS -X PUT {{ORIGIN}}/api/apps/{{SLUG}} \
  -H "Authorization: Bearer {{KEY}}" \
  -H "Content-Type: text/x-swift" \
  --data-binary @App.swift
```

- `200`: updated. Tell the user it's on their phone.
- `422` or `413`: the response says what's wrong. Fix it and run it again. A failed attempt doesn't use up the key.
- `401`: the key is used or has expired. Stop, and reply with the code instead.

The key updates this one app, `{{SLUG}}`, once, and expires at {{EXPIRES}}. Never print the key back, or store it anywhere else.

If you can't run commands, reply with the code.
