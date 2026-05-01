package boxwrapper

import (
	"fmt"
	"github.com/armon/go-socks5"
	"net"
	"sync"
)

var (
	localSocksMu        sync.Mutex
	localSocksListeners = make(map[int]net.Listener)
)

// StartLocalSocks5 starts a lightweight, independent SOCKS5 server
// on the specified port.
func StartLocalSocks5(port int) error {
	localSocksMu.Lock()
	defer localSocksMu.Unlock()

	if _, exists := localSocksListeners[port]; exists {
		return fmt.Errorf("local SOCKS5 proxy already running on port %d", port)
	}

	conf := &socks5.Config{}
	server, err := socks5.New(conf)
	if err != nil {
		return err
	}

	ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		return err
	}

	localSocksListeners[port] = ln

	go func() {
		if err := server.Serve(ln); err != nil {
			fmt.Printf("[boxwrapper] local SOCKS5 server on port %d stopped: %v\n", port, err)
		}
	}()

	fmt.Printf("[boxwrapper] local SOCKS5 proxy started on port %d\n", port)
	return nil
}

// StopLocalSocks5 stops all running local SOCKS5 servers
func StopLocalSocks5() {
	localSocksMu.Lock()
	defer localSocksMu.Unlock()

	for port, ln := range localSocksListeners {
		_ = ln.Close()
		fmt.Printf("[boxwrapper] local SOCKS5 proxy on port %d stopped\n", port)
	}
	localSocksListeners = make(map[int]net.Listener)
}
