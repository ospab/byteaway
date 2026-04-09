package xraywrapper_deprecated

import (
	"bytes"
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
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/quic-go/quic-go"
	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/infra/conf/serial"
	_ "github.com/xtls/xray-core/main/distro/all"
	"golang.org/x/net/proxy"
	_ "golang.org/x/mobile/bind"
)

var xrayInstance *core.Instance
var quicConn quic.Connection
var quicStream quic.Stream
var wsConn *websocket.Conn
var wsWriteMu sync.Mutex
var quicWriteMu sync.Mutex
var activeTransport string
var quicMu sync.Mutex

type nodeQuicHello struct {
	DeviceID string `json:"device_id"`
	Token    string `json:"token"`
	Country  string `json:"country"`
	ConnType string `json:"conn_type"`
	Speed    int    `json:"speed_mbps"`
}

// StartXrayWithFD запускает ядро Xray-core и привязывает его к переданному файловому дескриптору TUN-интерфейса.
func StartXrayWithFD(configJsonStr string, fd int) error {
	if xrayInstance != nil {
		return errors.New("Xray-core уже запущен")
	}

	// В данной версии мы просто сохраняем FD для логов или подготовки,
	// но основная магия будет заключаться в том, что Xray теперь будет сам
	// обрабатывать этот FD через внутренний Tun inbound, если он настроен.
	// Если нет - мы используем SOCKS5 как и раньше, но с исправленным Kotlin-мостом.
	fmt.Printf("StartXrayWithFD invoked with FD: %d\n", fd)
	
	// Нам нужно убедиться, что FD не закроется раньше времени
	tunFile := os.NewFile(uintptr(fd), "tun")
	if tunFile == nil {
		return errors.New("Не удалось создать file из FD")
	}

	return StartXray(configJsonStr)
}

// StartXray запускает ядро Xray-core из переданного JSON конфигурационного файла.
func StartXray(configJsonStr string) error {
	if xrayInstance != nil {
		return errors.New("Xray-core уже запущен")
	}

	conf, err := serial.DecodeJSONConfig(bytes.NewReader([]byte(configJsonStr)))
	if err != nil {
		return fmt.Errorf("DecodeJSONConfig error: %v", err)
	}

	config, err := conf.Build()
	if err != nil {
		return fmt.Errorf("Config build error: %v", err)
	}

	server, err := core.New(config)
	if err != nil {
		return fmt.Errorf("Core new error: %v", err)
	}

	if err := server.Start(); err != nil {
		return err
	}

	xrayInstance = server
	return nil
}

// StopXray аккуратно выключает запущенный инстанс Xray-core и освобождает порты.
func StopXray() {
	if xrayInstance != nil {
		xrayInstance.Close()
		xrayInstance = nil
	}
}

// TestConfig проверяет валидность переданного JSON конфига перед запуском.
func TestConfig(configJsonStr string) error {
	var dat map[string]interface{}
	if err := json.Unmarshal([]byte(configJsonStr), &dat); err != nil {
		return errors.New("Некорректный синтаксис JSON")
	}

	conf, err := serial.DecodeJSONConfig(bytes.NewReader([]byte(configJsonStr)))
	if err != nil {
		return fmt.Errorf("DecodeJSONConfig error: %v", err)
	}
	_, err = conf.Build()
	return err
}

// StartNodeQuic starts a direct QUIC control/data channel to master node.
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

	if mtu > 0 {
		fmt.Printf("StartNodeQuic using mtu=%d\n", mtu)
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


// StartNodeWs starts a direct or proxied WebSocket control/data channel to master node.
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
			type dialWithContext interface {
				DialContext(context.Context, string, string) (net.Conn, error)
			}
			if dctx, ok := socksDialer.(dialWithContext); ok {
				return dctx.DialContext(ctx, network, addr)
			}
			return socksDialer.Dial(network, addr)
		}
	}

	conn, resp, err := dialer.Dial(u.String(), http.Header{})
	if err != nil {
		if resp != nil {
			return fmt.Errorf("ws dial failed: %w (status=%s)", err, resp.Status)
		}
		return fmt.Errorf("ws dial failed: %w", err)
	}

	wsConn = conn
	activeTransport = "ws"
	return nil
}

// StopNodeQuic closes active QUIC transport.
func StopNodeQuic() {
	StopNodeTransport()
}

// StopNodeTransport closes active node control/data transport.
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

// SendNodeFrame sends raw node wire frame over active transport.
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

// ReadNodeFrame blocks until a new raw node wire frame arrives from active transport.
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

		frame, err := readLenPrefixed(stream)
		if err != nil {
			return nil, err
		}
		return frame, nil
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

func writeLenPrefixed(w io.Writer, payload []byte) error {
	if len(payload) == 0 {
		return errors.New("empty frame")
	}
	if len(payload) > 4*1024*1024 {
		return errors.New("frame too large")
	}

	header := make([]byte, 4)
	binary.BigEndian.PutUint32(header, uint32(len(payload)))
	if err := writeAll(w, header); err != nil {
		return err
	}
	return writeAll(w, payload)
}

func writeAll(w io.Writer, buf []byte) error {
	for len(buf) > 0 {
		n, err := w.Write(buf)
		if err != nil {
			return err
		}
		if n <= 0 {
			return errors.New("short write")
		}
		buf = buf[n:]
	}
	return nil
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
