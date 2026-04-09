package boxwrapper

import (
	"context"
	"crypto/tls"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/quic-go/quic-go"
	singbox "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/option"
	"golang.org/x/net/proxy"
)

var (
	boxInstance     *singbox.Box
	boxCancel       context.CancelFunc
	activeTransport string
	quicConn        quic.Connection
	quicStream      quic.Stream
	wsConn          *websocket.Conn
	wsWriteMu       sync.Mutex
	quicWriteMu     sync.Mutex
	quicMu          sync.Mutex
)

type nodeQuicHello struct {
	DeviceID string `json:"device_id"`
	Token    string `json:"token"`
	Country  string `json:"country"`
	ConnType string `json:"conn_type"`
	Speed    int    `json:"speed_mbps"`
}

// StartBox starts sing-box from JSON config.
func StartBox(configJsonStr string) error {
	if boxInstance != nil {
		return errors.New("sing-box is already running")
	}

	var options option.Options
	if err := json.Unmarshal([]byte(configJsonStr), &options); err != nil {
		return fmt.Errorf("failed to unmarshal config: %v", err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	instance, err := singbox.New(singbox.Options{
		Context: ctx,
		Options: options,
	})
	if err != nil {
		cancel()
		return fmt.Errorf("failed to create sing-box instance: %v", err)
	}

	if err := instance.Start(); err != nil {
		cancel()
		return fmt.Errorf("failed to start sing-box: %v", err)
	}

	boxInstance = instance
	boxCancel = cancel
	return nil
}

// StartBoxWithFD starts sing-box and can optionally use a TUN file descriptor.
// Note: for sing-box, the TUN config should point to the FD if needed, 
// but often on Android we just let sing-box handle the networking via its TUN inbound.
func StartBoxWithFD(configJsonStr string, fd int) error {
	fmt.Printf("StartBoxWithFD invoked with FD: %d (ignoring for now, relying on sing-box native tun)\n", fd)
	// On Android, sing-box usually prefers to handle FD inside the core if configured.
	// We'll keep the signature for compatibility with Kotlin.
	return StartBox(configJsonStr)
}

// StopBox stops the running sing-box instance.
func StopBox() {
	if boxInstance != nil {
		_ = boxInstance.Close()
		if boxCancel != nil {
			boxCancel()
		}
		boxInstance = nil
		boxCancel = nil
	}
}

// ──────────────────────────────────────────────────────
// Node Transport (QUIC/WS) - Ported from xraywrapper
// ──────────────────────────────────────────────────────

func StartNodeQuic(endpoint, deviceID, token, country, connType string, speedMbps int, mtu int) error {
	quicMu.Lock()
	defer quicMu.Unlock()

	if activeTransport != "" {
		return fmt.Errorf("node transport already started: %s", activeTransport)
	}

	u, err := url.Parse(endpoint)
	if err != nil {
		return fmt.Errorf("invalid QUIC endpoint: %w", err)
	}

	hostPort := u.Host
	if hostPort == "" {
		hostPort = endpoint
	}
	hostname := u.Hostname()
	if hostname == "" {
		hostname = hostPort
	}

	tlsConf := &tls.Config{
		ServerName:         hostname,
		InsecureSkipVerify: true,
	}

	qconf := &quic.Config{
		KeepAlivePeriod: 3 * time.Second,
		MaxIdleTimeout:  5 * time.Minute,
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	conn, err := quic.DialAddr(ctx, hostPort, tlsConf, qconf)
	if err != nil {
		return fmt.Errorf("quic dial failed: %w", err)
	}

	stream, err := conn.OpenStreamSync(ctx)
	if err != nil {
		_ = conn.CloseWithError(0, "open stream failed")
		return fmt.Errorf("quic open stream failed: %w", err)
	}

	hello := nodeQuicHello{
		DeviceID: deviceID,
		Token:    token,
		Country:  country,
		ConnType: connType,
		Speed:    speedMbps,
	}

	helloBytes, err := json.Marshal(hello)
	if err != nil {
		_ = stream.Close()
		_ = conn.CloseWithError(0, "hello marshal failed")
		return fmt.Errorf("quic hello marshal failed: %w", err)
	}

	if err := writeLenPrefixed(stream, helloBytes); err != nil {
		_ = stream.Close()
		_ = conn.CloseWithError(0, "hello write failed")
		return fmt.Errorf("quic hello send failed: %w", err)
	}

	quicConn = conn
	quicStream = stream
	activeTransport = "quic"
	return nil
}

func StartNodeWs(wsEndpoint, deviceID, token, country, connType string, speedMbps int, socks5Proxy string) error {
	quicMu.Lock()
	defer quicMu.Unlock()

	if activeTransport != "" {
		return fmt.Errorf("node transport already started: %s", activeTransport)
	}

	raw := strings.TrimSpace(wsEndpoint)
	if raw == "" {
		return errors.New("empty WS endpoint")
	}
	if !strings.Contains(raw, "://") {
		raw = "wss://" + raw
	}

	u, err := url.Parse(raw)
	if err != nil {
		return fmt.Errorf("invalid WS endpoint: %w", err)
	}

	q := u.Query()
	q.Set("device_id", deviceID)
	q.Set("token", token)
	q.Set("country", country)
	q.Set("conn_type", connType)
	q.Set("speed_mbps", strconv.Itoa(speedMbps))
	u.RawQuery = q.Encode()

	dialer := websocket.Dialer{
		HandshakeTimeout: 15 * time.Second,
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}

	proxyAddr := strings.TrimSpace(socks5Proxy)
	if proxyAddr != "" {
		socksDialer, err := proxy.SOCKS5("tcp", proxyAddr, nil, proxy.Direct)
		if err != nil {
			return fmt.Errorf("create SOCKS5 dialer failed: %w", err)
		}

		dialer.NetDialContext = func(ctx context.Context, network, addr string) (net.Conn, error) {
			return socksDialer.Dial(network, addr)
		}
	}

	conn, _, err := dialer.Dial(u.String(), http.Header{})
	if err != nil {
		return fmt.Errorf("ws dial failed: %w", err)
	}

	wsConn = conn
	activeTransport = "ws"
	return nil
}

func StopNodeTransport() {
	quicMu.Lock()
	defer quicMu.Unlock()

	if quicStream != nil {
		_ = quicStream.Close()
		quicStream = nil
	}
	if quicConn != nil {
		_ = quicConn.CloseWithError(0, "stopped")
		quicConn = nil
	}
	if wsConn != nil {
		_ = wsConn.Close()
		wsConn = nil
	}
	activeTransport = ""
}

func SendNodeFrame(frame []byte) bool {
	if len(frame) == 0 {
		return false
	}

	quicMu.Lock()
	mode := activeTransport
	stream := quicStream
	ws := wsConn
	quicMu.Unlock()

	switch mode {
	case "quic":
		if stream == nil {
			return false
		}
		quicWriteMu.Lock()
		defer quicWriteMu.Unlock()
		if err := writeLenPrefixed(stream, frame); err != nil {
			return false
		}
		return true
	case "ws":
		if ws == nil {
			return false
		}
		wsWriteMu.Lock()
		defer wsWriteMu.Unlock()
		if err := ws.WriteMessage(websocket.BinaryMessage, frame); err != nil {
			return false
		}
		return true
	default:
		return false
	}
}

func ReadNodeFrame() ([]byte, error) {
	quicMu.Lock()
	mode := activeTransport
	stream := quicStream
	ws := wsConn
	quicMu.Unlock()

	switch mode {
	case "quic":
		if stream == nil {
			return nil, errors.New("node QUIC transport is not started")
		}
		return readLenPrefixed(stream)
	case "ws":
		if ws == nil {
			return nil, errors.New("node WS is not started")
		}
		for {
			msgType, payload, err := ws.ReadMessage()
			if err != nil {
				return nil, err
			}
			if msgType == websocket.BinaryMessage {
				return payload, nil
			}
		}
	default:
		return nil, errors.New("node transport is not started")
	}
}

// ──────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────

func writeLenPrefixed(w io.Writer, payload []byte) error {
	header := make([]byte, 4)
	binary.BigEndian.PutUint32(header, uint32(len(payload)))
	if _, err := w.Write(header); err != nil {
		return err
	}
	_, err := w.Write(payload)
	return err
}

func readLenPrefixed(r io.Reader) ([]byte, error) {
	header := make([]byte, 4)
	if _, err := io.ReadFull(r, header); err != nil {
		return nil, err
	}
	ln := binary.BigEndian.Uint32(header)
	if ln == 0 || ln > 4*1024*1024 {
		return nil, errors.New("invalid frame length")
	}
	payload := make([]byte, ln)
	if _, err := io.ReadFull(r, payload); err != nil {
		return nil, err
	}
	return payload, nil
}
