/// Open capability contract for state projected into an external system.
///
/// Operation names are strings rather than a closed enum: current consumers
/// agree on read/create/update/retire/verify/local-rollback, while a future
/// projection may add a capability without changing this core contract.
class ProjectionCapabilities {
  final Map<String, String?> operations;

  const ProjectionCapabilities(this.operations);

  bool supports(String operation) =>
      operations.containsKey(operation) && operations[operation] == null;

  String? limitation(String operation) => operations[operation];
}

abstract class ExternalProjectionTransport {
  ProjectionCapabilities get projectionCapabilities;
}
