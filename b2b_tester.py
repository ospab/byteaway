#!/usr/bin/env python3
"""ByteAway B2B traffic tester.

This script creates valid SOCKS5 credentials via B2B API (Bearer auth), then
generates real outbound traffic through SOCKS5 to validate billing/usage flow.
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from urllib.parse import quote

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

DEFAULT_HOST = "byteaway.xyz"
DEFAULT_SOCKS_PORT = 31280
DEFAULT_API_BASE = "https://byteaway.xyz/api/v1"
DEFAULT_CHECK_URL = "https://api.ipify.org?format=json"
DEFAULT_TRAFFIC_URL = "https://speed.cloudflare.com/__down?bytes=104857600"
FALLBACK_TRAFFIC_URLS = [
    "https://speed.cloudflare.com/__down?bytes=104857600",
    "https://proof.ovh.net/files/100Mb.dat",
    "https://ash-speed.hetzner.com/100MB.bin",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="ByteAway B2B proxy traffic tester")
    parser.add_argument("--api-base", default=os.getenv("B2B_API_BASE", DEFAULT_API_BASE))
    parser.add_argument("--proxy-host", default=os.getenv("B2B_PROXY_HOST", DEFAULT_HOST))
    parser.add_argument(
        "--proxy-port",
        type=int,
        default=int(os.getenv("B2B_PROXY_PORT", str(DEFAULT_SOCKS_PORT))),
    )
    parser.add_argument("--country", default=os.getenv("B2B_COUNTRY", "RU"))
    parser.add_argument("--label", default=os.getenv("B2B_LABEL", "traffic-test"))
    parser.add_argument("--timeout", type=int, default=30)
    parser.add_argument("--traffic-timeout", type=int, default=600)
    parser.add_argument(
        "--read-timeout",
        type=int,
        default=20,
        help="Per-read timeout in seconds for traffic requests",
    )
    parser.add_argument(
        "--stall-timeout",
        type=int,
        default=8,
        help="Abort current source if no chunks arrive for this many seconds",
    )
    parser.add_argument(
        "--slice-mb",
        type=int,
        default=8,
        help="How many MB to download per single request before rotating source",
    )
    parser.add_argument("--target-mb", type=int, default=100)
    parser.add_argument("--check-url", default=DEFAULT_CHECK_URL)
    parser.add_argument("--traffic-url", default=DEFAULT_TRAFFIC_URL)
    parser.add_argument(
        "--bearer",
        default=os.getenv("B2B_BEARER_TOKEN", ""),
        help="Bearer token for /business/proxy-credentials",
    )
    return parser.parse_args()


def create_credentials(api_base: str, bearer: str, country: str, label: str, timeout: int) -> dict:
    if not bearer:
        raise RuntimeError("Missing Bearer token. Set --bearer or B2B_BEARER_TOKEN.")

    url = f"{api_base.rstrip('/')}/business/proxy-credentials"
    headers = {"Authorization": f"Bearer {bearer}", "Content-Type": "application/json"}
    payload = {"label": label, "country": country.upper()}

    resp = requests.post(url, headers=headers, json=payload, timeout=timeout)
    if resp.status_code >= 400:
        raise RuntimeError(f"Credential create failed: HTTP {resp.status_code} {resp.text}")

    data = resp.json()
    required = ["username", "password", "proxy_host"]
    for field in required:
        if not data.get(field):
            raise RuntimeError(f"Invalid credentials response: missing '{field}'")
    return data


def ensure_nodes_available(api_base: str, bearer: str, country: str, timeout: int) -> None:
    url = f"{api_base.rstrip('/')}/proxies"
    headers = {"Authorization": f"Bearer {bearer}"}
    last_error: Exception | None = None
    for attempt in range(1, 11):
        try:
            resp = requests.get(url, headers=headers, timeout=timeout)
            if resp.status_code >= 400:
                raise RuntimeError(f"Failed to fetch node pool: HTTP {resp.status_code} {resp.text}")

            data = resp.json()
            active_nodes = int(data.get("active_nodes", 0) or 0)
            if active_nodes <= 0:
                raise RuntimeError("No active nodes available")

            countries = data.get("countries") or []
            requested = country.upper()
            requested_nodes = 0
            for item in countries:
                if not isinstance(item, dict):
                    continue
                if str(item.get("code", "")).upper() == requested:
                    requested_nodes = int(item.get("nodes", 0) or 0)
                    break

            if requested_nodes <= 0:
                raise RuntimeError(
                    f"No active nodes for country {requested}. Active countries: "
                    f"{', '.join(sorted(str(c.get('code')) for c in countries if isinstance(c, dict) and c.get('code')))}"
                )
            return
        except Exception as exc:
            last_error = exc
            if attempt < 10:
                time.sleep(2)

    raise RuntimeError(f"Node pool did not become ready in time: {last_error}")


def make_session(proxy_host: str, proxy_port: int, username: str, password: str, timeout: int) -> requests.Session:
    user_enc = quote(username, safe="")
    pass_enc = quote(password, safe="")
    proxy_url = f"socks5h://{user_enc}:{pass_enc}@{proxy_host}:{proxy_port}"

    session = requests.Session()
    session.proxies.update({"http": proxy_url, "https": proxy_url})
    session.headers.update({"User-Agent": "ByteAway-B2B-Tester/2.0"})
    session.verify = True

    retry = Retry(
        total=3,
        connect=3,
        read=3,
        backoff_factor=0.5,
        status_forcelist=(429, 500, 502, 503, 504),
        allowed_methods=("GET", "HEAD", "OPTIONS"),
        raise_on_status=False,
    )
    adapter = HTTPAdapter(max_retries=retry, pool_connections=16, pool_maxsize=16)
    session.mount("http://", adapter)
    session.mount("https://", adapter)

    session.request = _with_default_timeout(session.request, timeout)
    return session


def _with_default_timeout(request_func, timeout: int):
    def wrapped(method, url, **kwargs):
        if "timeout" not in kwargs:
            kwargs["timeout"] = timeout
        return request_func(method, url, **kwargs)

    return wrapped


def verify_proxy(session: requests.Session, check_url: str) -> str:
    resp = session.get(check_url)
    resp.raise_for_status()
    ip = None
    content_type = (resp.headers.get("content-type") or "").lower()
    if "application/json" in content_type:
        data = resp.json()
        ip = data.get("ip")
    else:
        ip = (resp.text or "").strip()

    if not ip:
        raise RuntimeError(f"IP check returned unexpected payload: {resp.text[:200]}")
    return ip


def _download_slice(
    session: requests.Session,
    url: str,
    slice_bytes: int,
    traffic_timeout: int,
    read_timeout: int,
    stall_timeout: int,
) -> int:
    total = 0
    started = time.time()
    last_progress = started

    # Range forces short bounded requests where supported; non-supporting origins still work.
    headers = {"Range": f"bytes=0-{slice_bytes - 1}"}
    with session.get(url, stream=True, timeout=(10, read_timeout), headers=headers) as resp:
        resp.raise_for_status()
        for chunk in resp.iter_content(chunk_size=256 * 1024):
            now = time.time()
            if now - started > traffic_timeout:
                break
            if not chunk:
                if now - last_progress > stall_timeout:
                    raise TimeoutError(f"stalled for {stall_timeout}s")
                continue

            total += len(chunk)
            last_progress = now
            if total >= slice_bytes:
                break

            if now - last_progress > stall_timeout:
                raise TimeoutError(f"stalled for {stall_timeout}s")

    return total


def generate_traffic_active(
    session: requests.Session,
    urls: list[str],
    target_mb: int,
    traffic_timeout: int,
    read_timeout: int,
    stall_timeout: int,
    slice_mb: int,
) -> int:
    target_bytes = target_mb * 1024 * 1024
    slice_bytes = max(1, slice_mb) * 1024 * 1024
    total = 0
    src_idx = 0
    started = time.time()
    last_report = started
    failures = 0

    while total < target_bytes:
        if time.time() - started > traffic_timeout:
            raise TimeoutError(
                f"traffic generation timed out at {total / (1024 * 1024):.2f} MB"
            )

        url = urls[src_idx % len(urls)]
        src_idx += 1

        try:
            downloaded = _download_slice(
                session=session,
                url=url,
                slice_bytes=min(slice_bytes, target_bytes - total),
                traffic_timeout=traffic_timeout,
                read_timeout=read_timeout,
                stall_timeout=stall_timeout,
            )
            if downloaded <= 0:
                failures += 1
            else:
                total += downloaded
                failures = 0
        except Exception as e:
            sys.stdout.write(f"\r[!] Download slice failed: {type(e).__name__}: {str(e)}\n")
            sys.stdout.flush()
            failures += 1

        now = time.time()
        if now - last_report >= 1:
            mb = total / (1024 * 1024)
            sys.stdout.write(f"\rTraffic: {mb:.2f}/{target_mb:.2f} MB")
            sys.stdout.flush()
            last_report = now

        if failures >= len(urls) * 2:
            raise RuntimeError(
                f"all traffic sources keep failing/stalling, downloaded {total / (1024 * 1024):.2f} MB"
            )

    print()
    return total


def main() -> int:
    args = parse_args()

    print("=== ByteAway B2B Tester ===")
    print(f"API: {args.api_base}")
    print(f"SOCKS5 target: socks5://{args.proxy_host}:{args.proxy_port}")

    try:
        ensure_nodes_available(args.api_base, args.bearer, args.country, args.timeout)
        cred = create_credentials(args.api_base, args.bearer, args.country, args.label, args.timeout)
        username = cred["username"]
        password = cred["password"]
        returned_port = cred.get("proxy_port")
        effective_port = int(returned_port) if returned_port else args.proxy_port

        print(f"[*] Credential issued: {username}")
        if returned_port and int(returned_port) != args.proxy_port:
            print(f"[!] API returned proxy_port={returned_port}, using returned port")

        session = make_session(args.proxy_host, effective_port, username, password, args.timeout)

        print("[*] Verifying outbound IP through SOCKS5...")
        ip = verify_proxy(session, args.check_url)
        print(f"[+] Proxy works, egress IP: {ip}")

        print(f"[*] Generating traffic: {args.target_mb} MB")

        urls = [args.traffic_url] + [u for u in FALLBACK_TRAFFIC_URLS if u != args.traffic_url]
        for u in urls:
            print(f"[*] Traffic source candidate: {u}")

        total = generate_traffic_active(
            session=session,
            urls=urls,
            target_mb=args.target_mb,
            traffic_timeout=args.traffic_timeout,
            read_timeout=args.read_timeout,
            stall_timeout=args.stall_timeout,
            slice_mb=args.slice_mb,
        )

        print(f"[+] Done. Downloaded {total / (1024 * 1024):.2f} MB through proxy")
        return 0
    except Exception as exc:
        print(f"[x] Error: {exc}")
        print("\nTips:")
        print("- Provide valid Bearer token for B2B client")
        print("- Ensure nginx routes /api and SOCKS5 31280 are reachable")
        print("- Check master_node logs for Unauthorized / rate limits")
        return 1
    except KeyboardInterrupt:
        print("\n[x] Interrupted by user")
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
