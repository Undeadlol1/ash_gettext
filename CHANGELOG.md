# Changelog

## Unreleased

### Changes

- JSON:API replies are translated. A domain with a `gettext` block that also
  uses `AshJsonApi.Domain` gets `AshGettext.JsonApi` as its `error_handler`,
  with nothing to set up. It translates the `detail` of every error in a
  reply, including the text AshJsonApi writes itself ("is required", record
  not found) and errors from reads. `code`, `title`, `meta` and the source
  pointer are kept. Text with no catalog entry goes out unchanged. An
  `error_handler` you wrote still runs, first.
- Errors from generic actions (`action :name, :type`) are translated in the
  error, like create, update and destroy errors. Ash gives them an
  `error_handler` since 3.30.
- `AshGettext.TransportText.translate/3` holds the rules for translating a
  text a transport wrote itself. They belong to no transport;
  `AshGettext.JsonApi` is a thin adapter over them, and another transport
  needs one call.
- `AshGettext.Plug` sets Gettext's language to the actor's for one request,
  using the domain's `locale_resolver`, and puts it back when the reply is
  sent.
- `mix gettext.extract` adds the sentences AshJsonApi writes ("is required",
  "could not be found" and others listed in `AshGettext.AshMessages`).

### Fixes

- Ash's own errors stay Ash's own structs. A value that does not cast and a
  failed policy get the translated sentence in their own text field
  (`message`, or `custom_message` for a policy) instead of being swapped for
  `AshGettext.AshMessages.Translated`, which is gone. Code that matches on
  `%Ash.Error.Changes.InvalidAttribute{}` or `%Ash.Error.Forbidden.Policy{}`
  keeps working, and AshPhoenix forms show the sentence again.
- `Ash.Error.Changes.Required` is left untouched. It has no text field, so
  the error itself is no longer translated. Over JSON:API, the reply is; see
  `AshGettext.JsonApi`.

## 0.1.0 — 2026-11-11

The first packaged version.

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
- Running an action with `actor:` gives loaded `_label` fields and error
  messages in that user's language, using the domain's one `locale_resolver`.
  It gets the actor and returns its language. With no actor, Gettext's
  current process language is used. No action changes the process language,
  so a long-lived process never runs the next job in the last user's
  language.
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
- A resolver's answer is cut to a language your catalogs have (`ru_RU`
  becomes `ru`), or `default_locale`. A resolver must be a pure function of
  the actor and must not query the database.
- `AshGettext.Domain` and `AshGettext.Resource` extensions. A `gettext do`
  block on a domain translates the errors of every create, update and destroy
  action on its resources, in Gettext's current language.
- `text_domain` defaults to `"ash"`: one catalog for Ash's errors, enum labels
  and attribute names. Text from `translate/3` uses Gettext's `"default"`.
- Gettext's own `mix gettext.extract` finds every text AshGettext translates:
  enum labels and descriptions, attribute labels, the `message`s in a
  resource's DSL and in the validation, change and preparation modules it
  uses, and Ash's own error sentences. Each goes to its domain's backend and
  `text_domain`. There is no extract task of AshGettext's own.
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
  `mix gettext.extract` adds them to the template.
- `AshGettext.Error` is a user-facing error with a required `code`, a
  translatable `message`, and an optional `field` and `vars`. It renders for
  JSON:API, with no English `title`, when `:ash_json_api` is present, which is an optional dependency.
