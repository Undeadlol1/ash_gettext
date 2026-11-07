# Changelog

## 0.1.0 — unreleased

The first packaged version. Not published to Hex yet.

### Changes

- `use AshGettext.Translator` makes a module with `translate/3`,
  `translate_plural/5`, `enum_label/3`, `attribute_label/3` and `locale/1`.
  It knows your backend and locale resolvers, so a call says only what to
  translate.
- `AshGettext.translate/5` and `translate_plural/7` are the pure functions
  underneath, with the language passed as an argument.
- `enum_label` is keyed by the enum module. The msgid is the enum's own label
  for the value, so a `label:` on the value is honored. `attribute_label`
  looks up an attribute's name in words (`:date_of_birth` is "Date of
  birth") and raises for an attribute the resource does not have.
- A lookup with no translation sends the telemetry event
  `[:ash_gettext, :translation, :missing]`, with `backend`, `text_domain`,
  `msgid` and `locale`.
- `AshGettext.known_locales/1` includes the source locale.
- `AshGettext.Locale.resolve/2` picks a language your catalogs have from
  resolvers, such as one that reads the signed-in user. A resolver must be a
  pure function of its context and must not query the database.
- `AshGettext.Domain` and `AshGettext.Resource` extensions. A `gettext do`
  block on a domain translates the errors of every create, update and destroy
  action on its resources, in the locale its resolvers pick.
- `text_domain` defaults to `"ash"`: one catalog for Ash's errors, enum labels
  and attribute names. Text from `translate/3` uses Gettext's `"default"`.
- `mix ash_gettext.extract` writes every Ash `message:`, every public
  attribute's name and every enum value's label to a `.pot` template,
  into the file the lookups read: the backend's `priv` directory holding
  `<text_domain>.pot`. `--check` fails in CI when the template is out of date.
  When an app's domains name different text domains, the task lists them and
  asks for `--output`.
- `mix ash_gettext.install` previews, and with `--apply` writes, the domain
  and resource extensions and the `gettext` block for an existing app.
- `translate_or_missing/5`, `translate_plural_or_missing/7`,
  `enum_label_or_missing/5` and `attribute_label_or_missing/5` never report `:missing` in the source locale (the
  backend's default locale). The msgid is the text, so the source language
  needs no catalog.
- `require_resource_extension?` on the `gettext` block is an opt-in compile
  time check that every resource in the domain carries `AshGettext.Resource`.
- `AshGettext.Error` is a user-facing error with a required `code`, a
  translatable `message`, and an optional `field` and `vars`. It renders for
  JSON:API when `:ash_json_api` is present, which is an optional dependency.
- `AshGettext.Testing` has `assert_translates/6` and `assert_covered/5` for
  checking a message and a catalog in your own tests.
