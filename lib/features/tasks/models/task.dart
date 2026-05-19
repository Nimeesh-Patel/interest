class TaskFile {
  final String filePath;
  final String name;
  final int totalTasks;
  final int completedTasks;

  const TaskFile({
    required this.filePath,
    required this.name,
    required this.totalTasks,
    required this.completedTasks,
  });

  double get progress => totalTasks == 0 ? 0.0 : completedTasks / totalTasks;
}
