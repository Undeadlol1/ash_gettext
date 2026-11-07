# Locales

This page explains how AshGettext picks the language for an error, and how to
make it follow the signed-in user.

## Stop setting the locale in every process

Gettext keeps its locale in the current process. So every controller, channel
and background job has to set it before it runs an action:

```elixir
def perform(%{args: %{"user_id" => id}}) do
  user = Accounts.get_user!(id)
  Gettext.put_locale(MyApp.Gettext, user.locale)
  Orders.cancel_stale(actor: user)
end
```

With AshGettext, delete that line. The locale is worked out from the action
itself, so it is the same in any process.

## Pass a locale on the context

The default resolver is `AshGettext.Locale.FromContext`. It reads
`context[:locale]`:

```elixir
Ash.create(changeset, context: %{locale: "ru"})
```

A string key works too, `%{"locale" => "ru"}`, for a locale that came through
JSON. Use this when the locale is known at the call site, and in tests.

## Take the locale from the actor

A resolver is a module with one function. It gets a map and returns a locale
string, or `nil` if it has no answer:

```elixir
defmodule MyApp.UserLocale do
  @behaviour AshGettext.Locale.Resolver

  @impl true
  def resolve(%{actor: %{locale: locale}}), do: locale
  def resolve(_context), do: nil
end
```

The map holds `:locale` (from the action context), `:actor` and `:changeset`.
List the resolver in the domain:

```elixir
gettext do
  backend(MyApp.Gettext)
  locale_resolvers([MyApp.UserLocale, AshGettext.Locale.FromContext])
end
```

Now every error, from any process, comes out in the actor's language.

## Know the order resolvers run in

Resolvers run in the order you list them. The first one that returns a
locale wins, and a `nil` passes the question to the next:

```elixir
locale_resolvers([MyApp.UserLocale, AshGettext.Locale.FromContext])
```

Here the actor's language wins over `context[:locale]`. Swap the two to let an
explicit locale win. Setting `locale_resolvers` replaces the default list, so
add `AshGettext.Locale.FromContext` yourself if you still want it.

## Set the fallback locale

When no resolver answers, `default_locale` applies. It is `"en"` unless you
change it:

```elixir
gettext do
  backend(MyApp.Gettext)
  default_locale("ru")
end
```

## How a locale is matched to your catalogs

Clients send `ru_RU`, `en-US`, `ru` or nothing. AshGettext cuts the region off
and keeps the language, then checks it against the locales the backend has
catalogs for:

```elixir
AshGettext.Locale.Normalizer.normalize("ru_RU", ["en", "ru"], "en")
#=> "ru"

AshGettext.Locale.Normalizer.normalize("de", ["en", "ru"], "en")
#=> "en"
```

A language with no catalog falls back to `default_locale`. The list of known
locales comes from the backend's `priv` directory, so adding a language
directory is all it takes to support one. See `AshGettext.known_locales/1`.

## Call the resolver chain yourself

`AshGettext.Locale.resolve/2` runs the same steps outside an action:

```elixir
AshGettext.Locale.resolve(%{locale: "ru_RU"},
  resolvers: [AshGettext.Locale.FromContext],
  supported: AshGettext.known_locales(MyApp.Gettext),
  default: "en"
)
#=> "ru"
```

Use it to pick a locale for a page you render yourself, with the same rules
errors use.
