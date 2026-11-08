# AshGettext

[![CI](https://github.com/Undeadlol1/ash_gettext/actions/workflows/ci.yml/badge.svg)](https://github.com/Undeadlol1/ash_gettext/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/Undeadlol1/ash_gettext/blob/main/LICENSE)

A translation library for [Ash](https://hexdocs.pm/ash). Your text, your
enum values, your attribute names and Ash's own errors come out in each
user's language.

## TL;DR

```elixir
defmodule MyApp.Order.Status do
  use AshGettext.Enum,
    backend: MyApp.Gettext,
    values: [placed: [label: "Order placed"], awaiting_pickup: [label: "Ready for pickup"]]
end

# `mix gettext.extract` collects the labels you wrote into your template.
# You translate them in `priv/gettext/ru/LC_MESSAGES/ash.po`.

# The user's language is Russian. Load an order as that user:
order = Ash.get!(MyApp.Order, id, load: [:status_label], actor: user)

order.status        #=> :awaiting_pickup
order.status_label  #=> "Ожидает выдачи"

# The resource says: validate present(:delivery_date), message: "can't be blank"
{:error, error} = Ash.create(MyApp.Order, %{delivery_date: nil}, actor: user)

hd(error.errors).message
#=> "не может быть пустым"   (written in English, the user gets Russian)
```

Every enum attribute gets a translated `_label` field that clients can load. Errors come back in the user's language. The English you write is the key. That's it.

## Installation

Not on Hex yet, so take it from GitHub:

```elixir
def deps do
  [
    {:ash_gettext, github: "Undeadlol1/ash_gettext"}
  ]
end
```

Your app needs a Gettext backend (`use Gettext.Backend, otp_app: :my_app`).

## Usage

### 1. Set it up once

Add the extension and a `gettext` block to each domain, and the extension to
your resources. Put them in your base domain and base resource so you write
them once:

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

### 2. Tell it the user's language

A resolver is your code. It reads the language from wherever your app
keeps it. Here the user has a `:language` field:

```elixir
defmodule MyApp.Locale.FromActor do
  @behaviour AshGettext.Locale.Resolver

  @impl true
  def resolve(%{actor: %{language: language}}), do: language
  def resolve(_context), do: nil
end
```

Call the field whatever you like; the resolver is where you say it.

Now run any action with `actor: user` (or `context: %{locale: "ru"}`).
Labels loaded on records and errors come out in the actor's language. The
process language is never changed. Code outside an action, such as a job
that formats text, picks the language itself with `Gettext.with_locale/3`.

A resolver must be a pure function of its context: read the locale off the
loaded actor, do not query the database. `ru_RU` and `en-US` are cut to the
language, and a language with no catalog becomes `default_locale`. More in
[Locales](documentation/topics/locales.md).

### 3. Translate an enum

Write a label for every value. AshGettext never makes a label from a code
name, so a value without one fails the build. `use AshGettext.Enum` takes the
values and makes the Ash enum for you:

```elixir
defmodule MyApp.Order.Status do
  use AshGettext.Enum,
    backend: MyApp.Gettext,
    values: [
      placed: [label: "Order placed"],
      awaiting_pickup: [label: "Ready for pickup", description: "Ready at the pickup point"]
    ]
end

Gettext.with_locale(MyApp.Gettext, user.language, fn ->
  MyApp.Order.Status.label(:awaiting_pickup)
end)
#=> "Ожидает выдачи"

Gettext.with_locale(MyApp.Gettext, user.language, fn ->
  MyApp.Order.Status.description(:awaiting_pickup)
end)
#=> "Готов к выдаче в пункте"
```

`label/1` and `description/1` are still Ash's own functions. They now return
the translated text, in Gettext's current language. An empty value (`nil`) gives `nil`.

### 4. Show an enum on a record

Every attribute whose type uses `AshGettext.Enum` gets a field named
`<attribute>_label`. Load it like any calculation:

```elixir
order = Ash.get!(MyApp.Order, id, load: [:status_label], actor: user)

order.status        #=> :awaiting_pickup
order.status_label  #=> "Ожидает выдачи"
```

An empty value gives `nil`, a list attribute gives a list of labels, and a
field you already named `status_label` is left alone.

### 5. Show an attribute name

Write the name in the resource:

```elixir
gettext do
  label :date_of_birth, "Date of birth"
end
```

```elixir
Gettext.with_locale(MyApp.Gettext, user.language, fn ->
  AshGettext.attribute_label(MyApp.Order, :date_of_birth)
end)
#=> "Дата рождения"
```

An attribute with no written `label` raises `ArgumentError`. A `label` for an
attribute the resource does not have fails the build.

### 6. Errors

Ash's own errors come back in the user's language. Leave out a required
value and the user reads a sentence, not a field name:

```elixir
{:error, error} = Ash.create(MyApp.Order, %{}, actor: user)
hd(error.errors).message
#=> "обязательное поле"   (Ash says "attribute delivery_date is required")
```

The English sentence is "is required". `mix gettext.extract` adds it and
the other sentences for Ash's errors to your template.

Your own messages work the same way. Write them in your own language:

```elixir
validate present(:email), message: "can't be blank"
```

```elixir
{:error, error} = Ash.create(MyApp.User, %{email: nil}, actor: user)
hd(error.errors).message
#=> "не может быть пустым"
```

No code on the action. Create, update and destroy errors are translated.

### 7. Hand the texts to translators

```
mix gettext.extract --merge              # Gettext's own command
mix gettext.extract --check-up-to-date   # in CI: fails when a template is stale
```

AshGettext makes your enum labels, attribute labels, messages and Ash's error
sentences visible to it, so they land in `ash.pot`. Translators fill in
`ash.po` per language.

### 8. Catch missing translations

A lookup with no translation returns the text as written and sends a
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

In tests, assert a text is covered:

```elixir
import AshGettext.Testing

test "the status label has a Russian translation" do
  assert_covered(MyApp.Gettext, "ash", "Ready for pickup", "ru")
end
```

## Learn more

- [Translating text](documentation/topics/translating-text.md): enums,
  strings, plurals and attribute names.
- [Locales](documentation/topics/locales.md): where the user's language comes
  from, and how it is matched to your catalogs.
- [Translating errors](documentation/topics/translating-errors.md): which
  errors are translated, coded errors, and turning it on one domain at a time.
- [Extracting messages](documentation/topics/extracting-messages.md): what
  `mix gettext.extract` finds, and checking it in CI.
- [How to test with AshGettext](documentation/topics/testing.md): check that
  a translation exists and that an action returns it.
- [How AshGettext works](documentation/topics/how-it-works.md): the path of a
  lookup, the path of an error, and the limits.
- [DSL reference](documentation/dsls/DSL-AshGettext.Domain.md): every option
  in the `gettext` block.

## Limits

- **Only create, update and destroy errors are translated.** Ash gives read
  and generic actions no error handler, so their errors arrive as written.
- **Text passed to `AshGettext.translate/5` is not extracted.** `mix gettext.extract`
  does not see it. Add it to the
  template by hand, or write it with a Gettext macro. Enum labels, attribute
  labels and `message:` strings are extracted.
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
