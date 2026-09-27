# Part of Odoo. See LICENSE file for full copyright and licensing details.
{
    'name': 'Home Menu',
    'summary': 'Enterprise-style home menu (apps grid) for Odoo Community',
    'description': """
Home Menu
=========

Replaces the apps dropdown of the Community web client with a full-screen
home menu, like the one of Odoo Enterprise:

* a grid of application tiles shown after login and whenever no action is open,
* a top-left toggle that brings the home menu back on top of the current action
  (and back again),
* keyboard navigation with the arrow keys, Escape to return to the current action,
* typing any character opens the command palette in the "menus" namespace.
""",
    'version': '1.0',
    'category': 'Productivity',
    'depends': ['web'],
    'excludes': ['web_enterprise'],
    'application': True,
    'installable': True,
    'auto_install': False,
    'author': 'tsikopoulos',
    'license': 'LGPL-3',
    'assets': {
        'web.assets_backend': [
            'web_home_menu/static/src/**/*',
            ('remove', 'web_home_menu/static/src/main.js'),
            # Don't include dark mode files in light mode
            ('remove', 'web_home_menu/static/src/**/*.dark.scss'),
        ],
        'web.assets_web': [
            ('replace', 'web/static/src/main.js', 'web_home_menu/static/src/main.js'),
        ],
        'web.assets_web_dark': [
            'web_home_menu/static/src/**/*.dark.scss',
        ],
        'web.assets_unit_tests': [
            'web_home_menu/static/tests/**/*.test.js',
        ],
    },
}
