# How AshGettext works

This page explains what AshGettext does when you translate text, when a
resource compiles and when an error is raised, and why it has the limits it
has.

## When you translate text

`AshGettext.translate/5` takes the language as an argument. It runs Gettext's own `dgettext` with the backend, the
text domain, the text and the values you pass. It sets the language for that
one call with `Gettext.with_locale/3`, so the process's own language is left
as it was. `translate_plural/7` does the same with `dngettext`.

Gettext returns the text unchanged when it has no translation. In any
language but your own, AshGettext reports that as missing: the
`_or_missing` functions use it, and the plain
functions send a `[:ash_gettext, :translation, :missing]` telemetry event.

Attribute labels are lookups like any other. The key is the text you wrote in
the resource's `gettext` block, and the text domain defaults to `"ash"`.

`use AshGettext.Enum` checks that every value has a written label, then makes an
`Ash.Type.Enum` with the same values. It overrides Ash's `label/1` and
`description/1`: they call Ash's version for the source text, then looks that
text up with `AshGettext.translate/5` in Gettext's current locale. The key is
the label or description as written. A value with no written label fails to
compile.

## When a resource compiles

The `AshGettext.Resource` extension runs a transformer,
`AshGettext.Resource.Transformers.AttachErrorHandler`. It goes through the
resource's actions and sets the `error_handler` of each create, update,
destroy and generic action to `AshGettext.ErrorTranslation.ErrorHandler.translate_error/2`.

- An action that already has an `error_handler` is left alone.
- Read actions are skipped, because Ash has no `error_handler` option for
  them.

Nothing else about the resource changes. No attribute, action or policy is
rewritten.

## When an error is raised

Ash calls the handler once for each error an action collects. The handler does
three things:

1. It reads the domain's settings with `AshGettext.Info.settings/1`. If the
   domain has no `gettext` block, or `translate_errors?` is `false`, the
   error is returned as it is.
2. It works out the language. It asks the domain's `locale_resolver` with
   the action's actor, and cuts the answer to a language the backend has.
   With no actor or no answer it uses Gettext's current language. It never
   changes the process language.
3. It looks the error's `message` up in the backend, under the domain's
   `text_domain`, with the error's `vars` as values.

If the catalog has an entry, the error comes back with the translated message.
If it has none, the error comes back unchanged.

An Ash error with no message, such as a value that does not cast, takes its
sentence from `AshGettext.AshMessages` instead, written into its own text
field. Every error keeps its struct; `Ash.Error.Changes.Required`, which has
no text field, carries the sentence in `vars[:translation]`. See
[Why some errors are hard to translate](why-some-errors-are-hard.md).

## Text a transport writes itself

Some text never exists in the error. AshJsonApi and AshGraphql each write
"is required" on a missing value themselves, and neither reads it from the
error. That text can only be translated once the transport has written it.

The rules for it are in `AshGettext.TransportText`, and they know nothing
about any transport: look the text up, then the written sentence for the
error's code, else leave it alone. `AshGettext.JsonApi` and
`AshGettext.Graphql` are thin adapters over it, installed for you by
`AshGettext.Domain.Transformers.TranslateReplies`. Another transport needs one call to
`AshGettext.TransportText.translate/3` from its own error hook.

## Why transport does not matter

The handler changes the error struct itself. JSON:API and GraphQL
both render that same struct, so each of them shows the translated message
with no code of its own. An error with nested `errors`, such as an
`Ash.Error.Invalid`, is translated inside as well as at the top.

## The source language

The backend has a source locale: its default locale, `en` unless you set
another. In that locale the msgid is the text, so a lookup always counts as
found, and you keep no catalog for it. In any other locale, an entry that is
missing is reported as missing. `AshGettext.translate_or_missing/5` shows the
difference.

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
| `AshGettext.ErrorTranslation.ErrorHandler` | The `error_handler`. Translates in the action's language. |
| `AshGettext.ErrorTranslation` | Translates an error struct. Pure: no action, no database. |
| `AshGettext.Info` | Reads the `gettext` block. `language/2` asks the resolver, then normalizes. |
| `AshGettext.JsonApi`, `AshGettext.Graphql` | Translate the text AshJsonApi and AshGraphql write into a reply. |
| `AshGettext.Domain.Transformers.TranslateReplies` | Installs those two as the domain's `error_handler`. |
| `AshGettext.AshMessages` | The written sentences for Ash's own errors that have no message. |
| `AshGettext.Enum` | `use` it instead of `Ash.Type.Enum` to translate `label/1` and `description/1`. |
| `AshGettext` | Looks text up in the backend: strings, plurals, attribute labels. |

`AshGettext.ErrorTranslation.translate/2` takes everything it needs as
arguments, so you can call it yourself.

## Limits

- **Text passed to `translate/5` is not extracted.** `mix gettext.extract`
  does not see it. Add it to the template by hand. Enum labels and attribute labels
  are extracted.
- **Read errors are not translated in the error.** Ash has no
  `error_handler` for reads. A transport that writes the text can still
  translate it; `AshGettext.JsonApi` and `AshGettext.Graphql` do.
- **A handler you wrote is kept.** If an action declares its own
  `error_handler`, AshGettext does not replace it.
- **The message must be a constant string.** A message built with `#{...}`
  has no stable msgid. `mix gettext.extract` warns about these.
- **An entry that equals its msgid counts as missing.** In a non-source
  locale, a translation that is identical to the msgid cannot be told apart
  from a miss.
- **A resource needs the extension.** The domain block alone translates
  nothing. Set `require_resource_extension?` to find the resources that
  forgot.
