"""Tests for the office server's HTTPS (office_https.py) and its routes.

Run from the repo root:  python -m pytest backend/test_office_https.py
"""

import datetime
import ipaddress
import os
import sys

import pytest
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID
from cryptography.x509.verification import PolicyBuilder, Store, VerificationError

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from backend import office_https  # noqa: E402

NAMES = ["localhost", "pc-jawa", "pc-jawa.local"]
IPS = ["127.0.0.1", "192.168.1.42"]


def _load(path):
    return x509.load_pem_x509_certificate(path.read_bytes())


def _verify(ca, leaf, name):
    subject = (
        x509.IPAddress(ipaddress.ip_address(name))
        if name[0].isdigit()
        else x509.DNSName(name)
    )
    verifier = PolicyBuilder().store(Store([ca])).build_server_verifier(subject)
    verifier.verify(leaf, [])


@pytest.fixture
def certs(tmp_path):
    return office_https.ensure_certificates(tmp_path, ips=IPS, names=NAMES)


def test_server_certificate_is_trusted_for_every_local_address(certs):
    ca, leaf = _load(certs.ca_cert), _load(certs.server_cert)
    for name in NAMES + IPS:
        _verify(ca, leaf, name)  # raises if not trusted


def test_server_certificate_meets_tablet_requirements(certs):
    leaf = _load(certs.server_cert)
    life = leaf.not_valid_after_utc - leaf.not_valid_before_utc
    assert life <= datetime.timedelta(days=825)  # Apple's limit
    eku = leaf.extensions.get_extension_for_class(x509.ExtendedKeyUsage).value
    assert ExtendedKeyUsageOID.SERVER_AUTH in eku
    assert leaf.public_key().key_size >= 2048


def test_the_office_ca_cannot_vouch_for_real_websites(certs, tmp_path):
    """Even with the CA's key, a certificate for another site is rejected."""
    ca = _load(certs.ca_cert)
    ca_key = serialization.load_pem_private_key(
        (tmp_path / "office-ca.key").read_bytes(), password=None
    )
    now = datetime.datetime.now(datetime.timezone.utc)
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    forged = (
        x509.CertificateBuilder()
        .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "bank")]))
        .issuer_name(ca.subject)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(hours=1))
        .not_valid_after(now + datetime.timedelta(days=30))
        .add_extension(
            x509.SubjectAlternativeName(
                [x509.DNSName("www.maybank2u.com.my"), x509.IPAddress(ipaddress.ip_address("8.8.8.8"))]
            ),
            critical=False,
        )
        .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), critical=False)
        .add_extension(
            x509.AuthorityKeyIdentifier.from_issuer_public_key(ca_key.public_key()),
            critical=False,
        )
        .sign(ca_key, hashes.SHA256())
    )
    with pytest.raises(VerificationError):
        _verify(ca, forged, "www.maybank2u.com.my")


def test_a_renamed_computer_keeps_working_by_ip(certs, tmp_path):
    renamed = office_https.ensure_certificates(
        tmp_path, ips=IPS, names=["localhost", "new-laptop", "new-laptop.local"]
    )
    ca, leaf = _load(renamed.ca_cert), _load(renamed.server_cert)
    for name in ["localhost", "new-laptop.local"] + IPS:
        _verify(ca, leaf, name)
    assert "new-laptop" not in renamed.addresses


def test_public_addresses_are_left_out(tmp_path):
    certs = office_https.ensure_certificates(
        tmp_path, ips=["127.0.0.1", "203.0.113.9"], names=["localhost"]
    )
    sans = _load(certs.server_cert).extensions.get_extension_for_class(
        x509.SubjectAlternativeName
    ).value
    assert ipaddress.ip_address("203.0.113.9") not in sans.get_values_for_type(x509.IPAddress)


def test_new_wifi_address_renews_the_server_certificate_but_keeps_the_ca(certs, tmp_path):
    ca_before = certs.ca_cert.read_bytes()
    leaf_before = certs.server_cert.read_bytes()

    again = office_https.ensure_certificates(tmp_path, ips=IPS, names=NAMES)
    assert again.server_cert.read_bytes() == leaf_before  # nothing changed

    moved = office_https.ensure_certificates(
        tmp_path, ips=["127.0.0.1", "10.0.0.7"], names=NAMES
    )
    assert moved.ca_cert.read_bytes() == ca_before  # tablets stay set up
    assert moved.server_cert.read_bytes() != leaf_before
    _verify(_load(moved.ca_cert), _load(moved.server_cert), "10.0.0.7")


# ── Routes ──────────────────────────────────────────────────────────────────


@pytest.fixture
def client(tmp_path, monkeypatch):
    from fastapi.testclient import TestClient

    from backend.main import app

    monkeypatch.setattr(office_https, "CERT_DIR", tmp_path)
    app.state.https_port = 8443
    yield TestClient(app)
    app.state.https_port = None


def test_setup_page_links_the_certificate_and_the_secure_app(client):
    page = client.get("/setup")
    assert page.status_code == 200
    assert f"/setup/{office_https.CA_DOWNLOAD_NAME}" in page.text
    assert "https://testserver:8443/sales/" in page.text


def test_certificate_download_is_the_office_ca(client, tmp_path):
    response = client.get(f"/setup/{office_https.CA_DOWNLOAD_NAME}")
    assert response.status_code == 200
    assert response.headers["content-type"] == "application/x-x509-ca-cert"
    cert = x509.load_der_x509_certificate(response.content)
    assert cert == _load(tmp_path / "office-ca.crt")
    # Only the public certificate is ever served.
    assert client.get("/setup/office-ca.key").status_code == 404


def test_sales_app_over_http_moves_to_https(client):
    response = client.get("/sales/", follow_redirects=False)
    assert response.status_code == 307
    assert response.headers["location"] == "https://testserver:8443/sales/"


def test_api_stays_on_http_for_the_android_app(client):
    assert client.get("/health").status_code == 200
