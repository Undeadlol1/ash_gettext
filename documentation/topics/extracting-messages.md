# Extracting messages

This page shows how to turn the `message:` strings in your resources into a
`.pot` template, and how to keep that template current.

## Stop keeping a list of messages by hand

`mix gettext.extract` only finds calls to Gettext macros. Ash messages are
`message:` options, so it cannot see them. Without help, you keep a file like
this in step by hand:

```elixir
defmodule MyApp.AshMessages do
  use Gettext, backend: MyApp.Gettext

  def noop do
    dgettext_noop("errors", "This email is already registered")
    dgettext_noop("errors", "must be greater than or equal to %{min}")
  end
end
```

Delete it. `mix ash_gettext.extract` reads your source files and finds the
messages itself.

## Write the template

```
mix ash_gettext.extract
```

The task reads `lib` and writes `priv/gettext/ash_errors.pot`:

```
Scanned lib: 12 translatable messages.
Wrote 12 messages to priv/gettext/ash_errors.pot.
```

It finds `message: "..."` in keyword options and `message "..."` in DSL
blocks, such as an `identity`. Each entry lists the files it came from.

## Fail CI when the template is stale

```
mix ash_gettext.extract --check
```

`--check` writes nothing. It exits with an error if the file on disk is not
what a fresh run would write, so a new `message:` cannot be merged without its
template entry. Run it in CI next to your tests.

## Name the file

Gettext reads the catalog named by `text_domain`, so the template must have
the same name. The default text domain is `ash_errors`, and the task writes
`priv/gettext/ash_errors.pot` unless told otherwise. If you set another text
domain, pass `--output` to match:

```elixir
gettext do
  backend(MyApp.Gettext)
  text_domain("shipping")
end
```

```
mix ash_gettext.extract --output priv/gettext/shipping.pot
```

To scan more than `lib`, list the paths: `mix ash_gettext.extract lib apps/other/lib`.

## Add the other languages

Create each language's `.po` file from the template with Gettext's own task:

```
mix gettext.merge priv/gettext --locale ru
```

Then fill in the `msgstr` lines in `priv/gettext/ru/LC_MESSAGES/ash_errors.po`:

```po
msgid "This email is already registered"
msgstr "Этот email уже зарегистрирован"
```

Do not edit the `.pot` file. The next extraction overwrites it. The source
language gets no `.po` file, because its sentence is already the text.

## Fix a message with a variable in it

A message written with `#{...}` is not a constant, so it cannot be a msgid.
The task lists each one:

```
1 interpolated messages cannot be msgids as written:

  lib/my_app/shop/order.ex:31
```

Rewrite it with a placeholder and pass the value in `vars`:

```elixir
# before
message: "must be at most #{max}"

# after
message: "must be at most %{max}", vars: [max: max]
```

## Know what extraction skips

A `message:` that is not a plain string is not found. This includes a module
attribute:

```elixir
@too_light "must weigh at least %{min} kg"

InvalidAttribute.exception(field: :weight, message: @too_light, vars: [min: 30])
```

The task does not report it. Write the string in place, or add its msgid to
the `.pot` and `.po` files by hand.
