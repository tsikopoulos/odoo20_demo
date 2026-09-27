# Home Menu (`web_home_menu`)

Enterprise-style home menu for the Odoo 20 Community web client.

After login, and whenever there is no action to display (the `/odoo` url), the
web client shows a full-screen grid of application tiles instead of the first
app. The top-left navbar button brings the home menu back on top of the
current action, and back again.

* Arrow keys move between the apps, Enter opens the focused one, Escape
  returns to the action behind the home menu.
* Typing any character opens the command palette in the "menus" namespace,
  with the typed character as first search term.
* On small screens, the app sidebar is kept but its "All Apps" button opens
  the home menu.
* The module is excluded when `web_enterprise` is installed.

## How it works

* `home_menu/home_menu_service.js` registers the `menu` client action (the tag
  the router maps to `/odoo` and that breadcrumbs already ignore) and the
  `home_menu` service (`hasHomeMenu()`, `hasBackgroundAction()`, `toggle()`).
* `webclient/webclient.js` subclasses the web client to display the home menu
  as default app; `static/src/main.js` replaces `web/static/src/main.js` in
  the `web.assets_web` bundle so that this web client is the one started.
* `navbar/navbar.js` subclasses the navbar: the apps dropdown is replaced by
  the home menu toggle.

## Tests

The hoot tests live in `static/tests/`. Run them with:

    odoo-bin -d <db> -u web,web_home_menu --test-enable --stop-after-init \
        --test-tags "/web:WebSuite.test_unit_desktop[@web_home_menu],/web:MobileWebSuite.test_unit_mobile[@web_home_menu]"

(`web` must be part of the updated modules: the hoot suites are defined in
that module's Python tests.)
