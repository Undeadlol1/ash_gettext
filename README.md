# AshGettext

[![CI](https://github.com/Undeadlol1/ash_gettext/actions/workflows/ci.yml/badge.svg)](https://github.com/Undeadlol1/ash_gettext/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/Undeadlol1/ash_gettext/blob/main/LICENSE)

Translations for [Ash](https://hexdocs.pm/ash) apps, with Gettext. Your
text, your enum values and Ash's error messages come out in each user's
language.

## TL;DR

```elixir
AshGettext.translate(MyApp.Gettext, "default", "Order shipped", [], "ru")
#=> "Заказ отправлен"
```

Write the text in your own language and put the other languages in your
Gettext catalogs. The language is an argument, so nothing has to be set per
process. That's it.

## Features

- **Translate any text.** Strings, plurals and enum values, from any
  process.
- **Ash's errors in the user's language.** Add one block to a domain, and
  its create, update and destroy errors are translated, with no handler on
  each action.
- **Missing translations show up in tests.** Check that every language has
  a translation, with tests that run in parallel.

## Installation

Not on Hex yet, so take it from GitHub:

```elixir
def deps do
  [
    {:ash_gettext, github: "Undeadlol1/ash_gettext"}
  ]
end
```

Your app needs a Gettext backend, `use Gettext.Backend`. Translating text
needs nothing else. To translate Ash's errors, see
[Translate Ash's errors](#translate-ash-s-errors).

## Usage

### Translate text

The text you write is the key. In your own language it is also the
translation, so you keep catalogs only for the other languages:

```elixir
AshGettext.translate(MyApp.Gettext, "default", "Hello, %{name}", [name: "Ann"], "ru")
#=> "Привет, Ann"

AshGettext.translate_plural(MyApp.Gettext, "default", "%{count} parcel", "%{count} parcels", 3, [], "ru")
#=> "3 посылки"
```

### Show an enum value

```elixir
AshGettext.enum_label(MyApp.Gettext, "default", :status, :awaiting_pickup, "ru")
#=> "Ожидает выдачи"
```

The key is `status.awaiting_pickup`. With no translation, the label reads
"Awaiting pickup", never the raw key.

### Pick the user's language

Browsers send `ru_RU` or `en-US`. `AshGettext.Locale.resolve/2` turns that
into a language your catalogs have, or the default:

```elixir
AshGettext.Locale.resolve(%{locale: "ru_RU"},
  supported: AshGettext.known_locales(MyApp.Gettext),
  default: "en"
)
#=> "ru"
```

### Translate Ash's errors

Add a `gettext` block to the domain and the extension to its resources:

```elixir
defmodule MyApp.Shop do
  use Ash.Domain, extensions: [AshGettext.Domain]

  gettext do
    backend(MyApp.Gettext)
  end
end
```

```elixir
use Ash.Resource, extensions: [AshGettext.Resource]
```

Or let the install task add both to every domain and resource. The first
command shows the edits, the second writes them:

```
mix ash_gettext.install
mix ash_gettext.install --apply
```

An error's `message:` is now looked up like any other text, in the language
from the action's `context: %{locale: "ru"}`:

```elixir
validate present(:email), message: "can't be blank"
```

To take the language from the signed-in user instead, see
[Locales](documentation/topics/locales.md).

### Check translations in tests

```elixir
import AshGettext.Testing

test "the shipped message has a Russian translation" do
  assert_covered(MyApp.Gettext, "default", "Order shipped", "ru")
end
```

## Learn more

- [Translating text](documentation/topics/translating-text.md): strings,
  placeholders, plurals and enum values.
- [Locales](documentation/topics/locales.md): where the user's language comes
  from, and how it is matched to your catalogs.
- [Translating errors](documentation/topics/translating-errors.md): which
  errors are translated, coded errors, and turning it on one domain at a time.
- [Extracting messages](documentation/topics/extracting-messages.md): put
  Ash's `message:` strings in a `.pot` template, and check it in CI.
- [How to test with AshGettext](documentation/topics/testing.md): check that
  a translation exists and that an action returns it.
- [How AshGettext works](documentation/topics/how-it-works.md): the path of a
  lookup, the path of an error, and the limits.
- [DSL reference](documentation/dsls/DSL-AshGettext.Domain.md): every option
  in the `gettext` block.

## Limits

- **Only create, update and destroy errors are translated.** Ash gives read
  and generic actions no error handler, so their errors arrive as written.
- **Text passed to `AshGettext.translate/5` is not extracted.** Neither
  `mix gettext.extract` nor `mix ash_gettext.extract` sees it. Add it to the
  template by hand, or write it with a Gettext macro.
- **A message built with `#{...}` cannot be translated.** Write `%{name}` in
  the text and pass the value instead.
- **A handler you wrote is kept.** An action with its own `error_handler`
  is not translated.

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
