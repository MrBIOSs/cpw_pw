/// Takes arguments then returns an exit code.
typedef CommandAction = Future<int> Function(List<String> args);

typedef CommandInfo = ({
String name,
String description,
String? usage, // "./cpw x [executable]"
CommandAction action,
});