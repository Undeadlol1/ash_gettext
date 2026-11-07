# How AshGettext works

This page explains what AshGettext does when you translate text, when a
resource compiles and when an error is raised, and why it has the limits it
has.

## When you translate text

`AshGettext.translate/5` runs Gettext's own `dgettext` with the backend, the
text domain, the text and the values you pass. It sets the language for that
one call with `Gettext.with_locale/3`, so the process's own language is left
as it was. `translate_plural/7` does the same with `dngettext`.

Gettext returns the text unchanged when it has no translation. In any
language but your own, AshGettext reports that as missing. That is how the
`_or_missing` functions and `AshGettext.Testing` know.

## When a resource compiles

The `AshGettext.Resource` extension runs a transformer,
`AshGettext.Resource.Transformers.AttachErrorHandler`. It goes through the
resource's actions and sets the `error_handler` of each create, update and
destroy action to `AshGettext.ErrorTranslation.ErrorHandler.translate_error/2`.

- An action that already has an `error_handler` is left alone.
- Read and generic actions are skipped, because Ash has no `error_handler`
  option for them.

Nothing else about the resource changes. No attribute, action or policy is
rewritten.

## When an error is raised

Ash calls the handler once for each error an action collects. The handler does
four things:

1. It reads the domain's settings with `AshGettext.Info.settings/1`. If the
   domain has no `gettext` block, or `translate_errors?` is `false`, the
   error is returned as it is.
2. It builds a map from the changeset with the `:locale` from the action
   context, the `:actor` and the `:changeset`, and runs the resolver chain on
   it. The first resolver that returns a locale wins.
3. It normalizes that locale to one the backend has catalogs for. A language
   with no catalog becomes `default_locale`.
4. It looks the error's `message` up in the backend, under the domain's
   `text_domain`, with the error's `vars` as values.

If the catalog has an entry, the error comes back with the translated message.
If it has none, the error comes back unchanged.

## Why transport does not matter

The handler changes the error struct itself. JSON:API, GraphQL and LiveView
all render that same struct, so each of them shows the translated message
with no code of its own. An error with nested `errors`, such as an
`Ash.Error.Invalid`, is translated inside as well as at the top.

## The source language

The backend has a source locale: its default locale, `en` unless you set
another. In that locale the msgid is the text, so a lookup always counts as
found, and you keep no catalog for it. In any other locale, an entry that is
missing is reported as missing. `AshGettext.translate_or_missing/5` shows the
difference, and `AshGettext.Testing` is built on it.

## Why the settings live in the domain

The `gettext do` block is in the domain, not in `config.exs`. Application
config is shared by the whole node, so a test that changes it cannot run in
parallel with another. A domain's settings are read from the compiled module
every time, so they are the same in every process and every test can be
`async: true`.

The list of supported locales is not a setting. It is read from the backend's
catalogs, so it cannot disagree with the files on disk.

## Where the code is

| Module | Job |
|---|---|
| `AshGettext.Domain` | The `gettext` block and its verifier. |
| `AshGettext.Resource` | The extension that attaches the handler. |
| `AshGettext.ErrorTranslation.ErrorHandler` | The `error_handler`. Resolves the locale, then translates. |
| `AshGettext.ErrorTranslation` | Translates an error struct. Pure: no action, no database. |
| `AshGettext.Locale` | Runs the resolvers, then normalizes. |
| `AshGettext` | Looks text up in the backend: strings, plurals, enum values. |

`AshGettext.ErrorTranslation.translate/2` and `AshGettext.Locale.resolve/2`
take everything they need as arguments, so you can call them yourself.

## Limits

- **Text passed to `AshGettext.translate/5` is not extracted.** Neither
  extract task sees it. Add it to the template by hand.
- **Only write actions are translated.** Ash has no `error_handler` for reads
  or generic actions. Their errors reach the caller as written.
- **A handler you wrote is kept.** If an action declares its own
  `error_handler`, AshGettext does not replace it.
- **The message must be a constant string.** A message built with `#{...}`
  has no stable msgid. `mix ash_gettext.extract` lists these.
- **A module attribute as `message:` is not extracted.** The lookup works, but
  the template has no entry until you add it by hand.
- **An entry that equals its msgid counts as missing.** In a non-source
  locale, a translation that is identical to the msgid cannot be told apart
  from a miss.
- **A resource needs the extension.** The domain block alone translates
  nothing. Set `require_resource_extension?` to find the resources that
  forgot.
