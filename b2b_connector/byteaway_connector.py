#!/usr/bin/env python3
"""
ByteAway B2B Connector - Linux Client
Создаёт локальный SOCKS5 прокси и направляет трафик через ByteAway residential сеть

Использование:
    python3 byteaway_connector.py --api-key ВАШ_API_КЛЮЧ

Для использования в браузере/приложениях:
    SOCKS5 хост: 127.0.0.1
    Порт: 1080
    Username: RU-wifi (или US-mobile, DE-all)
    Password: ВАШ_API_КЛЮЧ
"""

import socket
import sys
import threading
import time
import socketserver
import struct
from datetime import datetime
import argparse

DEFAULT_PROXY_HOST = "byteaway.xyz"
DEFAULT_PROXY_PORT = 31280
DEFAULT_LISTEN = "127.0.0.1:1080"

C_GREEN = '\033[92m'
C_BLUE = '\033[94m'
C_YELLOW = '\033[93m'
C_RED = '\033[91m'
C_RESET = '\033[0m'

def log(msg, color=C_GREEN):
    print(f"{color}[{datetime.now().strftime('%H:%M:%S')}]{C_RESET} {msg}")

class ByteAwayProxyHandler(socketserver.StreamRequestHandler):
    timeout = 60
    
    def handle(self):
        try:
            greeting = self.connection.recv(2)
            if greeting[0] != 0x05:
                log(f"Non-SOCKS5: {greeting[0]}", C_RED)
                return
            nmethods = greeting[1]
            methods = self.connection.recv(nmethods)
            if 0x02 not in methods:
                log(f"No user/pass auth supported: {methods.hex()}", C_RED)
                self.connection.sendall(b'\x05\xff')
                return
            self.connection.sendall(b'\x05\x02')
            
            ver = self.connection.recv(1)
            ulen = self.connection.recv(1)
            username = self.connection.recv(ord(ulen))
            plen = self.connection.recv(1)
            password = self.connection.recv(ord(plen))
            
            filter_str = username.decode('utf-8').strip()
            api_key = password.decode('utf-8').strip()
            
            log(f"Auth: user={filter_str}, key={api_key[:20]}...", C_YELLOW)
            
            if not api_key:
                log("Empty password", C_RED)
                self.connection.sendall(b'\x01\x01')
                return
            self.connection.sendall(b'\x01\x00')
            
            req = self.connection.recv(4)
            if req[1] != 0x01:
                return
                
            if req[3] == 0x01:
                addr = self.connection.recv(4)
                target = socket.inet_ntoa(addr)
            elif req[3] == 0x03:
                dlen = self.connection.recv(1)
                domain = self.connection.recv(ord(dlen))
                target = domain.decode('utf-8')
            else:
                return
                
            port_bytes = self.connection.recv(2)
            port = struct.unpack("!H", port_bytes)[0]
            target_addr = f"{target}:{port}"
            
            try:
                proxy_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                proxy_sock.settimeout(300)
                proxy_sock.connect((self.server.proxy_host, self.server.proxy_port))
                
                # Запрашиваем username/password auth (0x02)
                proxy_sock.sendall(b'\x05\x01\x02')
                resp = proxy_sock.recv(2)
                log(f"Upstream greeting: {resp.hex()}", C_YELLOW)
                if resp[0] != 0x05 or resp[1] != 0x02:
                    log(f"Upstream no userpass auth: {resp[1]}", C_RED)
                    proxy_sock.close()
                    return
                
                # Отправляем username/password
                user_bytes = filter_str.encode()
                pass_bytes = api_key.encode()
                auth_req = bytes([0x01, len(user_bytes)]) + user_bytes + bytes([len(pass_bytes)]) + pass_bytes
                proxy_sock.sendall(auth_req)
                auth_resp = proxy_sock.recv(2)
                log(f"Upstream auth: {auth_resp.hex()}", C_YELLOW)
                if auth_resp[1] != 0x00:
                    log(f"Auth failed: {auth_resp[1]}", C_RED)
                    proxy_sock.close()
                    self.connection.sendall(b'\x05\x02\x00\x01\x00\x00\x00\x00\x00\x00')
                    return
                
                if req[3] == 0x01:
                    connect_req = b'\x05\x01\x00\x01' + addr + port_bytes
                else:
                    connect_req = b'\x05\x01\x00\x03' + bytes([len(domain)]) + domain + port_bytes
                log(f"CONNECT: {target_addr}", C_YELLOW)
                proxy_sock.sendall(connect_req)
                connect_resp = proxy_sock.recv(10)
                log(f"CONNECT resp: {connect_resp.hex()}", C_YELLOW)
                if connect_resp[1] != 0x00:
                    log(f"CONNECT failed: {connect_resp[1]}", C_RED)
                    proxy_sock.close()
                    return
                
                self.connection.sendall(b'\x05\x00\x00\x01\x00\x00\x00\x00\x00\x00')
                log(f"→ {target_addr} [{filter_str}]", C_BLUE)
                self.relay_loop(proxy_sock)
                
            except Exception as e:
                log(f"Ошибка: {e}", C_RED)
                try:
                    self.connection.sendall(b'\x05\x03\x00\x01\x00\x00\x00\x00\x00\x00')
                except:
                    pass
        except Exception as e:
            log(f"Ошибка: {e}", C_RED)

    def relay_loop(self, proxy_sock):
        def c2p():
            try:
                total = 0
                while True:
                    data = self.connection.recv(8192)
                    if not data:
                        log(f"c2p EOF: {total}B sent", C_YELLOW)
                        break
                    proxy_sock.sendall(data)
                    total += len(data)
                    self.server.bytes_sent += len(data)
                log(f"c2p ended: {total}B", C_YELLOW)
            except Exception as e:
                log(f"c2p error: {e}", C_RED)
            finally:
                # НЕ закрываем proxy_sock - p2c может ещё читать ответ
                pass
                    
        def p2c():
            try:
                total = 0
                while True:
                    data = proxy_sock.recv(8192)
                    if not data:
                        log(f"p2c EOF: {total}B received", C_YELLOW)
                        break
                    self.connection.sendall(data)
                    total += len(data)
                    self.server.bytes_received += len(data)
                log(f"p2c ended: {total}B", C_YELLOW)
            except Exception as e:
                log(f"p2c error: {e}", C_RED)
            finally:
                try:
                    self.connection.close()
                except:
                    pass
        
        t1 = threading.Thread(target=c2p, daemon=True)
        t2 = threading.Thread(target=p2c, daemon=True)
        t1.start()
        t2.start()
        t1.join()
        t2.join()


class ThreadedTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True
    
    def __init__(self, server_address, RequestHandlerClass, proxy_host, proxy_port):
        super().__init__(server_address, RequestHandlerClass)
        self.proxy_host = proxy_host
        self.proxy_port = proxy_port
        self.bytes_sent = 0
        self.bytes_received = 0


def parse_address(addr_str):
    if ':' in addr_str:
        host, port = addr_str.rsplit(':', 1)
        return host, int(port)
    return '127.0.0.1', int(addr_str)


def main():
    parser = argparse.ArgumentParser(description='ByteAway B2B Connector')
    parser.add_argument('--api-key', required=True, help='Ваш API ключ ByteAway')
    parser.add_argument('--proxy', default=DEFAULT_PROXY_HOST, help='Хост ByteAway SOCKS5')
    parser.add_argument('--port', type=int, default=DEFAULT_PROXY_PORT, help='Порт ByteAway SOCKS5')
    parser.add_argument('--listen', default=DEFAULT_LISTEN, help='Адрес для прослушивания')
    args = parser.parse_args()
    
    listen_host, listen_port = parse_address(args.listen)
    
    print(f"(SOCKS5: {listen_host}:{listen_port} -> {args.proxy}:{args.port})")
    
    log(f"Proxy: {args.proxy}:{args.port}", C_GREEN)
    log(f"Listen: {listen_host}:{listen_port}", C_GREEN)
    
    try:
        server = ThreadedTCPServer((listen_host, listen_port), ByteAwayProxyHandler, args.proxy, args.port)
        log("Started", C_GREEN)
        
        def stats_loop():
            while True:
                time.sleep(10)
                sent = server.bytes_sent / (1024*1024)
                received = server.bytes_received / (1024*1024)
                log(f"↑ {sent:.1f}MB | ↓ {received:.1f}MB", C_YELLOW)
        
        threading.Thread(target=stats_loop, daemon=True).start()
        server.serve_forever()
    except KeyboardInterrupt:
        log("Stopped", C_YELLOW)
        sys.exit(0)


if __name__ == "__main__":
    main()
