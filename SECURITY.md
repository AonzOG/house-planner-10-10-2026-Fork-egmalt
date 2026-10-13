# Security Policy

## Supported versions

Security fixes go into the latest release on the `main` branch. Self-hosted installations should update to it; see [updating](docs/guide/en/deploy.md#updating).

| Version | Supported |
|---|---|
| 0.1.x | yes |

## Reporting a vulnerability

**All vulnerability reports, suspected security flaws, and privacy concerns about this AonzOG House Planner repository must be sent directly by email to Astra, AonzOG's designated security contact: [astra.sharma8@gmail.com](mailto:astra.sharma8@gmail.com).** This email address is the sole reporting channel for vulnerabilities concerning this fork.

This includes the original House Planner application code as distributed in this fork, AonzOG-maintained installers, Docker and deployment configuration, and all other files or modifications included in this repository.

Use the email subject **Security report: AonzOG House Planner**. Where possible, include the affected file or endpoint, steps to reproduce, the observed impact, and a suggested fix. Do not include passwords, access tokens, or unrelated personal data in the report. Reports in English or Russian are welcome.

Do not disclose exploitable vulnerabilities through public GitHub issues or pull requests, and do not submit vulnerability reports concerning this fork to any other developer, repository, organisation, or email address.

## Scope

In scope: the PHP API in `public/api/` (authentication, the login cookie, CSRF protection, storage access, the setup wizard, the Petrovich cart proxy), the `.htaccess` rules that close `storage/`, `data/` and `plans/`, the Docker image, the deploy and plan scripts in `scripts/`, the frontend, and the AonzOG-maintained installer files in `Installer/` (Windows BAT/PowerShell, Linux/macOS wrappers, shared Unix core, source downloads, setup-key handling, repair, and uninstall).

Out of scope: misconfiguration of a particular hosting (for example, nginx without the equivalent of the `.htaccess` rules), the PHP built-in server used for local development, attacks that need the planner password, and third-party services (petrovich.ru, imagery tiles).

## Hardening a deployment

- Serve the site over HTTPS only; the login cookie gets the `Secure` flag on HTTPS.
- Keep the storage folder outside the web root (`../storage`) when the hosting allows it.
- Set `HOUSE_SETUP_KEY`, or in Docker `HOUSE_PASSWORD`, so nobody else can run the setup wizard before you.
- Use a long password: there is one password per installation, and the login endpoint only slows down guessing with a 1-second delay.
- On nginx, deny `/storage`, `/data`, `/plans` and `/api/_*` yourself, see [deploy.md](docs/guide/en/deploy.md#nginx).
