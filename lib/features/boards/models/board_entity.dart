class BoardEntity {
  final String boardId;
  final String entityId;

  const BoardEntity({required this.boardId, required this.entityId});

  factory BoardEntity.fromJson(Map<String, dynamic> json) => BoardEntity(
        boardId: json['board_id'] as String,
        entityId: json['entity_id'] as String,
      );

  Map<String, dynamic> toJson() => {'board_id': boardId, 'entity_id': entityId};
}
