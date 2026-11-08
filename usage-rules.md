# Rules for working with AshGettext

AshGettext is a translation library for Ash. It translates the text an Ash
app shows (strings, plurals, enum labels and descriptions, attribute labels and Ash's own error
messages) in the user's language, through Gettext. Translating text needs only
a Gettext backend. Translating Ash's errors is one feature on top, switched on
per domain. Read these rules before writing code that uses it. Prefer the
defaults; add options only when a requirement demands them.

## Setup

- AshGettext is not on Hex yet. Add
  `{:ash_gettext, github: "Undeadlol1/ash_gettext"}` to deps. It needs `:ash`,
  `:spark` and `:gettext` (a Gettext backend, `use Gettext.Backend`, must
  already exist in the app). `{:ash_json_api, "~> 1.4"}` is optional: add it
  only if the app serves JSON:API.
- Translating text needs nothing else: no domain block, no resource
  extension, no locale setup. The domain and resource extensions are
  only for translating errors.
- No application config is required. Do not add `config :ash_gettext`. All
  error settings live in the domain DSL.
- Keep the domain's `default_locale` equal to the backend's source
  language. The supported locales are never an option: they are the locale folders under the
  backend's `priv`, read through `AshGettext.known_locales/1`.

## Translating text

- Enums: write `use AshGettext.Enum, backend: MyApp.Gettext, values: [...]`
  instead of using `Ash.Type.Enum` yourself. It makes the Ash enum for you. Then
  `MyApp.Status.label(:awaiting_pickup)` and `description/1` return the
  translated text. Call those, never a wrapper. `label(nil)` and
  `description(nil)` return `nil`. Options: `:backend` and `:values`
  (required), `:text_domain` (default `"ash"`). The msgid
  is the `label:` or description you wrote on the value. Every value needs a
  written `label:`; a value without one is a compile error. Do not invent
  per-attribute keys.
- Labels are written by a person. The library never makes one from a code
  name. Never write code that turns `:awaiting_pickup` into "Awaiting pickup".
- On a record: every attribute with an `AshGettext.Enum` type gets a public
  `<attribute>_label` calculation (a list for `{:array, enum}`). Load it with
  `load: [:status_label]`. Do not write your own. A field already named that is
  kept.
- The language comes from the actor. Run the action with `actor:`, and loaded
  `_label` fields and errors use the language the domain's `locale_resolver`
  gives. No action changes the process language. With no actor, Gettext's
  current locale is used.
  Outside an action (a direct `label/1`, `AshGettext.attribute_label/2`, a job
  formatting text), wrap the call in `Gettext.with_locale/3`.
- The msgid is the plain sentence in the source language, with `%{var}`
  placeholders filled from `bindings`. Do not invent keys like
  `"orders.shipped"`. The source language needs no catalog.
- Attribute labels: write `gettext do label :date_of_birth, "Date of birth" end`
  in the resource (`AshGettext.Resource`), then call
  `AshGettext.attribute_label(MyApp.Order, :date_of_birth)`. It reads
  Gettext's current locale; backend and text domain come from the resource's
  domain. The msgid is the text you wrote. An attribute with no written label,
  or an unknown one, raises `ArgumentError`. A `label` for an attribute the
  resource lacks fails the build.
- A lookup with no translation returns the msgid and sends the telemetry event
  `[:ash_gettext, :translation, :missing]` with `backend`, `text_domain`,
  `msgid` and `locale`. Attach a handler to log or count gaps. The
  `_or_missing` functions send no event.
- The functions are `AshGettext.translate/5` `(backend, text_domain, msgid,
  bindings, locale)`, and `translate_plural/7`. The
  language is an argument.
- `translate_or_missing/5`, `translate_plural_or_missing/7`,
  and `attribute_label_or_missing/2` return
  `{:ok, string}` or `{:missing, string}`. They are not the `{:ok, v} | :error`
  shape. A translation identical to its msgid in a non-source locale counts as
  `:missing`.
- `mix gettext.extract` collects the written enum labels and attribute
  labels of every resource in a translating domain. It does not find text passed to
  `AshGettext.translate/5`. Keep that text in a Gettext `*_noop` macro.

## Picking the language

- Actions find their language themselves. For the pure functions, pass the
  `locale` argument; `AshGettext.Locale.Normalizer.normalize(locale,
  AshGettext.known_locales(backend), "en")` cuts `"ru_RU"` to `"ru"` and
  falls back to the default for a language with no catalog.
- A domain names one resolver: `locale_resolver MyApp.LocaleResolver`. It is
  required: the build fails without it.
- A resolver implements `@behaviour AshGettext.Locale.Resolver` with
  `resolve/1`. It receives the actor (never `nil`) and returns a locale
  string, or `nil` for Gettext's current language:
  `def resolve(%{language: language}), do: language` and
  `def resolve(_actor), do: nil`. The answer is cut to its language
  (`"ru_RU"` becomes `"ru"`); one with no catalog becomes `default_locale`.
- There is no language in the action context. With no actor, such as a
  visitor who is not signed in, wrap the call in
  `Gettext.with_locale(MyApp.Gettext, "ru", fn -> ... end)`.
- A resolver belongs in the host app. Do not add actor lookups to the
  library or guess the field.
- A resolver must be a pure function of the actor. Read the locale off the
  loaded actor. Never query the database in a resolver: it runs while an
  action's error is being built, possibly inside a failed transaction.

## Translating errors

- Run `mix ash_gettext.install` to preview the edits, then
  `mix ash_gettext.install --apply` to write them. It adds the
  `AshGettext.Domain` extension and a `gettext do` block to every domain, and
  the `AshGettext.Resource` extension to every resource. Re-running skips what
  is done. Options: `--backend MyApp.Gettext` (needed when the app has zero or
  several backends), `--resolver MyApp.LocaleResolver` (defaults to `LocaleResolver` next to
  the backend; you write that module), `--text-domain`.
- To wire by hand: `use Ash.Domain, extensions: [AshGettext.Domain]` with a
  `gettext do backend MyApp.Gettext end` block, and
  `use Ash.Resource, extensions: [AshGettext.Resource]` on each resource.
  The domain block alone changes no behavior.
- Options on the `gettext` block: `backend` (required module);
  `default_locale` (default `"en"`); `text_domain` (default `"ash"`);
  `locale_resolver` (required module);
  `translate_errors?` (default `true`); `require_resource_extension?`
  (default `false`).
- The `message:` of an error IS the msgid. Write it as the plain sentence in
  the source language: `message: "must weigh at least %{min} kg"`. Do not
  invent keys like `"errors.weight_too_low"`.
- The source-language sentence is itself the msgid, so the source language
  needs no catalog. The `.po` files hold only the other languages, and the
  source locale is never reported missing.
- Interpolate with `%{var}` in the message and pass the values as
  `vars: [min: 30]` on the error. Only `vars` with atom keys reach the
  catalog.
- A message no catalog covers is left unchanged. Adopting AshGettext never
  rewrites an existing message into something worse.
- Translation runs only for errors raised in `create`, `update` and `destroy`
  actions, through the `error_handler` the resource extension sets. Errors
  from read and generic actions are not translated. Do not expect or promise
  otherwise.
- An action that already declares its own `error_handler` is left alone and
  its errors are not translated.
- Validation errors, builtin constraint errors, cast errors, missing required
  values and failed policies all arrive at the same handler, so every
  transport (JSON:API, GraphQL) sees the translated text. A stale record
  error comes from the data layer after the handler and is not translated.
- Ash's own errors with no message (`Ash.Error.Changes.Required`,
  `InvalidAttribute`, `InvalidArgument`, `Ash.Error.Forbidden.Policy`) get a
  written sentence from `AshGettext.AshMessages`, such as "is required". They
  come back as `AshGettext.AshMessages.Translated`: `message` is the
  translated sentence, `original` is Ash's error, `field` and `class` are
  kept. Match on `field` or `original`, not on the Ash struct.
- `text_domain` defaults to `"ash"`, so catalogs live at
  `priv/gettext/<locale>/LC_MESSAGES/ash.po`. Errors, enum labels and
  attribute labels share it.
- Run Gettext's own `mix gettext.extract --merge`. AshGettext makes every
  enum label, attribute label, literal `message` (in resources and in the
  validation, change and preparation modules they use) and Ash's error
  sentences visible to it. Run `mix gettext.extract --check-up-to-date` in CI.
  There is no `ash_gettext` extract task.
- Write a `message:` as a literal string in the resource or in the validation
  or change module it uses. Text elsewhere follows Gettext's usual rules. An
  interpolated string (`"... #{x}"`) is a compile
  warning during extraction and cannot be a msgid: use a constant msgid with
  `%{var}` and `vars:`.
- Do not edit the generated `.pot`. Translations go in the `.po` files.
- Set `translate_errors? false` on a domain to switch translation off for
  all its resources. Set `require_resource_extension? true` to get a
  compile warning (an error under `--warnings-as-errors`) for each resource
  in the domain without `AshGettext.Resource`.
- A domain without the extension, or without a `gettext` block, passes errors
  through untouched.

## Coded errors

- Use `AshGettext.Error` for a rule a client must branch on without parsing
  a sentence. Build it with `AshGettext.Error.exception/1`:

  ```elixir
  {:error,
   AshGettext.Error.exception(
     code: :weight_too_low,
     field: :weight,
     message: "must weigh at least %{min} kg",
     vars: [min: 30]
   )}
  ```

- `code` is required and must be an atom. `exception/1` raises
  `ArgumentError` without it. `message` is the msgid. `field` is optional.
  `vars` are the `%{var}` values.
- With `:ash_json_api` installed it renders with `code` as a string, the
  translated message as `detail`, `vars` as `meta`, no `title`, and
  `source.pointer` set to `/data/attributes/<field>` when `field` is set. Its status class is
  `:invalid`.
- It is translated by the same handler as any other error, so it follows the
  same limit: create, update and destroy only.

## Rules

- Do not call `dgettext` or `Gettext.gettext` by hand to translate an Ash
  error message. The `message:` is the msgid and translation is automatic.
- Do not write an `error_handler` on an action to translate. The resource
  extension sets it. Writing your own disables translation for that action.
- Do not change the process language to pick the error language. Pass
  `actor:` and let the resolver answer, or wrap the call in
  `Gettext.with_locale/3` when there is no actor.
- Do not hand-write `.pot` entries that the extractor produces.
- Configuration lives in the domain DSL and is read through `AshGettext.Info`.
  Do not read it from `Application.get_env`.
- To share one `gettext` block across domains, put it in a base domain macro
  and `use` that. To avoid `extensions:` on every resource, put it in the
  base resource macro.

## Tests

- Tests with `async: true` are safe. Nothing is global: backend, text domain
  and locale are arguments or domain settings, and the locale of a run comes
  from the actor or `Gettext.with_locale/3`.
- Assert the text through the real action:
  `Gettext.with_locale(MyApp.Gettext, "ru", fn -> Ash.create(changeset) end)`,
  then check the error's message.
- `AshGettext.Testing.assert_translates(backend, text_domain, msgid, locale, expected, bindings \\ [])`
  asserts the exact rendering and returns the string.
- `AshGettext.Testing.assert_covered(backend, text_domain, msgid, locale, bindings \\ [])`
  fails when the locale's catalog has no entry for the msgid. Loop it over
  `AshGettext.known_locales(backend) -- [source_locale]` as a coverage sweep.
  For labels, pass the enum's label or description or an attribute label text as the
  msgid, with the `"ash"` text domain.
  The source locale always passes.
- Use these two helpers to test the translations themselves. In tests of
  application behavior, assert the text users read through your own API
  instead.
- Do not change the process language in a test. It leaks between tests and
  breaks `async: true`. Use `Gettext.with_locale(backend, "ru", fn -> ... end)`.
