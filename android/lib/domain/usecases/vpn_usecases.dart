import '../entities/vpn_status.dart';
import '../repositories/vpn_repository.dart';

/// Start sing-box VPN tunnel.
class ConnectVpnUseCase {
  final VpnRepository _repository;

  const ConnectVpnUseCase(this._repository);

  /// Connects VPN with the given sing-box [config] JSON.
  /// Returns `true` on successful connection initiation.
  Future<bool> call(String config) {
    return _repository.connect(config);
  }
}

/// Stop sing-box VPN tunnel.
class DisconnectVpnUseCase {
  final VpnRepository _repository;

  const DisconnectVpnUseCase(this._repository);

  Future<bool> call() {
    return _repository.disconnect();
  }
}
