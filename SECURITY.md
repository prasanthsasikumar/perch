# Security Policy

## Supported versions

Security fixes go into the latest release. Please update to the newest version
from the [releases page](https://github.com/prasanthsasikumar/perch/releases)
before reporting.

## Reporting a vulnerability

Please do not open a public issue for a security problem.

Report it privately through GitHub:
[Report a vulnerability](https://github.com/prasanthsasikumar/perch/security/advisories/new).

Include what you found, the Perch and macOS versions, and steps to reproduce.
You can expect a reply within a week, and a fix or a plan for one as soon as
the report is confirmed.

## What is in scope

- The Perch app and its plugins
- The keep-awake helper, which runs as root and accepts requests only from Perch
- How credentials are stored (service account keys and server passwords are
  kept in the login Keychain)

Issues in third-party services that plugins read from (Google Analytics,
Facebook Marketplace, Google Maps) should go to those services.
