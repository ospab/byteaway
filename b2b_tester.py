#!/usr/bin/env python3
"""
ByteAway B2B Performance & Reliability Tester v3.2
Copyright (c) 2026 OSPAB Team. All rights reserved.

This script validates the entire ByteAway B2B pipeline:
1. Authentication & Pool Availability
2. Dynamic Proxy Credential Generation
3. Multi-Protocol Proxy Connectivity (SOCKS5/UDP)
4. High-Volume Traffic Relay Stability
5. Real-time Speed & Latency Metrics
"""

import argparse
import os
import sys
import time
import json
import socket
import threading
from urllib.parse import quote
from datetime import datetime

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

# --- UI CONSTANTS (Safe ASCII alternatives) ---
C_BOLD = "\033[1m"
C_GREEN = "\033[32m"
C_BLUE = "\033[34m"
C_YELLOW = "\033[33m"
C_RED = "\033[31m"
C_DIM = "\033[2m"
C_RESET = "\033[0m"

# Use ASCII for borders to avoid encoding issues
B_TOP = "+------------------------------------------------------------+"
B_MID = "|          BYTEAWAY B2B INFRASTRUCTURE TESTER v3.2           |"
B_BOT = "+------------------------------------------------------------+"

# --- DEFAULTS ---
DEFAULT_HOST = "byteaway.xyz"
DEFAULT_SOCKS_PORT = 31280
DEFAULT_API_BASE = "https://byteaway.xyz/api/v1"
DEFAULT_TRAFFIC_URLS = [
    "https://speed.cloudflare.com/__down?bytes=52428800",
    "https://proof.ovh.net/files/100Mb.dat",
    "https://ash-speed.hetzner.com/100MB.bin",
]

class ByteAwayTester:
    def __init__(self, args):
        self.args = args
        self.session = None
        self.username = None
        self.password = None
        self.proxy_url = None
        self.total_downloaded = 0
        self.start_time = 0
        self.last_report_time = 0
        self.last_report_bytes = 0
        self.aborted = False

    def log(self, icon, message, color=C_RESET):
        timestamp = datetime.now().strftime("%H:%M:%S")
        # Map icons to safe ASCII strings
        icons = {
            "🔍": "[?]", "✅": "[OK]", "🔑": "[*]", "🌐": "[#]",
            "🌍": "[@]", "🚀": "[>>]", "🏆": "[V]", "❌": "[X]", "⚠️": "[!]"
        }
        safe_icon = icons.get(icon, f"[{icon}]")
        print(f"{C_DIM}[{timestamp}]{C_RESET} {color}{safe_icon} {message}{C_RESET}")
        sys.stdout.flush()

    def banner(self):
        print(f"\n{C_BOLD}{C_BLUE}{B_TOP}")
        print(f"{B_MID}")
        print(f"{B_BOT}{C_RESET}")
        print(f"{C_DIM}Target API:  {self.args.api_base}")
        print(f"Target Proxy: socks5://{self.args.proxy_host}:{self.args.proxy_port}")
        print(f"Target Pool:  {self.args.country} (Label: {self.args.label}){C_RESET}\n")
        sys.stdout.flush()

    def setup_session(self, username, password, proxy_host, proxy_port):
        user_enc = quote(username, safe="")
        pass_enc = quote(password, safe="")
        self.proxy_url = f"socks5h://{user_enc}:{pass_enc}@{proxy_host}:{proxy_port}"
        
        self.session = requests.Session()
        self.session.proxies = {"http": self.proxy_url, "https": self.proxy_url}
        self.session.headers.update({"User-Agent": "ByteAway-B2B-Tester/3.2"})
        
        retries = Retry(total=3, backoff_factor=1, status_forcelist=[502, 503, 504])
        self.session.mount("https://", HTTPAdapter(max_retries=retries))
        self.session.mount("http://", HTTPAdapter(max_retries=retries))

    def run(self):
        try:
            self.banner()
            
            # 1. Pool Discovery
            self.log("🔍", f"Querying node pool for {self.args.country}...", C_YELLOW)
            resp = requests.get(f"{self.args.api_base}/proxies", headers={"Authorization": f"Bearer {self.args.bearer}"}, timeout=10)
            resp.raise_for_status()
            pool = resp.json()
            
            # Count specifically for target country
            countries = pool.get("countries", [])
            target_nodes = 0
            for c in countries:
                if str(c.get("code")).upper() == self.args.country.upper():
                    target_nodes = int(c.get("nodes", 0))
                    break
            
            if target_nodes <= 0:
                self.log("❌", f"ABORTING: No active nodes found for {self.args.country.upper()}.", C_RED + C_BOLD)
                print(f"   {C_DIM}Check if any mobile nodes are connected in this country.{C_RESET}")
                return 1
                
            self.log("✅", f"Pool active: {target_nodes} nodes online in {self.args.country.upper()}", C_GREEN)

            # 2. Credential Issue
            self.log("🔑", "Requesting dynamic proxy credentials...", C_YELLOW)
            payload = {"label": self.args.label, "country": self.args.country.upper()}
            resp = requests.post(
                f"{self.args.api_base}/business/proxy-credentials",
                headers={"Authorization": f"Bearer {self.args.bearer}"},
                json=payload,
                timeout=10
            )
            resp.raise_for_status()
            creds = resp.json()
            self.username = creds["username"]
            self.password = creds["password"]
            self.log("✅", f"Auth issued for session: {self.username}", C_GREEN)

            # 3. Connection Setup
            self.setup_session(self.username, self.password, self.args.proxy_host, self.args.proxy_port)
            
            # 4. Latency & IP Check
            self.log("🌐", "Testing proxy egress and latency...", C_YELLOW)
            t0 = time.time()
            try:
                resp = self.session.get("https://api.ipify.org?format=json", timeout=15)
                latency = (time.time() - t0) * 1000
                egress_ip = resp.json().get("ip")
                self.log("🌍", f"Proxy tunnel established: {egress_ip} (RTT: {latency:.1f}ms)", C_GREEN)
            except Exception as e:
                self.log("❌", f"Proxy verification failed: {str(e)}", C_RED)
                return 1

            # 5. Traffic Load Test
            self.log("🚀", f"Starting load test: {self.args.target_mb}MB target...", C_BLUE + C_BOLD)
            self.start_time = time.time()
            self.last_report_time = self.start_time
            self.last_report_bytes = 0
            self.total_downloaded = 0
            
            try:
                self.generate_traffic()
            except KeyboardInterrupt:
                print(f"\n{C_RED}[!] Traffic generation interrupted by user.{C_RESET}")
                self.aborted = True
                return 130
            
            if not self.aborted:
                duration = time.time() - self.start_time
                avg_speed = (self.total_downloaded / (1024 * 1024)) / (duration if duration > 0 else 1)
                self.log("🏆", f"Test Completed Successfully!", C_GREEN + C_BOLD)
                print(f"   {C_DIM}» Total Data:   {self.total_downloaded / (1024*1024):.2f} MB")
                print(f"   » Duration:     {duration:.1f} seconds")
                print(f"   » Avg Speed:    {avg_speed:.2f} MB/s ({avg_speed*8:.2f} Mbps){C_RESET}\n")
                return 0
            return 1

        except Exception as e:
            self.log("❌", f"CRITICAL FAILURE: {str(e)}", C_RED + C_BOLD)
            if hasattr(e, 'response') and e.response is not None:
                print(f"   {C_DIM}HTTP Response: {e.response.text[:200]}{C_RESET}")
            return 1

    def generate_traffic(self):
        urls = DEFAULT_TRAFFIC_URLS
        target_bytes = self.args.target_mb * 1024 * 1024
        
        while self.total_downloaded < target_bytes and not self.aborted:
            url = urls[int(time.time()) % len(urls)]
            try:
                with self.session.get(url, stream=True, timeout=10) as r:
                    r.raise_for_status()
                    # Use smaller chunks for better progress granularity
                    for chunk in r.iter_content(chunk_size=32 * 1024):
                        if self.aborted: break
                        if not chunk: continue
                        self.total_downloaded += len(chunk)
                        self.report_progress(target_bytes)
                        if self.total_downloaded >= target_bytes:
                            return
            except (requests.RequestException, socket.error) as e:
                self.log("⚠️", f"Stream interrupted, rotating source...", C_YELLOW)
                time.sleep(1)

    def report_progress(self, total_target):
        now = time.time()
        # Force initial report or every 0.2s
        if self.last_report_time == self.start_time or now - self.last_report_time >= 0.2:
            delta_t = now - self.last_report_time
            delta_b = self.total_downloaded - self.last_report_bytes
            
            speed = 0
            if delta_t > 0:
                speed = (delta_b / (1024 * 1024)) / delta_t
            
            percent = (self.total_downloaded / total_target) * 100
            bar_len = 20
            filled = int(bar_len * percent / 100)
            bar = "#" * filled + "-" * (bar_len - filled)
            
            # Simple line for progress to avoid complex escapes on Windows
            sys.stdout.write(f"\r   [{bar}] {percent:5.1f}% | {speed:5.2f} MB/s | {self.total_downloaded/(1024*1024):.1f}MB   ")
            sys.stdout.flush()
            
            self.last_report_time = now
            self.last_report_bytes = self.total_downloaded

def main():
    parser = argparse.ArgumentParser(description="ByteAway B2B Tester v3.2")
    parser.add_argument("--api-base", default=DEFAULT_API_BASE)
    parser.add_argument("--proxy-host", default=DEFAULT_HOST)
    parser.add_argument("--proxy-port", type=int, default=DEFAULT_SOCKS_PORT)
    parser.add_argument("--country", default="RU")
    parser.add_argument("--label", default="b2b-stress-test")
    parser.add_argument("--bearer", required=True, help="B2B Bearer Token")
    parser.add_argument("--target-mb", type=int, default=50)
    
    args = parser.parse_args()
    tester = ByteAwayTester(args)
    return tester.run()

if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print(f"\n{C_RED}[!] Test aborted.{C_RESET}")
        sys.exit(130)
