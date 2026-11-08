# Translating text

This page covers translating your own text: enum values, strings,
placeholders, plurals and attribute names.

## Translate an enum

Put `use AshGettext.Enum` after `use Ash.Type.Enum`:

```elixir
defmodule MyApp.Order.Status do
  use Ash.Type.Enum,
    values: [
      :placed,
      awaiting_pickup: [label: "Awaiting pickup", description: "Ready at the pickup point"]
    ]

  use AshGettext.Enum, backend: MyApp.Gettext
end

MyApp.Order.Status.label(:awaiting_pickup)
#=> "Ожидает выдачи"
```

`label/1` and `description/1` are Ash's own functions. They now return the
translated text. `:backend` is required. `:text_domain` is the catalog file
and defaults to `"ash"`.

The key is the enum's own label for the value. By default that is the value in
words, "Awaiting pickup". A `label:` on the value changes it. The key of a
description is the description:

```po
# priv/gettext/ru/LC_MESSAGES/ash.po
msgid "Awaiting pickup"
msgstr "Ожидает выдачи"

msgid "Ready at the pickup point"
msgstr "Готов к выдаче в пункте"
```

The language is Gettext's current locale for the process. Set it with
`Gettext.put_locale/2`, or for one block with `Gettext.with_locale/3`:

```elixir
Gettext.with_locale(MyApp.Gettext, "ru", fn ->
  MyApp.Order.Status.label(:awaiting_pickup)
end)
```

With no translation, you get the label as written. A value without a
description still returns `nil`. `details/1` is Ash's own and is not
translated.

## The text is the key

Write the text in your app's own language. Gettext looks it up as written:

```elixir
AshGettext.translate(MyApp.Gettext, "default", "Order shipped", [], "ru")
#=> "Заказ отправлен"
```

```po
# priv/gettext/ru/LC_MESSAGES/default.po
msgid "Order shipped"
msgstr "Заказ отправлен"
```

In your own language the text is also the translation, so that language
needs no `.po` file. Your own language is the backend's default locale, `en`
unless you set another.

With no translation, `translate/5` returns the text as you wrote it.

## Choose the catalog file

The text domain, the second argument, is the name of the `.po` file.
`"default"` reads `default.po`. Use another name to keep a part of the app in
its own file:

```elixir
AshGettext.translate(MyApp.Gettext, "shipping", "Order shipped", [], "ru")
# reads priv/gettext/ru/LC_MESSAGES/shipping.po
```

## Put values in the text

Write `%{name}` in the text and pass the values:

```elixir
AshGettext.translate(MyApp.Gettext, "default", "Hello, %{name}", [name: "Ann"], "ru")
#=> "Привет, Ann"
```

```po
msgid "Hello, %{name}"
msgstr "Привет, %{name}"
```

Do not build the text with `#{...}`. The key has to be the same every time.

## Translate a count

`translate_plural/7` takes the singular, the plural and the count. The count
is always available as `%{count}`:

```elixir
AshGettext.translate_plural(MyApp.Gettext, "default", "%{count} parcel", "%{count} parcels", 3, [], "ru")
#=> "3 посылки"
```

```po
msgid "%{count} parcel"
msgid_plural "%{count} parcels"
msgstr[0] "%{count} посылка"
msgstr[1] "%{count} посылки"
msgstr[2] "%{count} посылок"
```

Each language has its own number of plural forms. Gettext picks the right
one.

## Show an attribute name

```elixir
AshGettext.attribute_label(MyApp.Gettext, "ash", MyApp.Order, :date_of_birth, "ru")
#=> "Дата рождения"
```

```po
# priv/gettext/ru/LC_MESSAGES/ash.po
msgid "Date of birth"
msgstr "Дата рождения"
```

The key is the attribute name in words. `AshGettext.attribute_msgid/1` gives
it. An attribute the resource does not have raises `ArgumentError`.

## Know when a translation is missing

`translate/5` falls back to the text, so a missing translation looks like a
working one. Two ways to find out.

Every miss sends a telemetry event, `[:ash_gettext, :translation, :missing]`,
with the `backend`, `text_domain`, `msgid` and `locale` in its metadata. Log
it, or count it:

```elixir
:telemetry.attach(
  "ash-gettext-missing",
  [:ash_gettext, :translation, :missing],
  &MyApp.Telemetry.log_missing/4,
  nil
)
```

Or ask in code. The pure functions have an `_or_missing` twin that tells you:

```elixir
AshGettext.translate_or_missing(MyApp.Gettext, "default", "Order lost", [], "ru")
#=> {:missing, "Order lost"}
```

The twins are `translate_or_missing/5`, `translate_plural_or_missing/7`
and `attribute_label_or_missing/5`. They send no
event. In your own language nothing is missing. In tests, use
`AshGettext.Testing`. See [How to test with AshGettext](testing.md).

## Get the language from the user

To turn what a browser sends, such as `ru_RU`, or the signed-in user into a
language your catalogs have, see [Locales](locales.md).

## Add the text to the template

`mix gettext.extract` finds only Gettext macro calls. Text you pass to
`translate/5` is not one, and `mix ash_gettext.extract` does not see it
either. Add it to your `.pot` file by hand, or keep the text in a Gettext
macro such as `dgettext_noop/2`.

Enum labels, enum descriptions and attribute names are different: `mix ash_gettext.extract`
collects them. See [Extracting messages](extracting-messages.md).
