# Changelog

## 0.1.0 — unreleased

The first packaged version. Not published to Hex yet.

### Changes

- Every attribute with an `AshGettext.Enum` type gets a public
  `<attribute>_label` field on resources that use `AshGettext.Resource`.
  Load it (`load: [:status_label]`) to get the translated label on the record.
- `use AshGettext.Enum, backend: MyApp.Gettext, values: [...]` makes an Ash
  enum whose own `label/1` and `description/1` return the translated text, in
  Gettext's current locale. It calls `use Ash.Type.Enum` for you. There is no
  wrapper to call. An empty value (`nil`) has no label and no description.
- `AshGettext.translate/5` and `translate_plural/7` are the pure functions
  underneath, with the language passed as an argument.
- Running an action with `actor:` (or `context: %{locale: "ru"}`) sets
  Gettext's language for that process, once, when the action starts, using the
  domain's `locale_resolvers`. Enum labels, error messages and attribute names
  all come out in it. With no actor and no locale the language is left alone.
- User-facing text is always written by a person. The library never makes it
  from a code name. An enum value without a `label:` is a compile error.
- A resource's `gettext` block holds written attribute labels
  (`label :delivery_date, "Delivery date"`). `attribute_label/2` translates
  one and raises for an attribute with no written label. A `label` for an
  attribute the resource does not have fails the build.
- A lookup with no translation sends the telemetry event
  `[:ash_gettext, :translation, :missing]`, with `backend`, `text_domain`,
  `msgid` and `locale`.
- `AshGettext.known_locales/1` includes the source locale.
- `AshGettext.Locale.resolve/2` picks a language your catalogs have from
  resolvers, such as one that reads the signed-in user. A resolver must be a
  pure function of its context and must not query the database.
- `AshGettext.Domain` and `AshGettext.Resource` extensions. A `gettext do`
  block on a domain translates the errors of every create, update and destroy
  action on its resources, in Gettext's current language.
- `text_domain` defaults to `"ash"`: one catalog for Ash's errors, enum labels
  and attribute names. Text from `translate/3` uses Gettext's `"default"`.
- `mix ash_gettext.extract` writes every Ash `message:`, every written
  attribute label and every enum value's label and description to a `.pot` template,
  into the file the lookups read: the backend's `priv` directory holding
  `<text_domain>.pot`. `--check` fails in CI when the template is out of date.
  When an app's domains name different text domains, the task lists them and
  asks for `--output`.
- `mix ash_gettext.install` previews, and with `--apply` writes, the domain
  and resource extensions and the `gettext` block for an existing app.
- `translate_or_missing/5`, `translate_plural_or_missing/7`
  and `attribute_label_or_missing/2` never report `:missing` in the source locale (the
  backend's default locale). The msgid is the text, so the source language
  needs no catalog.
- `require_resource_extension?` on the `gettext` block is an opt-in compile
  time check that every resource in the domain carries `AshGettext.Resource`.
- Ash's own errors that have no message (a missing required value, a value
  that does not cast, a failed policy) come back with a written sentence in
  the user's language, such as "is required", not text built from a field
  name. The sentences live in `AshGettext.AshMessages`, and
  `mix ash_gettext.extract` always adds them to the template.
- `AshGettext.Error` is a user-facing error with a required `code`, a
  translatable `message`, and an optional `field` and `vars`. It renders for
  JSON:API, with no English `title`, when `:ash_json_api` is present, which is an optional dependency.
- `AshGettext.Testing` has `assert_translates/6` and `assert_covered/5` for
  checking a message and a catalog in your own tests.
