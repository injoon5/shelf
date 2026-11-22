# Reply parser fixtures

Shared by the two copies of the reply parser: `src/lib/replyParser.ts` in
ij5.dev and the Swift parser in Shelf. Each `<case>.md` is an input (a chat
reply or a raw Swift file); `<case>.json` beside it is the exact result both
parsers must return. Change a rule here, in both parsers and in the fixtures
together.

## Rules

1. **Normalise first.** Drop one leading U+FEFF (byte-order mark). Replace
   every `\r\n`, then every remaining lone `\r`, with `\n`. Everything below
   works on the normalised text, and the stored source never contains `\r`.
2. **Lines.** Split on `\n`. "Whitespace" is Unicode whitespace (what `\s`
   matches). A *blank* line is empty or whitespace only. "Trimmed" means
   whitespace removed from both ends.
3. **Fences.** A fence is a line whose trimmed text starts with three
   backticks. Outside a block, a fence opens one; its info string is the
   trimmed text after all leading backticks. Inside a block, *any* fence line
   closes it (the closing line's own text is ignored). Fence lines themselves
   are never part of any block.
4. **Swift blocks.** A block is Swift when its info string starts with `swift`,
   compared case-insensitively (`swift`, `Swift`, `SWIFT`, `swift title=x`).
   Collect the lines of every Swift block, join each block's lines with `\n`,
   and join the blocks with `\n\n`. A block with no closing fence runs to the
   end of the input.
5. **No Swift blocks** (no fences at all, or only non-Swift fences): the whole
   normalised input is the source.
6. **Source.** Remove leading and trailing blank lines, then end with exactly
   one `\n`. Lines in between are untouched (indentation and trailing spaces
   included). If nothing is left, the source is the empty string `""`.
   The header lines stay in the source.
7. **Header.** Scan the source from the top through its leading run of blank
   lines and lines whose trimmed text starts with `//`; stop at the first line
   that is neither. Each line in that run is matched against
   `^\s*//\s*(name|icon|tint)\s*:\s*(.*?)\s*$`, case-insensitively. The
   *first* occurrence of each key wins, even when its value is empty. A
   `// Name:` after the first code line is never read.
8. **name**: the matched value, trimmed; `null` if missing or empty.
9. **icon**: the matched value, trimmed; `null` if missing or empty.
10. **tint**: the matched value, lowercased; `"blue"` if missing or not one of
    `red orange yellow green mint teal cyan blue indigo purple pink brown gray`.
11. **slug**: from `name` — Unicode NFKD, remove combining marks (`\p{M}`),
    lowercase, replace every run of characters outside `[a-z0-9]` with one
    `-`, trim `-` from both ends, cut to 64 characters, trim a trailing `-`
    again. If the result is empty, or `name` is `null`, the slug is `"app"`.

Result shape:

```json
{ "name": "string|null", "icon": "string|null", "tint": "string", "slug": "string", "source": "string" }
```

## Cases

| Case | What it pins |
|---|---|
| `plain-single-block` | one Swift block, nothing around it |
| `prose-around` | prose before and after the block is dropped |
| `two-blocks` | two Swift blocks joined with a blank line |
| `no-fences` | a raw file is the source as it is |
| `unclosed-fence` | a block cut off mid-reply runs to the end |
| `odd-header` | mixed-case keys, spaces around `//` and `:`, trailing spaces, upper-case tint |
| `missing-icon` | `icon` is `null` |
| `unknown-tint` | `magenta` falls back to `blue` |
| `missing-name` | `name` is `null`, slug `app` |
| `korean-name` | a name with nothing left after folding gets slug `app` |
| `accented-name` | accents fold away; punctuation and the em dash become one `-` |
| `late-name` | a `// Name:` below the first code line is not the header |
| `crlf` | CRLF input; source has `\n` only |
| `other-fences` | `sh` and `json` fences are skipped; `Swift` info string matches; `Pink` lowercases |
| `blank-padding` | leading/trailing blank lines (incl. whitespace-only) removed; inner trailing spaces kept |
| `empty-name-first` | the first `// Name:` wins even when empty; a whitespace-only icon is `null` |
| `long-name` | slug cut to 64 characters |
