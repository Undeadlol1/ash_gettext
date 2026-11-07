# What AshGettext is

**AshGettext is a translation library for Ash.** Read this before you
describe, review, redesign or document it.

## The goal

Translate the things an Ash app shows, so nobody translates them by hand
over and over:

- enum labels
- error messages
- attribute (property) names
- any other Ash integration that needs translating, as it comes up

## Why Gettext

Gettext is the standard for translation in Elixir. AshGettext uses its API
instead of reinventing one. That is the only reason "Gettext" is in the
name. The library is not "a Gettext wrapper" and not an i18n framework of
its own.

## Do not

- Describe it as an error translator. Errors are one feature of several.
- Lead with errors, Gettext or "languages" when you explain it. Lead with
  "a translation library for Ash".
- Suggest Phoenix, LiveView or any web layer as the answer. The author does
  not use Phoenix. AshGettext works on Ash alone.
- Judge the code against a different goal. When asking "is this right?",
  ask "does this help translate an Ash app's enums, errors, attributes and
  other things, without hand-written glue?"
