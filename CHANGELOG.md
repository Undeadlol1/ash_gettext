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
