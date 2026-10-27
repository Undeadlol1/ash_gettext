# Changelog

## 0.1.0 — unreleased

- `AshGettext.Domain` and `AshGettext.Resource` extensions: a `gettext do`
  block on a domain translates the errors of every write action on its
  resources, in the locale its resolvers pick.
- `mix ash_gettext.extract` writes every Ash `message:` to a `.pot` template;
  `--check` fails in CI when the template is out of date.
- `text_domain` defaults to `ash_errors`, the file the extractor writes.
- `AshGettext.translate/5`, `translate_plural/7` and `enum_label/5` for strings
  outside errors, with the locale passed as an argument.
- `mix ash_gettext.install` previews, and with `--apply` writes, the domain and
  resource extensions and `gettext` block for an existing app.
- `verify_resources?` on the domain `gettext` block: opt-in compile-time check
  that every resource in the domain carries `AshGettext.Resource`.
- `fetch/5`, `fetch_plural/7` and `fetch_enum_label/5` never report `:missing`
  in the source locale (the backend's default locale): the msgid is the text,
  so the source language needs no catalog.
