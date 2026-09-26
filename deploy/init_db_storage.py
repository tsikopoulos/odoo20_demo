"""Post-initialisation bootstrap, executed inside ``odoo-bin shell``.

``env`` (a superuser environment on the configured database) is injected by
the shell command; the script is piped on stdin by deploy/entrypoint.sh at
every container start and must stay idempotent.

1. Store binary attachments in PostgreSQL (``ir_attachment.location = db``)
   instead of the filestore: the container filesystem is ephemeral on
   DigitalOcean App Platform, so anything written there is lost on redeploy.
2. Move any attachment still on disk (e.g. created while installing ``base``)
   into the database.
3. On a freshly initialised database, set the ``admin`` user's password from
   ``ODOO_ADMIN_USER_PASSWORD`` when it is provided.
"""
import logging
import os

_logger = logging.getLogger("odoo.deploy.bootstrap")

env = env  # noqa: F821 -- injected by `odoo-bin shell`  # ty:ignore[unresolved-reference]

ICP = env["ir.config_parameter"].sudo()
if ICP.get_str("ir_attachment.location") != "db":
    ICP.set_str("ir_attachment.location", "db")
    _logger.info("ir_attachment.location set to 'db'")

Attachment = env["ir.attachment"].sudo()
# Mentioning res_field explicitly bypasses the automatic `res_field = False`
# filter of ir.attachment._search, like ir.attachment.force_storage() does.
on_disk = Attachment.search_count([
    ("type", "=", "binary"),
    ("store_fname", "!=", False),
    "|", ("res_field", "=", False), ("res_field", "!=", False),
])
if on_disk:
    _logger.info("moving %d attachment(s) from the filestore into the database", on_disk)
    Attachment.force_storage()

if os.environ.get("ODOO_FRESH_INIT") == "1":
    admin_password = os.environ.get("ODOO_ADMIN_USER_PASSWORD")
    if admin_password:
        env.ref("base.user_admin").sudo().write({"password": admin_password})
        _logger.info("password of the admin user set from ODOO_ADMIN_USER_PASSWORD")

env.cr.commit()
_logger.info("bootstrap done: %d attachment(s) in database storage", Attachment.search_count([
    ("type", "=", "binary"),
    ("db_datas", "!=", False),
    "|", ("res_field", "=", False), ("res_field", "!=", False),
]))
