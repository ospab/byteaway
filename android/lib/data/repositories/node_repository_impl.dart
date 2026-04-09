import '../../domain/entities/node_status.dart';
import '../../domain/repositories/node_repository.dart';
import '../datasources/node_remote_ds.dart';

/// Concrete [NodeRepository] — delegates to [NodeRemoteDataSource]
/// which bridges the Kotlin Foreground Service.
class NodeRepositoryImpl implements NodeRepository {
  final NodeRemoteDataSource _remoteDs;

  NodeRepositoryImpl(this._remoteDs);

  @override
  Future<bool> startNode({
    required String token,
    required String deviceId,
    required String country,
    String? transportMode,
    String? connType,
    int? speedMbps,
    int? mtu,
    String? masterWsUrl,
    String? coreConfigJson,
  }) {
    return _remoteDs.startNode(
      token: token,
      deviceId: deviceId,
      country: country,
      transportMode: transportMode,
      connType: connType,
      speedMbps: speedMbps,
      mtu: mtu,
      masterWsUrl: masterWsUrl,
      coreConfigJson: coreConfigJson,
    );
  }

  @override
  Future<bool> stopNode() {
    return _remoteDs.stopNode();
  }

  @override
  Future<NodeStatus> getStatus() async {
    final model = await _remoteDs.getStatus();
    return model.toEntity();
  }

  @override
  Stream<NodeStatus> get statusStream =>
      _remoteDs.statusStream.map((model) => model.toEntity());
}
