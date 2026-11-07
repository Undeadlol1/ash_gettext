# Rules for working with AshGettext

AshGettext translates Ash apps with Gettext. It translates text, plurals
and enum values through `AshGettext.translate/5` and its siblings, picks the
user's language, and translates the errors of create, update and destroy
actions. Read these rules before writing code that uses it. Prefer the defaults; add
options only when a requirement demands them.

## Setup

- AshGettext is not on Hex yet. Add
  `{:ash_gettext, github: "Undeadlol1/ash_gettext"}` to deps. It needs `:ash`,
  `:spark` and `:gettext` (a Gettext backend, `use Gettext.Backend`, must
  already exist in the app). `{:ash_json_api, "~> 1.4"}` is optional: add it
  only if the app serves JSON:API.
- Run `mix ash_gettext.install` to preview the edits, then
  `mix ash_gettext.install --apply` to write them. It adds the
  `AshGettext.Domain` extension and a `gettext do` block to every domain, and
  the `AshGettext.Resource` extension to every resource. Re-running skips what
  is done. Options: `--backend MyApp.Gettext` (needed when the app has zero or
  several backends), `--resolver MyApp.Localization`, `--text-domain`.
- To wire by hand: `use Ash.Domain, extensions: [AshGettext.Domain]` with a
  `gettext do backend MyApp.Gettext end` block, and
  `use Ash.Resource, extensions: [AshGettext.Resource]` on each resource.
  Both are needed only for translating errors; the domain block alone
  changes no behavior. Translating text needs neither.
- Options on the `gettext` block: `backend` (required module);
  `default_locale` (default `"en"`); `text_domain` (default `"ash_errors"`);
  `locale_resolvers` (default `[AshGettext.Locale.FromContext]`);
  `translate_errors?` (default `true`); `require_resource_extension?`
  (default `false`).
- No application config is required. Do not add `config :ash_gettext`. All
  settings live in the domain DSL.
- Keep `default_locale` equal to the backend's source language. The supported
  locales are never an option: they are the locale folders under the
  backend's `priv`, read through `AshGettext.known_locales/1`.

## Translating text

- Translate a string with `AshGettext.translate/5`:
  `(backend, text_domain, msgid, bindings, locale)`. It needs only a Gettext
  backend: no domain block, no resource extension, no `Gettext.put_locale`.
- The msgid is the plain sentence in the source language, with `%{var}`
  placeholders filled from `bindings`. Do not invent keys like
  `"orders.shipped"`. The source language needs no catalog.
- For plurals use `AshGettext.translate_plural/7` with
  `(backend, text_domain, msgid, msgid_plural, count, bindings, locale)`;
  `count` is always available as `%{count}`.
- To label an enum value use `AshGettext.enum_label/5` with
  `(backend, text_domain, attribute, value, locale)`. The msgid is
  `"<attribute>.<value>"` (`AshGettext.enum_msgid/2`). An uncovered value
  falls back to a humanized form (`:awaiting_pickup` becomes
  `"Awaiting pickup"`).
- `translate_or_missing/5`, `translate_plural_or_missing/7` and
  `enum_label_or_missing/5` return `{:ok, string}` or `{:missing, string}`.
  They are not the `{:ok, v} | :error` shape. A translation identical to its
  msgid in a non-source locale counts as `:missing`.
- Pick the `locale` argument with
  `AshGettext.Locale.resolve(context, resolvers: [...], supported: AshGettext.known_locales(backend), default: "en")`.
  It cuts `"ru_RU"` to `"ru"` and falls back to `default` for a language
  with no catalog.
- Neither `mix gettext.extract` nor `mix ash_gettext.extract` finds text
  passed to these functions. Add those msgids to the `.pot` by hand or keep
  them in a Gettext `*_noop` macro.

## Translating errors

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
- Validation errors, builtin constraint errors and data layer errors all
  arrive at the same handler, so every transport (JSON:API, GraphQL) sees the
  translated text.
- `text_domain` defaults to `"ash_errors"`, so catalogs live at
  `priv/gettext/<locale>/LC_MESSAGES/ash_errors.po`.
- Run `mix ash_gettext.extract` to write the template from every literal
  `message:` in `lib`. Arguments: source paths and `--output PATH`. Run
  `mix ash_gettext.extract --check` in CI: it fails when the `.pot` is stale.
- Without `--output` the task writes the file your own lookups read: the
  backend's `priv` directory holding `<text_domain>.pot`. Do not pass
  `--output` to correct the path; it is already right.
- One run writes one template. When the app's domains name different text
  domains, the task refuses to guess and `--output` becomes required, along
  with the source paths belonging to that domain.
- Extraction only sees `message:` written as a literal string. A message in a
  module attribute or any other expression is skipped silently: add its
  msgid to the `.pot` by hand. An interpolated string (`"... #{x}"`) is
  reported and cannot be a msgid: use a constant msgid with `%{var}` and
  `vars:`.
- Do not edit the generated `.pot`. Translations go in the `.po` files.
- The locale of an error comes from `locale_resolvers`, tried in order until
  one returns a string. A returned locale is cut to its language (`"ru_RU"`
  and `"ru-RU"` become `"ru"`). If that language has no catalog directory,
  `default_locale` is used.
- A resolver implements `@behaviour AshGettext.Locale.Resolver` with
  `resolve/1`. It receives `%{locale: ..., actor: ..., changeset: ...}` and
  returns a locale string, or `nil` to let the next resolver answer.
- `AshGettext.Locale.FromContext` reads `context: %{locale: "ru"}` from the
  action (atom or string key). When you set `locale_resolvers`, list it
  yourself if you still want it: `[MyApp.Localization, AshGettext.Locale.FromContext]`.
- A resolver that needs the signed-in user's saved language belongs in the
  host app. Do not add actor lookups to the library or guess the field.
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
  translated message as `detail`, `vars` as `meta`, and `source.pointer` set
  to `/data/attributes/<field>` when `field` is set. Its status class is
  `:invalid`.
- It is translated by the same handler as any other error, so it follows the
  same limit: create, update and destroy only.

## Rules

- Do not call `dgettext` or `Gettext.gettext` by hand to translate an Ash
  error message. The `message:` is the msgid and translation is automatic.
- Do not write an `error_handler` on an action to translate. The resource
  extension sets it. Writing your own disables translation for that action.
- Do not call `Gettext.put_locale` per process or request to pick the error
  language. Pass `context: %{locale: "ru"}` or use a resolver.
- Do not hand-write `.pot` entries that the extractor produces.
- Configuration lives in the domain DSL and is read through `AshGettext.Info`.
  Do not read it from `Application.get_env`.
- To share one `gettext` block across domains, put it in a base domain macro
  and `use` that. To avoid `extensions:` on every resource, put it in the
  base resource macro.

## Tests

- Tests with `async: true` are safe. Nothing is global: backend, text domain
  and locale are arguments or domain settings, and the locale of a run comes
  from `context: %{locale: "ru"}`.
- Assert the text through the real action:
  `Ash.create(changeset, context: %{locale: "ru"})`, then check the error's
  message.
- `AshGettext.Testing.assert_translates(backend, text_domain, msgid, locale, expected, bindings \\ [])`
  asserts the exact rendering and returns the string.
- `AshGettext.Testing.assert_covered(backend, text_domain, msgid, locale, bindings \\ [])`
  fails when the locale's catalog has no entry for the msgid. Loop it over
  `AshGettext.known_locales(backend) -- [source_locale]` as a coverage sweep.
  The source locale always passes.
- Use these two helpers to test the translations themselves. In tests of
  application behavior, assert the text users read through your own API
  instead.
- Do not set `Gettext.put_locale` in a test. It leaks between tests and
  breaks `async: true`.
