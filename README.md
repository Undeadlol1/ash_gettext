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

order_for_russian_user = Ash.get!(MyApp.Order, id, load: [:status_label], actor: russian_user)
order_for_english_user = Ash.get!(MyApp.Order, id, load: [:status_label], actor: english_user)

order_for_russian_user.status_label  #=> "Ожидает выдачи"
order_for_english_user.status_label  #=> "Ready for pickup"

# The resource says: validate present(:delivery_date), message: "can't be blank"
{:error, error_for_russian_user} = Ash.create(MyApp.Order, %{delivery_date: nil}, actor: russian_user)
{:error, error_for_english_user} = Ash.create(MyApp.Order, %{delivery_date: nil}, actor: english_user)

hd(error_for_russian_user.errors).message  #=> "не может быть пустым"
hd(error_for_english_user.errors).message  #=> "can't be blank"
```

Every enum attribute gets a translated `_label` field that clients can load. Errors come back in the user's language. The English you write is the key.

## Installation

Add it to your deps:

```elixir
def deps do
  [
    {:ash_gettext, "~> 0.3"}
  ]
end
```

Your app needs a Gettext backend (`use Gettext.Backend, otp_app: :my_app`).

## Usage

### Set it up once

Add the extension and a `gettext` block to each domain:

```elixir
defmodule MyApp.Shop do
  use Ash.Domain, extensions: [AshGettext.Domain]

  gettext do
    backend(MyApp.Gettext)
    locale_resolver(MyApp.LocaleResolver)
  end
end
```

Add the extension to each resource. It gives the resource its `_label`
fields, its attribute names and its translated errors.

```elixir
defmodule MyApp.Order do
  use Ash.Resource,
    domain: MyApp.Shop,
    extensions: [AshGettext.Resource]

  attributes do
    uuid_primary_key(:id)
    attribute(:status, MyApp.Order.Status, public?: true)
  end
end
```

Or let the install task add both to every domain and resource. The first
command shows the edits, the second writes them:

```
mix ash_gettext.install
mix ash_gettext.install --apply
```

To write all this once instead of in every domain and resource, see
[Set it up once for the whole app](documentation/topics/set-up-once.md).

### Tell it the user's language

A resolver is your code. It gets the actor and returns its language. Here
the user has a `:language` field:

```elixir
defmodule MyApp.LocaleResolver do
  @behaviour AshGettext.Locale.Resolver

  @impl true
  def resolve(%{language: language}), do: language
  def resolve(_actor), do: nil
end
```

Call the field whatever you like; the resolver is where you say it. One
resolver is enough for the whole app; list it in every domain (or your base
domain).

Now run any action with `actor: user`. Labels loaded on records and errors
come out in the actor's language. The process language is never changed.
Code outside an action, such as a job that formats text, picks the language
with `Gettext.with_locale/3`.

A resolver must be a pure function of the actor: read the language off the
loaded actor, do not query the database. `ru_RU` and `en-US` are cut to the
language, and a language with no catalog becomes `default_locale`. More in
[Locales](documentation/topics/locales.md).

### Translate an enum

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
```

```elixir
test "the status reads in Russian" do
  Gettext.put_locale(MyApp.Gettext, "ru")

  assert MyApp.Order.Status.label(:awaiting_pickup) == "Ожидает выдачи"
  assert MyApp.Order.Status.description(:awaiting_pickup) == "Готов к выдаче в пункте"
end
```

`label/1` and `description/1` are still Ash's own functions. They now return
the translated text, in Gettext's current language. An empty value (`nil`) gives `nil`.

### Show an enum on a record

Every attribute whose type uses `AshGettext.Enum` gets a field named
`<attribute>_label`. Load it like any calculation:

```elixir
order = Ash.get!(MyApp.Order, id, load: [:status_label], actor: user)

order.status        #=> :awaiting_pickup
order.status_label  #=> "Ожидает выдачи"
```

An empty value gives `nil`, a list attribute gives a list of labels, and a
field you already named `status_label` is left alone.

### Show an attribute name

Write the name in the resource:

```elixir
gettext do
  label :date_of_birth, "Date of birth"
end
```

```elixir
test "the attribute name reads in Russian" do
  Gettext.put_locale(MyApp.Gettext, "ru")

  assert AshGettext.attribute_label(MyApp.Order, :date_of_birth) == "Дата рождения"
end
```

An attribute with no written `label` raises `ArgumentError`. A `label` for an
attribute the resource does not have fails the build.

### Errors

Ash's own errors come back in the user's language, and stay Ash's own
structs. Send a value that does not cast and the user reads a sentence, not
a field name:

```elixir
{:error, error} = Ash.create(MyApp.Order, %{count: "abc"}, actor: user)
hd(error.errors)
#=> %Ash.Error.Changes.InvalidAttribute{field: :count, message: "неверное значение"}
```

The English sentence is "is invalid". `mix gettext.extract` adds it and
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

### Hand the texts to translators

```
mix gettext.extract --merge              # Gettext's own command
mix gettext.extract --check-up-to-date   # in CI: fails when a template is stale
```

AshGettext makes your enum labels, attribute labels and messages visible to
it, so they land in `ash.pot`. The sentences Ash and AshGettext ship go to
their own `ash_builtin.pot`. Translators fill in `ash.po` and
`ash_builtin.po` per language. Upgrading from a version without
`ash_builtin`? Before the first extract, copy each language's `ash.po` to
`ash_builtin.po` in the same folder, or `--merge` deletes the built-in
translations (see [Extracting messages](documentation/topics/extracting-messages.md)).

### Catch missing translations

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

## Learn more

- [Translating text](documentation/topics/translating-text.md): enums,
  strings, plurals and attribute names.
- [Locales](documentation/topics/locales.md): where the user's language comes
  from, and how it is matched to your catalogs.
- [Translating errors](documentation/topics/translating-errors.md): writing
  messages, coded errors, and what is not translated.
- [Extracting messages](documentation/topics/extracting-messages.md): what
  `mix gettext.extract` finds, and checking it in CI.
- [How to test with AshGettext](documentation/topics/testing.md): check that
  an action returns the translated text.
- [DSL reference](documentation/dsls/DSL-AshGettext.Domain.md): every option
  in the `gettext` block.

## Limits

- **Read errors are not translated in a direct call.** Over JSON:API and
  GraphQL they are. See [Translating errors](documentation/topics/translating-errors.md).
- **Text passed to `AshGettext.translate/5` is not extracted.** `mix gettext.extract`
  does not see it. Add it to the
  template by hand, or write it with a Gettext macro. Enum labels, attribute
  labels and `message:` strings are extracted.
- **A message built with `#{...}` cannot be translated.** Write `%{name}` in
  the text and pass the value instead.
- **An action with its own `error_handler` is not translated.**

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
