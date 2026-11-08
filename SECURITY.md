# Security

Strata Monitor can inspect process information and control eligible processes and devices.
Please report vulnerabilities privately through
[GitHub's vulnerability reporting](https://github.com/cristipufu/strata-monitor/security/advisories/new),
not a public issue or pull request.

Include the app version from Settings ▸ About, the macOS version, steps to reproduce,
and the information or action an attacker could gain. Use made-up process names and
redact paths, arguments, addresses and exported snapshots before sharing examples.
Do not include credentials, signing keys or private system reports.

## Scope

- The app, optional privileged helper, release workflow and update feed.
- Helper requests accepted from an untrusted caller, access beyond the caller's
  authorization, or changes outside its read-only allowlist.
- A process action reaching the wrong process, including after PID reuse, or
  bypassing confirmation or the protection of system and other users' processes.
- Unintended disclosure through history, export, process inspection or permissions.
- Malicious system-tool output, unbounded execution, or work surviving cancellation.
- Tampered update archives or feeds accepted without their required signatures.

Report macOS and third-party vulnerabilities to their maintainers as well if relevant.
Reports requiring an already compromised administrator account or automated scan results
without a demonstrated impact may not be actionable on their own.

## Supported versions and disclosure

Fixes target the latest release. Until the first release, report against the current
`main` branch. Please check whether a newer version already addresses the problem.

We investigate in the private advisory, coordinate a fix and publish the advisory after
the fix is available. Credit is included unless you ask to remain unnamed. There is no
promised response deadline or paid bounty.

## Security boundaries

Readings and history stay on the Mac. Update checks contact GitHub when requested or
when automatic checks are enabled; they do not send monitoring data. There is no
account, telemetry, packet capture or private API use.

The optional helper requires administrator approval and validates its caller's signature.
It is read-only: it does not send signals, run tools, write files, read file contents or
accept paths. Process and device actions belong to the unprivileged app.

Distribution builds require Developer ID signing and notarization. Sparkle also verifies
the signed update feed and archive before extraction. Update-signing private keys belong
in the maintainer's Keychain and CI secrets, never in the repository.
