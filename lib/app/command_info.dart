import '../config/config.dart';

/// Takes arguments, config and base directory then returns an exit code.
typedef CommandAction = Future<int> Function(
    List<String> args,
    PatcherConfig config,
    String baseDir,
    );

typedef CommandInfo = ({
String name,
String description,
String? usage, // "./cpw x [executable]"
CommandAction action,
});