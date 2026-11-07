# Changelog

## 0.1.0 — unreleased

The first packaged version. Not published to Hex yet.

### Changes

- `AshGettext.translate/5`, `translate_plural/7` and `enum_label/5` translate
  text, plurals and enum values, with the language passed as an argument.
- `AshGettext.Locale.resolve/2` picks a language your catalogs have from
  resolvers, such as one that reads the signed-in user.
- `AshGettext.Domain` and `AshGettext.Resource` extensions. A `gettext do`
  block on a domain translates the errors of every create, update and destroy
  action on its resources, in the locale its resolvers pick.
- `text_domain` defaults to `ash_errors`, naming the catalog errors are looked
  up in.
- `mix ash_gettext.extract` writes every Ash `message:` to a `.pot` template,
  into the file the lookups read: the backend's `priv` directory holding
  `<text_domain>.pot`. `--check` fails in CI when the template is out of date.
  When an app's domains name different text domains, the task lists them and
  asks for `--output`.
- `mix ash_gettext.install` previews, and with `--apply` writes, the domain
  and resource extensions and the `gettext` block for an existing app.
- `translate_or_missing/5`, `translate_plural_or_missing/7` and
  `enum_label_or_missing/5` never report `:missing` in the source locale (the
  backend's default locale). The msgid is the text, so the source language
  needs no catalog.
- `require_resource_extension?` on the `gettext` block is an opt-in compile
  time check that every resource in the domain carries `AshGettext.Resource`.
- `AshGettext.Error` is a user-facing error with a required `code`, a
  translatable `message`, and an optional `field` and `vars`. It renders for
  JSON:API when `:ash_json_api` is present, which is an optional dependency.
- `AshGettext.Testing` has `assert_translates/6` and `assert_covered/5` for
  checking a message and a catalog in your own tests.
