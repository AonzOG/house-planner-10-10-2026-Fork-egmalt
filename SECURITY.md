# Security Policy

## Supported versions

Security fixes go into the latest release on the `main` branch. Self-hosted installations should update to it; see [updating](docs/guide/en/deploy.md#updating).

| Version | Supported |
|---|---|
| 0.1.x | yes |

## Reporting a vulnerability

**Ordinary bugs and feature requests — public GitHub Issues:** Submit non-security bugs, installation failures, and feature requests to [AonzOG House Planner Issues](https://github.com/AonzOG/house-planner-10-10-2026-Fork-egmalt/issues). GitHub Issues are public, so remove passwords, setup keys, access tokens, personal information, and sensitive log contents before posting.

**Security vulnerabilities — confidential GitHub reporting only:** Do **not** disclose vulnerabilities, exploits, security-sensitive reproduction steps, or confidential security logs in public Issues, pull requests, or Discussions. Report security vulnerabilities **exclusively to AonzOG** through [GitHub Private Vulnerability Reporting for this repository](https://github.com/AonzOG/house-planner-10-10-2026-Fork-egmalt/security/advisories/new) under **Security → Report a vulnerability**.

This private channel covers vulnerabilities in all code distributed in this fork, including original House Planner application code, AonzOG-maintained Windows, Linux and macOS installers, Docker configuration, deployment scripts, and other repository content. Include the affected component, steps to reproduce, impact, and a suggested fix where possible, without sending passwords, access tokens, or unrelated personal data.

**Availability:** The private reporting form appears only if AonzOG has enabled GitHub's **Private vulnerability reporting** setting for this repository. If the form is unavailable, the repository administrator must enable it. **Do not publish vulnerability details in any public GitHub channel while it is unavailable.**

## Scope

In scope: the PHP API in `public/api/` (authentication, the login cookie, CSRF protection, storage access, the setup wizard, the Petrovich cart proxy), the `.htaccess` rules that close `storage/`, `data/` and `plans/`, the Docker image, the deploy and plan scripts in `scripts/`, the frontend, and the AonzOG-maintained installer files in `Installer/` (Windows BAT/PowerShell, Linux/macOS wrappers, shared Unix core, source downloads, setup-key handling, repair, and uninstall).

Out of scope: misconfiguration of a particular hosting (for example, nginx without the equivalent of the `.htaccess` rules), the PHP built-in server used for local development, attacks that need the planner password, and third-party services (petrovich.ru, imagery tiles).

## Hardening a deployment

- Serve the site over HTTPS only; the login cookie gets the `Secure` flag on HTTPS.
- Keep the storage folder outside the web root (`../storage`) when the hosting allows it.
- Set `HOUSE_SETUP_KEY`, or in Docker `HOUSE_PASSWORD`, so nobody else can run the setup wizard before you.
- Use a long password: there is one password per installation, and the login endpoint only slows down guessing with a 1-second delay.
- On nginx, deny `/storage`, `/data`, `/plans` and `/api/_*` yourself, see [deploy.md](docs/guide/en/deploy.md#nginx).
