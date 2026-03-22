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
    int? speedMbps,
  }) {
    return _remoteDs.startNode(
      token: token,
      deviceId: deviceId,
      country: country,
      speedMbps: speedMbps,
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
