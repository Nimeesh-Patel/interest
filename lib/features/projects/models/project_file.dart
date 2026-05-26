class ProjectFile {
  final String filePath;
  final String name;
  final int totalTasks;
  final int completedTasks;
  final bool isListStyle;

  const ProjectFile({
    required this.filePath,
    required this.name,
    required this.totalTasks,
    required this.completedTasks,
    this.isListStyle = false,
  });

  double get progress => totalTasks == 0 ? 0.0 : completedTasks / totalTasks;
}
