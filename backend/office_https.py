"""HTTPS for the office server, so the sales app's camera works in a browser.

Browsers only allow the camera on https:// (or localhost). This module gives
the office server its own small certificate authority (CA):

* ``ensure_certificates()`` creates the CA once, then a server certificate
  for this laptop's local network addresses. The server certificate is
  renewed automatically when it nears expiry or the laptop's address
  changes (another Wi-Fi). The CA stays the same, so tablets set up once
  stay set up.
* Each tablet installs the CA certificate once, from ``/setup``.
* The CA is restricted ("name constraints") to private network addresses,
  ``localhost``, ``*.local`` and this computer's name. Even if its key
  leaked, it could not be used to impersonate real websites.

Files live in ``backend/certs/`` (never commit it: it holds private keys).
"""

from __future__ import annotations

import datetime
import hashlib
import html
import ipaddress
import os
import socket
from dataclasses import dataclass
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID

CERT_DIR = Path(__file__).resolve().parent / "certs"
CA_NAME = "SS Love Office Server CA"
CA_DOWNLOAD_NAME = "ss-love-office-ca.crt"

# Addresses the CA may vouch for: the private and local ranges an office
# network uses. A certificate for any other address is rejected by devices.
PERMITTED_NETWORKS = [
    ipaddress.ip_network(n)
    for n in (
        "10.0.0.0/8",
        "172.16.0.0/12",
        "192.168.0.0/16",
        "100.64.0.0/10",  # carrier-grade NAT, also used by VPNs like Tailscale
        "169.254.0.0/16",  # link-local
        "127.0.0.0/8",
    )
]

CA_DAYS = 3650
# Apple accepts at most 825 days for a server certificate from a private CA;
# a shorter life is renewed automatically anyway.
SERVER_DAYS = 397
RENEW_BEFORE_DAYS = 30


@dataclass(frozen=True)
class OfficeCertificates:
    ca_cert: Path
    server_cert: Path
    server_key: Path
    addresses: list[str]  # IPs and names the server certificate covers

    @property
    def ca_der(self) -> bytes:
        cert = x509.load_pem_x509_certificate(self.ca_cert.read_bytes())
        return cert.public_bytes(serialization.Encoding.DER)

    @property
    def ca_fingerprint(self) -> str:
        """SHA-256 of the CA certificate, as devices show it ("AB:CD:...")."""
        digest = hashlib.sha256(self.ca_der).hexdigest().upper()
        return ":".join(digest[i : i + 2] for i in range(0, len(digest), 2))


# ── Addresses ────────────────────────────────────────────────────────────────


def _permitted_ip(address: str) -> bool:
    try:
        ip = ipaddress.ip_address(address)
    except ValueError:
        return False
    return any(ip in net for net in PERMITTED_NETWORKS)


def computer_name() -> str:
    """This computer's name in lower case, e.g. ``pc-jawa``."""
    return socket.gethostname().split(".")[0].lower()


def primary_lan_ip() -> str | None:
    """The address other devices on the Wi-Fi use to reach this computer."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            # No packet is sent: this only asks the OS which interface it
            # would use, and that interface's address.
            s.connect(("10.255.255.255", 1))
            address = s.getsockname()[0]
    except OSError:
        return None
    return address if _permitted_ip(address) and address != "127.0.0.1" else None


def lan_ips() -> list[str]:
    """This computer's IPv4 addresses that the certificate can cover."""
    found = {"127.0.0.1"}
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            found.add(info[4][0])
    except OSError:
        pass
    primary = primary_lan_ip()
    if primary:
        found.add(primary)
    return sorted(
        (a for a in found if _permitted_ip(a)),
        key=lambda a: ipaddress.ip_address(a),
    )


def server_names() -> list[str]:
    name = computer_name()
    names = ["localhost", name, f"{name}.local"]
    return list(dict.fromkeys(names))  # drop duplicates, keep order


# ── Certificates ─────────────────────────────────────────────────────────────


def _now() -> datetime.datetime:
    return datetime.datetime.now(datetime.timezone.utc)


def _write_private(path: Path, data: bytes) -> None:
    path.write_bytes(data)
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass  # Windows: file permissions follow the user's folder


def _new_key() -> rsa.RSAPrivateKey:
    # RSA 2048: accepted by every tablet and browser (Apple requires >= 2048).
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


def _key_pem(key: rsa.RSAPrivateKey) -> bytes:
    return key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    )


def _create_ca(
    cert_dir: Path, names: list[str]
) -> tuple[x509.Certificate, rsa.RSAPrivateKey]:
    key = _new_key()
    name = x509.Name(
        [
            x509.NameAttribute(NameOID.COMMON_NAME, f"{CA_NAME} ({computer_name()})"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "SS Love"),
        ]
    )
    now = _now()
    dns = ["localhost", "local"]  # "local": any mDNS name, e.g. pc-jawa.local
    dns += [n for n in names if n not in dns and not n.endswith(".local")]
    permitted = [x509.IPAddress(n) for n in PERMITTED_NETWORKS] + [
        x509.DNSName(n) for n in dns
    ]
    cert = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(hours=1))
        .not_valid_after(now + datetime.timedelta(days=CA_DAYS))
        .add_extension(x509.BasicConstraints(ca=True, path_length=0), critical=True)
        .add_extension(
            x509.KeyUsage(
                digital_signature=False,
                content_commitment=False,
                key_encipherment=False,
                data_encipherment=False,
                key_agreement=False,
                key_cert_sign=True,
                crl_sign=True,
                encipher_only=False,
                decipher_only=False,
            ),
            critical=True,
        )
        .add_extension(
            x509.NameConstraints(permitted_subtrees=permitted, excluded_subtrees=None),
            critical=True,
        )
        .add_extension(
            x509.SubjectKeyIdentifier.from_public_key(key.public_key()), critical=False
        )
        .sign(key, hashes.SHA256())
    )
    _write_private(cert_dir / "office-ca.key", _key_pem(key))
    (cert_dir / "office-ca.crt").write_bytes(cert.public_bytes(serialization.Encoding.PEM))
    return cert, key


def _load_ca(cert_dir: Path) -> tuple[x509.Certificate, rsa.RSAPrivateKey] | None:
    cert_path, key_path = cert_dir / "office-ca.crt", cert_dir / "office-ca.key"
    if not (cert_path.exists() and key_path.exists()):
        return None
    try:
        cert = x509.load_pem_x509_certificate(cert_path.read_bytes())
        key = serialization.load_pem_private_key(key_path.read_bytes(), password=None)
    except (ValueError, TypeError):
        return None
    if cert.not_valid_after_utc - _now() < datetime.timedelta(days=RENEW_BEFORE_DAYS):
        return None  # nearly expired: make a new one (tablets set up again)
    return cert, key  # type: ignore[return-value]


def _ca_permits_name(ca: x509.Certificate, name: str) -> bool:
    """Whether the CA's name constraints allow [name] (e.g. after the
    computer was renamed, its new name isn't covered)."""
    try:
        constraints = ca.extensions.get_extension_for_class(x509.NameConstraints).value
    except x509.ExtensionNotFound:
        return True
    allowed = [
        g.value for g in constraints.permitted_subtrees or [] if isinstance(g, x509.DNSName)
    ]
    return any(name == a or name.endswith("." + a) for a in allowed)


def _wanted_sans(ips: list[str], names: list[str]) -> list[x509.GeneralName]:
    return [x509.DNSName(n) for n in names] + [
        x509.IPAddress(ipaddress.ip_address(a)) for a in ips
    ]


def _server_is_current(
    cert_dir: Path, ca: x509.Certificate, sans: list[x509.GeneralName]
) -> bool:
    cert_path, key_path = cert_dir / "server.crt", cert_dir / "server.key"
    if not (cert_path.exists() and key_path.exists()):
        return False
    try:
        cert = x509.load_pem_x509_certificate(cert_path.read_bytes())
        current = cert.extensions.get_extension_for_class(
            x509.SubjectAlternativeName
        ).value
    except (ValueError, x509.ExtensionNotFound):
        return False
    return (
        cert.issuer == ca.subject
        and cert.not_valid_after_utc - _now() > datetime.timedelta(days=RENEW_BEFORE_DAYS)
        and set(current) == set(sans)
    )


def _create_server(
    cert_dir: Path,
    ca: x509.Certificate,
    ca_key: rsa.RSAPrivateKey,
    sans: list[x509.GeneralName],
) -> None:
    key = _new_key()
    now = _now()
    cert = (
        x509.CertificateBuilder()
        # Not a host name, so no device mistakes it for one.
        .subject_name(
            x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "SS Love office server")])
        )
        .issuer_name(ca.subject)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(hours=1))
        .not_valid_after(now + datetime.timedelta(days=SERVER_DAYS))
        .add_extension(x509.SubjectAlternativeName(sans), critical=False)
        .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
        .add_extension(
            x509.KeyUsage(
                digital_signature=True,
                content_commitment=False,
                key_encipherment=True,
                data_encipherment=False,
                key_agreement=False,
                key_cert_sign=False,
                crl_sign=False,
                encipher_only=False,
                decipher_only=False,
            ),
            critical=True,
        )
        .add_extension(
            x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), critical=False
        )
        .add_extension(
            x509.AuthorityKeyIdentifier.from_issuer_public_key(ca_key.public_key()),
            critical=False,
        )
        .sign(ca_key, hashes.SHA256())
    )
    _write_private(cert_dir / "server.key", _key_pem(key))
    (cert_dir / "server.crt").write_bytes(cert.public_bytes(serialization.Encoding.PEM))


def ensure_certificates(
    cert_dir: Path | None = None,
    ips: list[str] | None = None,
    names: list[str] | None = None,
) -> OfficeCertificates:
    """Creates or renews what's needed and returns the file paths."""
    cert_dir = cert_dir or CERT_DIR
    cert_dir.mkdir(parents=True, exist_ok=True)
    ips = lan_ips() if ips is None else [a for a in ips if _permitted_ip(a)]
    names = server_names() if names is None else names

    ca = _load_ca(cert_dir)
    if ca is None:
        ca = _create_ca(cert_dir, names)
    ca_cert, ca_key = ca

    # A name the CA can't vouch for would make devices reject the whole
    # certificate, so it's left out; the IP addresses still work.
    names = [n for n in names if _ca_permits_name(ca_cert, n)]
    sans = _wanted_sans(ips, names)
    if not _server_is_current(cert_dir, ca_cert, sans):
        _create_server(cert_dir, ca_cert, ca_key, sans)

    return OfficeCertificates(
        ca_cert=cert_dir / "office-ca.crt",
        server_cert=cert_dir / "server.crt",
        server_key=cert_dir / "server.key",
        addresses=names + ips,
    )


# ── Setup page ───────────────────────────────────────────────────────────────


def setup_page(host: str, http_port: int, https_port: int | None, fingerprint: str) -> str:
    """The page a tablet opens once, over plain http, to trust the server."""
    h = html.escape(host)
    app_url = f"https://{h}:{https_port}/sales/" if https_port else ""
    check_url = f"https://{h}:{https_port}/health" if https_port else ""
    not_running = (
        ""
        if https_port
        else '<p class="warn">The secure address isn\'t running. Start the server '
        "with <code>python main.py</code> on the office computer.</p>"
    )
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Set up this device · SS Love</title>
<style>
  :root {{ --bg:#FAF7F2; --card:#fff; --ink:#2C2724; --muted:#6E5F52; --line:#DDD5CA;
           --ok:#3D6B69; --bad:#A94444; }}
  * {{ box-sizing: border-box; }}
  body {{ margin:0; background:var(--bg); color:var(--ink);
         font:16px/1.5 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }}
  main {{ max-width:640px; margin:0 auto; padding:24px 16px 48px; }}
  h1 {{ font-size:24px; margin:0 0 4px; }}
  h2 {{ font-size:18px; margin:0 0 8px; }}
  p {{ margin:0 0 12px; }}
  .muted {{ color:var(--muted); }}
  .card {{ background:var(--card); border:1px solid var(--line); border-radius:16px;
           padding:16px; margin:16px 0; }}
  .status {{ font-weight:600; }}
  .status.ok {{ color:var(--ok); }} .status.bad {{ color:var(--bad); }}
  .warn {{ color:var(--bad); font-weight:600; }}
  .button {{ display:inline-block; background:var(--ink); color:#fff; text-decoration:none;
             padding:12px 18px; border-radius:12px; font-weight:600; min-height:48px; }}
  details {{ border-top:1px solid var(--line); padding:10px 0; }}
  summary {{ cursor:pointer; font-weight:600; min-height:32px; }}
  ol {{ padding-left:22px; margin:8px 0 0; }} li {{ margin:4px 0; }}
  code {{ background:#F1ECE5; padding:1px 5px; border-radius:6px; word-break:break-all; }}
</style>
</head>
<body>
<main>
  <h1>Set up this device</h1>
  <p class="muted">Do this once on each tablet or laptop, so the sales app can use the
  camera. It takes about two minutes.</p>
  {not_running}

  <div class="card" aria-live="polite">
    <p class="status" id="status">Checking this device…</p>
    <p id="next" class="muted"></p>
  </div>

  <div class="card">
    <h2>1. Install the office certificate</h2>
    <p>It lets this device recognise the office server.</p>
    <p><a class="button" href="/setup/{CA_DOWNLOAD_NAME}" download>Download certificate</a></p>
    <details>
      <summary>Android tablet or phone</summary>
      <ol>
        <li>Tap <b>Download certificate</b> above.</li>
        <li>Open <b>Settings</b> and search for <b>CA certificate</b> (often under
            Security › More security settings › Encryption &amp; credentials ›
            Install a certificate).</li>
        <li>Choose <b>CA certificate</b>, tap <b>Install anyway</b>, and pick
            <code>{CA_DOWNLOAD_NAME}</code> from Downloads.</li>
        <li>Come back to this page and reload it.</li>
      </ol>
    </details>
    <details>
      <summary>iPad or iPhone (use Safari)</summary>
      <ol>
        <li>Open this page in <b>Safari</b> and tap <b>Download certificate</b>,
            then <b>Allow</b>.</li>
        <li>Open <b>Settings</b> › <b>Profile Downloaded</b> › <b>Install</b>.</li>
        <li>Then <b>Settings</b> › <b>General</b> › <b>About</b> ›
            <b>Certificate Trust Settings</b>, and switch on
            <b>{html.escape(CA_NAME)}</b>.</li>
        <li>Come back to this page and reload it.</li>
      </ol>
    </details>
    <details>
      <summary>Windows laptop (Chrome or Edge)</summary>
      <ol>
        <li>Download the certificate and open it, then click <b>Install Certificate…</b>.</li>
        <li>Choose <b>Current User</b>, then <b>Place all certificates in the following
            store</b> › <b>Browse</b> › <b>Trusted Root Certification Authorities</b>.</li>
        <li>Click <b>Finish</b>, then <b>Yes</b>. Close and reopen the browser.</li>
      </ol>
    </details>
    <details>
      <summary>Mac</summary>
      <ol>
        <li>Download the certificate and open it: Keychain Access adds it.</li>
        <li>Double-click <b>{html.escape(CA_NAME)}</b> › <b>Trust</b> ›
            <b>When using this certificate: Always Trust</b>. Close the window and
            enter your password.</li>
      </ol>
    </details>
    <p class="muted">This certificate only works for this office server on the local
    network. It can't be used for any other website. Fingerprint (SHA-256), to
    check it if asked:<br><code>{html.escape(fingerprint)}</code></p>
  </div>

  <div class="card">
    <h2>2. Open the sales app</h2>
    <p>Always use this address (bookmark it or add it to the home screen):</p>
    <p><code>{app_url}</code></p>
    <p><a class="button" href="{app_url}">Open the sales app</a></p>
  </div>
</main>
<script>
  (async () => {{
    const status = document.getElementById('status');
    const next = document.getElementById('next');
    if (!{'true' if https_port else 'false'}) {{
      status.textContent = 'The secure address is not running.';
      status.className = 'status bad';
      return;
    }}
    // An untrusted certificate fails at once; no answer at all usually means
    // a firewall on the office computer is blocking the secure port.
    const timer = new AbortController();
    const timeout = setTimeout(() => timer.abort(), 6000);
    try {{
      const r = await fetch('{check_url}', {{ cache: 'no-store', signal: timer.signal }});
      if (!r.ok) throw new Error(String(r.status));
      status.textContent = '✓ This device is set up.';
      status.className = 'status ok';
      next.textContent = 'Open the sales app below. The camera will work.';
    }} catch (e) {{
      status.className = 'status bad';
      if (timer.signal.aborted) {{
        status.textContent = "Couldn't reach the secure address.";
        next.textContent = 'On the office computer, allow Python through the firewall '
          + '(Windows: allow it on Private networks), then reload this page.';
      }} else {{
        status.textContent = 'This device is not set up yet.';
        next.textContent = 'Install the office certificate (step 1), then reload this page.';
      }}
    }} finally {{
      clearTimeout(timeout);
    }}
  }})();
</script>
</body>
</html>
"""
