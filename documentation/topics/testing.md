# How to test with AshGettext

Test the real call. Set the language, call the code, assert on the text.

## Set the language

Use `Gettext.put_locale/2` at the top of the test. Each test runs in its own
process, so the language leaks nowhere and tests can stay `async: true`. A
`Task` the test starts does not inherit it.

## Enum labels

```elixir
test "the status label is Russian" do
  Gettext.put_locale(MyApp.Gettext, "ru")

  assert MyApp.Status.label(:awaiting_pickup) == "Ожидает выдачи"
end
```

## Loaded `_label` fields

```elixir
test "the loaded label follows the actor's language" do
  user = %{locale: "ru"}
  order = Ash.load!(order, [:status_label], actor: user)

  assert order.status_label == "Ожидает выдачи"
end
```

## Error messages

```elixir
test "creating a light parcel fails in Russian" do
  Gettext.put_locale(MyApp.Gettext, "ru")

  assert {:error, error} =
           MyApp.Shipping.Parcel
           |> Ash.Changeset.for_create(:create, %{weight: 5})
           |> Ash.create()

  assert Enum.map(error.errors, & &1.message) == ["должен весить не меньше 30 кг"]
end
```

This goes through the real action, so it also proves the resource has the
`AshGettext.Resource` extension. Read actions are not translated.

## Fail a test on a missing translation

Every plain lookup that misses sends `[:ash_gettext, :translation, :missing]`.
Attach a handler in the test that sends the event to the test process:

```elixir
:telemetry.attach(
  "gaps-#{inspect(self())}",
  [:ash_gettext, :translation, :missing],
  fn _event, _measurements, meta, pid -> send(pid, {:missing, meta}) end,
  self()
)

# ... run the code ...

refute_received {:missing, _meta}
```

## In CI

Check the template is current, next to `mix test`:

```
mix gettext.extract --check-up-to-date
```

To catch a resource that forgot the extension, set
`require_resource_extension?(true)` in the domain's `gettext` block and
compile with `--warnings-as-errors`.
