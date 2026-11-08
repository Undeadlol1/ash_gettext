# AshGettext

[![CI](https://github.com/Undeadlol1/ash_gettext/actions/workflows/ci.yml/badge.svg)](https://github.com/Undeadlol1/ash_gettext/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/Undeadlol1/ash_gettext/blob/main/LICENSE)

A translation library for [Ash](https://hexdocs.pm/ash). Your text, your
enum values, your attribute names and Ash's own errors come out in each
user's language.

## TL;DR

```elixir
defmodule MyApp.Order.Status do
  use Ash.Type.Enum, values: [:placed, awaiting_pickup: [label: "Awaiting pickup", description: "Ready at the pickup point"]]
  use AshGettext.Enum, backend: MyApp.Gettext
end

MyApp.Order.Status.label(:awaiting_pickup)
#=> "Ожидает выдачи"

MyApp.Shop.create_order(%{delivery_date: nil}, actor: user)
#=> {:error, %Ash.Error.Invalid{errors: [%{message: "не может быть пустым"}]}}
```

The enum's own `label/1` returns the user's language, and so does the message of a create that fails (the domain `gettext` block is further down). That's it.

## Features

- **Translate any text.** Strings and plurals, in the user's language.
- **Enum labels and attribute names.** An enum's own `label/1` returns the
  user's language. Attribute names come out as words too, with no keys to
  invent.
- **Ash's errors.** Add one block to a domain and its create, update and
  destroy errors are translated.

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
needs nothing else.

## Usage

### Translate an enum

Put `use AshGettext.Enum` after `use Ash.Type.Enum`:

```elixir
defmodule MyApp.Order.Status do
  use Ash.Type.Enum,
    values: [
      :placed,
      awaiting_pickup: [label: "Awaiting pickup", description: "Ready at the pickup point"]
    ]

  use AshGettext.Enum, backend: MyApp.Gettext
end

MyApp.Order.Status.label(:awaiting_pickup)
#=> "Ожидает выдачи"

MyApp.Order.Status.description(:awaiting_pickup)
#=> "Готов к выдаче в пункте"
```

`label/1` and `description/1` are still Ash's own functions. They now return
the translated text. The text you wrote is the key, and the key lives in
`ash.po` (`text_domain: "other"` picks another file).

The language is Gettext's current locale for the process. Set it the usual
way with `Gettext.put_locale/2`, or for one block of code with
`Gettext.with_locale/3`. Or run an action with `actor:` (or
`context: %{locale: "ru"}`) and AshGettext sets it for you, see below.

### Translate text

The text you write is the key. In your own language it is also the
translation, so you keep catalogs only for the other languages. These
functions take the backend and the language as arguments:

```elixir
AshGettext.translate(MyApp.Gettext, "default", "Hello, %{name}", [name: "Ann"], "ru")
#=> "Привет, Ann"

AshGettext.translate_plural(MyApp.Gettext, "default", "%{count} parcel", "%{count} parcels", 3, [], "ru")
#=> "3 посылки"
```

### Show an attribute name

```elixir
Gettext.with_locale(MyApp.Gettext, "ru", fn ->
  AshGettext.attribute_label(MyApp.Order, :date_of_birth)
end)
#=> "Дата рождения"
```

The language is Gettext's current one. The backend and text domain come from
the resource's domain. The key is the name in words: "Date of birth". An
attribute the resource does not have, or a resource whose domain has no
`gettext` block, raises `ArgumentError`.

### Pick the user's language

Run an action with `actor:` (or `context: %{locale: "ru"}`) and AshGettext
sets Gettext's language for that process, once, when the action starts.
Enums, errors and attribute names then come out in it. A resolver reads the
language off the actor:

```elixir
defmodule MyApp.Locale.FromActor do
  @behaviour AshGettext.Locale.Resolver

  @impl true
  def resolve(%{actor: %{locale: locale}}), do: locale
  def resolve(_context), do: nil
end
```

A resolver must be a pure function of its context. Read the locale off the
loaded actor and do not query the database: a resolver runs once, when the
action starts. With no actor and no `locale`, the process language is left
alone.

`ru_RU` and `en-US` are cut to the language, and a language with no catalog
becomes `default_locale`. More in [Locales](documentation/topics/locales.md).

### Translate Ash's errors

Add a `gettext` block to the domain and the extension to its resources:

```elixir
defmodule MyApp.Shop do
  use Ash.Domain, extensions: [AshGettext.Domain]

  gettext do
    backend(MyApp.Gettext)
    locale_resolvers([MyApp.Locale.FromActor, AshGettext.Locale.FromContext])
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
Gettext is set to, which an action's actor or its `context: %{locale: "ru"}`
sets when it starts:

```elixir
validate present(:email), message: "can't be blank"
```

Errors, enum labels and attribute names share one catalog, `ash.po`. Run
`mix ash_gettext.extract` to write all of them to `ash.pot`.

### Report missing translations

A lookup with no translation returns the text as written, and sends a
telemetry event. Log it:

```elixir
:telemetry.attach(
  "ash-gettext-missing",
  [:ash_gettext, :translation, :missing],
  &MyApp.Telemetry.log_missing/4,
  nil
)

def log_missing(_event, _measurements, meta, _config),
  do: Logger.warning("No #{meta.locale} translation for #{inspect(meta.msgid)}")
```

The metadata has `backend`, `text_domain`, `msgid` and `locale`.

### Check translations in tests

```elixir
import AshGettext.Testing

test "the shipped message has a Russian translation" do
  assert_covered(MyApp.Gettext, "default", "Order shipped", "ru")
end
```

## Learn more

- [Translating text](documentation/topics/translating-text.md): enums,
  strings, plurals and attribute names.
- [Locales](documentation/topics/locales.md): where the user's language comes
  from, and how it is matched to your catalogs.
- [Translating errors](documentation/topics/translating-errors.md): which
  errors are translated, coded errors, and turning it on one domain at a time.
- [Extracting messages](documentation/topics/extracting-messages.md): put
  Ash's `message:` strings, enum labels and attribute names in a `.pot`
  template, and check it in CI.
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
  template by hand, or write it with a Gettext macro. Enum labels, attribute
  names and `message:` strings are extracted.
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
