# AshGettext

[![CI](https://github.com/Undeadlol1/ash_gettext/actions/workflows/ci.yml/badge.svg)](https://github.com/Undeadlol1/ash_gettext/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/Undeadlol1/ash_gettext/blob/main/LICENSE)

Gettext translation for [Ash](https://hexdocs.pm/ash) errors. Validation
messages come out in the reader's language, with no handler on each action.

## TL;DR

```elixir
defmodule MyApp.Shop do
  use Ash.Domain, extensions: [AshGettext.Domain]

  gettext do
    backend(MyApp.Gettext)
  end
end

# in each resource
use Ash.Resource, extensions: [AshGettext.Resource]
```

Every error from a create, update or destroy action is looked up in your
Gettext catalogs, in the locale of the request. That's it.

## Features

- **No handler on each action.** The resource extension translates every
  create, update and destroy action, including ones you add later.
- **One place for the locale.** List resolvers in the domain, and errors
  follow the actor's language from any process.
- **No second message list.** `mix ash_gettext.extract` finds every `message:`
  and writes the `.pot` file.
- **The source language needs no catalog.** The sentence in your code is the
  msgid, so `.po` files hold only the other languages.
- **Coded errors.** `AshGettext.Error` carries a `code` for clients and a
  translated `message` for people, and renders for JSON:API.

## Installation

Not on Hex yet, so take it from GitHub:

```elixir
def deps do
  [
    {:ash_gettext, github: "Undeadlol1/ash_gettext"}
  ]
end
```

Then preview the edits the install task would make, and apply them:

```
mix ash_gettext.install
mix ash_gettext.install --apply
```

It adds the extensions to every domain and resource and names your Gettext
backend. See [Getting started](documentation/topics/getting-started.md) to do
it by hand.

## Usage

### Write the message in your own language

The `message:` is the msgid. Put values in with `%{name}` and `vars`:

```elixir
InvalidAttribute.exception(
  field: :weight,
  message: "must weigh at least %{min} kg",
  vars: [min: 30]
)
```

```po
# priv/gettext/ru/LC_MESSAGES/ash_errors.po
msgid "must weigh at least %{min} kg"
msgstr "должен весить не меньше %{min} кг"
```

See [Translating errors](documentation/topics/translating-errors.md).

### Choose the language from the user

```elixir
defmodule MyApp.UserLocale do
  @behaviour AshGettext.Locale.Resolver

  def resolve(%{actor: %{locale: locale}}), do: locale
  def resolve(_context), do: nil
end

gettext do
  backend(MyApp.Gettext)
  locale_resolvers([MyApp.UserLocale, AshGettext.Locale.FromContext])
end
```

The first resolver that returns a locale wins. See
[Locales](documentation/topics/locales.md).

### Write the template

```
mix ash_gettext.extract
mix ash_gettext.extract --check
```

The first writes `priv/gettext/ash_errors.pot`. The second fails in CI when
the file is out of date. See
[Extracting messages](documentation/topics/extracting-messages.md).

### Return a coded error

```elixir
{:error,
 AshGettext.Error.exception(
   code: :weight_too_low,
   field: :weight,
   message: "must weigh at least %{min} kg",
   vars: [min: 30]
 )}
```

`code` is required. See
[Translating errors](documentation/topics/translating-errors.md#return-a-coded-error).

## Learn more

- [Getting started](documentation/topics/getting-started.md): install, wire a
  domain and a resource, and see one error in two languages.
- [Translating errors](documentation/topics/translating-errors.md): what is
  translated, placeholders, coded errors and rolling out one domain at a time.
- [Locales](documentation/topics/locales.md): resolvers, their order, and how
  a locale is matched to your catalogs.
- [Extracting messages](documentation/topics/extracting-messages.md): the
  `.pot` template and the CI check.
- [How to test with AshGettext](documentation/topics/testing.md): check that a
  message is translated and that the template is current.
- [How AshGettext works](documentation/topics/how-it-works.md): the handler,
  the path of an error, and the limits.
- [DSL reference](documentation/dsls/DSL-AshGettext.Domain.md): every option
  in the `gettext` block.

## Limits

- **Only create, update and destroy actions are translated.** Ash gives read
  and generic actions no `error_handler`, so their errors reach the caller as
  written.
- **A `message:` set from a module attribute is skipped by extraction.** The
  lookup works, but the `.pot` has no entry until you add it by hand.
- **A message built with `#{...}` cannot be a msgid.** The extract task lists
  each one so you can rewrite it with `%{name}` and `vars`.
- **One run writes one template.** When your domains name different text
  domains, `mix ash_gettext.extract` asks you to pick one with `--output`.
- **An action's own `error_handler` is kept.** AshGettext does not replace a
  handler you wrote.

## For AI assistants

<details>
<summary>Instructions for coding agents (Claude Code, Cursor, Copilot, ...)</summary>
<p>
The file for agents is
<a href="https://github.com/Undeadlol1/ash_gettext/blob/main/usage-rules.md"><code>usage-rules.md</code></a>.
It ships inside the package, so after <code>mix deps.get</code> it is at
<code>deps/ash_gettext/usage-rules.md</code>. Point your agent at that file.
If your project uses the
<a href="https://hexdocs.pm/usage_rules"><code>usage_rules</code></a>
package, add <code>:ash_gettext</code> to its list instead.
</p>
</details>

## License

MIT. See [LICENSE](https://github.com/Undeadlol1/ash_gettext/blob/main/LICENSE).
