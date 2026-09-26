# Odoo 20 στο DigitalOcean App Platform

Οδηγός για να τρέξει αυτό το repository (Odoo 20, branch `20.0`) στο
DigitalOcean App Platform, με Managed PostgreSQL, με τα αρχεία (attachments,
assets, εικόνες) αποθηκευμένα **μέσα στη βάση** και με το domain
`odoo20-demo.stgroup.gr`.

> **Σημείωση για το domain:** ζητήθηκε `odoo20_demo.stgroup.gr`. Η κάτω παύλα
> (`_`) δεν επιτρέπεται σε hostnames (RFC 1123), το App Platform δεν τη δέχεται
> και το Let's Encrypt δεν εκδίδει πιστοποιητικό. Χρησιμοποιείται
> `odoo20-demo.stgroup.gr` (παύλα). Αν θέλεις άλλο όνομα, άλλαξέ το στο
> `.do/app.yaml` → `domains[].domain`.

## Τι υπάρχει στο repository

| Αρχείο | Ρόλος |
|---|---|
| `Dockerfile` | Image του Odoo (Python 3.12, fonts, wkhtmltopdf για PDF). Multi-stage build. |
| `.dockerignore` | Κρατά το build context μικρό (χωρίς `.git`, docs, κ.λπ.). |
| `deploy/entrypoint.sh` | Φτιάχνει το `odoo.conf` από environment variables, περιμένει τη βάση, την αρχικοποιεί την πρώτη φορά (`-i base`), τρέχει το bootstrap και ξεκινά το Odoo. |
| `deploy/init_db_storage.py` | Τρέχει μέσα από `odoo-bin shell` σε κάθε εκκίνηση: θέτει `ir_attachment.location = db`, μεταφέρει στη βάση ό,τι attachment βρίσκεται στο δίσκο, και στην πρώτη δημιουργία βάζει τον κωδικό του `admin`. |
| `.do/app.yaml` | Το App Spec: service (Dockerfile), Managed PostgreSQL, domain, env vars, health check. |
| `.do/deploy.template.yaml` | Το ίδιο spec σε μορφή για το κουμπί «Deploy to DigitalOcean» (μόνο για public repo). |

## Πώς είναι στημένο (και γιατί)

- **Ένα container, threaded mode (`workers = 0`).** Το App Platform εκθέτει ένα
  μόνο port ανά service. Σε prefork mode (`workers > 0`) το Odoo θέλει και
  δεύτερο port (8072) για websocket/live chat. Σε threaded mode όλα περνούν από
  το 8069, οπότε websocket, bus και chat δουλεύουν κανονικά.
- **Αρχεία στη PostgreSQL.** Ο δίσκος του container είναι εφήμερος (χάνεται σε
  κάθε deploy). Με `ir_attachment.location = db` όλα τα attachments και τα
  assets (JS/CSS bundles) αποθηκεύονται στον πίνακα `ir_attachment`. Έτσι το
  backup της managed βάσης περιέχει **τα πάντα**.
- **Sessions στο δίσκο.** Τα HTTP sessions μένουν στο container, άρα μετά από
  redeploy οι χρήστες ξανακάνουν login. Γι' αυτό `instance_count: 1`.
- **`db_system` = η ίδια βάση.** Το Odoo 20 χρησιμοποιεί μια «system database»
  (default `postgres`) για bus/cron notifications. Στο Managed PostgreSQL
  έχουμε μόνο την `defaultdb`, οπότε το entrypoint δηλώνει την ίδια βάση και
  για τα δύο (υποστηρίζεται επίσημα).
- **`proxy_mode = True`, `list_db = False`, `dbfilter`.** Το Odoo βλέπει τα
  `X-Forwarded-*` headers του load balancer της DO και ο database manager
  είναι απενεργοποιημένος.
- **SSL προς τη βάση.** `DB_SSLMODE=require` (το Managed PostgreSQL το
  απαιτεί). Αν θέλεις πλήρη επαλήθευση, βάλε `verify-full`: το CA cert
  περνάει αυτόματα από το `${odoo-db.CA_CERT}`.

## Βήμα 1 – Managed PostgreSQL

Το App Platform **δεν δημιουργεί** production clusters μέσα από το spec, μόνο
τα συνδέει (`cluster_name`). Φτιάξε πρώτα το cluster στην ίδια region με το app
(`fra` = Frankfurt, η κοντινότερη στην Ελλάδα):

```bash
doctl databases create odoo20-demo-db \
  --engine pg --version 17 --region fra \
  --size db-s-1vcpu-1gb --num-nodes 1
```

ή από το UI: **Databases → Create Database Cluster → PostgreSQL 17 →
Frankfurt → Basic 1 vCPU / 1 GB → name `odoo20-demo-db`**.

Το cluster έρχεται με βάση `defaultdb` και χρήστη `doadmin`. Αυτά χρησιμοποιεί
το spec. Όταν το app γίνει attach μέσω spec, η DO προσθέτει μόνη της το app στα
Trusted Sources της βάσης.

> Για δοκιμή μπορείς αντί για managed cluster να βάλεις «dev database» ($7):
> δες το σχόλιο στο `.do/app.yaml` → `databases`.

## Βήμα 2 – GitHub

1. Στο DigitalOcean: **Settings → Integrations → GitHub → Install & Authorize**
   και δώσε πρόσβαση στο repo `tsikopoulos/odoo20_demo`.
2. Το spec δείχνει στο branch `20.0` (`services[].github.branch`). Τα αρχεία
   deploy πρέπει να υπάρχουν σε αυτό το branch, άρα κάνε merge το branch
   `claude/hopeful-volta-j0vimd` στο `20.0`. Εναλλακτικά άλλαξε προσωρινά το
   `branch:` στο spec ώστε να δείχνει στο branch που θέλεις να δοκιμάσεις.
3. `deploy_on_push: true`: κάθε push στο branch κάνει αυτόματα νέο deploy.

## Βήμα 3 – Δημιουργία του App

**Με doctl** (προτείνεται, το spec μπαίνει αυτούσιο):

```bash
doctl auth init                      # μία φορά
doctl apps create --spec .do/app.yaml
doctl apps list                      # πάρε το APP_ID
doctl apps logs <APP_ID> --type build --follow
doctl apps logs <APP_ID> --type run --follow
```

**Από το UI:** Create App → GitHub → repo `tsikopoulos/odoo20_demo`, branch
`20.0` → Next μέχρι το Review → **Edit App Spec** → επικόλλησε το
`.do/app.yaml` → Save → Create Resources. (Μπορείς και μετά: **Settings → App
Spec → Edit**.)

Πριν το πρώτο deploy άλλαξε τα δύο SECRET στο spec (ή στο UI, Settings →
odoo → Environment Variables):

| Μεταβλητή | Τι είναι |
|---|---|
| `ODOO_ADMIN_PASSWD` | Master password του Odoo (database manager). Ο manager είναι κλειστός, αλλά μην το αφήσεις default. |
| `ODOO_ADMIN_USER_PASSWORD` | Ο κωδικός του χρήστη `admin`. Εφαρμόζεται **μόνο** όταν δημιουργείται η βάση. |

Χρόνοι: το build του image παίρνει περίπου 10–15 λεπτά (πρώτη φορά). Η πρώτη
εκκίνηση κάνει `-i base` με ελληνικά (`el_GR`) και demo data: 3–8 λεπτά σε
1 vCPU. Το health check έχει περιθώριο ~18 λεπτά (`initial_delay_seconds` +
`failure_threshold × period_seconds`), οπότε μην ανησυχείς αν το app δείχνει
«Deploying» για λίγο. Αν το init διακοπεί στη μέση, το entrypoint το
ξανατρέχει στην επόμενη εκκίνηση (κατάσταση `partial`).

## Βήμα 4 – DNS και HTTPS

- **DNS εκτός DigitalOcean (π.χ. στον registrar του stgroup.gr):** πρόσθεσε
  εγγραφή `CNAME odoo20-demo → <app>.ondigitalocean.app` (το default hostname
  φαίνεται στο Overview του app). Μόλις η DO δει το CNAME, εκδίδει
  πιστοποιητικό Let's Encrypt και το ανανεώνει μόνη της. HTTP → HTTPS
  redirect γίνεται αυτόματα.
- **DNS στο DigitalOcean:** ξεσχολίασε το `zone: stgroup.gr` στο spec και η
  DO φτιάχνει την εγγραφή μόνη της.
- Μετά το πρώτο login ως `admin` από το `https://odoo20-demo.stgroup.gr` το
  Odoo ενημερώνει μόνο του το `web.base.url`. Έλεγξέ το στο **Settings →
  Technical → System Parameters**.

## Βήμα 5 – Πρώτη σύνδεση και έλεγχος

1. `https://odoo20-demo.stgroup.gr/odoo` → login `admin` με τον κωδικό
   `ODOO_ADMIN_USER_PASSWORD` (αν δεν ορίστηκε, είναι `admin`: άλλαξέ τον).
2. Εγκατέστησε apps από το μενού **Apps**. Τα demo data μπαίνουν και στα νέα
   apps, γιατί η βάση δημιουργήθηκε με `ODOO_WITH_DEMO=true`.
3. Επιβεβαίωσε ότι τα αρχεία είναι στη βάση. Από το **Console** του app
   (Runtime Logs → Console) το `psql` συνδέεται απευθείας στη βάση του Odoo:

   ```bash
   psql -c "SELECT value FROM ir_config_parameter WHERE key = 'ir_attachment.location'"
   psql -c "SELECT count(*) FILTER (WHERE store_fname IS NOT NULL) AS on_disk,
                   count(*) FILTER (WHERE db_datas   IS NOT NULL) AS in_db
              FROM ir_attachment"
   ```

   Περιμένεις `db` και `on_disk = 0`.

## Environment variables

Όλες ορίζονται στο `.do/app.yaml` (`services[].envs`) και διαβάζονται από το
`deploy/entrypoint.sh`.

| Μεταβλητή | Default | Περιγραφή |
|---|---|---|
| `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` | από `${odoo-db.*}` | Σύνδεση με τη βάση. Εναλλακτικά ένα `DATABASE_URL`. |
| `DB_SSLMODE` | `require` | `disable`/`prefer`/`require`/`verify-ca`/`verify-full`. |
| `DB_CA_CERT` | `${odoo-db.CA_CERT}` | CA της βάσης, χρειάζεται μόνο για `verify-*`. |
| `ODOO_ADMIN_PASSWD` | τυχαίο | Master password. |
| `ODOO_ADMIN_USER_PASSWORD` | – | Κωδικός του `admin`, μόνο κατά τη δημιουργία της βάσης. |
| `ODOO_INIT_MODULES` | `base` | Modules που εγκαθίστανται στη δημιουργία (π.χ. `base,crm,sale_management`). |
| `ODOO_WITH_DEMO` | `false` (spec: `true`) | Demo data στη δημιουργία. |
| `ODOO_INIT_LANGUAGE` | – (spec: `el_GR`) | Γλώσσες που φορτώνονται στη δημιουργία. |
| `ODOO_WORKERS` | `0` | Άφησέ το `0` (threaded, ένα port). |
| `ODOO_MAX_CRON_THREADS` | `1` | Cron threads. |
| `ODOO_DB_MAXCONN` | `16` | Max συνδέσεις στη βάση. Το `db-s-1vcpu-1gb` επιτρέπει ~22. |
| `ODOO_LOG_LEVEL` | `info` | `debug`, `info`, `warn`, `error`. |
| `ODOO_EXTRA_ADDONS_PATH` | – | Επιπλέον φάκελοι addons (comma separated) μέσα στο image. |
| `ODOO_EXTRA_CONF` | – | Επιπλέον γραμμές για το `[options]`, π.χ. SMTP: `smtp_server = smtp.example.com`. |
| `ODOO_SKIP_DB_INIT` / `ODOO_SKIP_BOOTSTRAP` | `0` | Απενεργοποίηση του init / bootstrap (για debugging). |

## Λειτουργία

- **Logs:** `doctl apps logs <APP_ID> --type run --follow` ή Runtime Logs στο UI.
- **Νέα έκδοση:** push στο `20.0` → αυτόματο build και deploy. Το Odoo
  ξεκινά με την ίδια βάση, το bootstrap είναι idempotent.
- **Upgrade modules μετά από αλλαγές κώδικα:** από το Console του app
  `odoo-bin -u <module> --stop-after-init` (το `ODOO_RC` είναι ήδη ρυθμισμένο).
- **Backups:** το Managed PostgreSQL κρατά καθημερινά backups (7 ημέρες) και
  point-in-time recovery. Επειδή τα αρχεία είναι στη βάση, το backup είναι
  πλήρες. Restore = νέο cluster από backup και αλλαγή του `cluster_name`.
- **Μέγεθος:** `apps-s-1vcpu-2gb` (2 GB RAM) είναι το ελάχιστο λογικό για
  Odoo. Για περισσότερους χρήστες ή πολλά apps πήγαινε σε `apps-s-2vcpu-4gb`
  ή dedicated (`apps-d-…`) και μεγάλωσε τη βάση.
- **Ενδεικτικό κόστος:** app ~25 $/μήνα (`apps-s-1vcpu-2gb`) + βάση ~15 $/μήνα
  (`db-s-1vcpu-1gb`). Επιβεβαίωσε στη σελίδα τιμών της DO.

## Τοπική δοκιμή με Docker

```bash
docker build -t odoo20-demo .
docker run --rm -p 8069:8069 \
  -e DB_HOST=host.docker.internal -e DB_PORT=5432 \
  -e DB_USER=odoo -e DB_PASSWORD=odoo -e DB_NAME=odoo20 -e DB_SSLMODE=disable \
  -e ODOO_ADMIN_USER_PASSWORD=admin123 \
  odoo20-demo
```

Χρειάζεται μια PostgreSQL 16+ με χρήστη `odoo` και άδεια βάση `odoo20`.

## Troubleshooting

| Σύμπτωμα | Τι να δεις |
|---|---|
| Build αποτυγχάνει στο `pip install` | Build logs. Τα requirements είναι pinned για Python 3.12 (Dockerfile `PYTHON_VERSION`). |
| «waiting for PostgreSQL» για πολύ | Το cluster είναι σε άλλη region, ή δεν έγινε attach μέσω spec (Trusted Sources). |
| Health check αποτυγχάνει στο πρώτο deploy | Το init δεν πρόλαβε: δες τα run logs, αύξησε `initial_delay_seconds`/`failure_threshold`. |
| `FATAL: too many connections` | Μείωσε `ODOO_DB_MAXCONN` ή μεγάλωσε τον κόμβο της βάσης. |
| Ξανά login μετά από deploy | Αναμενόμενο (sessions στο container). |
| PDF reports κενά/σφάλμα | Το wkhtmltopdf είναι στο image. Έλεγξε `web.base.url` και ότι το domain απαντά σε HTTPS. |
