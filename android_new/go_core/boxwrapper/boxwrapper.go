package boxwrapper

import (
	"context"
	"crypto/tls"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/quic-go/quic-go"

	"golang.org/x/net/proxy"
)

var (
	activeTransport string
	quicConn        quic.Connection
	quicStream      quic.Stream
	wsConn          *websocket.Conn
	wsWriteMu       sync.Mutex
	quicWriteMu     sync.Mutex
	quicReadMu      sync.Mutex
	quicMu          sync.Mutex
	ostpConn        net.PacketConn
	ostpMu          sync.Mutex
)

type NodeHello struct {
	DeviceID  string `json:"device_id"`
	Token     string `json:"token"`
	Country   string `json:"country"`
	ConnType  string `json:"conn_type"`
	SpeedMbps int    `json:"speed_mbps"`
}

type OstpConfig struct {
	ServerHost string `json:"server_host"`
	ServerPort int    `json:"server_port"`
	Password   string `json:"password"`
	MTU        int    `json:"mtu"`
}

// ──────────────────────────────────────────────────────
// Node Transport (QUIC/WS/OSTP)
// ──────────────────────────────────────────────────────

func StartNodeQuic(endpoint, deviceID, token, country, connType string, speedMbps int, mtu int) error {
	return startNodeQuicInternal(endpoint, deviceID, token, country, connType, speedMbps, mtu, "quic")
}

func StartNodeWs(wsEndpoint, deviceID, token, country, connType string, speedMbps int, socks5Proxy string) error {
	quicMu.Lock()
	defer quicMu.Unlock()

	if activeTransport != "" {
		return fmt.Errorf("node transport already started: %s", activeTransport)
	}

	raw := strings.TrimSpace(wsEndpoint)
	if !strings.Contains(raw, "://") {
		raw = "wss://" + raw
	}

	u, err := url.Parse(raw)
	if err != nil { return err }

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
		if err == nil {
			dialer.NetDialContext = func(ctx context.Context, network, addr string) (net.Conn, error) {
				return socksDialer.Dial(network, addr)
			}
		}
	}

	conn, _, err := dialer.Dial(u.String(), http.Header{})
	if err != nil { return err }

	wsConn = conn
	activeTransport = "ws"
	return nil
}

func StartNodeOstp(endpoint, deviceID, token, country, connType string, speedMbps int, mtu int) error {
	// For now, OSTP uses the same underlying QUIC transport but with separate logical identification
	err := startNodeQuicInternal(endpoint, deviceID, token, country, connType, speedMbps, mtu, "ostp")
	return err
}

func StartNodeTuic(endpoint, deviceID, token, country, connType string, speedMbps int, mtu int) error {
	err := startNodeQuicInternal(endpoint, deviceID, token, country, connType, speedMbps, mtu, "tuic")
	return err
}

func StartNodeHy2(endpoint, deviceID, token, country, connType string, speedMbps int, mtu int) error {
	return startNodeHy2Tcp(endpoint, deviceID, token, country, connType, speedMbps)
}

func startNodeHy2Tcp(endpoint, deviceID, token, country, connType string, speedMbps int) error {
	quicMu.Lock()
	defer quicMu.Unlock()

	if activeTransport != "" {
		return fmt.Errorf("node transport already started: %s", activeTransport)
	}

	// Parse endpoint - remove quic:// prefix if present
	host := strings.TrimPrefix(endpoint, "quic://")
	if idx := strings.Index(host, ":"); idx == -1 {
		host = host + ":5443"
	}

	conn, err := net.Dial("tcp", host)
	if err != nil {
		return fmt.Errorf("HY2 dial failed: %w", err)
	}

	hello := NodeHello{
		DeviceID:  deviceID,
		Token:     token,
		Country:   country,
		ConnType:  connType,
		SpeedMbps: speedMbps,
	}
	helloBytes, _ := json.Marshal(hello)

	// Write length-prefixed frame
	lenBuf := make([]byte, 2)
	binary.BigEndian.PutUint16(lenBuf, uint16(len(helloBytes)))
	if _, err := conn.Write(lenBuf); err != nil {
		conn.Close()
		return fmt.Errorf("HY2 hello len write failed: %w", err)
	}
	if _, err := conn.Write(helloBytes); err != nil {
		conn.Close()
		return fmt.Errorf("HY2 hello write failed: %w", err)
	}

	// Store connection for later use
	wsConn = nil // Not used for HY2 TCP
	quicConn = nil // Not used
	activeTransport = "hy2"
	
	log.Printf("HY2 transport connected to %s", host)
	return nil
}

func startNodeQuicInternal(endpoint, deviceID, token, country, connType string, speedMbps int, mtu int, proto string) error {
	quicMu.Lock()
	defer quicMu.Unlock()

	if activeTransport != "" {
		return fmt.Errorf("node transport already started: %s", activeTransport)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	alpn := []string{"byteaway-node"}
	if proto == "hy2" {
		alpn = []string{"h3"}
	}

	tlsConf := &tls.Config{
		InsecureSkipVerify: true,
		NextProtos:         alpn,
	}

	conf := &quic.Config{
		MaxIdleTimeout:  60 * time.Second,
		KeepAlivePeriod: 10 * time.Second,
	}

	dialEndpoint := endpoint
	if strings.Contains(dialEndpoint, "://") {
		u, err := url.Parse(dialEndpoint)
		if err == nil {
			dialEndpoint = u.Host
		}
	}

	conn, err := quic.DialAddr(ctx, dialEndpoint, tlsConf, conf)
	if err != nil {
		return fmt.Errorf("%s dial failed: %w", proto, err)
	}

	stream, err := conn.OpenStreamSync(ctx)
	if err != nil {
		_ = conn.CloseWithError(0, "stream open failed")
		return fmt.Errorf("%s stream failed: %w", proto, err)
	}

	hello := NodeHello{
		DeviceID:  deviceID,
		Token:     token,
		Country:   country,
		ConnType:  connType,
		SpeedMbps: speedMbps,
	}
	helloBytes, _ := json.Marshal(hello)
	if err := writeLenPrefixed(stream, helloBytes); err != nil {
		_ = stream.Close()
		_ = conn.CloseWithError(0, "hello write failed")
		return fmt.Errorf("%s hello send failed: %w", proto, err)
	}

	quicConn = conn
	quicStream = stream
	activeTransport = proto
	log.Printf("%s transport connected to %s", strings.ToUpper(proto), endpoint)
	return nil
}

func StopNodeTransport() {
	quicMu.Lock()
	defer quicMu.Unlock()

	if quicStream != nil { _ = quicStream.Close(); quicStream = nil }
	if quicConn != nil { _ = quicConn.CloseWithError(0, "stopped"); quicConn = nil }
	if wsConn != nil { _ = wsConn.Close(); wsConn = nil }
	activeTransport = ""
}

func SendNodeFrame(frame []byte) bool {
	if len(frame) == 0 { return false }
	quicMu.Lock()
	mode := activeTransport
	stream := quicStream
	ws := wsConn
	quicMu.Unlock()

	switch mode {
	case "quic", "tuic", "hy2", "ostp":
		if stream == nil { return false }
		quicWriteMu.Lock()
		defer quicWriteMu.Unlock()
		err := writeLenPrefixed(stream, frame)
		if err != nil {
			fmt.Printf("[boxwrapper] %s send error: %v\n", mode, err)
			return false
		}
		return true
	case "ws":
		if ws == nil { return false }
		wsWriteMu.Lock()
		defer wsWriteMu.Unlock()
		err := ws.WriteMessage(websocket.BinaryMessage, frame)
		if err != nil {
			fmt.Printf("[boxwrapper] WS send error: %v\n", err)
			return false
		}
		return true
	default: return false
	}
}

func ReadNodeFrame() ([]byte, error) {
	quicReadMu.Lock()
	defer quicReadMu.Unlock()

	quicMu.Lock()
	mode := activeTransport
	stream := quicStream
	ws := wsConn
	quicMu.Unlock()

	var payload []byte
	var err error

	switch mode {
	case "quic", "tuic", "hy2", "ostp":
		if stream == nil { return nil, errors.New("no " + mode + " stream") }
		payload, err = readLenPrefixed(stream)
	case "ws":
		if ws == nil { return nil, errors.New("no ws conn") }
		for {
			var msgType int
			msgType, payload, err = ws.ReadMessage()
			if err != nil { break }
			if msgType == websocket.BinaryMessage { break }
		}
	default:
		time.Sleep(1 * time.Second)
		return nil, errors.New("not implemented")
	}

	if err == nil && len(payload) >= 17 {
		cmd := payload[0]
		sid := fmt.Sprintf("%x", payload[1:17])
		fmt.Printf("[boxwrapper] READ frame: cmd=%d sid=%s len=%d\n", cmd, sid, len(payload))
	} else if err != nil {
		fmt.Printf("[boxwrapper] READ error: %v\n", err)
	}

	return payload, err
}

func writeLenPrefixed(w io.Writer, payload []byte) error {
	header := make([]byte, 4)
	binary.BigEndian.PutUint32(header, uint32(len(payload)))
	if _, err := w.Write(header); err != nil { return err }
	_, err := w.Write(payload)
	return err
}

func readLenPrefixed(r io.Reader) ([]byte, error) {
	header := make([]byte, 4)
	if _, err := io.ReadFull(r, header); err != nil { return nil, err }
	ln := binary.BigEndian.Uint32(header)
	if ln == 0 || ln > 4*1024*1024 { return nil, errors.New("invalid frame length") }
	payload := make([]byte, ln)
	if _, err := io.ReadFull(r, payload); err != nil { return nil, err }
	return payload, nil
}

// ──────────────────────────────────────────────────────
// Helper types for OSTP
// ──────────────────────────────────────────────────────

// packetConnWrapper implements io.Reader and io.Writer for net.PacketConn
type packetConnWrapper struct {
	conn net.PacketConn
	buf  []byte
}

func (pcw *packetConnWrapper) Read(p []byte) (n int, err error) {
	n, _, err = pcw.conn.ReadFrom(p)
	return n, err
}

func (pcw *packetConnWrapper) Write(p []byte) (n int, err error) {
	return pcw.conn.WriteTo(p, nil)
}

// ──────────────────────────────────────────────────────
// OSTP Support
// ──────────────────────────────────────────────────────

func StartNodeOstpUdp(serverHost string, serverPort int, password string, deviceID, token, country, connType string, speedMbps, mtu int) error {
	ostpMu.Lock()
	defer ostpMu.Unlock()

	if ostpConn != nil {
		ostpConn.Close()
		ostpConn = nil
	}

	addr := fmt.Sprintf("%s:%d", serverHost, serverPort)
	log.Printf("Starting OSTP node to %s", addr)

	// Create UDP connection for OSTP
	conn, err := net.ListenPacket("udp", ":0")
	if err != nil {
		return fmt.Errorf("failed to create UDP connection: %w", err)
	}

	ostpConn = conn
	activeTransport = "ostp"

	// Send hello message
	hello := NodeHello{
		DeviceID:  deviceID,
		Token:     token,
		Country:   country,
		ConnType:  connType,
		SpeedMbps: speedMbps,
	}

	helloData, err := json.Marshal(hello)
	if err != nil {
		return fmt.Errorf("failed to marshal hello: %w", err)
	}

	// Send hello to server
	serverAddr, err := net.ResolveUDPAddr("udp", addr)
	if err != nil {
		return fmt.Errorf("failed to resolve server address: %w", err)
	}

	_, err = ostpConn.WriteTo(helloData, serverAddr)
	if err != nil {
		return fmt.Errorf("failed to send hello: %w", err)
	}

	log.Printf("OSTP node started and hello sent to %s", addr)
	return nil
}

func StopNodeOstp() error {
	ostpMu.Lock()
	defer ostpMu.Unlock()

	if ostpConn != nil {
		ostpConn.Close()
		ostpConn = nil
	}
	activeTransport = ""
	log.Printf("OSTP node stopped")
	return nil
}

func SendOstpFrame(data []byte) error {
	ostpMu.Lock()
	defer ostpMu.Unlock()

	if ostpConn == nil {
		return errors.New("OSTP connection not established")
	}

	// Send data with length prefix
	err := writeLenPrefixed(&packetConnWrapper{conn: ostpConn}, data)
	if err != nil {
		return fmt.Errorf("failed to send OSTP frame: %w", err)
	}

	return nil
}

func ReadOstpFrame() ([]byte, error) {
	ostpMu.Lock()
	defer ostpMu.Unlock()

	if ostpConn == nil {
		return nil, errors.New("OSTP connection not established")
	}

	// Read data with length prefix
	data, err := readLenPrefixed(&packetConnWrapper{conn: ostpConn})
	if err != nil {
		return nil, fmt.Errorf("failed to read OSTP frame: %w", err)
	}

	return data, nil
}

// ──────────────────────────────────────────────────────
// VPN OSTP Support
// ──────────────────────────────────────────────────────

func StartOstpVpn(config string, tunFd int64) error {
	log.Printf("Starting OSTP VPN with tun fd: %d", tunFd)

	var ostpConfig OstpConfig
	if err := json.Unmarshal([]byte(config), &ostpConfig); err != nil {
		return fmt.Errorf("failed to parse OSTP config: %w", err)
	}

	// TODO: Implement actual OSTP VPN integration
	// This would involve:
	// 1. Setting up TUN interface with the provided fd
	// 2. Connecting to OSTP server
	// 3. Routing traffic through OSTP tunnel
	
	log.Printf("OSTP VPN config parsed: %+v", ostpConfig)
	return errors.New("OSTP VPN not yet implemented")
}
