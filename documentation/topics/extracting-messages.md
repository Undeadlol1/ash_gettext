# Extracting messages

This page shows how to put every text AshGettext translates into your `.pot`
templates, and how to keep them current. You use Gettext's own command.

## Run Gettext's command

```
mix gettext.extract --merge
```

AshGettext makes your enum labels, attribute labels, `message:` strings and
Ash's error sentences visible to it, so they land in your templates with
everything else. There is no list to keep by hand and no second command.

`--merge` also updates each language's `.po` file. Translators fill in the
`msgstr` lines, for example in `priv/gettext/ru/LC_MESSAGES/ash.po`:

```po
msgid "This email is already registered"
msgstr "Этот email уже зарегистрирован"
```

Each text goes to the backend and `text_domain` of its domain's `gettext`
block (an enum uses its own `backend:` and `text_domain:`). With the default
text domain that is `priv/gettext/ash.pot`.

## What it finds

- Every `label` and `description` you wrote on an `AshGettext.Enum` value.
- Every `label` in a resource's `gettext` block.
- Every `message` in a resource's DSL: validations, identities and the rest.
- Every literal `message:` in the validation, change and preparation modules
  a resource uses. Their source files are read.
- The sentences for Ash's own errors (`AshGettext.AshMessages`), such as
  "is required".

Resources count when they use `AshGettext.Resource` and their domain has a
`gettext` block. A domain without one adds nothing. With
`translate_errors? false`, only the labels are added.

## Fail CI when a template is stale

```
mix gettext.extract --check-up-to-date
```

It writes nothing and fails when a template is out of date, so a new message
cannot be merged without its entry.

## Mark a message no resource uses

A message in a module no resource references, such as a helper that builds
errors, is not found. Mark it with Gettext's macro:

```elixir
use Gettext, backend: MyApp.Gettext

message = dgettext_noop("ash", "This email is already registered")
```

The same goes for a `message:` in a module that is not a plain string, such as
a module attribute, and for text you pass to `AshGettext.translate/5`. See
[Translating text](translating-text.md#add-the-text-to-the-template).

## Fix a message with a variable in it

A message written with `#{...}` is not a constant, so it cannot be a msgid.
`mix gettext.extract` prints a warning with its file and line. Rewrite it with
a placeholder and pass the value in `vars`:

```elixir
# before
message: "must be at most #{max}"

# after
message: "must be at most %{max}", vars: [max: max]
```
