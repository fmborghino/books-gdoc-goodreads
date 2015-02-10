# Collection of tools to move book lists from GDoc to Goodreads

## What we have here
- Ad-Hoc data cleanup and import/export from source GDoc spreadsheet to Goodreads
- google_drive to access the GDoc
- openlibrary to lookup missing ISBNs
- GLI for the command line

## Setup
- optionally bake your favorite ruby gem environment
- gem install bundler; bundle install
- cp example_config.yml config.yml
- [create oauth client at google](https://developers.google.com/drive/web/auth/web-server)
- add the secrets to the config
  - don't commit those secrets! (the .gitignore will help you there)

## Watch out
This is all highly specific to my own GDoc, so YMMV a whole lot. You should probably work on a copy of your sheet.
If you mess up completely, remember that GDoc lets you view and restore history with File -> See Revision History

Goodreads [import](https://www.goodreads.com/review/import/) has idiosyncrasies which will probably vary over time.

They have an [API](https://www.goodreads.com/api) too but at the time of writing this, I couldn't do what I wanted
with it.

