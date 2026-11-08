# Set it up once for the whole app

Every domain needs the `AshGettext.Domain` extension and a `gettext` block.
Every resource needs the `AshGettext.Resource` extension. Instead of writing
that in each one, write a base domain and a base resource once.

## The base domain

```elixir
defmodule MyApp.Domain do
  defmacro __using__(opts) do
    opts = Keyword.update(opts, :extensions, [AshGettext.Domain], &[AshGettext.Domain | &1])

    quote do
      use Ash.Domain, unquote(opts)

      gettext do
        backend(MyApp.Gettext)
        locale_resolver(MyApp.LocaleResolver)
      end
    end
  end
end
```

## The base resource

```elixir
defmodule MyApp.Resource do
  defmacro __using__(opts) do
    opts = Keyword.update(opts, :extensions, [AshGettext.Resource], &[AshGettext.Resource | &1])

    quote do
      use Ash.Resource, unquote(opts)
    end
  end
end
```

## Use them

Write `use MyApp.Domain` where you wrote `use Ash.Domain`, and
`use MyApp.Resource` where you wrote `use Ash.Resource`. Every other option
works as before.

```elixir
defmodule MyApp.Shop do
  use MyApp.Domain

  resources do
    resource(MyApp.Order)
  end
end

defmodule MyApp.Order do
  use MyApp.Resource,
    domain: MyApp.Shop,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource]
end
```

A resource or domain can still list its own `extensions:`. The base module
adds AshGettext's extension to that list.

A domain that needs one setting changed writes its own `gettext` block with
just that setting. The rest still comes from the base domain:

```elixir
defmodule MyApp.Billing do
  use MyApp.Domain

  gettext do
    text_domain("billing")
  end
end
```

## For an existing app

`mix ash_gettext.install` adds the extensions and the `gettext` block to
every domain and resource you already have. Use it when you would rather not
switch them to base modules.
