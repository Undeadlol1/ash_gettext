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
domain. No action changes the process language. So tests that use it can all
be `async: true`. To choose a language in a test, use `Gettext.with_locale/3`.

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

When you only need to know that the translation did the work, use
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

## Check enum labels and attribute labels

An enum returns its translation in Gettext's current locale. Use
`Gettext.with_locale/3` so the test stays `async: true`. The attribute label is
looked up in the `"ash"` catalog under the text you wrote in `label`:

```elixir
test "the status and the attribute name are translated" do
  assert Gettext.with_locale(MyApp.Gettext, "ru", fn ->
           MyApp.Status.label(:awaiting_pickup)
         end) == "Ожидает выдачи"

  assert_covered(MyApp.Gettext, "ash", "Date of birth", "ru")
end
```

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

## Fail a test on a missing translation

Every plain lookup that misses sends `[:ash_gettext, :translation, :missing]`.
Attach a handler in a test that sends the event to the test process, then
assert you received nothing:

```elixir
test "the order page has no gaps in Russian" do
  :telemetry.attach(
    "gaps-#{inspect(self())}",
    [:ash_gettext, :translation, :missing],
    &__MODULE__.forward/4,
    self()
  )

  AshGettext.translate(MyApp.Gettext, "default", "Order shipped", [], "ru")

  refute_received {:missing, _meta}
end

def forward(_event, _measurements, meta, test_pid), do: send(test_pid, {:missing, meta})
```

## Check that the template is current

Run the check in CI, next to `mix test`:

```
mix gettext.extract --check-up-to-date
```

It fails when a text was added without regenerating the `.pot`.

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
