# Changelog

## 0.3.0 — 2026-11-11

### Upgrading

Ash's built-in sentences ("is required", "must be present"…) now live in their own catalog, `ash_builtin`, apart from your app's texts. **Before** the first extract on this version, copy each language's catalog so the translations you already have move with them:

```bash
cp priv/gettext/<locale>/LC_MESSAGES/<text_domain>.po priv/gettext/<locale>/LC_MESSAGES/ash_builtin.po
mix gettext.extract --merge
```

The merge keeps the built-in entries in `ash_builtin.po` and your own texts in your `text_domain` file. Without the copy, the built-in translations are deleted. Until you re-extract, nothing changes at runtime.

### Added

- `builtin_text_domain` (default `"ash_builtin"`): the catalog for the sentences Ash and AshGettext ship. An error text is looked up in `text_domain` first, then there.
- `mix gettext.extract` again finds every literal `message:` in your app's own source, also in plain modules no resource names. `extract_messages_from` lists the folders read (default `["lib"]`; `[]` turns it off).

### Fixed

- Each catalog entry points at the file and line its text is written at, not at the domain's first line. A built-in sentence has one fixed reference instead of one per domain.
- References are relative paths on every machine, also for texts from sibling umbrella apps.

## 0.2.1 — 2026-11-11

### Fixed

- A read no longer asks your `locale_resolver` for the actor's language unless it has an error to translate. In 0.2.0 every read asked, so a resolver that reads from the database ran a query on each read.
- A `locale_resolver` that raises, exits or throws no longer replaces the real error. A warning is logged and the process language is used.
- A failed action asks the `locale_resolver` once, not twice per error. A JSON:API or GraphQL reply asks once more, not once per error.
- Errors from a read action's own `prepare` or `validate` are translated, also through a code interface or a query prepared with `for_read`.
- Actions added by another extension's transformer always get translated errors.
- A policy's translated message no longer fires a false missing-translation event.
- A process language such as `ru_RU` is fitted to your catalogs (`ru`) when no actor language is known.
- A JSON:API refusal no longer shows the message of a different resource's refusal from the same request.
- `mix gettext.extract` finds `message:` texts in generic-action `run` modules, `manual` modules and calculation modules, and in your other umbrella apps and path dependencies.
- A message with `\n` or a unicode escape is extracted as exactly the text users see. Run `mix gettext.extract --merge` after upgrading.

### Changed

- AshJsonApi must be 1.6 or newer (the range said 1.4, which never worked).

### Still not translated

- A read validation declared for the whole resource (`validations do validate ..., on: [:read] end`). Put it inside the read action.

## 0.2.0 — 2026-11-11

### Breaking

- Ash's own errors stay Ash's own structs. `AshGettext.AshMessages.Translated`
  is gone. If you matched on it, match on the Ash struct again
  (`%Ash.Error.Changes.InvalidAttribute{}`, `%Ash.Error.Forbidden.Policy{}`).
  The translated sentence is in the struct's own text field (`message`, or
  `custom_message` for a policy).

### Added

- Errors are now translated in JSON:API and GraphQL replies, in the actor's
  language, including the text those libraries write themselves ("is
  required", record not found).
- Errors from generic actions and read actions are translated, like create,
  update and destroy errors.
- A policy's own `error_message` is shown, translated, in JSON:API and
  GraphQL replies. Those libraries alone reply "forbidden".
- `mix gettext.extract` now also adds the sentences Ash and the JSON:API and
  GraphQL replies use ("must be present", "is required", "could not be found"
  and about 60 more), and every policy's `error_message`. Run it and
  translate the new entries.

### Changed

- The minimum Ash is `~> 3.32`.
- `Ash.Error.Changes.Required` carries its translated sentence in
  `vars[:translation]`. AshPhoenix passes `vars` on, so a form can show it.

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
