# Locales

This page explains how AshGettext picks a language: from what a client
sends, from the signed-in user, or from a default.

## Turn what a client sends into a language

Clients send `ru_RU`, `en-US`, `ru` or nothing. `AshGettext.Locale.resolve/2`
turns that into a language your catalogs have:

```elixir
AshGettext.Locale.resolve(%{locale: "ru_RU"},
  supported: AshGettext.known_locales(MyApp.Gettext),
  default: "en"
)
#=> "ru"

AshGettext.Locale.resolve(%{locale: "de"},
  supported: AshGettext.known_locales(MyApp.Gettext),
  default: "en"
)
#=> "en"
```

It cuts the region off and keeps the language. A language with no catalog
becomes the default. `AshGettext.known_locales/1` reads the languages from
the backend's `priv` directory, so adding a language directory is all it
takes to support one.

Pass the result as the last argument of `AshGettext.translate/5` and the
other functions in [Translating text](translating-text.md).

## Take the language from the signed-in user

A resolver is a module with one function. It gets a map and returns a
language, or `nil` if it has no answer:

```elixir
defmodule MyApp.UserLocale do
  @behaviour AshGettext.Locale.Resolver

  @impl true
  def resolve(%{actor: %{locale: locale}}), do: locale
  def resolve(_context), do: nil
end
```

Pass your resolvers to `resolve/2`:

```elixir
AshGettext.Locale.resolve(%{actor: current_user},
  resolvers: [MyApp.UserLocale, AshGettext.Locale.FromContext],
  supported: AshGettext.known_locales(MyApp.Gettext),
  default: "en"
)
```

The default resolver is `AshGettext.Locale.FromContext`. It reads
`:locale` from the map, or `"locale"` for a value that came through JSON.

## Know the order resolvers run in

Resolvers run in the order you list them. The first one that returns a
language wins, and a `nil` passes the question to the next:

```elixir
[MyApp.UserLocale, AshGettext.Locale.FromContext]
```

Here the user's language wins over an explicit `:locale`. Swap the two to let
an explicit `:locale` win. Your list replaces the default one, so add
`AshGettext.Locale.FromContext` yourself if you still want it.

## Choose the language of Ash's errors

[Translated errors](translating-errors.md) run the same steps, with the
settings from the domain's `gettext` block:

```elixir
gettext do
  backend(MyApp.Gettext)
  default_locale("en")
  locale_resolvers([MyApp.UserLocale, AshGettext.Locale.FromContext])
end
```

Each resolver gets a map with `:locale` from the action context, `:actor`
and `:changeset`. So a background job no longer has to call
`Gettext.put_locale/2` before it runs an action: the language comes from the
action itself, in any process.

```elixir
Ash.create(changeset, context: %{locale: "ru"})
```

`default_locale` is `"en"` unless you change it. Keep it equal to the
language your text is written in.
