import 'package:equatable/equatable.dart';
import '../../core/models/vpn_status.dart';

class VpnState extends Equatable {
  final VpnStatus status;
  final String? message;

  const VpnState({required this.status, this.message});

  factory VpnState.initial() => const VpnState(status: VpnStatus.disconnected());

  VpnState copyWith({VpnStatus? status, String? message}) {
    return VpnState(status: status ?? this.status, message: message);
  }

  @override
  List<Object?> get props => [status, message];
}
