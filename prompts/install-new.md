## Installing

If you can run shell commands, install the app yourself after writing it. Save the file as `App.swift`, then run:

```sh
curl -sS -X PUT {{ORIGIN}}/api/apps/<slug> \
  -H "Authorization: Bearer {{KEY}}" \
  -H "Content-Type: text/x-swift" \
  --data-binary @App.swift
```

- `<slug>` is the name in lowercase with hyphens, for example `habit-tracker`.
- `201`: installed. Tell the user it's on their phone.
- `409`: the slug is taken. Pick another and run it again.
- `422` or `413`: the response says what's wrong. Fix it and run it again. A failed attempt doesn't use up the key.
- `401`: the key is used or has expired. Stop, and reply with the code instead.

The key installs one new app. It can't change existing apps, and it expires at {{EXPIRES}}. Never print the key back, or store it anywhere else.

If you can't run commands, reply with the code.
