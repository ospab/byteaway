package boxwrapper

import (
	"context"
	"fmt"
	"sync"

	"github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
)

var (
	boxInstance *box.Box
	boxMu       sync.Mutex
	boxCancel   context.CancelFunc
	protector   SocketProtector
)

// SocketProtector is an interface for protecting sockets from VPN routing loops.
type SocketProtector interface {
	Protect(fd int32) bool
}

// SetSocketProtector sets the protector instance.
func SetSocketProtector(p SocketProtector) {
	boxMu.Lock()
	defer boxMu.Unlock()
	protector = p
}

// StartSingBox starts the sing-box service with the given JSON configuration.
// It also accepts a TUN file descriptor for the TUN inbound.
func StartSingBox(configJSON string, tunFd int64) error {
	boxMu.Lock()
	defer boxMu.Unlock()

	if boxInstance != nil {
		return fmt.Errorf("sing-box is already running")
	}

	var options option.Options
	
	parseCtx := include.Context(context.Background())
	err := options.UnmarshalJSONContext(parseCtx, []byte(configJSON))
	if err != nil {
		return fmt.Errorf("failed to parse sing-box config: %w", err)
	}

	// We re-enabled TUN FD injection in sing-box-fork via FileDescriptor field
	if tunFd > 0 {
		fmt.Printf("Injecting Android TUN FD %d into sing-box config\n", tunFd)
	}

	ctx, cancel := context.WithCancel(parseCtx)
	
	boxOptions := box.Options{
		Options: options,
		Context: ctx,
	}
	
	instance, err := box.New(boxOptions)
	if err != nil {
		cancel()
		return fmt.Errorf("failed to create sing-box instance: %w", err)
	}

	err = instance.Start()
	if err != nil {
		cancel()
		instance.Close()
		return fmt.Errorf("failed to start sing-box: %w", err)
	}

	boxInstance = instance
	boxCancel = cancel
	return nil
}

// StopSingBox stops the running sing-box service.
func StopSingBox() error {
	boxMu.Lock()
	defer boxMu.Unlock()

	if boxInstance == nil {
		return nil
	}

	if boxCancel != nil {
		boxCancel()
	}

	err := boxInstance.Close()
	boxInstance = nil
	boxCancel = nil
	
	if err != nil {
		return fmt.Errorf("failed to stop sing-box: %w", err)
	}
	return nil
}

// IsSingBoxRunning returns true if the sing-box service is currently running.
func IsSingBoxRunning() bool {
	boxMu.Lock()
	defer boxMu.Unlock()
	return boxInstance != nil
}

// GetSingBoxLogs could be implemented if needed, but for now we'll rely on Android logcat.
