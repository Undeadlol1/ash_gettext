# How to test with AshGettext

This page shows how to check that your translations exist and that an Ash
action returns them. The examples below use this Russian catalog. Swap in
your own.

```po
# priv/gettext/ru/LC_MESSAGES/default.po
msgid "Hello, %{name}"
msgstr "Привет, %{name}"
```

## Keep tests parallel

Nothing here needs setup. AshGettext keeps no global state: the locale is an
argument or part of the action context, and any settings are read from the
domain. So tests that use it can all be `async: true`. Never call
`Gettext.put_locale/2` in a test to choose a language.

## Check that a message is translated

Use `AshGettext.Testing.assert_translates/6`. Its arguments are the backend,
the text domain, the msgid, the locale and the text you expect. A map or
keyword list of values goes last.

```elixir
defmodule MyApp.TranslationsTest do
  use ExUnit.Case, async: true

  import AshGettext.Testing

  test "the greeting is translated to Russian" do
    assert_translates(MyApp.Gettext, "default", "Hello, %{name}", "ru", "Привет, Ann", name: "Ann")
  end
end
```

The test fails with the text the catalog produced, so a typo in the `.po` file
is easy to find. It also returns the translated string.

## Check that a message is covered

When you only need to know that a translator did the work, use
`AshGettext.Testing.assert_covered/5`. It does not pin the wording:

```elixir
test "the greeting has a Russian translation" do
  assert_covered(MyApp.Gettext, "default", "Hello, %{name}", "ru", name: "Ann")
end
```

It fails if the lookup falls through to the msgid. In the source locale it
always passes, because the msgid is the text.

## Check every locale

Loop over the locales the backend ships:

```elixir
for locale <- AshGettext.known_locales(MyApp.Gettext), locale != "en" do
  test "the greeting is covered in #{locale}" do
    assert_covered(MyApp.Gettext, "default", "Hello, %{name}", unquote(locale), name: "Ann")
  end
end
```

Add a new language directory and the loop checks it with no change to the
test.

## Check that an action returns the translated error

For a domain with a `gettext do backend(MyApp.Gettext) text_domain("shipping")
end` block and this catalog entry:

```po
# priv/gettext/ru/LC_MESSAGES/shipping.po
msgid "must weigh at least %{min} kg"
msgstr "должен весить не меньше %{min} кг"
```

run the action with a locale on the context and read the message:

```elixir
test "creating a light parcel fails in Russian" do
  assert {:error, error} =
           MyApp.Shipping.Parcel
           |> Ash.Changeset.for_create(:create, %{weight: 5}, context: %{locale: "ru"})
           |> Ash.create()

  assert Enum.map(error.errors, & &1.message) == ["должен весить не меньше 30 кг"]
end
```

This goes through the real action, so it also proves the resource has the
`AshGettext.Resource` extension. The same test works for a create, update or
destroy action. Read actions are not translated, so do not test them this way.

## Check that the template is current

Run the check in CI, next to `mix test`:

```
mix ash_gettext.extract --check
```

It fails when a `message:` was added without regenerating the `.pot`. To run
it inside a test, call `Mix.Tasks.AshGettext.Extract.run(["--check"])`; it
raises when the file is stale.

## Check that every resource is wired

Set `require_resource_extension?` in the domain:

```elixir
gettext do
  backend(MyApp.Gettext)
  require_resource_extension?(true)
end
```

A resource that forgets the extension now produces a compiler warning. Compile
with `--warnings-as-errors` in CI, and the build fails.
