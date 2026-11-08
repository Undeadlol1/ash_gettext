# Locales

This page explains how AshGettext picks a language: from the actor, or from
Gettext's current process language.

## Take the language from the actor

Name one resolver in the domain's `gettext` block:

```elixir
gettext do
  backend(MyApp.Gettext)
  default_locale("en")
  locale_resolver(MyApp.LocaleResolver)
end
```

A resolver is a module with one function. It gets the actor and returns a
language, or `nil`. It is your code. Here the user has a `:language` field:

```elixir
defmodule MyApp.LocaleResolver do
  @behaviour AshGettext.Locale.Resolver

  @impl true
  def resolve(%{language: language}), do: language
  def resolve(_actor), do: nil
end
```

It is called only when the action has an actor. When it answers, loaded
`_label` fields and [errors](translating-errors.md) come out in that
language.

A resolver must be a pure function of the actor. Read the language off the
loaded actor and do not query the database. It runs for each label and
error, and a query there is slow and hides work from the action.

## What the answer turns into

The answer is cut to a language your catalogs have. `ru_RU` and `en-US`
become `ru` and `en`. A language with no catalog becomes `default_locale`.
`AshGettext.known_locales/1` reads the languages from the backend's `priv`
directory, so adding a language directory is all it takes to support one.

`default_locale` is `"en"` unless you change it. Keep it equal to the
language your text is written in.

## No actor, or no answer

With no actor or a `nil` answer, Gettext's current process
language is used. For a visitor who is not signed in, wrap the call:

```elixir
Gettext.with_locale(MyApp.Gettext, "ru", fn ->
  Ash.create(MyApp.Order, %{weight: 5})
end)
```

No action changes the process language, so a long-lived process, such as a
job worker, never runs the next job in the last user's language.

Code outside an action picks the language the same way:

```elixir
Gettext.with_locale(MyApp.Gettext, user.language, fn ->
  AshGettext.attribute_label(MyApp.Order, :date_of_birth)
end)
```

A direct call to an [enum's](translating-text.md) `label/1` also uses
Gettext's current language. To fit a raw value to your catalogs yourself,
use `AshGettext.Locale.Normalizer.normalize/3`.
