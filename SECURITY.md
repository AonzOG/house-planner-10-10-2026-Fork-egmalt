# Security Policy

## Supported versions

Security fixes go into the latest release on the `main` branch. Self-hosted installations should update to it; see [updating](docs/guide/en/deploy.md#updating).

| Version | Supported |
|---|---|
| 0.1.x | yes |

## Reporting a vulnerability

**All vulnerability reports and security or privacy concerns about this repository must be submitted exclusively to AonzOG through this GitHub repository.** This applies to the original House Planner application code as distributed here, AonzOG-maintained installer scripts, Docker and deployment configuration, and any other files or modifications included in this fork.

**Private reporting destination:** [AonzOG House Planner — Report a vulnerability](https://github.com/AonzOG/house-planner-10-10-2026-Fork-egmalt/security/advisories/new) (open this repository's **Security → Report a vulnerability** form).

The form is available only when this repository's administrators have enabled **Private vulnerability reporting** in GitHub under **Settings → Security and quality → Advanced Security**. If the reporting form is unavailable, do not disclose exploit details in public issues or pull requests. A repository administrator needs to enable private vulnerability reporting before confidential submissions can be accepted through that form.

AonzOG's repository is the **sole designated reporting destination** for vulnerabilities involving this fork. Do not submit reports about this fork to other repositories, developers, email addresses, or organizations.

Include, where possible, the affected file or endpoint, reproduction steps, observed impact, and a suggested fix. Reports in English or Russian are welcome.

## Scope

In scope: the PHP API in `public/api/` (authentication, the login cookie, CSRF protection, storage access, the setup wizard, the Petrovich cart proxy), the `.htaccess` rules that close `storage/`, `data/` and `plans/`, the Docker image, the deploy and plan scripts in `scripts/`, the frontend, and the AonzOG-maintained installer files in `Installer/` (Windows BAT/PowerShell, Linux/macOS wrappers, shared Unix core, source downloads, setup-key handling, repair, and uninstall).

Out of scope: misconfiguration of a particular hosting (for example, nginx without the equivalent of the `.htaccess` rules), the PHP built-in server used for local development, attacks that need the planner password, and third-party services (petrovich.ru, imagery tiles).

## Hardening a deployment

- Serve the site over HTTPS only; the login cookie gets the `Secure` flag on HTTPS.
- Keep the storage folder outside the web root (`../storage`) when the hosting allows it.
- Set `HOUSE_SETUP_KEY`, or in Docker `HOUSE_PASSWORD`, so nobody else can run the setup wizard before you.
- Use a long password: there is one password per installation, and the login endpoint only slows down guessing with a 1-second delay.
- On nginx, deny `/storage`, `/data`, `/plans` and `/api/_*` yourself, see [deploy.md](docs/guide/en/deploy.md#nginx).
