# Translating text

This page covers translating your own text: strings, placeholders, plurals
and enum values. Each function takes the Gettext backend, the text domain,
the text and the language, so it works the same in any process.

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

The second argument is the Gettext text domain: the name of the `.po` file.
`"default"` reads `default.po`. Use another name to keep a part of the app
in its own file:

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
AshGettext.translate_plural(
  MyApp.Gettext,
  "default",
  "%{count} parcel",
  "%{count} parcels",
  3,
  [],
  "ru"
)
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

## Show an enum value

An Ash enum value like `:awaiting_pickup` is not text a user should see.
`enum_label/5` looks it up under `"<attribute>.<value>"`:

```elixir
AshGettext.enum_label(MyApp.Gettext, "default", :status, :awaiting_pickup, "ru")
#=> "Ожидает выдачи"
```

```po
msgid "status.awaiting_pickup"
msgstr "Ожидает выдачи"
```

With no translation, the label is the value in words: `"Awaiting pickup"`.
A screen never shows `status.awaiting_pickup`. `AshGettext.enum_msgid/2`
gives the key, if you write the `.po` entries yourself.

## Know when a translation is missing

`translate/5` falls back to the text, so a missing translation looks like a
working one. Each function has an `_or_missing` twin that tells you:

```elixir
AshGettext.translate_or_missing(MyApp.Gettext, "default", "Order shipped", [], "ru")
#=> {:ok, "Заказ отправлен"}

AshGettext.translate_or_missing(MyApp.Gettext, "default", "Order lost", [], "ru")
#=> {:missing, "Order lost"}
```

The twins are `translate_or_missing/5`, `translate_plural_or_missing/7` and
`enum_label_or_missing/5`. In your own language they always return `:ok`.
In tests, use `AshGettext.Testing` instead. See
[How to test with AshGettext](testing.md).

## Get the language from the user

Every function takes the language as its last argument. To turn what a
browser sends, such as `ru_RU`, into a language your catalogs have, see
[Locales](locales.md).

## Add the text to the template

`mix gettext.extract` finds only Gettext macro calls, and
`mix ash_gettext.extract` finds only Ash `message:` strings. Neither sees the
text you pass to these functions. Add it to your `.pot` file by hand, or
keep the text in a Gettext macro such as `dgettext_noop/2`.
